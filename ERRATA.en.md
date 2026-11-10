English | [Русский](ERRATA.md)

### revA:
----

1. Initial reset of the OPL3.

The OPL3 chip needs a reset while it has a clock.
The host starts faster than the megabuzz board, so the chip is not reset at startup and has garbage in its registers.
The result is some gurgling from the OPL3 chip until the host is reset once more.

2. The reset signal in ZX-Evolution is too short: the OPL3 chip does not manage to reset on F12.

The solution of both problems: do not connect the /RST signal of the OPL3 chip to ZX-BUS, and control it from the FPGA instead.
Generate the reset signal for the OPL3 (and for the MIDI chip as well) at least 2.7 us long.

Note: these points about the /RST signal are fixed in the latest updates of the schematics and Gerbers of revA from 2026-06-04.
Only the initial revision of the revA board needs modification.
If you ordered one of the first revA boards, to fix this problem lift the /RST leg of the OPL3 chip and wire it to TP1.
As the chip is on one side of the board and TP1 on the other, it is suggested to pass the wire through one of the unused pins of the JTAG connector, leaving that pin unsoldered.

3. 5 V signals from the OPL3 to the FPGA currently go by a simplified circuit through dropping resistors.
How long the FPGA will last like this is unclear.
It was decided in revision A1 to power the OPL3 chip from 3.3 V (unofficially, this is reported to work).
And accordingly to route the data bus signals from the 3.3 V data bus.
This is done in rev.A1, tested and works well.

### RevA1:

1. The ROM blocking signals are routed incorrectly
- cut the signal from A25 of the NemoBus slot
- connect A15 and B4 to the place the signal to A25 came from

2. LED1 is not connected to the FPGA
- no hotfix (not important: if it does not light up, so be it)

(In the master branch of the project from 2026-06-17 the corresponding fixes are already made on the revA1 board.)

### RevA2:

- no bugs in the schematics or layout have been found so far.

### RevA3:

- no pulldowns on GPIO0, GPIO1 of the VS1053 chip. As a hotfix, just solder them to ground (there is a ground leg nearby).
- no pullup on RX of the VS1053. Hotfix: pull it up to the nearest 3.3 V
- the fixes are needed only on boards made before 2026-09-23.

(In the master branch of the project from 2026-09-23 the corresponding fixes are already made on the revA3 board.)

### Host reset output (`oRST`), revA1, revA2, revA3:

Starting with the firmware from 2026-11-09 the board does not reset the host, the `oRST` line is always in high impedance. The reasons:

- through the diode on revA1 and revA2 there was no real logic zero, which was not enough for clones on CPLDs with CMOS levels;
- the initial reset got in the way of computers that start their own service on a reset (Pentadiv, for example).

The diode D18 (revA1, revA2) and the transistor Q1 (revA3) are no longer needed and can be left unsoldered. There is no need to remove those already soldered: with the new firmware they have no effect.

After power-up, press reset or NMI once so that DivMMC is picked up and esxDOS initializes.
