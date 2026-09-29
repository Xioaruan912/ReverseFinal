import re
d=open('/root/mmwx/dump/heap2.bin','rb').read()
# candidate setting key names
st=set()
for m in re.finditer(rb'[A-Za-z0-9_\-\.]{4,60}', d):
    s=m.group().decode()
    ls=s.lower()
    if any(k in ls for k in ['pubkey','pub_key','public_key','verify','signing','issuer','license_']) and len(s)<60:
        st.add(s)
print("=== candidates (%d) ==="%len(st))
for s in sorted(st): print("  ", s)
