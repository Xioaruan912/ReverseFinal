import struct, sys
sys.path.insert(0,'.')
from pe import PE
def funcs(path):
    p=PE(path)
    d=p.d
    sec=[s for s in p.secs if s['name']=='.pdata'][0]
    out=[]
    off=sec['raw']; n=sec['vsz']//12
    for i in range(n):
        b,e,u=struct.unpack_from('<III', d, off+i*12)
        if b==0: continue
        out.append((p.imgbase+b, p.imgbase+e))
    return p, sorted(out)
if __name__=='__main__':
    p,f=funcs(r'C:/Users/Administrator/Downloads/bc5-recon/extracted/BCompare.exe')
    print('functions:', len(f))
    for a in (0x1404f0900,0x1404f61f0,0x1404f65fc,0x1404f6160,0x1404f04ba):
        hit=[x for x in f if x[0]<=a<x[1]]
        print(hex(a), [(hex(s),hex(e),e-s) for s,e in hit])
