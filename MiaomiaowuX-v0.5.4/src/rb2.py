d=open('/root/mmwx/unpacked/mmwx-unpacked','rb').read()
T=[("wFeRoafTxm(user gate)",0x2acb6a0,16),
   ("yqkjNzz7(node gate)",0x2b3a2e0,16),
   ("CountLicensedUsers",0xdc3a80,16),
   ("CountLicensedNodes",0xc3e760,16),
   ("CreateRemoteServer.jge",0x285aa89,16)]
for n,va,l in T:
    print(f"{n:26s} VA={hex(va)} OFF={hex(va-0x400000)} orig={d[va-0x400000:va-0x400000+l].hex(' ')}")
