import re
d=open('/root/mmwx/dump/heap.bin','rb').read()
for kw in [b'license verification public key', b'/api/v1/', b'signature verification FAILED', b'possible forged license server',
           b'license public key', b'pubkey', b'lic-pub', b'license-pub']:
    print("\n#### %s"%(kw.decode()))
    n=0
    for m in re.finditer(re.escape(kw), d):
        s=max(0,m.start()-350); e=min(len(d),m.end()+350)
        txt=''.join(chr(x) if 32<=x<127 else ('|' if x==0 else '.') for x in d[s:e])
        print("  [%s] %s"%(hex(m.start()), txt))
        n+=1
        if n>=3: break
    print("   total:", len(re.findall(re.escape(kw), d)))
