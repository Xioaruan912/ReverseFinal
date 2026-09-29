import struct
d=open('/root/mmwx/unpacked/mmwx-unpacked','rb').read()
(e_type,e_machine,e_version,e_entry,e_phoff,e_shoff,e_flags,e_ehsize,e_phentsize,e_phnum,e_shentsize,e_shnum,e_shstrndx)=struct.unpack_from('<HHIQQQIHHHHHH', d, 16)
print(f"entry={hex(e_entry)} phoff={e_phoff} phnum={e_phnum} shnum={e_shnum}")
segs=[]
for i in range(e_phnum):
    o=e_phoff+i*e_phentsize
    p_type,p_flags,p_offset,p_vaddr,p_paddr,p_filesz,p_memsz,p_align=struct.unpack_from('<IIQQQQQQ',d,o)
    print(f"[{i}] type={p_type} flags={p_flags:#x} off={hex(p_offset)} vaddr={hex(p_vaddr)} filesz={hex(p_filesz)} memsz={hex(p_memsz)}")
    if p_type==1: segs.append((p_offset,p_vaddr,p_filesz))
def va2off(va):
    for o,v,sz in segs:
        if v<=va<v+sz: return o+(va-v)
    return None
def off2va(off):
    for o,v,sz in segs:
        if o<=off<o+sz: return v+(off-o)
    return None
print("size", hex(len(d)))
# find the start of the funcnametab: first dense ascii region
import re
print("\n=== candidate funcnametab start ===")
for probe in [b'runtime.text\x00', b'main.main\x00']:
    offs=[m.start() for m in re.finditer(re.escape(probe), d)][:5]
    print(probe, [hex(x) for x in offs])
# scan for dense ascii run start
best=None
i=0x2000000
while i < 0x7000000 and best is None:
    if d[i-1]==0 and 32<=d[i]<127:
        # count printable fraction in next 4096 bytes
        seg=d[i:i+4096]
        frac=sum(1 for c in seg if 32<=c<127 or c==0)/len(seg)
        if frac>0.9:
            # verify 300 nul-terminated strings
            p=i; ok=0
            for _ in range(300):
                e=d.find(b'\x00',p)
                if e<0 or e-p<1 or e-p>200: break
                s=d[p:e]
                if all(32<=c<127 for c in s): ok+=1
                p=e+1
            if ok>290:
                best=i; break
    i+=1
print("funcnametab start =", hex(best) if best else None, "va =", hex(off2va(best)) if best else None)
