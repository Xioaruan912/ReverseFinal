import struct, sys, json

BIN = '/root/mmwx/unpacked/mmwx-unpacked'
d = open(BIN,'rb').read()

MAGICS = {0xfffffffb:'go1.2-1.15', 0xfffffffa:'go1.16-1.17', 0xfffffff0:'go1.18-1.19', 0xfffffff1:'go1.20+'}
hdr = None
for magic,name in MAGICS.items():
    off = d.find(struct.pack('<I', magic))
    if off >= 0:
        hdr = (off, name); break
assert hdr, "pclntab not found"
off, ver = hdr
print("pclntab magic at file offset", hex(off), "->", ver)

p = off
magic, pad, minLC, ptrSize = struct.unpack_from('<IBBB', d, p); p += 7
(nfunc, nfiles, textStart, funcnameOffset, cuOffset, filetabOffset, pctabOffset, pclnOffset) = struct.unpack_from('<QQQQQQQQ', d, p); p += 64
print(f"nfunc={nfunc} nfiles={nfiles} textStart={hex(textStart)} ptrSize={ptrSize}")

functab = p
fns = []
for i in range(nfunc):
    eo, fo = struct.unpack_from('<II', d, functab + i*8)
    fns.append((eo, fo))

# function name table base
ftab0 = functab
namebase = None
# In go1.18+, funcnametab offset is relative to the pclntab start? funcnameOffset is an absolute offset from the base of the module (textStart) per source: it's an offset from pclntab base actually.
# Empirically: funcnameOffset is relative to the start of the pclntab blob.
namebase = off + funcnameOffset

def funcname(funcoff):
    q = functab + 4*nfunc + funcoff          # _func structs region
    # _func: entryoff(uint32) nameoff(int32) args int32 deferreturn uint32 pcsp uint32 pcfile uint32 pcln uint32 npcdata uint32 ...
    eo, no = struct.unpack_from('<Ii', d, q)
    s = d.index(b'\x00', namebase + no)
    return d[namebase + no:s].decode('latin1')

out = {}
for i,(eo, fo) in enumerate(fns):
    try:
        nm = funcname(fo)
    except Exception:
        continue
    # end = next func entry (tab is sorted by entry)
    if i+1 < nfunc:
        end = textStart + fns[i+1][0]
    else:
        end = textStart + eo
    out[nm] = (textStart + eo, end)

print("resolved", len(out), "functions")
json.dump(out, open('/root/mmwx/funcs.json','w'))
kw = ['License','Premium','Pro','Entitlement','Quota','Guard','Feature']
for k in kw:
    hits = [n for n in out if k.lower() in n.lower()]
    print(f"\n### '{k}' -> {len(hits)}")
    for n in sorted(hits)[:40]:
        a,b = out[n]
        print(f"   {hex(a)}-{hex(b)} sz={b-a:<6} {n}")
