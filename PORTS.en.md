# 🎵 Megabuzz ports

English | [Русский](PORTS.md)

All sound devices of the Megabuzz are available through their own ports. There are also service ports to control the Megabuzz itself (on revisions `A2`, `A3`). This document covers only the specific ports: those of the vs1053 and those that control the settings.

## 🔌 ZXUNO ports

The vs1053 chip and the service ports are controlled through a set of registers of the ZXUNO ports `#FC3B` / `#FD3B`.

### 🔌 ZXUNO register select port - `#FC3B`

As in the ZXUNO standard, this port selects the register that the data port `#FD3B` works with.

The Megabuzz currently supports these custom registers of the ZXUNO ports:

- `#F5` - status and control register of the VS1053 FIFO
- `#F6` - data register of the VS1053 FIFO
- `#F7` - Megabuzz configuration byte register
- `#F8` - Megabuzz ROM register
- `#F9` - Megabuzz control register
- `#FA` - Megabuzz configuration byte address register
- `#FB` - VS1053 volume register
- `#FC` - VS1053 effects register

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
- 3️⃣ bit 3 - MP3 decoder on the builds with neorv32 (revA3 on the XC6SLX25): `0` = the onboard VS1053 chip, `1` = neorv32. The bit is ignored on the other builds; on A2 with neorv32 the decoder is always neorv32

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

### 🔌 ZXUNO data port - `#FD3B`

This port writes a value to the register selected before through port `#FC3B`.
The values of the registers can be read through this port too.
