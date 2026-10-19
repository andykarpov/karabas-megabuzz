# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Karabas-MegaBuzz is an FPGA-based sound card for the ZX Spectrum (NemoBus slot). A Xilinx Spartan-6 (XC6SLX16 or XC6SLX25, ftg256) implements Turbosound FM, General Sound, SAA1099, Soundrive/Covox, Beeper, the bus glue for an external OPL3 (YMF262), MIDI (SAM2695) and VS1053 MP3 decoder chips, plus Z-Controller/DivMMC SD-card support. Audio goes out through a PCM5102 I2S DAC.

Repo layout: `firmware/src/` (all code), `pcb/revA*`, `pcb/revB` (KiCad), `docs/` (schematics PDFs, iBOMs), `HOWTO.md` (flashing and board usage, in Russian), `PORTS.md` (host-visible control registers, in Russian), `ERRATA.md` (per-revision hardware errata).

## Hardware revisions drive everything

There are four board revisions: `A`, `A1`, `A2`, `A3`. One top-level module, `firmware/src/rtl/megabuzz.v` (`karabas_megabuzz`), serves all of them through `` `ifdef HW_A / HW_A1 / HW_A2 / HW_A3 `` blocks. The port list and per-revision pin glue live in these blocks, and so do the A2-only and A3-only features (EEPROM config storage, VS1053). Each revision has its own constraints file, `firmware/src/syn/karabas-megabuzz[-aN].ucf`. When you change I/O, update the matching `ifdef` port block **and** the right `.ucf`, and keep the other revisions building.

## Building the FPGA bitstream

Synthesis uses Xilinx ISE 14.7 from the command line. The Makefile expects it at `/opt/Xilinx/14.7/ISE_DS`. Run everything from `firmware/src/syn/`:

```
make all16_a3      # XC6SLX16, rev A3 -> work16/karabas_megabuzz_a3.bit/.bin
make all25_a2      # XC6SLX25, rev A2 -> work25/karabas_megabuzz_a2.bit/.bin
make all           # all 8 variants (slow)
make clean
```

Target names follow `all{16,25}_{a,a1,a2,a3}`. The pipeline is: `.prj` → xst → ngdbuild → map → par → bitgen (`-g Binary:Yes`, so a `.bin` is produced too). The `.prj`/`.xst` files are generated in the work dir, and they are only rebuilt when missing.

**Source lists are explicit.** `VERILOG_SOURCES_COMMON` and `VHDL_SOURCES` in `syn/Makefile` are the source of truth. A new RTL file has to be added there, and you have to delete the stale `work*/*.prj` so it gets regenerated. Many files under `rtl/` are not in the build: `rtl/core/` (NEORV32 RISC-V), `rtl/mp3dec/`, `rtl/sound/jtopl/`, `ay_3_8912.v`, `saa1099.v`/`.sv`, and the `.v` twins of VHDL files in `adc/` and `flash/`. Note that `saa1099_new.v` is the one actually synthesized, while its module is still named `saa1099`.

The built `.bit`/`.bin` files in `syn/work16` and `syn/work25` are committed on purpose: README links to them as release downloads.

## Flashing (openocd + USB Blaster)

From `firmware/src/syn/`: `make flash{16,25}[_a1|_a2|_a3]`, plus `flash{16,25}_a2_nommc`, which uses `cfg2.rom`. The SPI flash layout is: bitstream at `0x0`, GS ROM (`rtl/sound/gs105b.rom`) at `0x100000`, 256-byte config ROM (`cfg1.rom` or `cfg2.rom`) at `0x1F0000`. `cfg2.rom` differs from `cfg1.rom` only in having DivMMC disabled (byte 0 bit 0). The `flash*` targets need an existing `.bin` (there is no rule that builds one). The Makefile has no openFPGALoader targets; HOWTO.md lists the manual openFPGALoader commands.

## Z80 / Spectrum-side code (sjasmplus)

- `firmware/src/rom/`: the Megabuzz configurator ROM, which the FPGA maps in place of the host ROM. Run `make` there to produce `megabuzz.rom`, `debug.rom` (`-DEMU_MODE=1 -DDEBUG_MODE=1`) and `megabuzz.mem`. The `.mem` hexdump gets baked into the bitstream through `sprom ... MEM_INIT_FILE("../rom/megabuzz.mem")` in `megabuzz.v`, so **rebuild the ROM before resynthesizing** whenever you change ROM code. The esxDOS ROM goes in the same way (`rtl/sd/esxdos.mem`).
- `firmware/src/plugin/`: esxDOS `mp3` plugin. Build with `make`.
- `firmware/src/playmp3/`: `.playmp3` esxDOS dot command. Build with `make`.
- `firmware/src/test/`: MP3 test assets and a test `.sna`.

## Simulation

The only testbench is VS1053. Run it from `firmware/src/rtl/sound/`: `./vs1053_tb.sh` (iverilog `-DSIMULATION` + vvp + gtkwave). There is no other test suite.

## Architecture notes

- **Host bus**: the FPGA decodes the Z80 bus directly (`bus_a`, `bus_d`, `bus_iorq_n`, `bus_m1_n`, …) from the NemoBus slot. Each sound device module gets the decoded bus and an enable bit, and returns audio samples.
- **Audio path**: device modules → `audio_mute` / `audio_resample` → `audio_mixer` → `pcm5102` I2S out. Two `vu_meter` instances drive the LED bars. A PCM1808 ADC is read through `i2s_transceiver` (`adc_l`/`adc_r`) and mixed in.
- **General Sound** (`gs_top.v`/`gs.v`) runs its own T80 Z80 core (`rtl/T80`, VHDL). At boot, `loader.vhd` + `flash.vhd` copy the GS ROM out of SPI flash.
- **Config & control** (A2/A3): the ZXUNO-style register ports `#FC3B` (register select) and `#FD3B` (data) expose custom registers `#F5`–`#FC`: VS1053 FIFO and volume/effects, config bytes, ROM switch, host reset. Config byte 0 is a per-device enable bitmask. Writing the second config byte triggers `cfg_write`, which persists both bytes to SPI flash (the 0x1F0000 area). `PORTS.md` is the spec; keep it in sync when you change register behavior in `megabuzz.v`.
- **SD**: `rtl/sd/zc_dicmmc.v` implements both Z-Controller and DivMMC (with the esxDOS ROM and the 128K SRAM on A2+).

## Conventions

- Verilog files use `` `default_nettype none ``. VHDL is used for T80 and the flash/loader/i2s modules. ISE's XST compiles both into the `work` library.
- Docs (HOWTO, PORTS, ERRATA) and some Makefile comments are written in Russian. Keep new user-facing docs consistent with that.
