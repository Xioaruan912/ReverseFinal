import struct
d = open("exports/nsis_solid_stream.bin", "rb").read(0x2000)
hdr = d
print("==== region 0xA80 - 0xC00 raw ====")
for i in range(0xA80, 0xC00, 16):
    row = hdr[i:i+16]
    print(f"{i:06x}  {row.hex(' '):<47} " + ''.join(chr(c) if 32 <= c < 127 else '.' for c in row))

print("\n==== as dwords from 0xA84 with stride 28, showing idx,off,size,b,text flags,timelo,timehi ====")
for k in range(8):
    o = 0xA84 + k * 28
    v = struct.unpack_from('<7I', hdr, o)
    print(f"rec{k} @{o:#x}: " + " ".join(f"{x:#010x}" for x in v))

print("\n==== try to detect file entry table: search header for 8-byte FILETIME-ish patterns ====")
import re
cnt = 0
o = 0
while o < 21690 - 8:
    lo, hi = struct.unpack_from('<II', hdr, o)
    if 0xD0000000 <= hi <= 0xE0000000 and (lo & 0xFFFF) != 0:
        cnt += 1
    o += 1
print("possible high-dword filetime count:", cnt)
