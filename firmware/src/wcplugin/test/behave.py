"""Behaviour checks: keys, seeking, exit codes, FIFO head-room."""
import sys
from wcsim import Sim
from run_tests import raw, tagged, row, TIT2

WMF = open(sys.argv[1], "rb").read()
cbr = raw("noise128.mp3")        # 95 s, 16000 B/s
c320 = raw("cbr320.mp3")
fails = 0


def t(name, cond, info=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + str(info)))
    fails += 0 if cond else 1


def prog(txt):
    return row(txt, "█") if "█" in txt else ""


# ESC in the middle: exit 0, sound stopped
s = Sim(WMF, cbr, drain_bps=16000, keys={100: "esc"})
code = s.run()
t("Esc -> exit 0", code == 0, code)
t("Esc resets the decoder", s.resets >= 2, s.resets)

# Space -> next (2), last file -> 0, BackSpace / P -> prev (4)
t("Space -> 2", Sim(WMF, cbr, keys={50: "space"}).run() == 2)
t("Space on the last file -> 0", Sim(WMF, cbr, index=3, count=3, keys={50: "space"}).run() == 0)
t("natural end on the last file -> 0", Sim(WMF, raw("mono22.mp3"), index=3, count=3, drain_bps=200000).run() == 0)
t("P -> 4", Sim(WMF, cbr, keys={50: "p"}).run() == 4)
t("BackSpace -> 4", Sim(WMF, cbr, keys={50: "bspc"}).run() == 4)

# real-time drain, pause, time display
s = Sim(WMF, cbr, drain_bps=16000, keys={600: "esc"}, )
s.run(snap_at=(510,))
line = s.line(s.snapshots[510], 11)
t("elapsed ~10 s after 500 frames", "00:09" in line or "00:10" in line, line)
t("no underrun at 128 kbps", s.underruns == 0, s.under_frames)

s = Sim(WMF, cbr, drain_bps=16000, keys={100: "s", 400: "s", 600: "esc"})
s.run(snap_at=(300, 590))
t("pause shows Paused", "Paused" in s.snapshots[300], row(s.snapshots[300], "Paused"))
p1 = row(s.snapshots[300], " 00:")
t("paused time stops near 2 s", "00:01" in p1 or "00:02" in p1, p1)
t("resume clears Paused", "Paused" not in s.snapshots[590])

# slow SD (40000 T per sector, ~180 KB/s) at 320 kbps
s = Sim(WMF, c320, drain_bps=40000, keys={1200: "esc"})
s.sector_cost = 40000
s.run()
t("no underrun at 320 kbps with slow SD", s.underruns == 0, s.under_frames)

# seek forward 3 x 10 s then back 10 s: position ~20 s
s = Sim(WMF, cbr, drain_bps=16000, keys={60: "right", 70: "right", 80: "right", 90: "left", 200: "esc"})
s.run(snap_at=(150,))
line = row(s.snapshots[150], " 00:")
t("seek -> about 0:23", any(x in line for x in ("00:22", "00:23", "00:24")), line)
# the stream after the last seek must be a copy of the file from some offset
idx = cbr.find(bytes(s.streams[-1][:2048]))
t("stream after seek is file data", idx > 0, idx)
t("seek target ~22 s (1.2 + 30 - 10)", abs(idx - 16000 * 22) < 16000 * 2, idx / 16000.0)

# seek back past the start, then forward to the end
s = Sim(WMF, cbr, drain_bps=16000, keys={60: "left", 100: "right", 110: "esc"})
s.run()
t("seek back at start rewinds to the first frame", s.log == [], s.log)

# volume and effects
s = Sim(WMF, cbr, keys={40: "up", 50: "up", 60: "up", 70: "-", 80: "b", 90: "t", 100: "t", 200: "esc"})
s.run(snap_at=(150,))
t("volume 8 -> 0 -> 4", s.vol == 4, s.vol)
t("bass 1 treble 2", s.fx == (2 << 3) | 1, hex(s.fx))
t("vol row shows -2dB", "-2dB" in row(s.snapshots[150], "Vol:"), row(s.snapshots[150], "Vol:"))

# neorv32: decoder name, bass/treble ignored
s = Sim(WMF, cbr, board_id=0x1A, keys={40: "b", 100: "esc"})
s.run(snap_at=(80,))
r = row(s.snapshots[80], "Decoder:")
t("neorv32 decoder shown", "neorv32" in r and "Bass: -" in r, r)
t("neorv32 fx untouched", s.fx == 0, s.fx)

# A3 with both decoders, config picks neorv32
s = Sim(WMF, cbr, board_id=0x3B, cfg1=0x08, keys={30: "esc"})
s.run(snap_at=(20,))
t("A3 cfg bit 3 -> neorv32", "neorv32" in row(s.snapshots[20], "Decoder:"))

# no decoder (SLX16 A2): say why, wait for a key, then not mine
def diag(name, expect, code, **kw):
    s = Sim(WMF, cbr, keys={10: "esc"}, **kw)
    r = s.run(snap_at=(5,))
    txt = s.snapshots[5]
    t(name + " -> exit %d" % code, r == code, r)
    t(name + " -> " + expect, expect in txt, txt)
    t(name + " -> waits for a key", s.frame >= 10, s.frame)
    return txt

diag("no decoder", "no MP3 decoder", 1, board_id=0x02)
diag("no board", "No answer", 1, no_board=True)
diag("firmware without #F4 (bus reads #FF)", "#F4): 14 MHz #FF", 1, board_id=0xFF)
diag("odd id", "Not a Megabuzz id", 1, board_id=0x55)
diag("all clocks read #FF", "14 MHz #FF, 7 MHz #FF, 3.5 MHz #FF", 1, board_id=0xFF)
txt = diag("F10, board right at 7 MHz only", "7 MHz #2B", 0, board_id=0x2B, call_type=3,
           clock_ids={2: 0xFF})
t("F10, 7 MHz only -> says so", "runs at 7 MHz" in txt and "#F4): 14 MHz #FF, 7 MHz #2B" in txt, txt)
txt = diag("F10, board right at 3.5 MHz only", "3.5 MHz #2B", 0, board_id=0x2B, call_type=3,
           clock_ids={2: 0xFF, 1: 0xFF})
t("F10, 3.5 MHz only -> says so", "runs at 3.5 MHz" in txt, txt)

# Enter, board right at 7 MHz only: plays at 7 MHz, no window
s = Sim(WMF, cbr, board_id=0x2B, clock_ids={2: 0xFF}, keys={60: "esc"})
r = s.run(snap_at=(30,))
t("7 MHz only: plays", r == 0 and "Decoder:" in s.snapshots[30], r)
t("7 MHz only: runs at 7 MHz", s.clock == 1, s.clock)

diag("F10 with VS1053", "VS1053 chip", 0, board_id=0x2B, call_type=3)
diag("F10 with neorv32", "neorv32", 0, board_id=0x1A, call_type=3)
diag("F10 without a board", "No answer", 0, no_board=True, call_type=3)
txt = diag("F10 shows the firmware id", "Firmware: A2 25 RV 2026-11-24 1a2b3c4", 0, board_id=0x1A,
           call_type=3, coreid=b"A2 25 RV 2026-11-24 1a2b3c4")
diag("F10 on firmware without the id", "Firmware: no id (reg #FF)", 0, board_id=0x1A, call_type=3)
diag("Shift+F3 without a board", "No answer", 0, no_board=True, call_type=4)

# Shift+F3 menu: plays like Enter
s = Sim(WMF, cbr, call_type=4, keys={40: "esc"})
r = s.run(snap_at=(30,))
t("Shift+F3 plays the file", r == 0 and "Decoder:" in s.snapshots[30] and s.resets >= 1, r)

# header: F10 + Shift+F3, menu text
t("header +197 = #05", WMF[197] == 0x05, WMF[197])
t("header +204 viewer text", WMF[204:228] == b"Play on Megabuzz".ljust(24), WMF[204:228])
t("header format #10", WMF[32] == 0x10, WMF[32])

t("config bytes never written", not any(l[0] == "cfg write!" for l in s.log))
print("fails:", fails)
sys.exit(1 if fails else 0)
