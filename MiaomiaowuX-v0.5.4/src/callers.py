import struct, json
BIN='/root/mmwx/unpacked/mmwx-unpacked'
d=open(BIN,'rb').read()
TEXT_VA=0x401000; TEXT_OFF=0x1000; TEXT_SZ=0x3a7ffd1
f=json.load(open('/root/mmwx/gofuncs.json'))
# invert: addr -> name
inv={}
for n,(a,b) in f.items():
    inv[a]=n

def find_callers(target, limit=200):
    res=[]
    end=TEXT_OFF+TEXT_SZ-5
    for i in range(TEXT_OFF, end):
        if d[i]!=0xE8: continue
        rel=struct.unpack_from('<i', d, i+1)[0]
        addr=TEXT_VA+(i-TEXT_OFF)
        if addr+5+rel==target:
            res.append(addr)
    return res

def owner(addr):
    best=None
    for a,b in f.values():
        if a<=addr<b and (best is None or a>best[0]): best=(a,b)
    return best
# build sorted list for fast owner lookup
srt=sorted((a,b,n) for n,(a,b) in f.items())
import bisect
starts=[x[0] for x in srt]
def own(addr):
    i=bisect.bisect_right(starts, addr)-1
    if i>=0 and srt[i][0]<=addr<srt[i][1]: return srt[i][2]
    return None

TARGETS={
 'HasFeature':0x17b4180,
 'HasFeatureForDataPlane':0x17b44a0,
 'CanUsePremiumTheme':0x17b2f40,
 'QuotaEnforced':0x17b3180,
 'EffectiveServerQuota':0x17b3280,
 'EffectiveUserQuota':0x17b3a20,
 'EffectiveNodeQuota':0x17b37c0,
 'EntitlementForFrontend':0x17b14a0,
}
out={}
for name,addr in TARGETS.items():
    c=find_callers(addr)
    owners=sorted(set(own(x) or hex(x) for x in c))
    out[name]=owners
    print(f"\n### {name} @ {hex(addr)} -> {len(c)} call sites, {len(owners)} distinct callers")
    for o in owners[:40]: print("    ", o)
json.dump(out, open('/root/mmwx/callers.json','w'), ensure_ascii=False, indent=1)
