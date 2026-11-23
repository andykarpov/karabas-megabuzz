#!/bin/bash
# NeoGS ports testbench: VS1053 chip mode, then neorv32 mode (-DRV32)
set -e
cd "$(dirname "$0")"
SRC="ngs_tb.v gs.v ngs_mp3.v vs1053.v ../fifo/fifo.v ../sd/sd_arbiter.v ../sd/zc_dicmmc.v"
for mode in chip rv32; do
    DEF="-DSIMULATION"
    [ $mode = rv32 ] && DEF="$DEF -DRV32"
    iverilog -g2005 $DEF -s ngs_tb -o ngs_tb_$mode.out $SRC
    echo "== $mode"
    vvp -n ngs_tb_$mode.out | grep -v "^VCD"
done
