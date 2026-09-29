import re, struct, sys, os

PID = sys.argv[1]
OUT = '/root/mmwx/dump/limit.bin'

# --- dump memory ---
maps = open(f'/proc/{PID}/maps').read().splitlines()
regions = []
for line in maps:
    p = line.split()
    if len(p) < 2 or 'r' not in p[1]:
        continue
    a, b = [int(x, 16) for x in p[0].split('-')]
    if b - a > 300 * 1024 * 1024:
        continue
    path = p[5] if len(p) > 5 else ''
    regions.append((a, b, path))
blob = bytearray()
layout = []
mem = open(f'/proc/{PID}/mem', 'rb', 0)
for a, b, path in regions:
    try:
        mem.seek(a); data = mem.read(b - a)
    except Exception:
        continue
    layout.append((len(blob), len(blob) + len(data), a, path))
    blob += data
mem.close()
open(OUT, 'wb').write(blob)
print(f"dumped {len(blob)//1024//1024} MB from pid {PID}")

def off2va(off):
    for s, e, base, path in layout:
        if s <= off < e:
            return base + (off - s), path
    return None, None

def va2off_in_blob(va):
    for s, e, base, path in layout:
        if base <= va < base + (e - s):
            return s + (va - base)
    return None

# --- find the error message ---
NEEDLES = ['已达到用户数量上限', '已达到服务器数量上限', '已达到节点数量上限', '请升级许可证']
for n in NEEDLES:
    nb = n.encode('utf-8')
    hits = [m.start() for m in re.finditer(re.escape(nb), blob)]
    print(f"\n### '{n}' -> {len(hits)} 命中")
    for h in hits[:5]:
        va, path = off2va(h)
        print(f"   blob_off={hex(h)} va={hex(va) if va else '-'} region={path}")
        if va:
            # look for {ptr,len} qword pairs pointing here
            p = struct.pack('<Q', va)
            refs = [m.start() for m in re.finditer(re.escape(p), blob)]
            print(f"    指向该字符串的 8 字节指针: {len(refs)}")
            for r in refs[:6]:
                rva, rpath = off2va(r)
                ln = struct.unpack_from('<Q', blob, r + 8)[0] if r + 16 <= len(blob) else 0
                print(f"      -> 全局变量 @ va={hex(rva) if rva else '-'} len字段={ln} region={rpath}")
