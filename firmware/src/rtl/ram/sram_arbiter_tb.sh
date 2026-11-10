#!/bin/sh
# Simulation of sram_arbiter: random GS and host accesses against an SRAM model with real timing.
set -e
cd "$(dirname "$0")"
OUT=${OUT:-/tmp/sram_arbiter_tb.vvp}
iverilog -g2012 -o "$OUT" sram_arbiter.v sram_arbiter_tb.v
vvp "$OUT"
