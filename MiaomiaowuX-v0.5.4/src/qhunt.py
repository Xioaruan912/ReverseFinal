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
# find CountLicensed* addresses
targets={}
for n,(a,b) in f.items():
    if n.startswith('VLgBxN.(*CjOdSUIBHq4).CountLicensed') and '.func' not in n:
        targets[n]=a
targets['JLKbOa2Pg.wFeRoafTxm']=0x2acb6a0
targets['IWPMOgYs4.(*BcGS_j).GetStatus']=0x17b27c0
for n,a in sorted(targets.items()):
    cs=sorted(set(own(x) for x in callers(a)))
    print(f"\n### {n} @ {hex(a)}  调用方 {len(cs)}")
    for c in cs: print("    ", c)
