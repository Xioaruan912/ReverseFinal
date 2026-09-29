import json
f=json.load(open('/root/mmwx/gofuncs.json'))
for pref in ['IWPMOgYs4.']:
    h=sorted((n,v) for n,v in f.items() if n.startswith(pref))
    print(f"### {pref} -> {len(h)}")
    for n,v in h:
        if '.func' in n and n.count('.func')>1: continue
        print(f"   {hex(v[0])}-{hex(v[1])} sz={v[1]-v[0]:<6} {n}")
