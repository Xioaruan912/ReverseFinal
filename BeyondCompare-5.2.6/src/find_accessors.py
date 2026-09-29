import struct, sys, re, collections, json
sys.path.insert(0,'.')
from pe import PE
from pdata import funcs
p, F = funcs(r'C:/Users/Administrator/Downloads/bc5-recon/extracted/BCompare.exe')
d=p.d
def rd(va,n):
    o=p.va2off(va); return d[o:o+n] if o else b''
acc=collections.defaultdict(dict)
PATS=[
 ('get8',  rb'(?:\x48)?\x0f\xb6[\x80-\x87](....)\xc3'),
 ('get8b', rb'(?:\x48)?\x0f\xb6[\x40-\x7f](.)\xc3'),
 ('get32', rb'(?:\x48)?\x8b[\x80-\x87](....)\xc3'),
 ('get64', rb'\x48\x8b[\x80-\x87](....)\xc3'),
 ('set8dl',rb'(?:\x40)?\x88[\x90-\x97](....)\xc3'),
 ('set8al',rb'(?:\x40)?\x88[\x80-\x87](....)\xc3'),
 ('set8imm',rb'(?:\x40)?\xc6[\x80-\x87](....)(.)\xc3'),
 ('set32edx',rb'\x89[\x90-\x97](....)\xc3'),
 ('set32imm',rb'\xc7[\x80-\x87](....)(....)\xc3'),
 ('set64rdx',rb'\x48\x89[\x90-\x97](....)\xc3'),
 ('set64imm',rb'\x48\xc7[\x80-\x87](....)(....)\xc3'),
]
comp=[(n,re.compile(v,re.S)) for n,v in PATS]
for s,e in F:
    n=e-s
    if n>16: continue
    b=rd(s,n)
    if not b: continue
    for name,rx in comp:
        m=rx.match(b)
        if m:
            disp=struct.unpack('<i', m.group(1).ljust(4,b'\0'))[0]
            acc[disp][name]=s
            break
print('accessors:', len(acc))
json.dump({hex(k):{kk:hex(vv) for kk,vv in v.items()} for k,v in sorted(acc.items())}, open('accessors.json','w'), indent=0)
want=[0x1f0,0x400,0x610,0x611,0x612,0x618,0x620,0x628,0x630,0x631,0x632,0x638,0x648,0x658,0x668,0x678,0x688,0x698,0x6a8,0x6b8,0x6c8,0x6d8,0x6e8,0x6f8,0x708,0x718,0x728,0x738,0x748,0x758,0x768,0x17d0,0x1a8]
for o in want: print(hex(o), {k:hex(v) for k,v in acc.get(o,{}).items()})
