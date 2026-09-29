import struct
d=open('/root/mmwx/unpacked/mmwx-unpacked','rb').read()
(e_type,e_machine,e_version,e_entry,e_phoff,e_shoff,e_flags,e_ehsize,e_phentsize,e_phnum,e_shentsize,e_shnum,e_shstrndx)=struct.unpack_from('<HHIQQQIHHHHHH', d, 16)
print(f"shoff={hex(e_shoff)} shnum={e_shnum} shstrndx={e_shstrndx} entsize={e_shentsize}")
secs=[]
for i in range(e_shnum):
    o=e_shoff+i*e_shentsize
    name,typ,flags,addr,off,size,link,info,align,entsize=struct.unpack_from('<IIQQQQIIQQ',d,o)
    secs.append((name,typ,flags,addr,off,size))
shstr=secs[e_shstrndx]
def sname(n):
    p=shstr[4]+n
    e=d.index(b'\x00',p)
    return d[p:e].decode()
print(f"{'name':22s} {'vaddr':>12s} {'off':>12s} {'size':>12s}")
for (n,t,f,a,o,s) in secs:
    print(f"{sname(n):22s} {hex(a):>12s} {hex(o):>12s} {hex(s):>12s}")
