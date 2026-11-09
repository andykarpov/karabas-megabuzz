import sys, subprocess, bisect, collections
# usage: prof.py <main.elf> <prof.txt> [nm]  -> per-function share of sampled fetch addresses
elf, prof = sys.argv[1], sys.argv[2]
nm = sys.argv[3] if len(sys.argv) > 3 else 'riscv-none-elf-nm'
syms = []
for ln in subprocess.run([nm, '-n', elf], capture_output=True, text=True).stdout.splitlines():
    p = ln.split()
    if len(p) == 3 and p[1] in 'tTwW':
        syms.append((int(p[0], 16), p[2]))
addrs = [a for a, _ in syms]
cnt = collections.Counter()
total = 0
for ln in open(prof):
    a = int(ln, 16)
    i = bisect.bisect_right(addrs, a) - 1
    cnt[syms[i][1] if i >= 0 else '?'] += 1
    total += 1
for name, c in cnt.most_common(25):
    print(f"{100.0*c/total:6.2f}%  {name}")
