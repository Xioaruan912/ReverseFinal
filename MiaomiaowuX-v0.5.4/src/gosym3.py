import struct, re, json
BIN='/root/mmwx/unpacked/mmwx-unpacked'
d=open(BIN,'rb').read()
def va2off(v):
    if 0x400000 <= v < 0x400000+0x3a80fd1: return v-0x400000
    if 0x3e81000 <= v < 0x3e81000+0x3fcb750: return v-0x3e81000+0x3a81000
    if 0x7e4d000 <= v < 0x7e4d000+0x428840: return v-0x7e4d000+0x7a4d000
    return None
M=0x7a4d0c0
def s(i, n): return struct.unpack_from('<'+'Q'*n, d, M+i)
pcHeader, = s(0,1)
fnptr,fnlen,_ = s(8,3)
ftptr,ftlen,_ = s(128,3)
plptr,pllen,_ = s(104,3)
text, = s(176,1)
etext, = s(184,1)
print(f"pcHeader={hex(pcHeader)} funcnametab={hex(fnptr)}+{hex(fnlen)} pclntable={hex(plptr)}+{hex(pllen)} ftab={hex(ftptr)} len={ftlen} text={hex(text)} etext={hex(etext)}")
fn_off=va2off(fnptr); pl_off=va2off(plptr); ft_off=va2off(ftptr)
print("offsets:", hex(fn_off), hex(pl_off), hex(ft_off))
funcs={}
ents=[]
for i in range(ftlen):
    eo, fo = struct.unpack_from('<II', d, ft_off+i*8)
    ents.append((eo,fo))
def name_at(fo):
    eo2, no = struct.unpack_from('<Ii', d, pl_off+fo)
    p = fn_off + no
    if not (fn_off <= p < fn_off+fnlen): return None
    e = d.index(b'\x00', p)
    return d[p:e].decode('latin1')
good=0; bad=0
for i,(eo,fo) in enumerate(ents):
    nm = name_at(fo)
    if nm is None: bad+=1; continue
    good+=1
    end = ents[i+1][0] if i+1 < len(ents) else etext-text
    funcs[nm]=(text+eo, text+end)
print(f"names ok={good} bad={bad}")
print("sample:", list(funcs)[:4])
json.dump({k:[v[0],v[1]] for k,v in funcs.items()}, open('/root/mmwx/gofuncs.json','w'))
for k in ['License','Entitlement','HasFeature','Premium','Quota','ActionGuard','guard']:
    h=sorted(x for x in funcs if k.lower() in x.lower())
    print(f"\n### {k} -> {len(h)}")
    for x in h[:22]:
        a,b=funcs[x]; print(f"   {hex(a)}-{hex(b)} sz={b-a:<6} {x}")
