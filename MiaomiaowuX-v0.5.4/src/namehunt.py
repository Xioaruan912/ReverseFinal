import json
f=json.load(open('/root/mmwx/gofuncs.json'))
seen=set()
for kw in ['Quota','Limit','Usage','Quota','Snapshot','Current']:
    print(f"\n### 名称含 '{kw}'")
    for n,(a,b) in sorted(f.items(), key=lambda x:x[1][0]):
        if n in seen: continue
        if kw in n and 'xray' not in n.lower() and 'grpc' not in n and 'protobuf' not in n and 'sing' not in n and 'tg' not in n.lower():
            seen.add(n)
            print(f"   {hex(a)}-{hex(b)} sz={b-a:<6} {n}")
