import re
BIN='/root/mmwx/unpacked/mmwx-unpacked'
d=open(BIN,'rb').read()
for kw in ['用户数量上限','服务器数量上限','节点数量上限','请升级许可证','数量上限','PRO 功能']:
    nb=kw.encode('utf-8')
    hits=[m.start() for m in re.finditer(re.escape(nb), d)]
    print(f"\n### '{kw}' file hits={len(hits)}")
    for h in hits[:6]:
        s=max(0,h-120); e=min(len(d),h+120)
        print(f"   off={hex(h)} va~{hex(h+0x400000)}  ctx: {d[s:e].decode('utf-8','replace')!r}")
