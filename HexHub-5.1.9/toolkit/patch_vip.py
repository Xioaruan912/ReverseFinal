"""HexHub VIP 鉴权旁路 —— 等长二进制微创补丁
两个补丁点（均为等长替换，不改变 PE 布局 / 文件大小）：
  P1) session store 的 isMemberValid()  ->  恒返回 true（绕过期判定）
  P2) 成员对象完整性校验 ue()            ->  恒返回 true（绕 SHA256 sign 校验）
"""
import shutil, sys, os

ROOT = os.path.dirname(os.path.abspath(__file__))
os.chdir(ROOT)

SRC = "samples/extracted/hexhub-backend.exe"
DST = "patches/hexhub-backend.patched.exe"

P1_OLD = b"isMemberValid(){var r;return(r=this==null?void 0:this.member)!=null&&r.endTime?this.member.endTime>new Date().getTime():!1}"
P1B_OLD = b"isMemberValid(){var s;return(s=this==null?void 0:this.member)!=null&&s.endTime?this.member.endTime>new Date().getTime():!1}"
P2_OLD = b"ue=le=>{const f=new Array(3);return le.endTime?f[0]=le.endTime:f[0]=\"\",f[1]=le.email,f[2]=Ui(le.publicKey).toString(),Ui(f.join(\"*\")).toString()!==le.sign?(Qi().then(()=>{}).catch(D=>{console.error(\"err\",D),Xe.error(D.message)}).finally(()=>{s.logout(),_e.delay(()=>{location.reload()},500)}),!1):!0}"

P1_NEW = b"isMemberValid(){return!0}"

# ---- 更新检查根除（唯一汇聚点）----
# 原：!((o=t.updateInfo)!=null&&o.hasUpdate)||!((i=t.updateInfo)!=null&&i.targetVersion)
# 该条件为真即走「当前已是最新版本 -> return」分支；恒真 = 永不提示更新。
UPD_OLD = b"!((o=t.updateInfo)!=null&&o.hasUpdate)||!((i=t.updateInfo)!=null&&i.targetVersion)"
UPD_NEW = b"!0x0"
P2_NEW = b"ue=le=>!0"


def pad(new, old_len):
    assert len(new) <= old_len, (len(new), old_len)
    return new + b" " * (old_len - len(new))


def main():
    d = bytearray(open(SRC, "rb").read())
    for name, old, new in (("P1a isMemberValid(main)", P1_OLD, P1_NEW),
                           ("P1b isMemberValid(worker)", P1B_OLD, P1_NEW),
                           ("P2 ue(sign-check)", P2_OLD, P2_NEW),
                           ("UPD hasUpdate 汇聚点", UPD_OLD, UPD_NEW)):
        n = d.count(old)
        print(f"[{name}] occurrences = {n}  old_len={len(old)}")
        if n == 0:
            print("  !! not found"); continue
        d = d.replace(old, pad(new, len(old)))
        print(f"  -> patched to {new!r} (+{len(old)-len(new)} spaces padding)")
    os.makedirs(os.path.dirname(DST) or ".", exist_ok=True)
    open(DST, "wb").write(bytes(d))
    print("\n[+] written:", DST)


if __name__ == "__main__":
    main()
