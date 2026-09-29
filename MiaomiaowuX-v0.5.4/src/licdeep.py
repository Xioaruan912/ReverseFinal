import re
d=open('/root/mmwx/unpacked/mmwx-unpacked','rb').read()
def uniq(kw, limit=40, maxlen=200):
    st=set()
    for m in re.finditer(rb'[\x20-\x7e]{%d,%d}'%(len(kw),maxlen), d):
        s=m.group().decode('latin1')
        if kw.lower() in s.lower(): st.add(s)
    print("\n##### '%s' -> %d"%(kw,len(st)))
    for s in sorted(st)[:limit]: print("  ", s)
for kw in ['license.miaomiaowux.com','license_server_url','CanUsePremiumTheme','Premium','license_key_hash','slot_id','authorized_']:
    uniq(kw)
