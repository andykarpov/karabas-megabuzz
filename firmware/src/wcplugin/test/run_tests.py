"""Build tagged test files and check MEGABUZZ.WMF on them in the simulator."""
import io
import os
import struct
import sys

from mutagen.id3 import (ID3, TIT2, TPE1, TALB, TYER, TDRC, TRCK, TCON,
                         APIC, TPE2)
from wcsim import Sim

HERE = os.path.dirname(os.path.abspath(__file__))
MP3 = os.path.join(HERE, "work")
WMF = sys.argv[1]


def raw(name):
    return open(os.path.join(MP3, name), "rb").read()


def tagged(stream, frames, v2_version=3, padding=256):
    t = ID3()
    for f in frames:
        t.add(f)
    buf = io.BytesIO()
    t.save(buf, v2_version=v2_version, padding=lambda info: padding)
    return buf.getvalue() + stream


def syncsafe(n):
    return bytes([(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F])


def v22(stream):
    def fr(fid, text):
        body = b"\x00" + text
        return fid + struct.pack(">I", len(body))[1:] + body
    body = fr(b"TT2", b"Old tag title") + fr(b"TP1", b"Old artist") + \
        fr(b"TCO", b"(17)") + bytes(20)
    return b"ID3\x02\x00\x00" + syncsafe(len(body)) + body + stream


def unsync23(stream):
    # v2.3 tag-level unsync; the title contains 0xFF bytes (cp1251 'я')
    def fr(fid, payload):
        return fid + struct.pack(">I", len(payload)) + b"\0\0" + payload
    body = fr(b"TIT2", b"\x00" + "Моя песня я".encode("cp1251")) + \
        fr(b"APIC", b"\x00image/jpeg\x00\x03\x00" + b"\xff\xe0" * 3000) + \
        fr(b"TPE1", b"\x00" + "Ёжик".encode("cp1251"))
    out = bytearray()
    for i, b in enumerate(body):
        out.append(b)
        nxt = body[i + 1] if i + 1 < len(body) else 0
        if b == 0xFF and (nxt == 0 or nxt >= 0xE0):
            out.append(0)
    out += bytes(10)
    return b"ID3\x03\x00\x80" + syncsafe(len(out)) + bytes(out) + stream


def junk_front(stream):
    # garbage with fake syncs before the first real frame
    return b"\xff\xfb\x10\x00" + b"\x00\xff\xe3" * 200 + stream


def audio_start(data):
    if data[:3] == b"ID3":
        s = data[6:10]
        n = (s[0] << 21) | (s[1] << 14) | (s[2] << 7) | s[3]
        return 10 + n
    return 0




def row(text, label):
    for line in text.splitlines():
        if label in line:
            return line
    return ""


CASES = []


def case(name, data, expect, **kw):
    CASES.append((name, data, expect, kw))


cbr = raw("cbr128.mp3")
vbr = raw("vbr.mp3")
mono = raw("mono22.mp3")
c320 = raw("cbr320.mp3")

case("v2.3 UTF-16 cyrillic, APIC 300 KB, genre (17)",
     tagged(cbr, [TIT2(encoding=1, text="Группа крови"),
                  TPE1(encoding=1, text="Кино"),
                  TALB(encoding=1, text="Группа крови"),
                  TYER(encoding=1, text="1988"),
                  TRCK(encoding=1, text="1/11"),
                  TCON(encoding=1, text="(17)"),
                  APIC(encoding=0, mime="image/jpeg", type=3, desc="",
                       data=raw("cover.jpg"))]),
     {"Title:": "Группа крови", "Artist:": "Кино", "Album:": "Группа крови",
      "Year:": "1988", "Track:": "1/11", "Genre:": "Rock",
      "MPEG": "MPEG-1 Layer III  128 kbps CBR  44.1 kHz  Joint Stereo"})

case("v2.4 UTF-8, TDRC, VBR Xing",
     tagged(vbr, [TIT2(encoding=3, text="Ёлка — новогодняя"),
                  TPE1(encoding=3, text="Ансамбль «Тест»"),
                  TALB(encoding=3, text="Ünïcode Latin"),
                  TDRC(encoding=3, text="2001-05-01"),
                  TCON(encoding=3, text="Electronic")], v2_version=4),
     {"Title:": "Ёлка - новогодняя", "Artist:": "Ансамбль ?Тест?",
      "Album:": "?n?code Latin", "Year:": "2001", "Genre:": "Electronic",
      "MPEG": "VBR  44.1 kHz"})

case("v2.3 latin-1 frames holding CP1251, TPE2 only",
     tagged(mono, [TIT2(encoding=0, text="Привет, мир".encode("cp1251").decode("latin1")),
                   TPE2(encoding=0, text="Album Artist"),
                   TCON(encoding=0, text="(20)Indie")]),
     {"Title:": "Привет, мир", "Artist:": "Album Artist", "Genre:": "Indie",
      "MPEG": "MPEG-2 Layer III  32 kbps CBR  22.05 kHz  Mono"})

case("v2.2 tag", v22(c320),
     {"Title:": "Old tag title", "Artist:": "Old artist", "Genre:": "Rock",
      "MPEG": "MPEG-1 Layer III  320 kbps CBR  48 kHz"})

case("v2.3 tag-level unsync", unsync23(cbr),
     {"Title:": "Моя песня я", "Artist:": "Ёжик"})

case("no tag", cbr, {"Title:": "(no ID3v2 tag)",
                     "MPEG": "MPEG-1 Layer III  128 kbps CBR"})

case("very long title is cut",
     tagged(cbr, [TIT2(encoding=1, text="A" * 70)]),
     {"Title:": "A" * 52 + "~"})

case("junk before the first frame", junk_front(cbr),
     {"MPEG": "MPEG-1 Layer III  128 kbps CBR  44.1 kHz"}, start=4 + 600)

case("not audio at all", bytes(range(256)) * 64,
     {"MPEG": "No MPEG audio frames found"})


def check(name, data, expect, kw):
    forced_start = kw.pop("start", None)
    sim = Sim(open(WMF, "rb").read(), data, name=b"\x8f\xe0\xa8\xa2\xa5\xe2.mp3",
              drain_bps=kw.pop("drain", 200000), **kw)
    code = sim.run(snap_at=(30,))
    txt = sim.text()
    ok = True
    msgs = []
    for label, want in expect.items():
        line = row(txt, label)
        if want not in line:
            ok = False
            msgs.append("  %s: want %r in %r" % (label, want, line.strip()))
    # stream check: what reached the FIFO must be the audio from the frame on
    start = forced_start if forced_start is not None else audio_start(data)
    if bytes(sim.sent) != data[start:]:
        ok = False
        msgs.append("  stream: sent %d bytes, want %d from %d (resets %d)" % (
            len(sim.sent), len(data) - start, start, sim.resets))
    if sim.overflow:
        ok = False
        msgs.append("  FIFO overflow x%d" % sim.overflow)
    if code != 2:
        ok = False
        msgs.append("  exit code %d" % code)
    print(("PASS " if ok else "FAIL ") + name + "  [window at frame %d, %d frames total]" % (sim.prwow_frame, sim.frame))
    for msg in msgs:
        print(msg)
    if not ok:
        print(txt)
    return ok, sim, txt


if __name__ == "__main__":
    results = [check(*c) for c in CASES]
    passed = sum(r[0] for r in results)
    print("%d/%d passed" % (passed, len(results)))
    print(results[0][2])
    sys.exit(0 if passed == len(results) else 1)
