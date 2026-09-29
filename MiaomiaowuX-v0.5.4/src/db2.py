import sqlite3, json
c=sqlite3.connect('file:/root/mmwx/run/data/mmwx.db?mode=ro', uri=True)
print("=== system_settings ===")
for k,v,u in c.execute("select key,value,updated_at from system_settings order by key"):
    if 'traffic_' in k or '_migrate' in k: continue
    print(f"  {k} = {v!r}")
