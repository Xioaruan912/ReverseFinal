import re
d=open('/root/mmwx/dump/heap2.bin','rb').read()
st=set()
for m in re.finditer(rb'[\x20-\x7e]{4,200}', d):
    s=m.group().decode('latin1')
    if 'PRO ' in s and ('功能' in s or 'feature' in s.lower() or 'license' in s.lower() or '升级' in s):
        st.add(s)
print("=== PRO error messages (%d) ==="%len(st))
for s in sorted(st): print("  ", s)
