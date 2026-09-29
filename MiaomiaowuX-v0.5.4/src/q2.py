import struct, json, bisect
BIN='/root/mmwx/unpacked/mmwx-unpacked'
d=open(BIN,'rb').read()
TEXT_VA=0x401000; TEXT_OFF=0x1000; TEXT_SZ=0x3a7ffd1
f=json.load(open('/root/mmwx/gofuncs.json'))
srt=sorted((a,b,n) for n,(a,b) in f.items()); starts=[x[0] for x in srt]
def own(a):
    i=bisect.bisect_right(starts,a)-1
    return srt[i][2] if i>=0 and srt[i][0]<=a<srt[i][1] else None
def callers(t):
    r=[]
    for i in range(TEXT_OFF, TEXT_OFF+TEXT_SZ-5):
        if d[i]!=0xE8: continue
        rel=struct.unpack_from('<i', d, i+1)[0]
        a=TEXT_VA+(i-TEXT_OFF)
        if a+5+rel==t: r.append(a)
    return r
import sys
for n,(a,b) in sorted(f.items(), key=lambda x:x[1][0]):
    if any(k in n for k in ['CreateRemoteServer','fFezoBa','yqkjNzz7','wFeRoafTxm','GetUsage']) and '.func' not in n:
        print(f"{hex(a)}-{hex(b)} sz={b-a:<6} {n}")
        for c in sorted(set(own(x) or hex(x) for x in callers(a))):
            print(f"      caller: {c}")
