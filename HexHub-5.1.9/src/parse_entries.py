import struct, re, datetime

d = open("exports/nsis_solid_stream.bin", "rb").read()
hdr = d[:21690]

pat = b"\x90\x00\x00\x05"
pos = [m.start() for m in re.finditer(re.escape(pat), hdr)]
print("occurrences of 90 00 00 05 in header:", len(pos))
print("first 20:", [hex(p) for p in pos[:20]])
if len(pos) > 2:
    print("strides:", [pos[i+1]-pos[i] for i in range(min(20, len(pos)-1))])

# assume record = 28 bytes starting at pos-4
if len(pos) > 5:
    starts = [p-4 for p in pos]
    print("\n=== parsed candidate entries ===")
    prev_off = None
    bad = 0
    for i, s in enumerate(starts[:200]):
        if s+28 > len(hdr):
            break
        f = struct.unpack_from('<7I', hdr, s)
        off = f[3]
        if prev_off is not None and off < prev_off:
            bad += 1
        prev_off = off
        if i < 25 or i > len(starts)-6:
            print(f"idx{i:3d} @{s:#07x}: f0={f[0]:#010x} f1={f[1]:#010x} name={f[2]:5d} off={off:12d} (0x{off:x}) f4={f[4]:#010x} f5={f[5]:#010x} f6={f[6]:#010x}")
    print("non-monotonic count:", bad, "total entries:", len(starts))
