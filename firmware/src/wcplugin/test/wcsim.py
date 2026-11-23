"""Minimal Wild Commander + Karabas-MegaBuzz simulator for MEGABUZZ.WMF.

Runs the plugin on the z80 package, emulates the WC API calls it uses, the
ZXUNO register ports and a 4 KB decoder FIFO that drains at a given rate.
"""
import sys
import z80

WC_API = 0x6006
TMN = 0x6009
HEI = 0x600E
EXIT_PC = 0x5F00
FRAME = 280000          # T-states per frame at 14 MHz
SECTOR_COST = 3000      # T-states per 512-byte sector read (set per test)


class Sim:
    def __init__(self, wmf, data, name=b"test.mp3", index=1, count=3,
                 board_id=0x2B, cfg1=0x00, drain_bps=16000, keys=None,
                 hei=25, no_loadnone=False, no_board=False):
        self.m = z80.Z80Machine()
        self.data = data
        self.keys = keys or {}          # frame -> key name or char
        self.drain = drain_bps / 50.0
        self.board_id = board_id
        self.cfg = [0xFF, cfg1]
        self.cfga = 0
        self.zreg = 0xFF
        self.vol = 0x08
        self.fx = 0x00
        self.fifo = 0
        self.fifo_acc = 0.0
        self.sent = bytearray()          # bytes since the last reset
        self.streams = []
        self.reset_frame = 0
        self.resets = 0
        self.overflow = 0
        self.pos = 0
        self.frame = 0
        self.screen = [[' '] * 90 for _ in range(hei)]
        self.attr = [[0] * 90 for _ in range(hei)]
        self.last_span = None
        self.win = None
        self.calls = {}
        self.log = []
        self.no_loadnone = no_loadnone
        self.sector_cost = SECTOR_COST
        self.underruns = 0
        self.under_frames = []
        self.no_board = no_board
        self.cur_key = None
        self.snapshots = {}

        import random
        rnd = random.Random(1)
        mem = bytearray(0x10000)
        # WC loads only the code blocks: the rest of the page holds old data
        mem[0x8000:0xC000] = bytes(rnd.getrandbits(8) for _ in range(0x4000))
        code = wmf[512:]
        mem[0x8000:0x8000 + len(code)] = code
        mem[HEI] = hei
        self.m.set_memory_block(0, mem)
        self.wmf = wmf
        self.start(data, name, index, count)

    def start(self, data, name=b"test.mp3", index=1, count=3):
        """(Re)enter the plugin with a file, keeping the memory image."""
        self.data = data
        self.pos = 0
        mem = self.m.memory
        mem[0x7000:0x7000 + len(name) + 1] = name + b"\0"
        self.m.set_input_callback(self.port_in)
        self.m.set_output_callback(self.port_out)
        self.m.set_breakpoint(WC_API)
        self.m.set_breakpoint(EXIT_PC)
        size = len(data)
        m = self.m
        m.sp = 0x7F00
        self.push(EXIT_PC)
        m.pc = 0x8000
        m.a = 0
        m.hl = size & 0xFFFF
        m.de = size >> 16
        m.bc = 0x7000
        m.ix = 0x7100
        m.alt_de = count
        m.alt_hl = index
        m.iff1 = 1

    # -- helpers ----------------------------------------------------------
    def push(self, v):
        m = self.m
        m.sp = (m.sp - 2) & 0xFFFF
        m.memory[m.sp] = v & 0xFF
        m.memory[m.sp + 1] = v >> 8

    def pop(self):
        m = self.m
        v = m.memory[m.sp] | (m.memory[m.sp + 1] << 8)
        m.sp = (m.sp + 2) & 0xFFFF
        return v

    def setz(self, z):
        f = self.m.f
        self.m.f = (f | 0x40) if z else (f & ~0x40)

    # -- ports ------------------------------------------------------------
    def port_in(self, port):
        if port == 0xFD3B and not self.no_board:
            r = self.zreg
            if r == 0xF4:
                return self.board_id
            if r in (0xF5, 0xF6):
                full = 0x80 if self.fifo >= 4096 else 0
                return full | ((self.fifo >> 5) & 0x7F)
            if r == 0xF7:
                return self.cfg[self.cfga] if self.cfga < 2 else 0xFF
            if r == 0xFA:
                return self.cfga
            if r == 0xFB:
                return self.vol
            if r == 0xFC:
                return self.fx
        return 0xFF

    def port_out(self, port, value):
        if port == 0xFC3B:
            self.zreg = value
        elif port == 0xFD3B:
            r = self.zreg
            if r == 0xF5:
                if value & 0x80:
                    self.fifo = 0
                    self.streams.append(self.sent)
                    self.sent = bytearray()
                    self.reset_frame = self.frame
                    self.resets += 1
            elif r == 0xF6:
                if self.fifo >= 4096:
                    self.overflow += 1
                else:
                    self.fifo += 1
                    self.sent.append(value)
            elif r == 0xFA:
                self.cfga = value
            elif r == 0xF7:
                self.log.append(("cfg write!", value))
            elif r == 0xFB:
                self.vol = value
            elif r == 0xFC:
                self.fx = value
        else:
            self.log.append(("out", hex(port), value))

    # -- WC API -----------------------------------------------------------
    def win_xy(self, ix):
        mem = self.m.memory
        return mem[ix + 2], mem[ix + 3], mem[ix + 4], mem[ix + 5]

    def put(self, y, x, text):
        for i, ch in enumerate(text):
            if 0 <= y < len(self.screen) and 0 <= x + i < 90:
                self.screen[y][x + i] = ch

    def api(self):
        m = self.m
        fn = m.a
        self.calls[fn] = self.calls.get(fn, 0) + 1
        mem = m.memory
        cost = 200
        if fn == 0x01:                      # PRWOW
            self.prwow_frame = self.frame
            x, y, w, h = self.win_xy(m.ix)
            self.win = (x, y, w, h)
            self.put(y, x, '+' + '-' * (w - 2) + '+')
            for r in range(1, h - 1):
                self.put(y + r, x, '|' + ' ' * (w - 2) + '|')
            self.put(y + h - 1, x, '+' + '-' * (w - 2) + '+')
        elif fn == 0x02:                    # RRESB
            pass
        elif fn == 0x03:                    # PRSRW
            x, y, w, h = self.win_xy(m.ix)
            n = m.bc
            assert 0x8000 <= m.hl < 0xC000, hex(m.hl)
            assert m.e + n <= w and m.d < h, ("PRSRW out of window", m.d, m.e, n)
            raw = bytes(mem[m.hl:m.hl + n])
            self.put(y + m.d, x + m.e, raw.decode('cp866').replace('\x10', '>'))
            self.last_span = (y + m.d, x + m.e, n)
        elif fn == 0x04:                    # PRIAT: A' = colour
            yy, xx, n = self.last_span
            for i in range(n):
                if xx + i < 90:
                    self.attr[yy][xx + i] = self.m.alt_a
        elif fn in (0x0E, 0x0F):
            pass
        elif 0x10 <= fn <= 0x29:            # key tests
            names = {0x10: 'space', 0x11: 'up', 0x12: 'down', 0x13: 'left',
                     0x14: 'right', 0x16: 'enter', 0x17: 'esc', 0x18: 'bspc'}
            self.setz(self.cur_key != names.get(fn))
            if self.cur_key == names.get(fn):
                self.cur_key = None
        elif fn == 0x2A:                    # KBSCN
            k = self.cur_key
            if k is not None and len(k) == 1:
                m.a = ord(k)
                self.setz(False)
                self.cur_key = None
            else:
                m.a = 0xFF
                self.setz(True)
        elif fn == 0x2E:                    # USPO
            pass
        elif fn == 0x30:                    # LOAD512
            n = m.b
            dst = m.hl
            assert 0x8000 <= dst and dst + n * 512 <= 0x10000
            chunk = self.data[self.pos:self.pos + n * 512]
            chunk = chunk + bytes(n * 512 - len(chunk))
            mem[dst:dst + n * 512] = chunk
            self.pos += n * 512
            m.hl = dst + n * 512
            m.a = 0x0F if self.pos >= len(self.data) else 0
            cost = n * self.sector_cost
        elif fn == 0x32:                    # GIPAGPL
            self.pos = 0
        elif fn == 0x3D:                    # LOADNONE
            assert not self.no_loadnone
            self.pos += m.b * 512
            cost = m.b * 50
        else:
            raise RuntimeError("unexpected WC call %02X" % fn)
        # WC clobbers these
        m.bc = 0xDEAD
        if fn not in (0x30,):
            m.hl = 0xBEEF
        m.de = 0xCAFE
        m.ix = 0x1234
        m.pc = self.pop()
        return cost

    # -- run ----------------------------------------------------------------
    def new_frame(self):
        self.frame += 1
        mem = self.m.memory
        t = (mem[TMN] | mem[TMN + 1] << 8) + 1
        mem[TMN] = t & 0xFF
        mem[TMN + 1] = (t >> 8) & 0xFF
        self.fifo_acc += self.drain
        d = int(self.fifo_acc)
        self.fifo_acc -= d
        if self.fifo > 0 and self.fifo - d <= 0 and self.pos < len(self.data) \
                and self.frame > self.reset_frame + 3:
            self.underruns += 1
            self.under_frames.append((self.frame, self.pos))
        self.fifo = max(0, self.fifo - d)
        if self.frame in self.keys:
            self.cur_key = self.keys[self.frame]
        if self.frame in self.snap_at:
            self.snapshots[self.frame] = self.text()

    def run(self, max_frames=100000, snap_at=()):
        self.snap_at = set(snap_at)
        m = self.m
        budget = FRAME
        while self.frame < max_frames:
            m.ticks_to_stop = budget
            ev = m.run()
            if ev & m._BREAKPOINT_HIT:
                left = m.ticks_to_stop
                if m.pc == EXIT_PC:
                    return m.a
                cost = self.api()
                left -= cost
                while left <= 0:
                    self.new_frame()
                    left += FRAME
                budget = left
                continue
            self.new_frame()
            budget = FRAME
        raise RuntimeError("no exit after %d frames" % max_frames)

    def line(self, txt, y):
        return txt.split("\n")[self.win[1] + y] if self.win else ""

    def attr_at(self, y, x):
        return self.attr[self.win[1] + y][self.win[0] + x]

    def text(self):
        return "\n".join("".join(r).rstrip() for r in self.screen)


if __name__ == "__main__":
    wmf = open(sys.argv[1], "rb").read()
    data = open(sys.argv[2], "rb").read()
    s = Sim(wmf, data)
    code = s.run()
    print("exit", code, "frames", s.frame, "sent", len(s.sent))
    print(s.text())
