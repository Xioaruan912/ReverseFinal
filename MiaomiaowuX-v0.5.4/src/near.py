import struct, subprocess, bisect, json, sys
BIN='/root/mmwx/unpacked/mmwx-unpacked'
d=open(BIN,'rb').read()
TEXT_VA=0x401000; TEXT_OFF=0x1000; TEXT_SZ=0x3a7ffd1
f=json.load(open('/root/mmwx/gofuncs.json'))
srt=sorted((a,b,n) for n,(a,b) in f.items()); starts=[x[0] for x in srt]
def own(a):
    i=bisect.bisect_right(starts,a)-1
    return srt[i][2] if i>=0 and srt[i][0]<=a<srt[i][1] else None
def find_callers(target):
    res=[]
    for i in range(TEXT_OFF, TEXT_OFF+TEXT_SZ-5):
        if d[i]!=0xE8: continue
        rel=struct.unpack_from('<i', d, i+1)[0]
        a=TEXT_VA+(i-TEXT_OFF)
        if a+5+rel==target: res.append(a)
    return res
target=int(sys.argv[1],16)
back=int(sys.argv[2],0) if len(sys.argv)>2 else 0x300
fwd=int(sys.argv[3],0) if len(sys.argv)>3 else 0x80
for c in find_callers(target):
    print(f"\n### call site {hex(c)} in {own(c)}")
    out=subprocess.run(['objdump','-d',f'--start-address={c-back}',f'--stop-address={c+fwd}','-M','intel',BIN],
                       capture_output=True,text=True).stdout
    for line in out.splitlines():
        if '>:' in line: continue
        print("   ", line.rstrip())
