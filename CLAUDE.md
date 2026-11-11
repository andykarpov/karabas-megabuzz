# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Karabas-MegaBuzz is an FPGA-based sound card for the ZX Spectrum (NemoBus slot). A Xilinx Spartan-6 (XC6SLX16 or XC6SLX25, ftg256) implements Turbosound FM, General Sound, SAA1099, Soundrive/Covox, Beeper, the bus glue for an external OPL3 (YMF262), MIDI (SAM2695) and VS1053 MP3 decoder chips, plus Z-Controller/DivMMC SD-card support. Audio goes out through a PCM5102 I2S DAC.

Repo layout: `firmware/src/` (all code), `pcb/revA*`, `pcb/revB` (KiCad), `docs/` (schematics PDFs, iBOMs), `README.md` / `README.ru.md` and `HOWTO.en.md` / `HOWTO.md` (flashing and board usage; English and Russian versions, keep both in sync), `PORTS.en.md` / `PORTS.md` (host-visible control registers), `ERRATA.en.md` / `ERRATA.md` (per-revision hardware errata).

## Hardware revisions drive everything

There are four board revisions: `A`, `A1`, `A2`, `A3`. One top-level module, `firmware/src/rtl/megabuzz.v` (`karabas_megabuzz`), serves all of them through `` `ifdef HW_A / HW_A1 / HW_A2 / HW_A3 `` blocks. The port list and per-revision pin glue live in these blocks, and so do the A2+ features (config ROM switch, flash-stored config, DivMMC SRAM) and the A3-only VS1053 chip (`vs1053_en = 1` only under `HW_A3`; A2 has no VS1053). On A1–A3 an optional QSPI PSRAM (APS6404L, 8 MB) footprint shares the config flash bus (CONF_CLK/CONF_IO0..3) and has only its own `psram_cs_n`, which is currently tied high. Each revision has its own constraints file, `firmware/src/syn/karabas-megabuzz[-aN].ucf`. When you change I/O, update the matching `ifdef` port block **and** the right `.ucf`, and keep the other revisions building.

## Building the FPGA bitstream

Synthesis uses Xilinx ISE 14.7 from the command line. The Makefile expects it at `/opt/Xilinx/14.7/ISE_DS`. Run everything from `firmware/src/syn/`:

```
make all16_a3      # XC6SLX16, rev A3 -> work16/karabas_megabuzz_a3.bit/.bin
make all25_a2      # XC6SLX25, rev A2 with the neorv32 MP3 decoder -> work25/karabas_megabuzz_a2.bit/.bin
make all           # all 8 variants (slow)
make clean
```

Target names follow `all{16,25}_{a,a1,a2,a3}`; `all25_a`, `all25_a1`, `all25_a2` and `all25_a3` are always built with neorv32 (`-define RV32`). The pipeline is: `.prj` → xst → ngdbuild → map → par → bitgen (`-g Binary:Yes`, so a `.bin` is produced too). The `.prj`/`.xst` files are generated in the work dir, and they are only rebuilt when missing.

**Source lists are explicit.** `VERILOG_SOURCES_COMMON` and `VHDL_SOURCES` in `syn/Makefile` are the source of truth. A new RTL file has to be added there, and you have to delete the stale `work*/*.prj` so it gets regenerated. Many files under `rtl/` are not in the build: `rtl/core/` (NEORV32 RISC-V, see below), `rtl/mp3dec/`, `rtl/sound/jtopl/`, `ay_3_8912.v`, `saa1099.v`/`.sv`, and the `.v` twins of VHDL files in `adc/` and `flash/`. Note that `saa1099_new.v` is the one actually synthesized, while its module is still named `saa1099`.

The built `.bit`/`.bin` files in `syn/work16` and `syn/work25` are committed on purpose: README links to them as release downloads.

## Flashing (openocd + USB Blaster)

From `firmware/src/syn/`: `make flash{16,25}[_a1|_a2|_a3]`, plus `flash{16,25}_a2_nommc`, which uses `cfg2.rom`. The SPI flash layout is: bitstream at `0x0`, GS ROM (`rtl/sound/gs105b.rom`) at `0x100000`, 256-byte config ROM (`cfg1.rom` or `cfg2.rom`) at `0x1F0000`, and on `flash25`, `flash25_a1`, `flash25_a2`, `flash25_a2_nommc`, `flash25_a3` also the neorv32 firmware (`syn/mp3dec.bin`) at `0x180000`; `flash25_a2*` use `cfg{1,2}_a2_rv32.rom`, with the MP3 option already on. `cfg2.rom` differs from `cfg1.rom` only in having DivMMC disabled (byte 0 bit 0). The `flash*` targets need an existing `.bin` (there is no rule that builds one). The Makefile has no openFPGALoader targets; HOWTO.md lists the manual openFPGALoader commands.

## Z80 / Spectrum-side code (sjasmplus)

- `firmware/src/rom/`: the Megabuzz configurator ROM, which the FPGA maps in place of the host ROM. Run `make` there to produce `megabuzz.rom`, `debug.rom` (`-DEMU_MODE=1 -DDEBUG_MODE=1`) and `megabuzz.mem`. The `.mem` hexdump gets baked into the bitstream through `sprom ... MEM_INIT_FILE("../rom/megabuzz.mem")` in `megabuzz.v`, so **rebuild the ROM before resynthesizing** whenever you change ROM code. The esxDOS ROM goes in the same way (`rtl/sd/esxdos.mem`).
- `firmware/src/plugin/`: esxDOS `mp3` plugin. Build with `make`.
- `firmware/src/playmp3/`: `.playmp3` esxDOS dot command. Build with `make`.
- `firmware/src/test/`: MP3 test assets and a test `.sna`.

## Simulation

RTL testbenches in `firmware/src/rtl/sound/`: `./vs1053_tb.sh` (iverilog `-DSIMULATION` + vvp + gtkwave), `python3 audio_fir_tb.py` and `python3 audio_img_tb.py` (bit-exact against the Python model); `rtl/ram/sram_arbiter_tb.sh` for the SRAM arbiter.

`firmware/src/sw/bench/run.sh` is an MP3-decode benchmark: it builds Helix for neorv32, runs it in GHDL (`--std=08`, mcode backend, so use `ghdl -r`; it creates no executable) and prints `mcycle` per frame. It takes a few minutes per frame.

## NEORV32 / MP3 emulation (work in progress)

`PLAN.md` holds the plan and measurements for emulating VS1053 on neorv32 on SLX25 (`all25_a`, `all25_a1`, `all25_a2`, `all25_a3`); section 7 describes what is implemented. Read it before touching `rtl/core`, `rtl/mp3dec` or `sw/`. Key facts:
- `rtl/mp3dec/rv_vs1053.vhd` is the wrapper. On A3 the decoder is chosen by config bit 11 (`0` = VS1053 chip, `1` = neorv32), on A, A1 and A2 it is always neorv32. They use ~85-88% slices and 38-43/52 RAMB16.
- Firmware image for the flash: after changing `sw/src/mp3dec` run `make clean bin` there and copy `neorv32_raw_exe.bin` to `syn/mp3dec.bin`. It must not exceed 32768 bytes (the linker enforces it). End-to-end test: `sw/bench/run_rv.sh`; it rebuilds the firmware, so copy the image only from a build of the current sources.
- `rtl/core` is neorv32 v1.13.5.4. XST 14.7 synthesizes it: compile it into library `neorv32` (`vhdl neorv32 <file>`, package first). Use `CPU_FAST_MUL_REGS => 3`, otherwise the DSP cascade limits Fmax to ~54 MHz.
- RISC-V toolchain: `/opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin` (not in PATH). Firmware: `sw/src/mp3dec` (`make elf|image|bin`, `NEORV32_HOME` points to `firmware/src`). `make install` overwrites `rtl/core/neorv32_imem_image.vhd`.
- The free BRAM on SLX25 is the hard limit for CPU code, data and PCM buffers: if it runs out, XST silently moves memories to LUTs and the design stops fitting.

## Architecture notes

- **Host bus**: the FPGA decodes the Z80 bus directly (`bus_a`, `bus_d`, `bus_iorq_n`, `bus_m1_n`, …) from the NemoBus slot. Each sound device module gets the decoded bus and an enable bit, and returns audio samples.
- **Audio path**: device modules (each holds its last sample at its own rate) → `audio_mixer` (19-bit sum, saturated to 16 bits, `audio_mute` silences it on reset; GS and MP3 are summed apart into `img_l/img_r`) → `audio_fir_decim` (64-tap FIR, 875 kHz → 109.375 kHz, 4 channels: the main mix and GS+MP3; coefficients from `audio_fir_gen.py`, test `audio_fir_tb.py`). GS+MP3 first go through `audio_avg` (32-clock average) and after the decimator through `audio_img_lpf` (64-tap image filter at 109.375 kHz, flat to 18 kHz, −60 dB above 24.4 kHz; `audio_img_gen.py`, test `audio_img_tb.py`, run without `python3 -I`), then both are summed and saturated → `kg_pcm5102` I2S out (copied from karabas-go-modules, not a submodule). Two `vu_meter` instances drive the LED bars from the final output. A PCM1808 ADC is read through `i2s_transceiver` (`adc_l`/`adc_r`) and mixed in.
- **General Sound** (`gs_top.v`/`gs.v`) runs its own T80 Z80 core (`rtl/T80`, VHDL). At boot, `loader.vhd` + `flash.vhd` copy the GS ROM out of SPI flash.
- **Config & control** (A2/A3): the ZXUNO-style register ports `#FC3B` (register select) and `#FD3B` (data) expose custom registers `#F4`–`#FC`: a read-only board id (`#F4`: revision, SLX25, neorv32, VS1053 chip; the configurator ROM hides the RV32 option on SLX16), VS1053 FIFO and volume/effects, config bytes, ROM switch, internal reset (the board never resets the host). Config byte 0 is a per-device enable bitmask. Writing the second config byte triggers `cfg_write`, which persists both bytes to SPI flash (the 0x1F0000 area). `PORTS.md` and `PORTS.en.md` are the spec; keep them in sync when you change register behavior in `megabuzz.v`.
- **SD**: `rtl/sd/zc_dicmmc.v` implements both Z-Controller and DivMMC (with the esxDOS ROM and the 128K SRAM on A2+).
- **SRAM arbiter**: with `MMC_ON_GS_SRAM` (A1 today) the DivMMC RAM lives in the upper 512 KB of the GS SRAM (`rtl/ram/sram_arbiter.v`, test `sram_arbiter_tb.sh`). GS keeps its direct path to the pads because its CPU reads in one 71 ns CE period; a host access freezes GS through CE and takes the pads, and `bus_wait_n` covers fast hosts. GS memory is 1.5 MB while DivMMC is enabled.

## Conventions

- Verilog files use `` `default_nettype none ``. VHDL is used for T80 and the flash/loader/i2s modules. ISE's XST compiles both into the `work` library.
- README, HOWTO, PORTS and ERRATA exist in English and Russian, keep both versions in sync. Some Makefile comments are in Russian. Keep new user-facing docs consistent with that.
