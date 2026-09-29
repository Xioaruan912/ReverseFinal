import struct, subprocess, bisect, json, sys
BIN='/root/mmwx/unpacked/mmwx-unpacked'
d=open(BIN,'rb').read()
TEXT_VA=0x401000; TEXT_OFF=0x1000; TEXT_SZ=0x3a7ffd1
f=json.load(open('/root/mmwx/gofuncs.json'))
srt=sorted((a,b,n) for n,(a,b) in f.items()); starts=[x[0] for x in srt]
def own(a):
    i=bisect.bisect_right(starts,a)-1
    return srt[i][2] if i>=0 and srt[i][0]<=a<srt[i][1] else None
def callers_in(t, lo, hi):
    r=[]
    for i in range(lo-0x400000+TEXT_OFF, hi-0x400000+TEXT_OFF-5):
        if d[i]!=0xE8: continue
        rel=struct.unpack_from('<i', d, i+1)[0]
        a=TEXT_VA+(i-TEXT_OFF)
        if a+5+rel==t and lo<=a<hi: r.append(a)
    return r
for name,(lo,hi) in [('(*FX0hJe7Qj).CreateRemoteServer',(0x285a940,0x286a520)),
                     ('(*GJSopcS).fFezoBa',(0x2c2d260,0x2c36340))]:
    cs=callers_in(0x17b27c0, lo, hi)
    print(f"\n###### {name}  GetStatus 调用点: {[hex(c) for c in cs]}")
    for c in cs:
        print(f"--- around {hex(c)} ---")
        out=subprocess.run(['objdump','-d',f'--start-address={c-0x30}',f'--stop-address={c+0x120}','-M','intel',BIN],
                           capture_output=True,text=True).stdout
        for line in out.splitlines():
            if '>:' in line or 'Disassembly' in line or 'file format' in line or not line.strip(): continue
            print("   ", line.rstrip())
