import re
d=open('/root/mmwx/dump/heap.bin','rb').read()
st=set()
for m in re.finditer(rb'https?://[\x21-\x7e]{4,120}', d):
    st.add(m.group().decode('latin1'))
lic=[s for s in st if 'licen' in s.lower()]
print("=== urls containing 'licen' (%d) ==="%len(lic))
for s in sorted(lic): print("  ", s)
print("\n=== mmwx-related domains (all) ===")
dom=set()
for s in st:
    m=re.match(r'https?://([^/]+)', s)
    if m and ('miaomiao' in m.group(1) or 'mmwx' in m.group(1)): dom.add(s)
for s in sorted(dom)[:60]: print("  ", s)
print("\n=== structured license storage keys ===")
for kw in ['license_status','license_key','licenseServerURL','LicenseServerURL','licenseServerUrl','licenseserver']:
    hits=set()
    for m in re.finditer(rb'[\x20-\x7e]{3,120}', d):
        s=m.group().decode('latin1')
        if kw in s: hits.add(s)
    print(f"-- {kw} ({len(hits)}):", sorted(hits)[:12])
