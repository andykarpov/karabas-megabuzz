/**
 * MP3 decoder firmware, VS1053 emulation on neorv32 (see rtl/mp3dec/rv_vs1053.vhd).
 *
 * The host writes MP3 data into the FIFO of the VS1053 host interface. The firmware pulls it byte by
 * byte, decodes a frame straight into the PCM ring and commits it to the hardware, which plays the
 * ring at the sample rate of the stream.
 */

#include <neorv32.h>
#include <stdint.h>
#include "lib/mp3dec.h"

// memory map of rv_vs1053
#define PCM_BASE        0x10000000u         // ring of 2048 words, mirrored: a frame may run past its end
#define REG_DATA        (*(volatile uint32_t *)0x20000000u)  // r: bit 8 = byte valid, bits 7:0 = byte
#define REG_VOLUME      (*(volatile uint32_t *)0x20000004u)  // r: bits 7:0 = #FB
#define REG_PCM_PTR     (*(volatile uint32_t *)0x20000008u)  // r: play pointer, w: end of the committed data
#define REG_NCO         (*(volatile uint32_t *)0x2000000Cu)  // w: phase increment per CPU clock

#define PCM_WORDS       2048
#define PTR_MASK        0xFFFu              // pointers are one bit wider than the ring
#define FRAME_WORDS     1152
#define NCO_PER_KHZ     61357u              // 2^32 / 70 MHz is 61.357 per Hz

#define INBUF_SIZE      (MAINBUF_SIZE + 108)
#define HEADER_BYTES    38                  // frame header, CRC and the longest side info

static uint8_t inbuf[INBUF_SIZE];
static int in_left;                         // valid bytes at the start of inbuf
static uint32_t tag_left;                   // bytes of an ID3v2 tag still to drop

// VS1053 volume is in -0.5 dB steps: one table entry per step within 6 dB, Q15
static const uint16_t gain_table[12] = {
  32768, 30935, 29205, 27571, 26029, 24572, 23198, 21900, 20675, 19519, 18427, 17396
};

static int32_t volume_gain(uint32_t vol) {
  uint32_t shift = vol / 12;
  if (vol >= 0xFE || shift > 15) return 0;
  return gain_table[vol % 12] >> shift;
}

static void input_compact(uint8_t *from) {
  int n = in_left;
  uint8_t *to = inbuf;
  while (n--) *to++ = *from++;
}

static void input_fill(void) {
  while (in_left < INBUF_SIZE) {
    uint32_t w = REG_DATA;
    if (!(w & 0x100)) break;
    inbuf[in_left++] = (uint8_t)w;
  }
}

// Returns 1 while the start of inbuf is, or may still become, an ID3v2 tag. Skipping the tag keeps the
// sync words inside cover art away from the decoder.
static int id3_check(void) {
  static const char id[3] = {'I', 'D', '3'};
  for (int i = 0; i < 3 && i < in_left; i++) {
    if (inbuf[i] != (uint8_t)id[i]) return 0;
  }
  if (in_left < 10) return 1;
  if ((inbuf[6] | inbuf[7] | inbuf[8] | inbuf[9]) & 0x80) return 0;   // size bytes are 7 bit: not a tag
  tag_left = 10u + (((uint32_t)inbuf[6] << 21) | ((uint32_t)inbuf[7] << 14) | ((uint32_t)inbuf[8] << 7) | inbuf[9]);
  if (inbuf[5] & 0x10) tag_left += 10;                                // footer
  return 1;
}

// Layer III with a usable bit rate and sample rate. Bit rate 0 is free format: a false sync word of that
// kind switches Helix into free format mode for good, so that no real frame decodes after it.
static int header_valid(const uint8_t *h) {
  uint32_t version = (h[1] >> 3) & 3;
  uint32_t layer = (h[1] >> 1) & 3;
  uint32_t bitrate = h[2] >> 4;
  uint32_t samprate = (h[2] >> 2) & 3;
  return version != 1 && layer == 1 && bitrate != 0 && bitrate != 15 && samprate != 3;
}

// PCM of the frame, in place at the ring; mono is expanded from the end so nothing is overwritten
static void pcm_finish(uint32_t wp, const MP3FrameInfo *fi) {
  uint32_t words = fi->outputSamps / fi->nChans;
  int32_t gain = volume_gain(REG_VOLUME & 0xFF);
  volatile uint32_t *ring = (volatile uint32_t *)PCM_BASE + (wp & (PCM_WORDS - 1));
  volatile int16_t *mono = (volatile int16_t *)ring;

  if (fi->nChans == 1) {
    for (int i = (int)words - 1; i >= 0; i--) {
      uint16_t s = (uint16_t)mono[i];
      ring[i] = ((uint32_t)s << 16) | s;
    }
  }
  if (gain != 32768) {
    for (uint32_t i = 0; i < words; i++) {
      uint32_t w = ring[i];
      int32_t l = ((int16_t)w * gain) >> 15;
      int32_t r = ((int16_t)(w >> 16) * gain) >> 15;
      ring[i] = ((uint32_t)r << 16) | ((uint32_t)l & 0xFFFF);
    }
  }
}

int main(void) {
  static MP3FrameInfo fi;
  uint32_t wp = 0;

  HMP3Decoder decoder = MP3InitDecoder();
  in_left = 0;

  for (;;) {
    input_fill();

    if (tag_left > 0) {
      uint32_t n = tag_left < (uint32_t)in_left ? tag_left : (uint32_t)in_left;
      tag_left -= n;
      in_left -= (int)n;
      input_compact(inbuf + n);
      continue;
    }
    if (id3_check()) continue;

    int off = MP3FindSyncWord(inbuf, in_left);
    if (off < 0) {
      // keep the tail in case a sync word starts at the very end
      if (in_left > 3) {
        uint8_t *tail = inbuf + in_left - 3;
        in_left = 3;
        input_compact(tail);
      }
      continue;
    }

    if (off > 0) {
      in_left -= off;
      input_compact(inbuf + off);
    }
    // the host is much slower than this loop, and MP3Decode trusts the buffer for the headers
    if (in_left < HEADER_BYTES) continue;

    if (!header_valid(inbuf)) {
      in_left--;
      input_compact(inbuf + 1);
      continue;
    }

    while (((wp - REG_PCM_PTR) & PTR_MASK) > PCM_WORDS - FRAME_WORDS) { }

    uint8_t *start = inbuf;
    uint8_t *ptr = start;
    int left = in_left;
    short *out = (short *)(PCM_BASE + (wp & (PCM_WORDS - 1)) * 4u);
    int err = MP3Decode(decoder, &ptr, &left, out, 0);

    if (err == ERR_MP3_INDATA_UNDERFLOW) {
      if (left + (int)(ptr - start) >= INBUF_SIZE) {
        // can not be a real frame: the buffer holds more than any frame has
        ptr = start + 1;
        left = in_left - 1;
      } else {
        ptr = start;            // MP3Decode has consumed the headers, the data must stay for the retry
        left = in_left;
      }
    } else if (err == ERR_MP3_NONE) {
      MP3GetLastFrameInfo(decoder, &fi);
      pcm_finish(wp, &fi);
      REG_NCO = (uint32_t)fi.samprate * NCO_PER_KHZ / 1000u;
      wp = (wp + fi.outputSamps / fi.nChans) & PTR_MASK;
      REG_PCM_PTR = wp;
    } else if (err != ERR_MP3_MAINDATA_UNDERFLOW) {
      ptr = start + 1;          // a corrupt frame: look for the next sync word
      left = in_left - 1;
    }

    in_left = left;
    input_compact(ptr);
  }

  return 0;
}
