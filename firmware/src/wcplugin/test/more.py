"""Seeking through rewind, v2.4 frame flags, screen height, SD speed."""
import struct, sys
from wcsim import Sim
from run_tests import raw, row, syncsafe
WMF = open(sys.argv[1], "rb").read()
noise = raw("noise128.mp3")
c320 = raw("cbr320.mp3")
fails = 0
def t(name, cond, info=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + str(info)))
    fails += 0 if cond else 1

# far back seek: right x6 (to ~61 s) then left x4 (~21+ s)
keys = {60 + i * 5: "right" for i in range(6)}
keys.update({100 + i * 5: "left" for i in range(4)})
keys[200] = "esc"
s = Sim(WMF, noise, drain_bps=16000, keys=keys)
s.run()
idx = noise.find(bytes(s.streams[-1][:2048]))
t("back seek via rewind lands ~21 s", abs(idx - 16000 * 22) < 16000 * 3, idx / 16000)
t("GIPAGPL used for it", s.calls.get(0x32, 0) >= 2, s.calls)

# seek past the end, then the track ends by itself
s = Sim(WMF, noise, drain_bps=16000, keys={60 + i * 3: "right" for i in range(12)})
code = s.run()
t("seek past end -> plays out, exit 2", code == 2, code)

# v2.4 with per-frame unsync + data length indicator on TIT2
def fr4(fid, payload, flags=0):
    return fid + syncsafe(len(payload)) + b"\0" + bytes([flags]) + payload
title = "яяя".encode("cp1251")          # FF FF FF in cp1251
data = b"\x00" + title
uns = bytearray()
for i, b in enumerate(data):
    uns.append(b)
    if b == 0xFF:
        uns.append(0)
pl = syncsafe(len(data)) + bytes(uns)
body = fr4(b"TIT2", pl, 0x03) + fr4(b"TPE1", b"\x03" + "Тест".encode()) + bytes(16)
tag = b"ID3\x04\x00\x00" + syncsafe(len(body)) + body
s = Sim(WMF, tag + noise, drain_bps=400000)
s.run()
txt = s.text()
t("v2.4 frame unsync + DLI", "яяя" in row(txt, "Title:"), row(txt, "Title:"))
t("v2.4 next frame after it", "Тест" in row(txt, "Artist:"), row(txt, "Artist:"))
t("v2.4 stream starts after tag", bytes(s.sent) == noise, len(s.sent))

# 36-line screen
s = Sim(WMF, noise, hei=36, keys={20: "esc"})
s.run()
t("HEI 36 (90x36) centres the window", s.win[:2] == (13, 9), s.win)
s = Sim(WMF, noise, hei=30, keys={20: "esc"})
s.run()
t("HEI 30 (80x30) centres the window", s.win[:2] == (8, 6), s.win)

# SD speed threshold at 320 kbps
for cost in (60000, 80000, 100000, 120000):
    s = Sim(WMF, c320, drain_bps=40000, keys={600: "esc"})
    s.sector_cost = cost
    s.run()
    t("320 kbps with SD at %.0f KB/s: no underrun" % (14e6 / cost / 2),
      s.underruns == 0, s.under_frames)
# colours of the parts of the window
s = Sim(WMF, tag + noise, keys={60: "esc"})
s.run(snap_at=(40,))
cols = {"title bar": (0, 20, 0xF7), "label File:": (1, 2, 0x71), "value file": (1, 10, 0x7E),
        "label Decoder:": (9, 2, 0x71), "decoder name": (9, 11, 0x7E), "time": (11, 4, 0x70),
        "progress bar": (11, 10, 0x71), "keys": (16, 1, 0x70), "separator": (2, 5, 0x7F)}
for what, (y, x, want) in cols.items():
    got = s.attr_at(y, x)
    t("colour of %s is %02X" % (what, want), got == want, "%02X" % got)

# two tracks in a row in one memory image: tagged, then untagged
s = Sim(WMF, tag + noise, drain_bps=400000)
t("first run ends with next", s.run() == 2)
s.start(noise, name=b"second.mp3", index=2, count=3)
s.screen = [[' '] * 90 for _ in range(25)]
t("second run ends with next", s.run() == 2)
txt = s.text()
t("second run: no stale title", "(no ID3v2 tag)" in row(txt, "Title:"), row(txt, "Title:"))
t("second run: no stale artist", row(txt, "Artist:").strip(" |") == "Artist:", row(txt, "Artist:"))
t("second run: file name", "second.mp3" in row(txt, "File:"), row(txt, "File:"))
t("second run: whole stream", bytes(s.sent) == noise, len(s.sent))

# EMU build: no board at all, the UI still runs and the track plays out
if len(sys.argv) > 2:
    E = open(sys.argv[2], "rb").read()
    s = Sim(E, noise, no_board=True)
    code = s.run(snap_at=(300,))
    t("EMU: plays out without a board, exit 2", code == 2, code)
    t("EMU: no port writes", not any(l[0] == "out" for l in s.log), s.log[:3])
    t("EMU: shows EMU in the title", "EMU" in s.text().split("\n")[s.win[1]])
    line = s.line(s.snapshots[300], 11)
    t("EMU: time runs at the stream rate (~6 s at frame 300)",
      any(x in line for x in ("00:05", "00:06")), line)
    t("EMU: frames until the end ~ duration", 95 * 50 - 100 < s.frame < 95 * 50 + 200, s.frame)
print("fails:", fails)
sys.exit(1 if fails else 0)
