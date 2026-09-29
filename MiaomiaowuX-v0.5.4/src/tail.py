import json
f=json.load(open('/root/mmwx/gofuncs.json'))
for n,(a,b) in sorted(f.items(), key=lambda x:x[1][0]):
    if 'nGWMWbWxEUa' in n or 'CreateUser' in n and 'VLgBxN' in n:
        print(f"{n}  {hex(a)}-{hex(b)} size={b-a}")
