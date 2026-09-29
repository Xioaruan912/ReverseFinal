"""打包交付物（剔除大体积中间产物，保持轻量可分发给接手人）"""
import os, zipfile, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "dist")
os.makedirs(OUT, exist_ok=True)
zip_path = os.path.join(OUT, "HexHub-白盒鉴权脆弱性测试包-v1.0.zip")

INCLUDE_FILES = [
    "README-交付说明.md",
    "preflight.ps1",
    "run_test.ps1",
    "poc_test.js",
    "poc_fake_login.js",
    "extract.py",
    "patch_vip.py",
]
INCLUDE_DIRS = {
    "tools":   (".py",),
    "reports": (".md",),
    "patches": (".js", ".md"),          # 排除 118MB 的 exe 副本
    "optional": None,
    "exports": (".png",),               # 只带证据截图
}
EXCLUDE = {"nsis_solid_stream.bin"}

count = 0
total = 0
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for f in INCLUDE_FILES:
        p = os.path.join(ROOT, f)
        if os.path.isfile(p):
            z.write(p, f); count += 1; total += os.path.getsize(p)
    for d, exts in INCLUDE_DIRS.items():
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dirpath, _, files in os.walk(base):
            for fn in files:
                if fn in EXCLUDE:
                    continue
                if exts and not fn.lower().endswith(exts):
                    continue
                fp = os.path.join(dirpath, fn)
                rel = os.path.relpath(fp, ROOT).replace("\\", "/")
                z.write(fp, rel); count += 1; total += os.path.getsize(fp)

size = os.path.getsize(zip_path)
print(f"[+] 打包完成: {zip_path}")
print(f"    文件数: {count}   原始: {total/1024:.1f} KB   压缩后: {size/1024:.1f} KB")

with zipfile.ZipFile(zip_path) as z:
    print("\n=== 包内清单 ===")
    for n in sorted(z.namelist()):
        print("   ", n)
