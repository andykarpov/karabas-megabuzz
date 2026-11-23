#!/bin/sh
# Make the MP3 streams the tests use (needs ffmpeg with libmp3lame)
set -e
cd "$(dirname "$0")"
mkdir -p work
cd work
mk() { out=$1; shift; [ -f "$out" ] || ffmpeg -loglevel error -y "$@" -id3v2_version 0 "$out"; }
mk cbr128.mp3   -f lavfi -i "sine=frequency=440:duration=95"  -ac 2 -ar 44100 -c:a libmp3lame -b:a 128k -write_xing 0
mk noise128.mp3 -f lavfi -i "anoisesrc=d=95:c=pink:a=0.3"     -ac 2 -ar 44100 -c:a libmp3lame -b:a 128k -write_xing 0
mk vbr.mp3      -f lavfi -i "sine=frequency=330:duration=200" -ac 2 -ar 44100 -c:a libmp3lame -q:a 2
mk mono22.mp3   -f lavfi -i "sine=frequency=550:duration=40"  -ac 1 -ar 22050 -c:a libmp3lame -b:a 32k -write_xing 0
mk cbr320.mp3   -f lavfi -i "sine=frequency=550:duration=30"  -ac 2 -ar 48000 -c:a libmp3lame -b:a 320k -write_xing 0
[ -f cover.jpg ] || head -c 300000 /dev/urandom > cover.jpg
