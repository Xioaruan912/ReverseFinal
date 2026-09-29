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

---

# 附录 C：前端许可状态补丁（本轮新增，修复"面板仍显示试用版"）

> **问题**：附录 B 的 11 处补丁全部生效后，面板 `/system-settings` 仍显示
> 「当前状态：有效 · 套餐：**试用版**」「当前效果 **TRIAL · 试用版**」，且 PRO 功能全部带 🔒。
>
> **根因**：11 处补丁补的是**后端功能门禁**（`HasFeature` / 配额），
> 而面板的 TRIAL 与 🔒 由**另一套独立判据**驱动 —— 内嵌 React SPA 里的
> `/api/user/license/status` 与 `Gy()` 特性门禁。只补一层必然出现"后端已解锁、面板还显示试用"。
> 这一点在附录 B.4「未覆盖项」中已有记录，本轮补齐。

## C.1 前端判据链（从内嵌 bundle 反推）

```js
// ① 特性总开关：全部 PRO 门禁的唯一汇聚点
function Gy(feature){
  const verified = data['_verifiedFeatures'];
  let has;
  return verified ? has = verified.includes(feature)
                  : has = data?.plan?.features?.includes(feature) ?? false,   // fail-open
  {hasFeature: has, plan: data?.plan};
}

// ② 套餐徽标取数
_0x54636b = data?.['plan']?.['name'] ?? data?.['name'] ?? ''
_0x4cec1a = data?.['plan']?.['display_name'] ?? data?.['display_name'] ?? ''
'valid': !!data?.['valid']

// ③ 系统设置页的试用判定
const isTrial = !licenseKey || license?.['plan']?.['name'] === 'TRIAL'
```

> 注：`var ps = 'true'`（B.3 的验证点）**只控制主题样式**，
> 与 PRO 许可状态无关 —— 这是 B.3 验收口径的一个盲区，本轮订正。

## C.2 补丁清单（内嵌 bundle 等长替换）

方法：前端 bundle 以 `embed.FS` 内嵌在二进制中，按 **等长字节替换 + 空格填充** 原位修改，
文件大小不变（132,604,030 B）。每个片段在二进制中**全库唯一**。

| 文件偏移 | 目标 | 改前 | 改后 | 长度 |
| --- | --- | --- | --- | --- |
| `0x54a395a` | `Gy()` 特性总开关 | 127 B 三元表达式 | `_0x5c3c11=!0x0` | 127 |
| `0x54a8030` | 套餐名 | 54 B `plan.name??…??''` | `'PRO'` | 54 |
| `0x54a8071` | 套餐显示名 | 70 B `plan.display_name??…` | `'专业版'` | 70 |
| `0x54a8112` | 有效位 | 30 B `!!data?.valid` | `'valid':!0x0` | 30 |
| `0x4fadb75` | 试用判定 | 51 B `!key\|\|name==='TRIAL'` | `!0x1` | 51 |
| `0x4fb022f` | PRO 功能按钮门禁 | 34 B `_0x1a70b6['has'](key)` | `!0x0` | 34 |

**合成产物 sha256**：`84bf303bcbf11ec1080b746d60a2d9d9df645403f76abd6f52343548eea980a0`
（= 11 处 Go 门禁 + 6 处前端许可状态，共 17 处）

## C.3 验证（浏览器实拍）

| 观测点 | 补丁前 | 补丁后 |
| --- | --- | --- |
| 当前状态 / 套餐 | 有效 · **试用版** | 有效 · **PRO**（金色徽章） |
| 试用提示条 + 购买按钮 | 存在 | **消失** |
| PRO 功能 🔒 | 全部带锁 | **全部解除** |
| 当前效果 | **TRIAL · 试用版** | **PRO · 专业版** |
| 关键字计数 | 试用版>0 / TRIAL>0 | 试用版 0 / TRIAL 0 / 购买许可证 0 / 不可用 0 |
| **PRO 功能 5 项** | 全部 `<button disabled>` + tooltip「需要升级许可证」 | **全部 `<a>` 启用**，locked=0 |
| **功能开关真点** | 不可切换 | `aria-checked: true → false` 可切换 ✅ |
| **高级主题** | 不生效 | cookie 选 premium → `<html class="theme-premium ...">` ✅ |

另经服务端确认：实际下发的 `/assets/index-B2G2S9sm.js` 含全部 5 处补丁特征串。

## C.4 仍未覆盖

- **数量配额（服务器/节点/用户上限）**：面板卡片仍显示服务端下发的 `0/1 · 0/5 · 0/3`。
  该路径见附录 B.4 —— 在 `VLgBxN.(*CjOdSUIBHq4).CreateUser @ 0xd43000` 内部，
  经接口间接读取计划限额 / `LicenseUsage` 快照，**不经过** `Effective*Quota`。
  本轮未完成，需对该函数做运行时断点定位（gdb 硬件断点或 patch `LicenseUsage` 返回值）。
- 本补丁为**前端展示层 + 后端功能门禁**两层判据的解除，**不改动**许可服务器交互与签名链。

---

# 附录 D：数量配额路径 —— 交接说明（未完成）

> **状态**：本轮未打通。以下为已确认事实与最短路径，供下一轮直接接手。

## D.1 现象

面板卡片显示服务端下发的 `服务器 0/1 · 节点 0/5 · 用户 0/3`，
新建第 4 个用户时被拦（附录 B.4 实测报错：`已达到用户数量上限 (3/3)，请升级许可证`）。

## D.2 已确认事实

| 项 | 结论 |
| --- | --- |
| 配额判定位置 | `VLgBxN.(*CjOdSUIBHq4).CreateUser`，VA `0xd43000`（fileoff `0x943000`），8896 B |
| 与已有补丁的关系 | **不经过** `(*BcGS_j).Effective*Quota`，所以 §B.2 的 3 条配额补丁对该路径无效 |
| 字面量 | 被 `garble -literals` 加密：`已达到用户数量上限` 明文 **0 次**（`升级许可证` 尚存 2 次残存） |
| 符号名 | garble 全量重命名，pclntab 虽可解析（真头部 `0x582b7a0`，nfunc=102730）但**无可用可读名** |
| 静态反汇编 | `objdump -b binary` 无法解析相对 `call` 目标，需先转成带节头的 ELF 或用 r2/capstone |
| 调用链（已知） | `… → bcrypt.GenerateFromPassword → CreateUser → GetOrCreateUserToken`，配额判定在 `CreateUser` 内部或其闭包内，**经接口间接调用**取计划限额 |

## D.3 建议路径（按性价比排序）

1. **patch `LicenseUsage` 返回 0 用量**（推荐）
   `used >= limit` 永不成立 → 用户/节点/服务器一次全解，比改 `CreateUser` 内部干净得多。
   需先定位 `LicenseUsage`（可用 gdb：在 `CreateUser` 内单步，观察哪次 `call` 返回结构体被拿去比较）。
2. **gdb 硬件断点**
   `gdb -p <pid>` → `hbreak *0xd43000` → 通过 UI 建第 4 个用户 → 单步到比较指令，
   把 `jae/jg`（`used >= limit` 跳转到错误分支）改成 `jmp` 或 NOP。
3. **先验证是否仍需补**
   附录 B.4 的拦截实测是在**旧的 6 处补丁**产物上做的；
   当前产物已是 **17 处补丁**（新增 `wFeRoafTxm` / `yqkjNzz7` / `CountLicensedUsers` / `CountLicensedNodes`），
   **该路径可能已被其中某处覆盖** —— 下一轮应先做一次功能性复测（建第 4 个用户），
   确认仍被拦再动手，避免无效补丁。

## D.4 复测脚本要点（本轮踩坑）

- 登录页有两种形态：**首次启动**（按钮 `创建管理员账号`）与**已有账号**（按钮 `登录`），脚本必须都兼容；
  建号后往往**不会自动登录**，需再走一次登录。
- 用户管理页的新增弹窗用 `data-slot="dialog-overlay"` 遮罩，
  前一个弹窗未关时后续 `click` 会被 `intercepts pointer events` 拦掉 → 每次操作后按 `Escape`。
- 新增用户表单的字段 `name` 属性与预期不符（`input[name=username]` 未命中），
  需先 dump 弹窗内 input 的 `name`/`placeholder` 再写选择器。
