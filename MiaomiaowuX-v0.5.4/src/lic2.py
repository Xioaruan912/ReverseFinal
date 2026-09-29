import re
d=open('/root/mmwx/unpacked/mmwx-unpacked','rb').read()
def uniq(kw, limit=30, maxlen=220, minlen=None):
    st=set()
    for m in re.finditer(rb'[\x20-\x7e]{%d,%d}'%(minlen or len(kw),maxlen), d):
        s=m.group().decode('latin1')
        if kw.lower() in s.lower(): st.add(s)
    print("\n##### '%s' -> %d"%(kw,len(st)))
    for s in sorted(st)[:limit]: print("  ", s)
uniq('ed25519')
uniq('https://license')
uniq('mmwx-entitlement')
uniq('signing_key_certificate')
uniq('entitlement_session_sig')
uniq('master_public_key')
uniq('X-MMWX-Guard')
uniq('license_identity')
uniq('SecureChannel')
uniq('securechan_enforce')
