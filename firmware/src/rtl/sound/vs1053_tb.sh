#!/bin/bash

rm vs1053_sim.out
rm vs1053_sim.vcd

iverilog -DSIMULATION -o vs1053_sim.out vs1053_tb.v vs1053.v
vvp vs1053_sim.out
gtkwave vs1053_tb.gtkw

