import struct, re
d=open('/root/mmwx/unpacked/mmwx-unpacked','rb').read(); n=len(d)
for magic in (0xfffffff1,0xfffffff0):
    pat=struct.pack('<I',magic)
    offs=[m.start() for m in re.finditer(re.escape(pat), d)][:4]
    for off in offs:
        print(f"\nmagic {hex(magic)} at {hex(off)}")
        b=d[off:off+72]
        print("  hex:", b.hex())
        print("  u64:", [hex(x) for x in struct.unpack_from('<9Q', d, off)])
