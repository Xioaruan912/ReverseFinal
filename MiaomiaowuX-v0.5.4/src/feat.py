import re
d=open('/root/mmwx/dump/heap.bin','rb').read()
for kw in [b'reality_pool', b'node_ratelimit']:
    print("\n===== %s ====="%kw.decode())
    n=0
    for m in re.finditer(re.escape(kw), d):
        s=max(0,m.start()-700); e=min(len(d),m.end()+700)
        print(''.join(chr(c) if 32<=c<127 else ('\n' if c==10 else '.') for c in d[s:e]))
        print('-----')
        n+=1
        if n>=2: break
