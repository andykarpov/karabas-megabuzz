# MEGABUZZ.WMF — MP3 player for Wild Commander

English | [Русский](README.md)

A Wild Commander (WC) plugin for TSConf (ZX Evolution, Karabas Mini and others) that plays MP3 through the Karabas-MegaBuzz decoder: the VS1053 chip or the neorv32 software decoder. It uses the registers `#F4`, `#F5`, `#F6`, `#FB`, `#FC` (see [PORTS.en.md](../../../PORTS.en.md)).

```
+------------------ Megabuzz MP3 Player v0.2 ------------------+
| File:   01-kino-gruppa_krovi.mp3                             |
|--------------------------------------------------------------|
| Title:  Группа крови                                         |
| Artist: Кино                                                 |
| Album:  Группа крови                                         |
| Year:   1988      Track: 1/11       Genre: Rock              |
|--------------------------------------------------------------|
| MPEG-1 Layer III  128 kbps CBR  44.1 kHz  Joint Stereo       |
| Decoder: VS1053   Vol: █████████░ -4dB    Bass: 0  Treble: 0 |
|--------------------------------------------------------------|
| ► 01:23 ██████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 04:47 |
|                                                              |
|                                                              |
| Buf ███████░ 87%                                             |
|--------------------------------------------------------------|
|Spc:next P:prev <>:seek S:pause +-:vol B/T:bass/treb Esc:exit |
+--------------------------------------------------------------+
```

## Installing

1. Put `MEGABUZZ.WMF` into the `WC` folder of the boot device.
2. Add it to the `[PLUGINS]` section of `WC/wc.ini` **before** `GSPLAYER.WMF`, which opens MP3 files too:

   ```ini
   [PLUGINS]
   MEGABUZZ.WMF
   GSPLAYER.WMF -midi_chip=2
   ```

   WC hands the file to the first plugin in the list that has its extension. If there is no Megabuzz or no MP3 decoder on it, the plugin shows a window with what the board answered (register `#F4`, and on a failure the same read at 3.5 MHz) and why, and after a key WC opens its Shift+Enter menu. WC does not offer the file to the other plugins with the MP3 extension: GS Player (Sound Player) is not in the Shift+Enter menu, so while `MEGABUZZ.WMF` comes first in the list MP3 files cannot be played through GS. The plugin's F10 menu item shows the same board information. In the Shift+Enter menu the plugin is called "Play on Megabuzz".
3. Turn the Megabuzz Z-Controller and DivMMC off (in the configurator on A2/A3, with the DIP switches on A1): TSConf has its own Z-Controller on the same ports, and they would get in the way of the host SD card.

It needs a Megabuzz bitstream with an MP3 decoder (Rev.A3, or any revision on the XC6SLX25) and the `#F4` board id register, and WC 1.09 or newer (plugin system `#10`).

`MEGABUZZ_EMU.WMF` is the same build without Megabuzz: it does not touch the ports, its FIFO is in software and drains at the stream rate, and the window title says `EMU`. It plays no sound; it is there to look at the UI, tags, time and keys on any TSConf host. Put it into `wc.ini` instead of `MEGABUZZ.WMF`.

## Keys

| Key | Action |
|---|---|
| `Space`, `Enter` | next track |
| `P`, `Backspace` | previous track |
| `←` / `→` | seek 10 s back / forward |
| `S` | pause |
| `+` / `-`, `↑` / `↓` | volume, 2 dB steps |
| `B` / `T` | bass / treble, cycling 0..7 (VS1053 chip only) |
| `Esc` | back to WC |

When a track ends the plugin moves on to the next file of the panel, after the last file it returns to WC. Volume and effects live in the Megabuzz registers and carry over from track to track.

## What it shows

- **File name**: the long name from WC.
- **ID3v2.2, 2.3 and 2.4 tags:** title, artist (or album artist), album, year, track number, genre (numeric ID3v1 genres become names). Encodings: UTF-16, UTF-8, and the single-byte one, taken as CP1251. Cyrillic is printed in CP866. Anything outside Cyrillic and ASCII becomes `?`. Cover art and other big frames are skipped without reading them.
- **Stream:** MPEG version, layer, bitrate (the average one for VBR), sample rate, channel mode.
- **Time and progress.** The VBR duration comes from the Xing/Info or VBRI header, for CBR it is worked out from the bitrate. Elapsed time is the file position minus what still sits in the FIFO, so it stays right after seeking.
- **Buf**: how full the decoder FIFO (4 KB) is.

## Limitations

- ID3v1 (at the end of the file) is not read: WC gives no way to reach the end of the file before playback starts.
- Minutes on screen stop at 99:59, seeking works for files up to 32 MB.
- MP3 only for now. The VS1053 chip also plays AAC, WAV, OGG and more, they can come later.
- No L/R peaks yet (the window keeps room for them), see item 6 in [BACKLOG.md](../../../BACKLOG.md).

## Building and tests

You need [sjasmplus](https://github.com/z00m128/sjasmplus):

```
make            # -> MEGABUZZ.WMF and MEGABUZZ_EMU.WMF
```

If `LOADNONE` (`#3D`) does not work on some WC version, build with `sjasmplus --inc=src -DNO_LOADNONE src/main.asm`: seeking and skipping cover art then go through plain reads, which is slower.

`make test` runs the plugin in a simulator (`test/wcsim.py`): the Z80 core from the [z80](https://github.com/kosarev/z80) package, an emulation of the WC API (windows, `LOAD512`, `GIPAGPL`, `LOADNONE`, keys, timer) and of the Megabuzz ports with a 4 KB FIFO that drains at the bitrate. The tests check tags and encodings, the stream that reaches the decoder, keys, seeking, exit codes, and the FIFO head-room on a slow SD card. It needs `ffmpeg` and Python with the `z80` and `mutagen` packages:

```
python3 -m venv venv && venv/bin/pip install z80 mutagen
make test PYTHON=venv/bin/python
```

The simulator does not replace a hardware check: colours, the WC font glyphs (`►`, `■`, `║`, `█`) and bus timing can only be checked on a real host.
