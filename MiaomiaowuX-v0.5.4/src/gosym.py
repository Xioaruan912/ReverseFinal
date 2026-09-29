import struct, re, json

BIN='/root/mmwx/unpacked/mmwx-unpacked'
d=open(BIN,'rb').read(); n=len(d)
PCLN_OFF=0x582b7a0; PCLN_VA=0x5c2b7a0
def off2va(o): return 0x400000 + (o - 0x0) if o < 0x3a81000 else 0x3e81000 + (o-0x3a81000)
def va2off(v):
    if 0x400000 <= v < 0x400000+0x3a80fd1: return v-0x400000
    if 0x3e81000 <= v < 0x3e81000+0x3fcb750: return v-0x3e81000+0x3a81000
    if 0x7e4d000 <= v < 0x7e4d000+0x428840: return v-0x7e4d000+0x7a4d000
    return None
print("va2off(0x5c2b7a0) =", hex(va2off(0x5c2b7a0)))
# find moduledata: pointer to pcHeader VA in noptrdata/data
needle = struct.pack('<Q', PCLN_VA)
hits=[m.start() for m in re.finditer(re.escape(needle), d)]
print("ptr-to-pcHeader occurrences:", [hex(h) for h in hits][:10])
mod = None
for h in hits:
    if not (0x7a4d000 <= h <= 0x8260000): continue
    # moduledata begins with pcHeader ptr
    if h+200 < n:
        ftab_ptr, ftab_len, ftab_cap = struct.unpack_from('<QQQ', d, h+128)
        if ftab_len > 1000 and va2off(ftab_ptr) is not None:
            mod = (h, ftab_ptr, ftab_len, ftab_cap); break
print("moduledata candidates found:", bool(mod))
if not mod:
    raise SystemExit("moduledata not found")

mod_off, ftab_ptr, ftab_len, ftab_cap = mod
print(f"moduledata file off = {hex(mod_off)} va = {hex(off2va(mod_off))}")
print(f"ftab ptr={hex(ftab_ptr)} len={ftab_len} cap={ftab_cap}")
fnptr, fnlen, fncap = struct.unpack_from('<QQQ', d, mod_off+8)
print(f"funcnametab ptr={hex(fnptr)} len={hex(fnlen)}")
fn_off = va2off(fnptr)
print("funcnametab file off =", hex(fn_off))
print("first names:", d[fn_off:fn_off+120])

ft_off = va2off(ftab_ptr)
funcs={}
entries=[]
for i in range(ftab_len):
    eo, fo = struct.unpack_from('<II', d, ft_off + i*8)
    entries.append((eo, fo, eo))
# resolve names
ok=0
for i,(eo,fo,_) in enumerate(entries):
    try:
        e2, no = struct.unpack_from('<Ii', d, ft_off + ftab_len*8 + fo)
        p = fn_off + no
        e = d.index(b'\x00', p)
        nm = d[p:e].decode('latin1')
        ok+=1
    except Exception:
        continue
    end = entries[i+1][2] if i+1 < len(entries) else eo
    funcs[nm] = (eo, end)
print("resolved", ok, "names; sample:", list(funcs.items())[:3])
json.dump({k:[v[0],v[1]] for k,v in funcs.items()}, open('/root/mmwx/gofuncs.json','w'))
for k in ['License','Entitlement','Premium','Quota','Feature']:
    h=sorted(x for x in funcs if k.lower() in x.lower())
    print(f"\n### {k} -> {len(h)}")
    for x in h[:30]:
        a,b=funcs[x]; print(f"   {hex(a)} - {hex(b)}  sz={b-a:<6} {x}")
