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

# no decoder (SLX16 A2): not mine
t("no decoder -> exit 1", Sim(WMF, cbr, board_id=0x02).run() == 1)
t("no board -> exit 1", Sim(WMF, cbr, no_board=True).run() == 1)
t("firmware without #F4 (bus reads #FF) -> exit 1", Sim(WMF, cbr, board_id=0xFF).run() == 1)

t("config bytes never written", not any(l[0] == "cfg write!" for l in s.log))
print("fails:", fails)
sys.exit(1 if fails else 0)
