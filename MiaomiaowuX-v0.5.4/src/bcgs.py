import json
f=json.load(open('/root/mmwx/gofuncs.json'))
print("### IWPMOgYs4.(*BcGS_j) 方法清单")
for n,(a,b) in sorted(f.items(), key=lambda x:x[1][0]):
    if n.startswith('IWPMOgYs4.(*BcGS_j).') and n.count('.func')==0 and 'deferwrap' not in n:
        print(f"   {hex(a)}-{hex(b)} sz={b-a:<6} {n}")
print("\n### 其它许可相关方法")
for n,(a,b) in sorted(f.items(), key=lambda x:x[1][0]):
    if n.startswith('IWPMOgYs4.') and '(BcGS_j)' not in n and '.init' not in n and 'deferwrap' not in n:
        print(f"   {hex(a)}-{hex(b)} sz={b-a:<6} {n}")
