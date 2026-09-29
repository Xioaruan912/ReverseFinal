import sys, struct
sys.path.insert(0,'.')
from pe import PE
p=PE(r'C:/Users/Administrator/Downloads/bc5-recon/extracted/BCompare.exe')
d=p.d
KIND={0:'tkUnknown',1:'tkInteger',2:'tkChar',3:'tkEnumeration',4:'tkFloat',5:'tkString',6:'tkSet',7:'tkClass',8:'tkMethod',9:'tkWChar',10:'tkLString',11:'tkWString',12:'tkVariant',13:'tkArray',14:'tkRecord',15:'tkInterface',16:'tkInt64',17:'tkDynArray',18:'tkUString',19:'tkClassRef',20:'tkPointer',21:'tkProcedure'}
def off(va): return p.va2off(va)
def deref_pp(pp):
    o=off(pp)
    return struct.unpack_from('<Q', d, o)[0]
def shortstr(o):
    L=d[o]; return d[o+1:o+1+L].decode('latin1'), o+1+L
def tinfo(pp, depth=0, maxd=2):
    ind='  '*depth
    if pp is None: return ind+'(nil)'
    real=deref_pp(pp); o=off(real)
    if o is None: return ind+'bad ptr %#x'%real
    k=d[o]; nm,e=shortstr(o+1)
    s='%s%#x: kind=%d(%s) name=%r'%(ind,real,k,KIND.get(k,'?'),nm)
    if k==3:  # enumeration: OrdType(1) MinValue MaxValue BaseType(ptr)
        ordt=d[e]; mn=struct.unpack_from('<i',d,e+1)[0]; mx=struct.unpack_from('<i',d,e+5)[0]
        base=struct.unpack_from('<Q',d,e+9)[0]
        s+='  ordtype=%d min=%d max=%d base=%#x'%(ordt,mn,mx,base)
        o2=off(base)
        if o2 is not None:
            names=[]; 
            try:
                cnt=d[o2]; kk=d[o2+1]
                q=o2+2
                for i in range(cnt):
                    L=d[q]; names.append(d[q+1:q+1+L].decode('latin1')); q+=1+L
                s+='  ENUM='+', '.join('%d:%s'%(mn+i,n) for i,n in enumerate(names))
            except Exception as ex: s+=' enum parse fail %s'%ex
    elif k==14:  # record: RecSize(4) ? 
        sz=struct.unpack_from('<I',d,e)[0]
        s+='  RecSize=%#x'%sz
    elif k==7:   # class
        vt=struct.unpack_from('<Q',d,e)[0]; par=struct.unpack_from('<Q',d,e+8)[0]
        pc=struct.unpack_from('<h',d,e+16)[0]
        un,ue=shortstr(e+18)
        s+='  ClassType(VMT)=%#x parent=%#x PropCount=%d unit=%r'%(vt,par,pc,un)
    elif k in (1,16):
        ordt=d[e]; mn=struct.unpack_from('<i',d,e+1)[0]; mx=struct.unpack_from('<i',d,e+5)[0]
        s+=' ordtype=%d min=%d max=%d'%(ordt,mn,mx)
    elif k==4:
        ft=d[e]+1; s+=' floattype=%d'%ft
    elif k in (10,18,11):
        pass
    return s
if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    for pp in [int(x,16) for x in sys.argv[1:]]:
        print(tinfo(pp))
