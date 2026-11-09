// MP3 decode benchmark for neorv32 (GHDL): prints mcycle per decoded frame
#include <neorv32.h>
#include <stdlib.h>
#include "../src/mp3dec/lib/mp3dec.h"
#include "mp3data.h"

static short pcm[1152 * 2];

static uint32_t pcm_sum(int n) {
  uint32_t s = 0;
  for (int i = 0; i < n; i++) s = s * 31 + (uint16_t)pcm[i];
  return s;
}

#ifdef USE_CFU_MAC
#include "../src/mp3dec/lib/cfu_mac.h"

static uint32_t rnd_state = 0x1234ABCD;
static int rnd32(void) {
  rnd_state ^= rnd_state << 13;
  rnd_state ^= rnd_state >> 17;
  rnd_state ^= rnd_state << 5;
  return (int)rnd_state;
}
// random value of random magnitude, so that not every sum saturates
static int rnd_op(void) { int s = rnd32() & 31; return rnd32() >> s; }

static short ref_rd(long long s) {
  int x = (int)(s >> 20);
  x >>= 6;
  int sign = x >> 31;
  if (sign != (x >> 15)) x = sign ^ 0x7fff;
  return (short)x;
}

// compares the CFU with a 64-bit C model; returns the number of mismatches
static int cfu_selftest(void) {
  int fails = 0;
  for (int pass = 0; pass < 24; pass++) { // GHDL runs ~2k CPU cycles/s, so keep this short
    long long s[4];
    int v = rnd32();
    CFU_SET(0, v); CFU_SET(1, v); CFU_SET(2, v); CFU_SET(3, v);
    s[0] = s[1] = s[2] = s[3] = v;
    for (int j = 0; j < 16; j++) {
      int a = rnd_op(), b = rnd_op();
      if (j == 0 && (pass & 7) == 0) a = b = (int)0x80000000;
      long long p = (long long)a * b;
      CFU_MAC(0, a, b); s[0] += p;
      CFU_MAC(5, a, b); s[1] -= p;
      CFU_MAC(2, a, b); s[2] += p;
      CFU_MAC(7, a, b); s[3] -= p;
    }
    int r[4];
    r[0] = CFU_RD(0); r[1] = CFU_RD(1); r[2] = CFU_RD(2); r[3] = CFU_RD(3);
    for (int k = 0; k < 4; k++) fails += (r[k] != ref_rd(s[k]));
    // MACRD must have left the rounding constant behind, which reads back as 0
    fails += (CFU_RD(0) != 0) + (CFU_RD(1) != 0) + (CFU_RD(2) != 0) + (CFU_RD(3) != 0);
  }
  return fails;
}
#endif

static void bench(const char *name, const unsigned char *buf, int len, int max_frames) {
  HMP3Decoder h = MP3InitDecoder();
  MP3FrameInfo fi;
  unsigned char *p = (unsigned char *)buf;
  int left = len;
  if (h == 0) {
    neorv32_uart0_printf("%s: init failed\n", name);
    return;
  }
  for (int n = 0; n < max_frames; n++) {
    int off = MP3FindSyncWord(p, left);
    if (off < 0) break;
    p += off; left -= off;
    uint32_t t0 = (uint32_t)neorv32_cpu_get_cycle();
    int err = MP3Decode(h, &p, &left, pcm, 0);
    uint32_t t1 = (uint32_t)neorv32_cpu_get_cycle();
    if (err == ERR_MP3_INDATA_UNDERFLOW || err == ERR_MP3_MAINDATA_UNDERFLOW) {
      neorv32_uart0_printf("%s #%d: underflow (%d)\n", name, n, err);
      if (err == ERR_MP3_INDATA_UNDERFLOW) break;
      continue;
    }
    MP3GetLastFrameInfo(h, &fi);
    neorv32_uart0_printf("%s #%d: err=%d sr=%d ch=%d kbps=%d samps=%d cycles=%u pcm=%x\n",
      name, n, err, fi.samprate, fi.nChans, fi.bitrate / 1000, fi.outputSamps, t1 - t0, pcm_sum(fi.outputSamps));
  }
  MP3FreeDecoder(h);
}

int main(void) {
  neorv32_rte_setup();
  neorv32_uart0_setup(115200, 0);
  NEORV32_UART0->CTRL |= (1 << UART_CTRL_SIM_MODE);
  neorv32_uart0_printf("bench start\n");
  { void *m = malloc(100); neorv32_uart0_printf("heap %x..%x size %u, malloc(100)=%x\n", (uint32_t)NEORV32_HEAP_BEGIN, (uint32_t)NEORV32_HEAP_END, (uint32_t)NEORV32_HEAP_SIZE, (uint32_t)m); free(m); }
#ifdef USE_CFU_MAC
  neorv32_uart0_printf("cfu selftest: %d mismatches\n", cfu_selftest());
#endif
#define X(name, arr, frames) bench(name, arr, sizeof(arr), frames);
  BENCH_LIST
#undef X
  neorv32_uart0_printf("bench done\n");
  // signal the testbench
  neorv32_gpio_port_set(0xD0E);
  while (1);
  return 0;
}
