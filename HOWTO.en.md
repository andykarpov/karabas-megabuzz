## Karabas-MegaBuzz How-to

English | [Русский](HOWTO.md)

### Checking the Spartan with a multimeter

It is best to start assembling the board with the Spartan.
After soldering it, check the board with a multimeter.
Set the multimeter to continuity (diode) mode and put the red probe on ground.
With the black probe, touch the pads marked in red on the map: [top of revA](docs/karabas-megabuzz_revA_top_map.png) and [bottom of revA](docs/karabas-megabuzz_revA_bottom_map.png).
There are maps for revA2 too: [top of revA2](docs/karabas-megabuzz_revA2_top_map.png) and [bottom of revA2](docs/karabas-megabuzz_revA2_bottom_map.png).
All the marked pads should show roughly the same reading.
A reading of 0 means the ball is probably shorted to ground.
No reading means the ball probably has not seated. Heat the board again, blow with the hot air gun and nudge the chip.

### Flashing

The board has to be flashed before it can run.
To keep the design cheap, the JTAG header on the board is laid out for an Altera USB Blaster.

The SPI flash can be written in several ways:

1) Put it in a programmer and write the bitstream BIN file, the GS ROM and the configuration ROM (bitstream at address 0, GS ROM at 0x100000, configuration at 0x1F0000).
2) Connect a Xilinx Platform USB Cable and flash with iMPACT (same addresses).
3) Use the open source openFPGALoader with any JTAG programmer, including the Altera USB Blaster.
4) The same with openOCD.
5) The same with urJTAG.

The first two need no explanation.
The sections below cover openFPGALoader (for now only for the xc6slx16: on the xc6slx25 it does not see the flash through the JTAG-SPI bridge) and openOCD.

#### Flashing with openFPGALoader

1) Install openFPGALoader. Modern Linux distributions have it, but the version is old, so it is better to build it from source following the manual on its site. There are builds for Windows and macOS too.
2) Connect the USB Blaster.
3) Supply 5 V to the board (the prg connector on the board can be used for this).

The Makefile has no targets for openFPGALoader, so flash by hand. All commands run from `firmware/src/syn`.

4) Write the bitstream of your revision (file name: `karabas_megabuzz.bit` for revA, `karabas_megabuzz_a1.bit`, `karabas_megabuzz_a2.bit`, `karabas_megabuzz_a3.bit` for revA1/A2/A3). For revA3:

`openFPGALoader -c usb-blaster --fpga-part xc6slx16ftg256 -f work16/karabas_megabuzz_a3.bit`

5) Write the 32 KB GS ROM at 0x100000 (needed on revA1 and newer, optional on revA):

`openFPGALoader -c usb-blaster --fpga-part xc6slx16ftg256 -f -o 0x100000 ../rtl/sound/gs105b.rom`

6) Write the 256 bytes of configuration at 0x1F0000 (`cfg1.rom`, or `cfg2.rom` without DivMMC; needed on revA2 and newer, optional on revA and revA1):

`openFPGALoader -c usb-blaster --fpga-part xc6slx16ftg256 -f -o 0x1F0000 cfg1.rom`

After programming the board starts.
It sweeps the level indicators from maximum to minimum.
The RESET button shows the same sweep. This is a sure sign that the FPGA part of the board is running.

#### Flashing with openocd

1) Install openocd (modern Linux distributions have it). There are builds for Windows and macOS too.
2) Connect the USB Blaster.
3) Supply 5 V to the board (the prg connector on the board can be used for this).
4) From `firmware/src/syn`, run the target you need. Each target writes the bitstream (at 0), the GS ROM (at 0x100000) and the configuration (at 0x1F0000) in one pass:

| Target | FPGA | Revision | Configuration |
| :--- | :--- | :--- | :--- |
| `make flash16` | XC6SLX16 | revA | cfg1 |
| `make flash16_a1` | XC6SLX16 | revA1 | cfg1 |
| `make flash16_a2` | XC6SLX16 | revA2 | cfg1 |
| `make flash16_a2_nommc` | XC6SLX16 | revA2 | cfg2 |
| `make flash16_a3` | XC6SLX16 | revA3 | cfg1 |
| `make flash25` | XC6SLX25 | revA | cfg1 |
| `make flash25_a1` | XC6SLX25 | revA1 | cfg1 |
| `make flash25_a2` | XC6SLX25 | revA2 | cfg1_a2_rv32 (cfg1 with the MP3 option on) |
| `make flash25_a2_nommc` | XC6SLX25 | revA2 | cfg2_a2_rv32 (cfg2 with the MP3 option on) |
| `make flash25_a3` | XC6SLX25 | revA3 | cfg1 |

The targets use the already built `.bin` from `work16/` or `work25/`. If it is missing, build the bitstream first (`make all16_a3`, `make all25_a2` and so on) or use the one from the repository.

To do it by hand instead of with the Makefile, for example the bitstream for the SLX25:

`sudo openocd -f ocd.cfg -c "init; jtagspi_init 0 bscan_spi_xc6slx25.bit; jtagspi_program work25/karabas_megabuzz_a2.bin 0; jtagspi_program ../rtl/sound/gs105b.rom 0x100000; jtagspi_program cfg1.rom 0x1F0000; xc6s_program xc6s.tap; exit"`

After programming the board starts.
It sweeps the level indicators from maximum to minimum.
The RESET button shows the same sweep. This is a sure sign that the FPGA part of the board is running.

For the XC6SLX16 the command is the same, with the `bscan_spi_xc6slx16.bit` bridge and a file from `work16/`.

#### neorv32 MP3 decoder (XC6SLX25, revA, revA1, revA2 and revA3)

In the builds for the XC6SLX25 of revA, revA1, revA2 and revA3, MP3 can be decoded by a neorv32 soft processor inside the FPGA. It is controlled from the host the same way as the VS1053 (ports `#F5`/`#F6`/`#FB`, see `PORTS.md`). Only the volume is supported, bass and treble (`#FC`) are accepted and ignored. The stream is MPEG Layer III up to 320 kbps stereo, free format is not supported.

There are no separate targets for it: the `make all25` builds of these revisions and the `make flash25`, `make flash25_a1`, `make flash25_a2`, `make flash25_a2_nommc` and `make flash25_a3` targets already include neorv32, and also write its firmware `syn/mp3dec.bin` at 0x180000. The loader reads it from the flash at startup, so the firmware can be updated without resynthesis:

`openocd -f ocd.cfg -c "init; jtagspi_init 0 bscan_spi_xc6slx25.bit; jtagspi_program mp3dec.bin 0x180000; xc6s_program xc6s.tap; exit"`

Which decoder runs:

- revA, revA1 and revA2: there is no VS1053 chip, the decoder is always neorv32.
- revA3: chosen in the configurator with the `MP3 on RV32` option: off is the onboard VS1053 chip, on is neorv32. The setting is kept in the flash.

The XC6SLX16 does not have the resources for neorv32, those builds work as before.

#### DivMMC memory on revA1

revA1 has no separate SRAM for DivMMC, its memory is the upper 512 KB of the SRAM of General Sound. So with DivMMC enabled, GS has 1.5 MB (players show about 1488 KB), with DivMMC disabled it has the full 2 MB.

### DIP switches

revA and revA1 have 5 DIP switches.
If they are not soldered, all the devices on the board work.

#### Switches on revA:

1) SW1 - Soundrive + Covox + Beeper
2) SW2 - SAA1099
3) SW3 - General Sound
4) SW4 - TurbosoundFM + Midi
5) SW5 - OPL3

#### Switches on revA1:

1) SW1 - DivMMC
2) SW2 - Soundrive + Covox + Beeper + SAA1099
3) SW3 - General Sound
4) SW4 - TurbosoundFM + Midi
5) SW5 - OPL3

#### Settings on revA2 and revA3:

These boards have no DIP switches.
Instead, it is all set by the bits of the first byte of the configuration ROM (cfg1.rom or cfg2.rom), 1 is on and 0 is off. For example, byte 0xFF means all the hardware is on:

- bit 0 - DivMMC
- bit 1 - ZC
- bit 2 - Soundrive + Covox
- bit 3 - Beeper
- bit 4 - SAA1099
- bit 5 - General Sound
- bit 6 - Turbosound + FM + Midi
- bit 7 - OPL3

Important: if you hold the reset + nmi buttons on the board after it starts, it enters the configuration ROM, where all these bits can be set and applied (saved to the configuration in the flash).

As a bonus, besides the sound devices, you can also set the type of the LED indicator and change its direction, or turn it off altogether so it does not distract you :)

### Test points on the back of the board

#### revA

- TP1 - /OPL3_RST output, for a revA fix (OPL3 reset at board start: lift leg 8 RST off the board and wire it to TP1)
- TP2 - soldered to ground, reverses the direction of the indicators
- TP3 - soldered to ground, hides the VU bar
- TP4 - soldered to ground, hides the VU dot
- TP5-TP8 - unused for now
- The others are connected to the corresponding configuration signals of the Spartan.

#### revA1

- TP1 - TP4 - reserved
- TP5 - TP8 - system

#### revA2, revA3

- TP1 - TP4 - reserved
- TP5 - TP8 - system
- I2S - i2s sound output

### Playing MP3

Revision A3 has a hardware MP3 decoder (the vs1053 / vs1063 chip).
There is an mp3 plugin for the NMI browser by Bob Fossil, to be put in bin/bplugins/ on the SD card.
It can play MP3 files, including a whole directory in a row.

Controls:

    - Space - next track
    - Q - exit
