#!/bin/sh
# End-to-end test of rtl/mp3dec/rv_vs1053.vhd in GHDL: builds the real firmware (sw/src/mp3dec) and plays
# file.mp3 through the bridge. Prints the PCM checksum per frame, compare with ./run.sh on the same file.
# usage: ./run_rv.sh [file.mp3 [nbytes [frames]]]    env: OUT (GHDL work dir, default lib_rv)
set -e
cd "$(dirname "$0")"
export PATH=$(ls -d /opt/xpack-riscv-none-elf-gcc-*/bin | tail -1):$PATH
MP3=${1:-st320.mp3}; NBYTES=${2:-4300}; FRAMES=${3:-2}
OUT=${OUT:-lib_rv}
BENCH=$PWD
make -C ../src/mp3dec clean bin SIM=1 > /dev/null
rm -rf $OUT && mkdir $OUT
python3 -I - ../src/mp3dec/neorv32_raw_exe.bin $OUT/fw.hex $MP3 $NBYTES $OUT/mp3.hex <<'EOF'
import sys
fw, fwhex, mp3, n, mp3hex = sys.argv[1:]
def dump(data, path):
    with open(path, 'w') as f:
        f.write(''.join('%02x\n' % b for b in data))
dump(open(fw, 'rb').read(), fwhex)
dump(open(mp3, 'rb').read()[:int(n)], mp3hex)
EOF
CORE=../../rtl/core
FILES="$CORE/neorv32_package.vhd"
for f in $CORE/*.vhd; do
  case $(basename $f) in neorv32_package.vhd) ;; *) FILES="$FILES $f";; esac
done
ghdl -i --std=08 --work=neorv32 --workdir=$OUT $FILES
ghdl -i --std=08 --workdir=$OUT -P$OUT ../../rtl/mp3dec/rv_vs1053.vhd tb_rv.vhd
ghdl -m --std=08 --workdir=$OUT -P$OUT tb_rv
ghdl -r --std=08 --workdir=$OUT -P$OUT tb_rv -gFW_HEX=$OUT/fw.hex -gMP3_HEX=$OUT/mp3.hex -gFRAMES=$FRAMES --ieee-asserts=disable | grep --line-buffered -v assertion
