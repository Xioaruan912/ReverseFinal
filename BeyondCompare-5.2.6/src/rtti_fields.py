import sys, struct
sys.path.insert(0,'.')
from pe import PE
p=PE(r'C:/Users/Administrator/Downloads/bc5-recon/extracted/BCompare.exe')
d=p.d
def typename(pp):
    o=p.va2off(pp)
    if o is None: return 'bad@%x'%pp
    real=struct.unpack_from('<Q', d, o)[0]
    o2=p.va2off(real)
    if o2 is None: return 'noptr@%x'%real
    k=d[o2]; L=d[o2+1]
    if not (0<L<40): return 'kind%02x/%d'%(k,L)
    nm=d[o2+2:o2+2+L]
    try: s=nm.decode('ascii')
    except: return 'kind%02x??'%k
    return 'k%-2d %s'%(k,s)
def run(start, maxn=200):
    o=start; out=[]
    for i in range(maxn):
        L=d[o]
        if not (0<L<64): break
        nm=d[o+1:o+1+L]
        if any(c<32 or c>126 for c in nm): break
        tr=o+1+L
        ptr=struct.unpack_from('<Q', d, tr+3)[0]
        off=struct.unpack_from('<I', d, tr+11)[0]
        if not (p.imgbase+0x1000 <= ptr < p.imgbase+0x2000000): break
        out.append((p.off2va(o), nm.decode(), off, ptr))
        o=tr+15
    return out
best=None
for s in range(0x4edb00, 0x4ede60):
    r=run(s)
    if best is None or len(r)>len(best[1]): best=(s,r)
s,r=best
print('best table start off=%#x va=%#x entries=%d'%(s,p.off2va(s),len(r)))
prev=-1
for i,(va,nm,off,ptr) in enumerate(r):
    print('%3d %-22s off=%#7x  %s'%(i,nm,off,typename(ptr)))
