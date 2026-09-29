import struct, json, subprocess, bisect, re
BIN='/root/mmwx/unpacked/mmwx-unpacked'
f=json.load(open('/root/mmwx/gofuncs.json'))
srt=sorted((a,b,n) for n,(a,b) in f.items()); starts=[x[0] for x in srt]
def own(a):
    i=bisect.bisect_right(starts,a)-1
    return srt[i][2] if i>=0 and srt[i][0]<=a<srt[i][1] else None
def calls_of(a,b):
    out=subprocess.run(['objdump','-d',f'--start-address={a}',f'--stop-address={b}','-M','intel',BIN],
                       capture_output=True,text=True).stdout
    res=[]
    for line in out.splitlines():
        parts=line.strip().split('\t')
        if len(parts)>=3 and parts[2].startswith('call'):
            m=re.search(r'call\s+([0-9a-f]+)', parts[2])
            if m:
                t=int(m.group(1),16); res.append((t, own(t)))
    return res
targets=[(a,b,n) for n,(a,b) in f.items() if n.startswith('JLKbOa2Pg.(*xGRYHwaSuI).ServeHTTP')]
targets.sort(key=lambda x:x[0])
print(f"# {len(targets)} ServeHTTP pieces")
import collections
for a,b,n in targets[:40]:
    cs=calls_of(a,b)
    interesting=[x for x in cs if x[1] and ('License' in x[1] or 'Quota' in x[1] or 'bcrypt' in x[1] or 'Usage' in x[1] or 'Count' in x[1] or 'Limit' in x[1])]
    if interesting:
        print(f"\n=== {n} {hex(a)}-{hex(b)}")
        for t,o in cs: print("    ", o or hex(t))
