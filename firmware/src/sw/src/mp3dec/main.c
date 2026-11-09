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

static uint8_t inbuf[INBUF_SIZE];
static int in_left;                         // valid bytes at the start of inbuf

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

  neorv32_rte_setup();
  neorv32_uart0_setup(115200, 0);
#ifdef SIM
  NEORV32_UART0->CTRL |= (1 << UART_CTRL_SIM_MODE);
#endif
  neorv32_uart0_puts("mp3dec\n");

  HMP3Decoder decoder = MP3InitDecoder();
  in_left = 0;

  for (;;) {
    input_fill();

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

    while (((wp - REG_PCM_PTR) & PTR_MASK) > PCM_WORDS - FRAME_WORDS) { }

    uint8_t *start = inbuf + off;
    uint8_t *ptr = start;
    int left = in_left - off;
    short *out = (short *)(PCM_BASE + (wp & (PCM_WORDS - 1)) * 4u);
#ifdef SIM
    uint32_t t0 = (uint32_t)neorv32_cpu_get_cycle();
#endif
    int err = MP3Decode(decoder, &ptr, &left, out, 0);
#ifdef SIM
    neorv32_uart0_printf("err=%d cycles=%u\n", err, (uint32_t)neorv32_cpu_get_cycle() - t0);
#endif

    if (err == ERR_MP3_INDATA_UNDERFLOW) {
      if (left + (int)(ptr - start) >= INBUF_SIZE) {
        // can not be a real frame: the buffer holds more than any frame has
        ptr = start + 1;
        left = in_left - off - 1;
      } else {
        ptr = start;            // MP3Decode has consumed the headers, the data must stay for the retry
        left = in_left - off;
      }
    } else if (err == ERR_MP3_NONE) {
      MP3GetLastFrameInfo(decoder, &fi);
      pcm_finish(wp, &fi);
      REG_NCO = (uint32_t)fi.samprate * NCO_PER_KHZ / 1000u;
      wp = (wp + fi.outputSamps / fi.nChans) & PTR_MASK;
      REG_PCM_PTR = wp;
    } else if (err != ERR_MP3_MAINDATA_UNDERFLOW) {
      ptr = start + 1;          // a corrupt frame: look for the next sync word
      left = in_left - off - 1;
    }

    in_left = left;
    input_compact(ptr);
  }

  return 0;
}
