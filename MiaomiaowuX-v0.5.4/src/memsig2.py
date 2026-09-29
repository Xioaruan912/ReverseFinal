import re
d=open('/root/mmwx/dump/heap2.bin','rb').read()
for kw in [b'/api/v1/activate', b'signature verification FAILED', b'license verification public key',
           b'possible forged license server', b'/api/v1/heartbeat', b'entitlement', b'license_pub', b'signing_key']:
    ms=[m.start() for m in re.finditer(re.escape(kw), d)]
    print("\n#### %s -> %d"%(kw.decode(), len(ms)))
    for off in ms[:3]:
        s=max(0,off-300); e=min(len(d),off+300)
        txt=''.join(chr(x) if 32<=x<127 else ('|' if x==0 else '.') for x in d[s:e])
        print("  [%s] %s"%(hex(off), txt))
