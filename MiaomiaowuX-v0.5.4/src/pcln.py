import struct, re, json, sys

BIN='/root/mmwx/unpacked/mmwx-unpacked'
d=open(BIN,'rb').read(); n=len(d)

def parse(off):
    p=off
    magic,pad1,pad2,minLC,ptrSize=struct.unpack_from('<IBBBB',d,p)
    if minLC not in (1,2,4) or ptrSize not in (4,8): return None
    q=p+8
    (nfunc,nfiles,textStart,funcnameOffset,cuOffset,filetabOffset,pctabOffset,pclnOffset)=struct.unpack_from('<QQQQQQQQ',d,q)
    if not (1000 < nfunc < 1000000): return None
    if not (0 < nfiles < 500000): return None
    if not (0x400000 <= textStart < 0x20000000): return None
    # sanity: functab+nfunc*8 within file
    ftab=q+64
    if ftab+8*nfunc > n: return None
    # sanity: first function should be runtime.text
    try:
        eo,fo=struct.unpack_from('<II',d,ftab)
        fptr=ftab+4*nfunc+fo
        e2,no=struct.unpack_from('<Ii',d,fptr)
        s=d.index(b'\x00', off+funcnameOffset+no)
        nm=d[off+funcnameOffset+no:s].decode('latin1')
    except Exception as e:
        return None
    if not nm.startswith('runtime.'): return None
    return dict(off=off,ptrSize=ptrSize,nfunc=nfunc,nfiles=nfiles,textStart=textStart,
                funcnameOffset=funcnameOffset,cuOffset=cuOffset,filetabOffset=filetabOffset,
                pctabOffset=pctabOffset,pclnOffset=pclnOffset,ftab=ftab,firstname=nm)

cands=[]
for magic in (0xfffffff1,0xfffffff0):
    for m in re.finditer(re.escape(struct.pack('<I',magic)), d):
        r=parse(m.start())
        if r: cands.append(r)
print("valid pclntab candidates:", len(cands))
for c in cands[:5]: print("  ", {k:(hex(v) if isinstance(v,int) else v) for k,v in c.items()})
if cands:
    c=cands[0]
    ftab=c['ftab']; nfunc=c['nfunc']; off=c['off']; nb=off+c['funcnameOffset']; ts=c['textStart']
    def fname(funcoff):
        fptr=ftab+4*nfunc+funcoff
        e2,no=struct.unpack_from('<Ii',d,fptr)
        s=d.index(b'\x00',nb+no)
        return d[nb+no:s].decode('latin1')
    funcs={}
    entries=[]
    for i in range(nfunc):
        eo,fo=struct.unpack_from('<II',d,ftab+i*8)
        entries.append((ts+eo,fo))
    for i,(ea,fo) in enumerate(entries):
        try: nm=fname(fo)
        except Exception: continue
        end = entries[i+1][0] if i+1<nfunc else ea
        funcs[nm]=(ea,end)
    print("resolved", len(funcs), "funcs")
    json.dump({k:[v[0],v[1]] for k,v in funcs.items()}, open('/root/mmwx/funcs.json','w'))
    for k in ['License','Entitlement','Premium','Quota','Feature','guardclient']:
        hits=sorted(x for x in funcs if k.lower() in x.lower())
        print(f"\n### {k} -> {len(hits)}")
        for x in hits[:30]:
            a,b=funcs[x]; print(f"   {hex(a)}-{hex(b)} sz={b-a:<7} {x}")
