"""从内嵌前端 bundle 中全量提取 VIP 门禁点与会员字段使用点"""
import re, sys, json

BIN = "samples/extracted/hexhub-backend.exe"
d = open(BIN, "rb").read()
js = d.decode("latin1")


def ctx(o, before=260, after=260):
    return js[max(0, o - before):o + after]


def unescape(s):
    # bundle 里的中文是 UTF-8 被按 latin1 读出来的，还原一下
    try:
        return s.encode("latin1").decode("utf-8", "ignore")
    except Exception:
        return s


print("=" * 78)
print("① vip:!0 —— 菜单/功能项的 VIP 标记（共 %d 处）" % js.count("vip:!0"))
print("=" * 78)
seen = set()
for m in re.finditer(r'vip:!0', js):
    o = m.start()
    seg = unescape(ctx(o, 220, 40)).replace("\n", " ")
    # 提取 title 字段（i18n key）
    t = re.findall(r'title:"([^"]{0,60})"', seg)
    icon = re.findall(r'icon:"([^"]{0,50})"', seg)
    hk = re.findall(r'hotkey:"([^"]{0,40})"', seg)
    key = (tuple(t), tuple(icon))
    if key in seen:
        continue
    seen.add(key)
    print(f"  @{o:<9} title={t[-1] if t else '-':<38} icon={icon[-1] if icon else '-':<32} hotkey={hk[-1] if hk else '-'}")

print()
print("=" * 78)
print("② isMemberValid() 调用点（共 %d 处）—— 每个 VIP 门禁" % js.count("isMemberValid()"))
print("=" * 78)
seen = set()
for m in re.finditer(r'isMemberValid\(\)', js):
    o = m.start()
    seg = unescape(ctx(o, 170, 170)).replace("\n", " ")
    seg = re.sub(r"\s+", " ", seg)
    if seg[:120] in seen:
        continue
    seen.add(seg[:120])
    print(f"  @{o:<9} …{seg}…")
    print()

print("=" * 78)
print("③ 会员字段使用点 member.<field>")
print("=" * 78)
from collections import Counter
c = Counter(re.findall(r'member\.([A-Za-z_][A-Za-z0-9_]*)', js))
for k, v in c.most_common():
    print(f"  member.{k:<18} x{v}")

print()
print("=" * 78)
print("④ isPlus / 套餐区分")
print("=" * 78)
for m in list(re.finditer(r'isPlus', js))[:12]:
    o = m.start()
    print(f"  @{o:<9} …{unescape(ctx(o,120,120)).replace(chr(10),' ')}…")
