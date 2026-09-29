import struct, re, json
exec(open('/mnt/c/Users/Administrator/Desktop/Reverse/Tool/mcp/mmwx-license-audit/scripts/gosym.py').read().split('mod = None')[0])

MOD_OFF = 0x7a4d0c0
print("moduledata at", hex(MOD_OFF), "va", hex(0x7e4d0c0))
p = MOD_OFF
pcHeader, = struct.unpack_from('<Q', d, p)
fnptr, fnlen, fncap = struct.unpack_from('<QQQ', d, p+8)
cuptr, culen, _ = struct.unpack_from('<QQQ', d, p+32)
ftptr, ftlen, ftcap = struct.unpack_from('<QQQ', d, p+128)
print(f"pcHeader={hex(pcHeader)} funcnametab={hex(fnptr)}/{hex(fnlen)} ftab={hex(ftptr)} len={ftlen} cap={ftcap}")
fn_off = va2off(fnptr); ft_off = va2off(ftptr)
print("funcnametab off", hex(fn_off), "ftab off", hex(ft_off))
print("names head:", d[fn_off:fn_off+80])
entries=[]
for i in range(ftlen):
    eo, fo = struct.unpack_from('<II', d, ft_off + i*8)
    entries.append((eo, fo))
print("first ftab entries:", [(hex(a),hex(b)) for a,b in entries[:5]])
funcs={}
for i,(eo,fo) in enumerate(entries):
    try:
        e2, no = struct.unpack_from('<Ii', d, ft_off + ftlen*8 + fo)
        p2 = fn_off + no
        e = d.index(b'\x00', p2)
        nm = d[p2:e].decode('latin1')
    except Exception:
        continue
    end = entries[i+1][0] if i+1 < len(entries) else eo
    funcs[nm]=(eo,end)
print("resolved", len(funcs), "functions")
json.dump({k:[v[0],v[1]] for k,v in funcs.items()}, open('/root/mmwx/gofuncs.json','w'))
print("sample:", list(funcs)[:5])
for k in ['License','Entitlement','Premium','Quota','Feature','guardclient']:
    h=sorted(x for x in funcs if k.lower() in x.lower())
    print(f"\n### {k} -> {len(h)}")
    for x in h[:26]:
        a,b=funcs[x]; print(f"   {hex(a)}-{hex(b)} sz={b-a:<6} {x}")
