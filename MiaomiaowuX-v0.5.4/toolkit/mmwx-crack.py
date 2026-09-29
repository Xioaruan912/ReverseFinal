#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mmwx-crack.py  —  妙妙屋X (miaomiaowux) v0.5.4  白盒鉴权归零补丁（最终版）
==============================================================================
授权白盒审计用途：仅用于自建沙箱实例。

一、目标：把许可体系的三层门禁全部归零
  1) 特性门禁（VIP/PRO）     —— 单点汇聚在 HasFeature
  2) 高级主题门禁            —— CanUsePremiumTheme -> HasFeature("premium_theme")
  3) 数量配额（用户/服务器/节点）—— 三个独立的 gate 函数 + 两个计数函数

二、定位方法
  - UPX 脱壳后解析 Go pclntab（厂商把 magic 从 0xfffffff1 改成 0xd7c8c0ec）
    恢复 102,731 个函数的精确地址；
  - 全 .text 扫描 `call rel32`，统计每个候选函数的调用方，找到"汇聚点"；
  - 对每个 gate 函数反汇编其调用点，确认返回值寄存器与分支极性；
  - 对 garble -literals 加密的字符串，改用 /proc/pid/mem 运行时取证。

三、验证（A/B：官方 12889 / 破解 12890，同客户端同操作）
  官方 12889 : 用户 3 上限、服务器 1 上限、premium_theme=false、var ps='false'
  破解 12890 : 用户 8、服务器 4、premium_theme=true、var ps='true'

用法
----
    python3 mmwx-crack.py <官方 mmwx-linux-amd64> -o mmwx-cracked
    PORT=12889 MMWX_DATA_DIR=$PWD/data ./mmwx-cracked
"""
import argparse, hashlib, os, shutil, subprocess, sys, tempfile

OFFICIAL_SHA256 = "ecc1020ad9e5448fdb04bf510f85f9eec329844809cd62f131ccbd635b0d5657"

# 脱壳后 ELF：.text vaddr=0x401000 fileoff=0x1000  =>  fileoff = VA - 0x400000
VA_BIAS = 0x400000

RET_TRUE   = b"\xb0\x01\xc3"                                        # mov al,1 ; ret
RET_FALSE  = b"\x31\xc0\xc3"                                        # xor eax,eax ; ret
RET_INTMAX = bytes([0x48, 0xB8]) + (0x7FFFFFFFFFFFFFFF).to_bytes(8, "little") + b"\xc3"
RET_ZERO_TRIO = bytes([0x31, 0xC0, 0x31, 0xDB, 0x31, 0xC9, 0xC3])   # xor eax/eax ebx/ecx ; ret
RET_CL1    = bytes([0xB9, 0x01, 0x00, 0x00, 0x00, 0xC3])            # mov ecx,1 ; ret
NOP2       = b"\x90\x90"

# (名称, VA, 原始首字节(校验), 补丁, 说明)
PATCHES = [
    # ---------- 1. VIP / PRO 特性门禁（单点） ----------
    ("IWPMOgYs4.(*BcGS_j).HasFeature", 0x17b4180,
     "4c8da42420fdffff4d3b6610", RET_TRUE,
     "★ 全部 VIP/PRO 特性判定恒真（20 处调用点 / 18 个调用方一次覆盖）"),

    ("IWPMOgYs4.(*BcGS_j).HasFeatureForDataPlane", 0x17b44a0,
     "4c8da424e0fcffff4d3b6610", RET_TRUE,
     "数据面特性（节点限速 / 连接数限制）恒真"),

    # ---------- 2. 配额开关与有效配额 ----------
    ("IWPMOgYs4.(*BcGS_j).QuotaEnforced", 0x17b3180,
     "493b6610", RET_FALSE,
     "关闭配额强制开关"),

    ("IWPMOgYs4.(*BcGS_j).EffectiveUserQuota", 0x17b3a20,
     "4c8da42430fdffff4d3b6610", RET_INTMAX, "有效用户配额 -> INT64_MAX"),

    ("IWPMOgYs4.(*BcGS_j).EffectiveServerQuota", 0x17b3280,
     "493b6610", RET_INTMAX, "有效服务器配额 -> INT64_MAX"),

    ("IWPMOgYs4.(*BcGS_j).EffectiveNodeQuota", 0x17b37c0,
     "4c8da42430fdffff4d3b6610", RET_INTMAX, "有效节点配额 -> INT64_MAX"),

    # ---------- 3. 数量配额 gate（真正生效的路径） ----------
    ("JLKbOa2Pg.wFeRoafTxm  (用户配额 gate)", 0x2acb6a0,
     "4c8da424f8feffff4d3b6610", RET_ZERO_TRIO,
     "返回 blocked=false；调用点: test cl,cl; jne <403 错误> —— cl!=0 才拦截"),

    ("JLKbOa2Pg.(*pax4j7Y80P).yqkjNzz7  (节点配额 gate)", 0x2b3a2e0,
     "4c8da42468feffff4d3b6610", RET_CL1,
     "返回 ok=true；调用点: test cl,cl; jne <继续> —— 极性相反，cl==0 才拦截"),

    ("VLgBxN.(*CjOdSUIBHq4).CountLicensedUsers", 0xdc3a80,
     "4c8d6424a04d3b6610", RET_ZERO_TRIO,
     "已用用户数恒为 0（同时把面板 usage.users.current 归零，UI 门禁自然放行）"),

    ("VLgBxN.(*CjOdSUIBHq4).CountLicensedNodes", 0xc3e760,
     "4c8d6424e04d3b6610", RET_ZERO_TRIO,
     "已用节点数恒为 0"),

    # ---------- 4. 服务器配额（内联在 CreateRemoteServer 中） ----------
    ("(*FX0hJe7Qj).CreateRemoteServer  服务器配额分支", 0x285aa89,
     "7d5448", NOP2,
     "cmp current,max; jge <上限错误> -> NOP，永不走上限分支"),
]


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def is_upx(path):
    with open(path, "rb") as f:
        return b"UPX!" in f.read(1 << 20)


def unpack_upx(path, outdir):
    out = os.path.join(outdir, "mmwx-unpacked")
    shutil.copy2(path, out)
    r = subprocess.run(["upx", "-d", out], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("upx -d 失败：\n" + r.stdout + r.stderr)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input", help="官方 mmwx-linux-amd64（加壳或已脱壳均可）")
    ap.add_argument("-o", "--output", default="mmwx-cracked")
    ap.add_argument("--force", action="store_true", help="跳过 sha256 校验")
    a = ap.parse_args()

    src = os.path.abspath(a.input)
    digest = sha256(src)
    print(f"[*] 输入   : {src}")
    print(f"[*] sha256 : {digest}")
    if digest == OFFICIAL_SHA256:
        print("[+] 与官方 v0.5.4 发行物一致")
    elif not a.force:
        print("[!] 非官方 v0.5.4 发行物（若确认同版本，加 --force）")

    tmp = tempfile.mkdtemp(prefix="mmwx-crack-")
    work = src
    if is_upx(src):
        print("[*] 检测到 UPX 加壳，脱壳中 (upx -d) ...")
        work = unpack_upx(src, tmp)
        print(f"[+] 脱壳完成: {os.path.getsize(work):,} bytes")
    else:
        print("[*] 输入未加壳，直接打补丁")

    data = bytearray(open(work, "rb").read())
    log, ok = [], 0
    for name, va, expect_hex, patch, why in PATCHES:
        off = va - VA_BIAS
        expect = bytes.fromhex(expect_hex)
        cur = bytes(data[off:off + len(expect)])
        if cur != expect:
            print(f"[!] SKIP {name} @ file+{hex(off)} 原始字节不匹配")
            print(f"        期望 {expect.hex(' ')}")
            print(f"        实际 {cur.hex(' ')}")
            log.append((name, va, off, cur.hex(), "SKIPPED(mismatch)", why))
            continue
        data[off:off + len(patch)] = patch
        ok += 1
        print(f"[+] patched {name:52s} file+{hex(off)}  {cur.hex(' ')} -> {patch.hex(' ')}")
        log.append((name, va, off, cur.hex(), patch.hex(), why))

    out = os.path.abspath(a.output)
    with open(out, "wb") as f:
        f.write(data)
    os.chmod(out, 0o755)
    print(f"\n[+] 成功打补丁 {ok}/{len(PATCHES)}")
    print(f"[+] 已写出: {out}  ({os.path.getsize(out):,} bytes)  sha256={sha256(out)}")

    with open(out + ".patchlog", "w", encoding="utf-8") as f:
        f.write("# mmwx v0.5.4 白盒鉴权归零补丁日志\n")
        f.write(f"# 输入 sha256 : {digest}\n# 输出 sha256 : {sha256(out)}\n\n")
        for name, va, off, old, new, why in log:
            f.write(f"{name}\n  VA={hex(va)} FILE_OFFSET={hex(off)}\n"
                    f"  {old} -> {new}\n  {why}\n\n")
    print(f"[+] 补丁日志: {out}.patchlog")
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n[*] 启动: PORT=12889 MMWX_DATA_DIR=$PWD/data ./{os.path.basename(out)}")


if __name__ == "__main__":
    main()
