import struct, json, subprocess, bisect, re
BIN='/root/mmwx/unpacked/mmwx-unpacked'
d=open(BIN,'rb').read()
TEXT_VA=0x401000; TEXT_OFF=0x1000
f=json.load(open('/root/mmwx/gofuncs.json'))
srt=sorted((a,b,n) for n,(a,b) in f.items()); starts=[x[0] for x in srt]
def own(a):
    i=bisect.bisect_right(starts,a)-1
    return srt[i][2] if i>=0 and srt[i][0]<=a<srt[i][1] else None
def funcs_named(sub):
    return sorted(((a,b,n) for n,(a,b) in f.items() if sub in n))
for a,b,n in funcs_named('(*xGRYHwaSuI).ServeHTTP'):
    print(f"=== {n}  {hex(a)}-{hex(b)}  size={b-a}")
    out=subprocess.run(['objdump','-d',f'--start-address={a}',f'--stop-address={b}','-M','intel',BIN],
                       capture_output=True,text=True).stdout
    calls=[]
    for line in out.splitlines():
        m=re.search(r'call\s+([0-9a-f]+)\s+<', line) or re.search(r'call\s+([0-9a-f]+)\s*$', line.strip())
        if m:
            t=int(m.group(1),16)
            calls.append((t, own(t)))
    # print sequence compactly
    seq=[]
    for t,o in calls:
        seq.append(o or hex(t))
    print("  call sequence (%d):"%len(seq))
    for s in seq: print("    ", s)
    break
