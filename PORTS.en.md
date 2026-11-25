# 🎵 Megabuzz ports

English | [Русский](PORTS.md)

All sound devices of the Megabuzz are available through their own ports. There are also service ports to control the Megabuzz itself (on revisions `A2`, `A3`). This document covers only the specific ports: those of the vs1053 and those that control the settings.

## 🔌 ZXUNO ports

The vs1053 chip and the service ports are controlled through a set of registers of the ZXUNO ports `#FC3B` / `#FD3B`.

### 🔌 ZXUNO register select port - `#FC3B`

As in the ZXUNO standard, this port selects the register that the data port `#FD3B` works with.

The Megabuzz currently supports these custom registers of the ZXUNO ports:

- `#F4` - Megabuzz board id register (read only)
- `#F5` - status and control register of the VS1053 FIFO
- `#F6` - data register of the VS1053 FIFO
- `#F7` - Megabuzz configuration byte register
- `#F8` - Megabuzz ROM register
- `#F9` - Megabuzz control register
- `#FA` - Megabuzz configuration byte address register
- `#FB` - VS1053 volume register
- `#FC` - VS1053 effects register
- `#FF` - Megabuzz firmware id (read only)

##### 📟 Register `#F4` - Megabuzz board id

Read only. The value is set at synthesis: it describes the board and the firmware the bitstream was built for.

- 2️⃣...0️⃣ bits 2:0 - board revision: `0` = A, `1` = A1, `2` = A2, `3` = A3
- 3️⃣ bit 3 - XC6SLX25 FPGA (`0` = XC6SLX16)
- 4️⃣ bit 4 - the firmware has the neorv32 MP3 decoder
- 5️⃣ bit 5 - the board has a VS1053 chip (A3)
- 7️⃣...6️⃣ bits 7:6 - reserved, read as `0`

`#F4` is free in ZX-UNO (there `#F4` is the Timex I/O port, not a register) and in the profi and tsconf cores. The register exists from this firmware version on; on older firmware a read returns whatever the host puts on the bus (usually `#FF`).

##### 📟 Register `#F5` - VS1053 FIFO status and control

reading from the data port returns:

- 7️⃣ bit 7 - VS1053 FIFO overflow status
- 6️⃣...0️⃣ bits 6:0 - number of occupied 32-byte blocks in the VS1053 FIFO

writing to the data port:

- 7️⃣ bit 7 - resets the FIFO and the VS1053 by a soft reset
- 6️⃣...0️⃣ bits 6:0 = 0

##### 📟 Register `#F6` - VS1053 FIFO data

- on a write - the given byte is written to the VS1053 FIFO
- on a read - returns the same as register #F5 (the FIFO status)

##### 📟 Register `#F7` - Megabuzz configuration byte

- writing to the data port writes the configuration byte at the address set in register `#FA`
- reading from the data port returns the configuration byte at the address set in register `#FA`

There are only 2 configuration bytes at the moment.

First configuration byte (address = 0x00):

- 0️⃣ bit 0 - DivMMC on = 1, off = 0
- 1️⃣ bit 1 - Z-Controller on = 1, off = 0
- 2️⃣ bit 2 - Soundrive
- 3️⃣ bit 3 - Beeper
- 4️⃣ bit 4 - SAA1099
- 5️⃣ bit 5 - General Sound
- 6️⃣ bit 6 - Turbosound FM + MIDI
- 7️⃣ bit 7 - OPL3

Second configuration byte (address = 0x01):

- 0️⃣ bit 0 - VU meter bar on
- 1️⃣ bit 1 - VU meter dot on
- 2️⃣ bit 2 - reverses the direction of the VU meter
- 3️⃣ bit 3 - MP3 decoder on the builds with neorv32 (revA3 on the XC6SLX25): `0` = the onboard VS1053 chip, `1` = neorv32. The bit is ignored on the other builds; on A2 with neorv32 the decoder is always neorv32. The configurator shows this option only on the XC6SLX25

##### 📟 Register `#F8` - Megabuzz ROM

- 0️⃣ bit 0 - switches between the regular ROM of the host and the Megabuzz configurator ROM. `1` = Megabuzz ROM, `0` = Spectrum ROM

##### 📟 Register `#F9` - Megabuzz control

- 0️⃣ bit 0 - value `1` resets the internal logic of the Megabuzz. This register does not reset the host

##### 📟 Register `#FA` - Megabuzz configuration byte address

- 7️⃣...0️⃣ bits 7:0 - set the address of the configuration byte. Valid values today are `0x00`, `0x01`

##### 📟 Register `#FB` - VS1053 volume

- value `0x00` - maximum volume
- value `0xFE` - minimum volume

By default, the board resets with volume `0x08` (about `-5 dB` below the maximum volume).

##### 📟 Register `#FC` - VS1053 effects

- 7️⃣...6️⃣ bits 7:6 - ear speaker (`00` - off, `01` - low, `10` - mid, `11` - high)
- 5️⃣...3️⃣ bits 5:3 - treble boost (`000` - off, `111` - max +10.5dB) at 5kHz
- 2️⃣...0️⃣ bits 2:0 - bass boost (`000` - off, `111` - max + 14dB) at 60Hz

By default, the effects register holds `0x00`.

##### 📟 Register `#FF` - Megabuzz firmware id

Read only, as `COREID` in ZX-UNO. Selecting `#FF` through `#FC3B` rewinds the string; each read of `#FD3B` returns its next ASCII character, and after the last one it returns `0`. Example: `A2 25 RV 2026-11-24 1a2b3c4`:

- board revision: `A`, `A1`, `A2`, `A3`
- FPGA: `16` = XC6SLX16, `25` = XC6SLX25
- `RV` - the firmware has the neorv32 MP3 decoder (missing otherwise)
- build date and the short git hash of the sources; `+` after the hash means the build had uncommitted changes. The committed bitstreams are built before their commit, so the hash points to the commit before them, and the date identifies the build best.

The configurator ROM shows the string at the bottom of its screen, the Wild Commander plugin shows it in its F10 window. Firmware older than this register has no id: the read returns whatever the host puts on the bus (usually `#FF`).

### 🔌 ZXUNO data port - `#FD3B`

This port writes a value to the register selected before through port `#FC3B`.
The values of the registers can be read through this port too.

## 🔌 NeoGS ports

The General Sound of the Megabuzz understands the [NeoGS](http://www.nedopc.com/gs/ngs.php) ports of the GS CPU side: MP3 and the SD card for programs written for NeoGS (for example Neo Player Light). The ports follow the description of the standard NeoGS FPGA firmware (`GS_info` v0.4.2.2). MP3 through the NeoGS ports goes to the same decoder as through the registers `#F5`/`#F6`/`#FB`: the VS1053 chip on Rev.A3 or the software decoder on the XC6SLX25. The ports work while General Sound is on. Rev.A, A1, A2 on the XC6SLX16 have no MP3 decoder: a NeoGS program sees MP3 (`_MPDRQ` is always `1`), but the data is dropped and there is no sound.

### 🔌 Port `#33` (Spectrum side, write only)

Bits 7..5 are compared exactly:

- `100` (`#80`) - resets the GS (its CPU and ports; the rest of the Megabuzz and the host are not reset)
- `010` (`#40`) - NMI to the GS CPU
- `001` (`#20`) - the NeoGS LED, ignored

The GS and the MP3 decoder are reset together with the host (the RESET line of the bus, the RESET button on the board), as a plain GS and NeoGS with its reset jumper are: classic software (zplayer, demos) does not know port `#33` and expects a clean GS after a reset. The exception is an MP3 that plays (the decoder took data from its FIFO in the last 0.6 s): then a host reset leaves them alone, as NeoGS without the jumper does, and an MP3 started by a NeoGS player plays on. Power-on, port `#33` and the internal reset of the Megabuzz (register `#F9`, the configurator) always reset the GS. A decoder left without data after a host reset outputs silence after 60 ms.

### 🔌 GS CPU ports

The ports are decoded by `A5..A0`. Ports that do not exist read as `#FF`.

- `#0F` `GSCFG0` - read and write, reads back what was written. After a reset `#23`: the NeoGS loader leaves it so, and the Megabuzz starts the GS ROM right away.
  - bit 0 `NOROM`: `1` - RAM in all windows; `0` - "flash" in the windows `#0000`, `#8000`, `#C000`. There is no NeoGS flash, a copy of the GS ROM stands in for it, writes there are ignored.
  - bit 1 `RAMRO`: with `NOROM=1`, `1` write-protects pages 0-1 (absolute `#0000`-`#7FFF`, the GS ROM), `0` allows writes. If the ROM was changed this way, the next GS reset (a host reset, `#33`, a Megabuzz reset) copies the ROM from flash again, as on NeoGS. This takes ~0.12 s; the GS CPU stays in reset meanwhile, the ports `#BB`/`#B3` keep working.
  - bit 3 `EXPAG`: extended paging. `MPAG` (`#00`) sets the 16 KB page of `#8000`, `MPAGEX` (`#10`) the one of `#C000`; the page number is the byte rotated by one bit (`axxxxxxx` → `xxxxxxxa`).
  - bits 5..4 (Z80 clock), bit 2 (`8CHANS`), bit 6 (`PAN4CH`), bit 7 (`INV7B`): only stored. The Z80 always runs at 14 MHz, there are 4 channels.
- `#10` `MPAGEX` - write, the page of `#C000` in the `EXPAG` mode.
- `#11` `SCTRL` - read and write. On a write bit 7 is the value, bits 5..0 select the bits to change. Bit 0 `_SDNCS`, bit 1 `_MPNCS`, bit 2 `_MPXRS`, bit 3 `_MPHLF`, bit 4 `_MDHLF`. After a reset `#0B`.
- `#12` `SSTAT` - read. Bit 0 `_MPDRQ` (at least 32 bytes free in the FIFO), bit 1 `_SDDET` (`0` - a card is in), bit 2 `_SDWP` (always `0`), bit 3 `_MCRDY`.
- `#13` `SD_SEND` (write) / `SD_READ` (read) - exchanges a byte with the SD card / the byte received in the last exchange.
- `#14` `SD_RSTR` (read) - the received byte, and a new exchange with `#FF`; `MD_SEND` (write) - a byte of the MP3 stream.
- `#15` `MC_SEND` (write) / `MC_READ` (read) - the control channel (SCI) of the decoder.
- `#16`-`#19` - volumes of the channels 5-8, ignored.

When a port cannot do its operation right away (the SD card is busy, the FIFO is full, the SCI answer is not there yet), the GS CPU waits on `WAIT`. The NeoGS rule of 16 clocks between exchanges need not be kept.

#### SCI

Programs for NeoGS are written for a VS1001/VS1011, so the SCI frames do not go to the decoder as they are:

- a `MODE` write with `SM_RESET` - a soft reset of the Megabuzz decoder (the FIFO is flushed too);
- a `MODE` write - to the chip, with `SM_SDINEW` always on;
- a `CLOCKF` write - not passed on: the Megabuzz sets the clock of the chip;
- a `VOL` write - to the volume `#FB` (the louder of the two channels);
- other writes - to the chip as they are (patches, real-time MIDI);
- reads - from the chip. With the software decoder: `STATUS` = `#0040` (VS1053), `MODE`, `CLOCKF`, `BASS` - the last value written, `VOL` - the volume `#FB`, the rest `0`.

`_MPXRS` going from `0` to `1` is a hard reset of the decoder.

#### SD card

One SD card serves the host (Z-Controller / DivMMC) and the GS. One of them owns it at a time, the host by default. The owner changes when the other one wants to exchange a byte and the owner is idle: its CS is high, or it is low with no exchange for ~50 ms. While the card is busy, the host waits on `/WAIT`, the GS on its own `WAIT`. A GS reset gives the card back to the host.

A NeoGS player keeps its CS low while it reads a sector and hands it to the MP3 decoder at the stream rate (on `_MPDRQ`). A host that turns to the card meanwhile may wait on `/WAIT` until the sector ends: ~13 ms at 320 kbps, ~32 ms at 128 kbps, ~64 ms at 64 kbps. The 50 ms timeout does not fire here: exchanges go on.

On a host without `/WAIT` support, do not use a NeoGS player with the SD card together with DivMMC/ZC: turn DivMMC and Z-Controller off in the configurator.
