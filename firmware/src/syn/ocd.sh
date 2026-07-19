#!/bin/sh

sudo openocd -f ocd.cfg -c "init;\
jtagspi_init 0 bscan_spi_xc6slx25.bit;\
jtagspi_program work25/karabas_megabuzz_a2.bin 0;\
jtagspi_program ../rtl/sound/gs105b.rom 0x100000;\
jtagspi_program cfg1.rom 0x1F0000;\
xc6s_program xc6s.tap;\
exit"

