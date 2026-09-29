import re, sys

d = open("exports/nsis_solid_stream.bin", "rb").read()
hdr = d[:21690]

def regions(name, start, end, step=16):
    print(f"\n########## {name}  [{start:#x}..{end:#x}] ##########")
    for i in range(start, min(end, start + 0x600), step):
        row = hdr[i:i+step]
        hexs = row.hex(' ')
        asc = ''.join(chr(c) if 32 <= c < 127 else ('.' if c else '.') for c in row)
        print(f"{i:06x}  {hexs:<47}  {asc}")

regions("head", 0, 0x100)
regions("blockB1", 0x12C, 0x180)
regions("blockB2", 0x26C, 0x2C0)
regions("blockB3", 0xA84, 0xB00)
regions("blockB4", 0x3890, 0x3900)
regions("blockB5", 0x5348, 0x5390)
regions("blockB6", 0x5472, 0x54BA + 0x40)

print("\n===== UTF-16 strings >=3 with offsets (all) =====")
ss = [(m.start(), m.group().decode('utf-16le', 'ignore')) for m in re.finditer(rb'(?:[\x20-\x7e]\x00){3,}', hdr)]
print("count", len(ss))
for off, s in ss:
    print(f"{off:6d}  {s}")
