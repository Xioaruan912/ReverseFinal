import re
d=open('/root/mmwx/unpacked/mmwx-unpacked','rb').read()
for kw in [b'last_check', b'max_servers', b'display_name']:
    print("\n##### %s"%kw.decode())
    st=set()
    for m in re.finditer(rb'[\x20-\x7e]{10,400}', d):
        s=m.group().decode('latin1')
        if kw.decode() in s and 'json:' in s: st.add(s)
    for s in sorted(st)[:10]: print("  ", s)
