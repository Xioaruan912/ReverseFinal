import re, base64
d=open('/root/mmwx/dump/heap2.bin','rb').read()
for kw in [b'1mOqVQuZPyeioJVLzG66z+Xdh3AdpdL0JsTmZ2nlEEA', b'mmwx-signing-key-cert', b'mmwx-entitlement', b'mmwx-master-response', b'response_sig', b'sig_v2', b'key_id', b'cert_pub']:
    ms=[m.start() for m in re.finditer(re.escape(kw), d)]
    print("\n#### %s -> %d"%(kw.decode(), len(ms)))
    for off in ms[:2]:
        s=max(0,off-250); e=min(len(d),off+250)
        txt=''.join(chr(x) if 32<=x<127 else ('|' if x==0 else '.') for x in d[s:e])
        print("   ", txt)
# raw 32-byte root key?
raw=base64.b64decode('1mOqVQuZPyeioJVLzG66z+Xdh3AdpdL0JsTmZ2nlEEA=')
print("\nraw root key hex:", raw.hex())
print("raw occurrences:", len(re.findall(re.escape(raw), d)))
