import sqlite3, re
c=sqlite3.connect('file:/root/mmwx/run/data/mmwx.db?mode=ro',uri=True)
print("=== all system_settings ===")
for k,v in c.execute("select key,value from system_settings"):
    if 'traffic' in k or '_migrate' in k: continue
    print(f"  {k} = {v[:90]!r}")
d=open('/root/mmwx/dump/heap2.bin','rb').read()
st=set()
for m in re.finditer(rb'[A-Za-z0-9_\-\.]{4,50}', d):
    s=m.group().decode('latin1')
    if 'theme' in s.lower() or s.lower()=='pixel' or 'wallpaper' in s.lower() or 'glass' in s.lower():
        st.add(s)
print("\n=== theme-ish tokens (%d) ==="%len(st))
for s in sorted(st)[:70]: print("  ", s)
