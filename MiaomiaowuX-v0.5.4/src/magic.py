import struct, re
d=open('/root/mmwx/unpacked/mmwx-unpacked','rb').read()
print("size", hex(len(d)))
for m in (0xfffffffb,0xfffffffa,0xfffffff0,0xfffffff1):
    pat=struct.pack('<I',m)
    offs=[x.start() for x in re.finditer(re.escape(pat), d)]
    print(f"magic {hex(m)} -> {len(offs)} hits, first: {[hex(o) for o in offs[:6]]}")
# look for the go build version string
for kw in [b'go1.2', b'go1.24', b'go1.23']:
    m=d.find(kw)
    print(kw, hex(m) if m>=0 else None, d[m:m+40] if m>=0 else '')
