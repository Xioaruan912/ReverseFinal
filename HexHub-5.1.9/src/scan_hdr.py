import re
d = open("exports/nsis_solid_stream.bin", "rb").read(400000)
hdr = d[:21690]
print("=== UTF-16LE strings in header[0:21690] ===")
ss = [(m.start(), m.group().decode('utf-16le', 'ignore')) for m in re.finditer(rb'(?:[\x20-\x7e]\x00){3,}', hdr)]
print("count", len(ss))
for off, s in ss[:300]:
    print(f"{off:6d}  {s}")
print("\n=== raw hex 0x00-0x120 ===")
for i in range(0, 0x140, 16):
    row = hdr[i:i+16]
    print(f"{i:06x}  {row.hex(' '):<47} " + ''.join(chr(c) if 32 <= c < 127 else '.' for c in row))
