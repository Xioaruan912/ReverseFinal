import re
d=open('/root/mmwx/dump/heap2.bin','rb').read()
for kw in ['OverridableFeatures','请升级','PRO 功能','speed_test','reality_pool','server_share']:
    kb=kw.encode()
    ms=[m.start() for m in re.finditer(re.escape(kb), d)]
    print("\n#### %s -> %d"%(kw,len(ms)))
    for off in ms[:3]:
        s=max(0,off-400); e=min(len(d),off+400)
        txt=''.join(chr(x) if 32<=x<127 else ('|' if x==0 else '.') for x in d[s:e])
        print("   ", txt)
