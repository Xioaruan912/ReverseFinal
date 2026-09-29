import re
f = open("exports/nsis_solid_stream.bin", "rb")
import os
size = os.path.getsize("exports/nsis_solid_stream.bin")
print("stream size", size, hex(size))
f.seek(0)
head = f.read(1 << 20)
print("MZ at 21690?", head[21690:21692])
# find first MZ
buf = open("exports/nsis_solid_stream.bin", "rb").read(40 << 20)
idx = buf.find(b'MZ')
print("first MZ overall:", idx)
pos = 0
found = []
while True:
    i = buf.find(b'MZ', pos)
    if i < 0 or len(found) > 40:
        break
    # validate PE
    if i + 0x40 < len(buf):
        pe = int.from_bytes(buf[i+0x3c:i+0x40], 'little')
        if 0 < pe < 0x400 and buf[i+pe:i+pe+4] == b'PE\x00\x00':
            found.append(i)
    pos = i + 1
print("valid PE offsets(<=40MB):", found[:40])
print("deltas:", [found[i+1]-found[i] for i in range(len(found)-1)][:30])
