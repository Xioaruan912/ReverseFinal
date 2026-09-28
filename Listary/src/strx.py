import sys, re
def strings(data, minlen=5, wide=False):
    out=[]
    if wide:
        pat = re.compile((b'(?:[\x20-\x7e]\x00){%d,}'%minlen))
        for m in pat.finditer(data):
            out.append((m.start(), m.group().decode('utf-16-le','replace')))
    else:
        pat = re.compile((rb'[\x20-\x7e]{%d,}'%minlen))
        for m in pat.finditer(data):
            out.append((m.start(), m.group().decode('latin1')))
    return out
if __name__=='__main__':
    path=sys.argv[1]; minlen=int(sys.argv[2]) if len(sys.argv)>2 else 5
    pat=sys.argv[3] if len(sys.argv)>3 else None
    d=open(path,'rb').read()
    res=strings(d,minlen)+(strings(d,minlen,True))
    res.sort()
    rx=re.compile(pat,re.I) if pat else None
    for off,s in res:
        if rx and not rx.search(s): continue
        print(f'{off:#010x}  {s}')
