#!/bin/sh
# MP3 decode benchmark for neorv32 in GHDL (prints mcycle per frame).
# usage: ./run.sh [file.mp3:nbytes:nframes ...]
#   env: EFFORT (default -Os), OUT (GHDL work dir, default lib), TB_GENERICS (e.g. "-gZBB=true"),
#        CFU=1 (build with the MAC CFU; nframes=0 runs only its self-test)
# needs /opt/xpack-riscv-none-elf-gcc-*, ghdl, python3
set -e
cd "$(dirname "$0")"
export PATH=$(ls -d /opt/xpack-riscv-none-elf-gcc-*/bin | tail -1):$PATH
T=../../test
[ $# -eq 0 ] && set -- $T/sweep.mp3:2400:8 $T/test.mp3:4400:7
OUT=${OUT:-lib}
: > mp3data.h
LIST=""
i=0
for a in "$@"; do
  f=${a%%:*}; r=${a#*:}; nb=${r%%:*}; nf=${r#*:}
  python3 -I mp3hdr.py $f mp3_$i $nb >> mp3data.h
  LIST="$LIST X(\"$(basename $f)\", mp3_$i, $nf)"
  i=$((i+1))
done
echo "#define BENCH_LIST$LIST" >> mp3data.h
make clean image EFFORT="${EFFORT:--Os}" CFU="${CFU:-0}"
[ "${CFU:-0}" = 1 ] && TB_GENERICS="$TB_GENERICS -gCFU=true"
CORE=../../rtl/core
rm -rf $OUT && mkdir $OUT
cp neorv32_imem_image.vhd main.elf $OUT/
FILES="$CORE/neorv32_package.vhd $OUT/neorv32_imem_image.vhd"
for f in $CORE/*.vhd; do
  case $(basename $f) in neorv32_package.vhd|neorv32_imem_image.vhd) ;; *) FILES="$FILES $f";; esac
done
ghdl -i --std=08 --work=neorv32 --workdir=$OUT $FILES
ghdl -i --std=08 --workdir=$OUT -P$OUT tb.vhd
ghdl -m --std=08 --workdir=$OUT -P$OUT tb
ghdl -r --std=08 --workdir=$OUT -P$OUT tb $TB_GENERICS --ieee-asserts=disable | grep --line-buffered -v assertion
