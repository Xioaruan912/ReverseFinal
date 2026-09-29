import re
d=open('/root/mmwx/unpacked/mmwx-unpacked','rb').read()
kws=[b'response signature verification FAILED', b'license verification public key is unavailable',
     b'/api/v1/activate', b'/api/v1/heartbeat', b'/api/v1/', b'license_pubkey', b'LICENSE_PUBKEY',
     b'signing_key_certificate', b'activation']
for kw in kws:
    n=len(re.findall(re.escape(kw), d))
    print("\n#### %s -> %d"%(kw.decode(), n))
    c=0
    for m in re.finditer(re.escape(kw), d):
        s=max(0,m.start()-260); e=min(len(d),m.end()+260)
        seg=d[s:e]
        txt=''.join(chr(x) if 32<=x<127 else ('|' if x==0 else '.') for x in seg)
        print("  [%s] %s"%(hex(m.start()), txt))
        c+=1
        if c>=3: break
# base64 blobs 43-44 chars (32 bytes) anywhere
b64=set(m.group().decode() for m in re.finditer(rb'[A-Za-z0-9+/]{43}=?', d))
print("\n#### 32-byte base64 candidates: %d"%len(b64))
