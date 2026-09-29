import struct, json, re

BIN='/root/mmwx/unpacked/mmwx-unpacked'
d=open(BIN,'rb').read()
n=len(d)
MAGICS=[(0xfffffff1,'go1.20+'),(0xfffffff0,'go1.18-1.19'),(0xfffffffa,'go1.16-1.17')]

cands=[]
for magic,ver in MAGICS:
    pat=struct.pack('<I',magic)
    for m in re.finditer(re.escape(pat), d):
        off=m.start()
        if off+72>n: continue
        p=off
        _m,_pad,minLC,ptrSize=struct.unpack_from('<IBBB',d,p)
        if minLC not in (1,2,4) or ptrSize not in (4,8): continue
        q=p+8
        (nfunc,nfiles,textStart,funcnameOffset,cuOffset,filetabOffset,pctabOffset,pclnOffset)=struct.unpack_from('<QQQQQQQQ',d,q)
        if not (10 < nfunc < 600000): continue
        if not (0 < nfiles < 200000): continue
        if not (0x400000 <= textStart < 0x10000000): continue
        cands.append((off,ver,ptrSize,nfunc,nfiles,textStart,funcnameOffset,cuOffset,filetabOffset,pctabOffset,pclnOffset))
        print(f"  candidate off={hex(off)} {ver} ptrSize={ptrSize} nfunc={nfunc} nfiles={nfiles} textStart={hex(textStart)} nameOff={hex(funcnameOffset)} pclnOff={hex(pclnOffset)}")

print("total candidates:", len(cands))
json.dump(cands, open('/root/mmwx/pclntab_cands.json','w'))
