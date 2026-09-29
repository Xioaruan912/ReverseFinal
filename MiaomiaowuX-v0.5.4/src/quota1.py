import struct, json, bisect
d=open('/root/mmwx/unpacked/mmwx-unpacked','rb').read()
TEXT_VA=0x401000; TEXT_OFF=0x1000; TEXT_SZ=0x3a7ffd1
f=json.load(open('/root/mmwx/gofuncs.json'))
srt=sorted((a,b,n) for n,(a,b) in f.items()); starts=[x[0] for x in srt]
def own(a):
    i=bisect.bisect_right(starts,a)-1
    return srt[i][2] if i>=0 and srt[i][0]<=a<srt[i][1] else None
def callers(target):
    res=[]
    for i in range(TEXT_OFF, TEXT_OFF+TEXT_SZ-5):
        if d[i]!=0xE8: continue
        rel=struct.unpack_from('<i', d, i+1)[0]
        a=TEXT_VA+(i-TEXT_OFF)
        if a+5+rel==target: res.append(a)
    return res
def addr_of(sub):
    return [(n,a,b) for n,(a,b) in f.items() if sub.lower() in n.lower()]
for pat in ['bcrypt.GenerateFromPassword','bcrypt.CompareHashAndPassword']:
    for n,a,b in addr_of(pat):
        if n.count('.')>0 and 'GenerateFromPassword' in n and not n.endswith('.func'):
            cs=sorted(set(own(x) for x in callers(a)))
            print(f"\n### {n} @ {hex(a)}  callers={len(cs)}")
            for c in cs[:20]: print("    ", c)
print("\n### name search: user create handlers")
for n,a,b in sorted(f.items()):
    if 'CreateUser' in n or 'AddUser' in n or 'RegisterUser' in n:
        print(f"   {hex(a)}-{hex(b)} {n}")
