## Karabas-MegaBuzz

Simple FPGA based sound card for ZX Spectrum (NemoBus). 
Inspired by a ZX-Multisound and karabas-opl3 soundcards :)

[![photo](docs/karabas-megabuzz_revA2_top.png)](docs/karabas-megabuzz_revA2_top.png?raw=true)

[![photo](docs/karabas-megabuzz_revA2_bottom.png)](docs/karabas-megabuzz_revA2_bottom.png?raw=true)

### Tech specs

* Turbosound FM
* General Sound 2 MB
* OPL3 sound by YMF-262-M
* MIDI by Dream SAM2695
* SAA1099
* Soundrive, Covox + Beeper
* 16-bit DAC PCM5102
* XC6SLX16 / XC6SLX25 FPGA
* SD Card by Z-Controller / DivMMC (since rev.A1)
* Low profile PCB: 92x44mm
* 5V only power required

### Changelog & current status [ERRATA](ERRATA.md)

* Rev.A - initial release

* Rev.A1 - intermediate revision

    * [x] Added SD card
    * [x] Changed OPL3 chip power to 3v3 rail, reset controlled by FPGA
    * [x] Added NMI button
    * [x] Added SD LED
    * [x] Added PSRAM chip
    * [x] Added new signals to grab and emit on nemobus (NMI, ROMCS)
    * [x] Added ability to pass sound out via nemobus slot

* Rev.A2 - current revision

    * [x] Removed DIP switches
    * [x] Added 128kB SRAM chip for DivMMC
    * [x] Added 8kb EEPROM chip to store configuration

* Rev.A3 - current dev version

    * [x] Added VS1053 IC


### How-to & Documentation

Please [read the manual](HOWTO.md) how to flash your card with alt tools, like Altera Usb Blaster + openocd.

Some links to the documentation files:

* revA: [Schematics](docs/karabas-megabuzz-revA.pdf), [interactive BOM](docs/karabas-megabuzz-revA-ibom.html)
* revA1: [Schematics](docs/karabas-megabuzz-revA1.pdf), [interactive BOM](docs/karabas-megabuzz-revA1-ibom.html)
* revA2: [Schematics](docs/karabas-megabuzz-revA2.pdf), [interactive BOM](docs/karabas-megabuzz-revA2-ibom.html)
* revA3: [Schematics](docs/karabas-megabuzz-revA3.pdf), [interactive BOM](docs/karabas-megabuzz-revA3-ibom.html)


### Related projects

* Karabas-OPL3 - [link](https://github.com/andykarpov/karabas-opl3)
* BomgeMoon - [link](https://github.com/Kulicheg/BomgeMoon)
* ZX-Multisound - [link](https://github.com/UzixLS/zx-multisound)
* Turbo Sound FM - [link](http://www.nedopc.com/TURBOSOUND/ts-fm.php)
* ZXM-SoundCard - [link](http://micklab.ru/My%20Soundcard/ZXMSoundCard.htm)
* ZXM-GeneralSound - [link](http://micklab.ru/My%20Soundcard/ZXMGeneralSound.htm)
* NeoGS - [link](http://www.nedopc.com/gs/ngs.php)
