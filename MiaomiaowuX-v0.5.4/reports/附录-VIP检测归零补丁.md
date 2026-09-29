# 附录 B：VIP / PRO 检测移除补丁（本轮新增）

> 承接 `miaomiaowuX-mmwx-v0.5.4-license_security_assessment_report.md`。
> 完整补丁包见 `patches/`，验证证据见 `reports/CRACK_VERIFICATION.txt`。

---

## B.1 关键结论：VIP 判定是**单点汇聚**的

| 阶段 | 手段 | 结果 |
|---|---|---|
| 1 | `upx -d` | 36,605,840 B → 132,604,030 B 原始 Go ELF |
| 2 | 解析 pclntab | **厂商把 magic 从 `0xfffffff1` 改成 `0xd7c8c0ec`**（轻度反分析）；其余头部字段完整 → 恢复 **102,731 个函数**的精确地址 |
| 3 | 全 `.text` 扫描 `call` 指令 | 定位 VIP 判定的**唯一汇聚点**：`IWPMOgYs4.(*BcGS_j).HasFeature @ 0x17b4180` |
| 4 | 调用方统计 | **20 处调用点 / 18 个调用方**，覆盖全部 5 项 PRO 功能 + 高级主题 + 数据面限速/限连 |

因此把 `HasFeature` 入口改成 `mov al,1; ret`（3 字节），**全部 VIP 检测一次归零**。

## B.2 补丁清单

```
0x13b4180  b0 01 c3                                  # HasFeature              -> 恒真 ★
0x13b44a0  b0 01 c3                                  # HasFeatureForDataPlane  -> 恒真
0x13b3180  31 c0 c3                                  # QuotaEnforced           -> false
0x13b3a20  48 b8 ff ff ff ff ff ff ff 7f c3          # EffectiveUserQuota      -> INT64_MAX
0x13b3280  48 b8 ff ff ff ff ff ff ff 7f c3          # EffectiveServerQuota    -> INT64_MAX
0x13b37c0  48 b8 ff ff ff ff ff ff ff 7f c3          # EffectiveNodeQuota      -> INT64_MAX
```

（`fileoff = VA - 0x400000`，脱壳后 ELF：`.text vaddr 0x401000 / fileoff 0x1000`）

产物 sha256：`573a95ffbafe3a75cdd6b196aa738ed24cab3771af90668ec9b9d6d6c2cb0243`
（`patches/mmwx-crack.py` 与 `patches/oneliner.sh` 两条路径产物**逐字节一致**）

## B.3 验证（A/B：官方 12889 vs 破解 12890）

| 观测点 | 官方 | 破解 | 结论 |
|---|---|---|---|
| `GET /` 注入 `var ps` | `'false'` | `'true'` | ✅ |
| `/api/user/license/status` → `premium_theme` | `false` | `true` | ✅ |
| 浏览器 `<html class>`（premium 主题） | `font-oplusans3 light` | `theme-premium font-oplusans3 light` | ✅ 高级主题真正生效 |
| `HasFeature` 机器码 | 736 B 完整实现 | `mov al,1; ret` | ✅ |

## B.4 未覆盖项（如实记录）

**用户/服务器/节点数量配额**走的是**独立路径**：

- 官方版与破解版新建用户时**都**被服务端拦回：`已达到用户数量上限 (3/3)，请升级许可证`
- 即使把前端 UI 的 `usage.max` 改大（解除浏览器侧拦截）重测，破解版**仍被拦**
- 该配额在 `VLgBxN.(*CjOdSUIBHq4).CreateUser @ 0xd43000`（8896 B）内部，
  读取计划限额 / `LicenseUsage` 快照，**不经过** `(*BcGS_j).Effective*Quota`
  → §B.2 中 3 条配额补丁对该路径无效（保留无害，但不算有效补丁）

**下一步定位路径（已铺好）**：
`(*xGRYHwaSuI).ServeHTTP`（含 `SetLicenseManager` 的 admin users handler）
→ `bcrypt.GenerateFromPassword` → `VLgBxN.(*CjOdSUIBHq4).CreateUser` → `GetOrCreateUserToken`；
配额判定在 `CreateUser` 或其闭包内，经**接口间接调用**取计划限额
→ 对 `CreateUser` 做 gdb 硬件断点，或直接 patch `LicenseUsage` 返回值即可覆盖。

## B.5 反检测提示

| 指纹 | 值 | 服务端可见性 |
|---|---|---|
| 官方发行物 | `ecc1020a…5657` | 与签名 manifest 一致 |
| 仅脱壳 | `c11d44d4…` | ⚠ 已随 `build_fingerprint` / `client_fp.exe_sha256` 上报 |
| 打过补丁 | `573a95ff…` | ⚠ 同上，服务端可识别改包 |

- **Action Guard 默认关闭**（`MMWX_ACTION_GUARD=required` 才启用）。
  一旦默认强制，`mmwx-guardd-master --verify-manifest-for` 会用签名 manifest 校验主控哈希，本补丁立即失效。
- 补丁产物是 132 MB 的**脱壳** ELF，可自行 `upx` 再压回，但重压缩头与官方 UPX 版本不同，同样可被指纹识别。

---

## B.6 防御建议（针对"单点汇聚"这一根因）

1. **不要把 5 项 PRO 能力的判定收敛到同一个函数**。`HasFeature` 单点化让 3 字节补丁即可清空全部 VIP 门禁；
   应对每项能力做**独立的服务端权威判定**，且判定点分散在不同调用链。
2. **判定结果不要下发到前端让前端裁决**（前端 `Gy()` 的 fail-open 已在主报告记录）。
3. **对许可状态做完整性保护**：许可状态（valid / plan / features / 限额）在内存与
   `system_settings.license_status` 中应带 AEAD 标签；被篡改的实例应直接拒绝服务而非降级。
4. **缩短刷新周期并对脱壳产物做主动检测**：服务端已经能收到
   `build_fingerprint`，应将其与官方 manifest 比对，不一致即拒发授权。
5. **默认启用 Action Guard**，且不要让 `MMWX_ACTION_GUARD` 只作为可选环境变量存在。
