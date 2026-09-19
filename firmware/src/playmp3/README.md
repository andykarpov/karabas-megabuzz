# Karabas MegaBuzz MP3 player dot command for esxDOS

Play mp3 via Karabas Megabuzz with esxDOS dot-command!

## Usage

Just download binary file from releases page and put it into /BIN folder of your SD/CF card.

Remember it requires Karabas Megabuzz connected to your speccy. 

Execute `.playmp3` from your basic and see command line parameters. If specified file name - it tries to load it and play.

## Development

To compile project all you need is [sjasmplus](https://github.com/z00m128/sjasmplus).

I'm also using GNU Make but if you call sjasmplus for main.asm - it will build `PLAYMP3` binary.

## Credits

Credits goes to Alexander Nihirash!

