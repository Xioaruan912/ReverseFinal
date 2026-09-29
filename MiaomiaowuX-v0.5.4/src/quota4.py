import json, subprocess, bisect, re, sys
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
pats=sys.argv[1:]
for n,(a,b) in sorted(f.items()):
    if any(p in n for p in pats):
        print(f"\n=== {n}  {hex(a)}-{hex(b)} size={b-a}")
        for t,o in calls_of(a,b):
            mark = ' ★' if o and any(k in o for k in ['License','Quota','Usage','Limit','bcrypt','Plan','Entitlement']) else ''
            print("    ", (o or hex(t)) + mark)
