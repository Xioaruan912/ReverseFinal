# HexHub VIP 功能测绘 · 服务端依赖分析 · 登录场景测试方案

> 配套：`HexHub-5.1.9-VIP鉴权脆弱性评估报告.md`
> 本文回答三个问题：**VIP 到底有什么功能？旁路后哪些真能用？需要登录时怎么测？**

---

## 0. 结论速览

| 问题 | 答案 |
| :--- | :--- |
| VIP 门禁点有多少？ | **23 个菜单项 `vip:!0` + 49 处 `isMemberValid()` 调用**（含组件级判定） |
| 旁路后哪些真能用？ | **21/23 纯客户端门禁 → 立即生效**；云端同步类 3 项需服务端，但**私有储存仓库（local/WebDAV/S3）可完全离线** |
| 唯一无法绕的？ | **设备数配额**（Pro 2 台 / Plus 5 台）——服务端会话表强制 |
| 需要登录还能测吗？ | **能，且更强**。四条路线，其中「完全离线模拟登录」已在实测中打通 |

---

## 1. VIP 功能全量清单（按门禁类型分组）

### 1.1 终端 / SSH 类

| 功能 | 门禁点 | 服务端依赖 | 旁路后可用 |
| :--- | :--- | :--- | :---: |
| 终端广播（批量执行） | `isMemberValid()` | ❌ 无 | ✅ |
| 批量上传文件 / 文件夹 | `isMemberValid()` | ❌ 无 | ✅ |
| 全部关闭 / 全部开启（广播会话） | `isMemberValid()` | ❌ 无 | ✅ |
| 上传 SSH 公钥 `ssh-copy-id` | `vip:!0` | ❌ 无 | ✅ |
| 保存为日志 | `vip:!0` | ❌ 无 | ✅ |
| 跨服务器文件传输（SFTP↔SFTP） | `isMemberValid()` | ❌ 无（客户端直连两端） | ✅ |
| 压缩 / 解压缩（tar.gz/tar.bz2/zip/7z/rar） | `vip:!0` | ❌ 无 | ✅ |
| 通过服务器代理打开 Chrome | `vip:!0` | ❌ 无 | ✅ |

### 1.2 窗口 / 视图类

| 功能 | 门禁点 | 服务端依赖 | 旁路后可用 |
| :--- | :--- | :--- | :---: |
| 多窗口 / 新窗口打开 / 同屏打开 / 复制窗口 | `isMemberValid()` + `vip:!0` | ❌ 无 | ✅ |
| 多视图 / 视图拆分 | `isMemberValid()` | ❌ 无 | ✅ |
| 垂直分屏 / 水平分屏 | `vip:!0` | ❌ 无 | ✅ |
| 标签重命名 | `vip:!0` | ❌ 无 | ✅ |
| **解除会话数限制**（社区版上限 6 会话） | `isMemberValid()` | ❌ 无 | ✅ |

### 1.3 Docker 类

| 功能 | 门禁点 | 服务端依赖 | 旁路后可用 |
| :--- | :--- | :--- | :---: |
| 自选镜像仓库（自定义 registry） | `isMemberValid()` | ❌ 无（客户端直连 registry） | ✅ |
| 使用本地网络拉取（SSH 隧道） | `isMemberValid()` | ❌ 无（走 SSH 隧道） | ✅ |
| 容器文件管理 | `isMemberValid()` | ❌ 无 | ✅ |

### 1.4 外观类

| 功能 | 门禁点 | 服务端依赖 | 旁路后可用 |
| :--- | :--- | :--- | :---: |
| 主题包（`ql.map((o,e)=>({...o, vip: e>=2}))` → 第 3 个起为 VIP） | `vip:!0` + `isMemberValid()` | ❌ 无 | ✅ |

### 1.5 数据同步类（★ 唯一有服务端依赖的一组）

| 功能 | 门禁点 | 服务端依赖 | 旁路后可用 |
| :--- | :--- | :--- | :--- |
| **资产云端同步** | `isMemberValid()` + `memberId` | ✅ `api.hexhub.cn/client/member-asset/{sync,diff,clear}` + `oss.hexhub.cn` | ⚠️ **官方云同步不可用**（服务端按 memberId 校验） |
| **表数据 / 结构同步** | `isMemberValid()` | ✅ 走 member 资产云 | ⚠️ 同上 |
| **自定义私有储存仓库** | `isMemberValid()` | 分类型见下 | ✅ **local / WebDAV / S3 可完全离线** |
| 资产导入/导出（本地文件） | `isMemberValid()` | ❌ 无 | ✅ |

**私有储存仓库的四种类型（逆向自 `Rm=Object.freeze([...])`）**：

```js
[
  { label: "HexHub官方同步", value: "default" },   // ← 走服务端，需授权
  { label: "本地文件",       value: "local"   },   // ← 纯客户端，✅ 离线可用
  { label: "WebDAV",         value: "webdav"  },   // ← 客户端直连用户 WebDAV，✅
  { label: "S3",             value: "s3"      },   // ← 客户端直连用户对象存储，✅
]
```

> **关键洞察**：`default` 之外的三种储存类型，数据面**完全由客户端直连用户自有存储**。
> 只要旁路了 `isMemberValid()`，这三类云端同步可**完全离线、不依赖厂商任何服务**地工作。

### 1.6 真正由服务端强制、无法绕过的

| 项 | 强制方 | 说明 |
| :--- | :--- | :--- |
| **登录设备数配额** | 服务端会话表 | 专业版 2 台 / 增强版 5 台（Mac/Win/Linux）。`client/auth/session-list` + `kick-session` 由服务端裁决 |
| 专属售后群 | 人工 | — |
| 官方云同步的服务端校验 | `api.hexhub.cn` | 按 `memberId` 校验；伪造 memberId 会被服务端拒绝 |

---

## 2. 服务端依赖分级图

```
                     ┌─────────────────────────────────────────┐
   21 / 23 门禁      │  ★ 纯客户端判定（isMemberValid / vip 标记）│
   ────────────────► │  多窗口 · 多视图 · 分屏 · 终端广播 ·      │
                     │  跨服务器传输 · 会话数 · 主题包 ·         │
                     │  Docker 三项 · 压缩 · ssh-copy-id · 日志  │
                     └─────────────────────────────────────────┘
                                   │ 旁路即生效
                                   ▼
                     ┌─────────────────────────────────────────┐
                     │  ⚠ 客户端判定 + 数据面在服务端            │
                     │  官方云同步 / 表数据同步                  │
                     │  → 门禁能过，但服务端按 memberId 校验会拒 │
                     └─────────────────────────────────────────┘
                                   │
                                   ▼
                     ┌─────────────────────────────────────────┐
                     │  ✅ 客户端判定 + 数据面在用户自有存储      │
                     │  私有储存仓库 local / WebDAV / S3         │
                     │  → 旁路后可完全离线工作（厂商零参与）      │
                     └─────────────────────────────────────────┘

                     ┌─────────────────────────────────────────┐
                     │  ❌ 服务端唯一权威（无法客户端绕过）       │
                     │  登录设备数配额（2 / 5 台）               │
                     └─────────────────────────────────────────┘
```

---

## 3. 需要登录时的测试方案（四条路线）

> 前置结论：**登录不构成障碍**。分两种情形：
> - 服务端**可达**且 token 有效 → 服务端会下发真实 member **覆盖**本地伪造 → 需路线 B/C/D
> - 服务端**不可达** → `catch` 分支保留本地 member → 路线 A 直接生效

### 路线 A · 无需登录（默认 PoC，已验证）

```powershell
powershell -ExecutionPolicy Bypass -File .\run_test.ps1
```
`poc_test.js`：页面级阻断 + 注入伪造 session + 重载 → 👑 Plus。

### 路线 B · 真实账号 + 页面级阻断（会话不被覆盖）

用真实（免费/过期）账号登录后，在**页面级阻断** `client/member/currentv2`，
再注入伪造 member 并重载：`Xs()` 走 `catch` 分支 → **本地 member 不被覆盖** → VIP 保留。
（`poc_test.js` 已经隐含验证了该路径：token 存在与否不影响结论。）

### 路线 C · 二进制补丁（服务端覆盖也不怕）★ 登录场景首选

```powershell
python patch_vip.py
# isMemberValid(){...} -> isMemberValid(){return!0}    (主 bundle + worker bundle)
# ue=le=>{...}         -> ue=le=>!0                    (完整性校验)
```
**A/B 实测**：同一份「2023 已过期 + 伪造签名」的 member，
原版 ❌ 无徽章 / 补丁版 ✅ 👑 Plus。**服务端下发的真实会员数据也无法否决这个判定。**

### 路线 D · 完全离线「模拟登录」（无需任何账号）★★ 新增，已实测通过

**原理**（逆向自内嵌 bundle）：

```js
// TopBar chunk:  Xs(priKey, token)
const n = await hn.get("client/member/currentv2", {headers:{Authorization: token}});
// 响应信封: {code:0, msg, data}  → axios 响应拦截器返回 .data
priKey -> "-----BEGIN PRIVATE KEY-----\n..." -> RSA-2048 (WASM 实现)
member = JSON.parse( concat( RSA_PKCS1v15_decrypt(chunk) for chunk in data ) )

// 完整性校验
ue(m) => SHA1(`${m.endTime}*${m.email}*${SHA1(m.publicKey)}`) === m.sign
```

**攻击构造**：

| 步骤 | 做法 |
| :--- | :--- |
| ① 自建密钥 | Node 生成 RSA-2048，`priKey` = base64(PKCS#8 DER) |
| ② 伪造会员 | `endTime = 2524579200000`（终身哨兵），`isPlus = true` |
| ③ 自算签名 | `sign = SHA1(`${endTime}*${email}*${SHA1(publicKey)}`)` ← **零密钥** |
| ④ 自加密 | 用**自建公钥** PKCS1v15 加密会员 JSON，按 245 字节切片，base64 |
| ⑤ 替换响应 | `page.route` 拦截 `currentv2` → 返回 `{code:0,msg:'ok',data:[...chunks]}` |
| ⑥ 写入会话 | `localStorage["session"] = {token:'任意', priKey:自建私钥, member:null}` |

**实测输出**：

```json
{
  "crownCount": 1,
  "hasPlusLabel": true,
  "memberFromServer": true,          ← 客户端自己"从服务端拉取"到了会员
  "email": "audit@hexhub.local",
  "endTime": 2524579200000,
  "isPlus": true,
  "isLifetimeSentinel": true,
  "isMemberValid": true,
  "notLoggedIn": true
}
✔ 完全离线模拟登录成功：客户端用【自建密钥】解出【伪造会员】并点亮 👑 Plus
```

📷 `exports/fake_login.png`

> **安全含义**：所谓"服务端加密下发会员"**不构成任何信任锚** ——
> 私钥（`priKey`）在客户端本地、签名算法与输入全部公开可复算。
> 攻击者连"登录"这一步都不需要，就能让客户端完整走通
> 「拉取 → 解密 → 验签 → 落盘 → 点亮会员」全链路。

**一键复现**：

```powershell
# 客户端需以 CDP 启动（run_test.ps1 会自动做）
NODE_PATH="C:\Users\Administrator\.pi\agent\npm\node_modules" node poc_fake_login.js
```

---

## 4. 登录场景对照表

| 场景 | 服务端状态 | 本地 member | 推荐路线 | 结果 |
| :--- | :--- | :--- | :--- | :--- |
| 未登录 | 阻断 | 伪造 | A | ✅ 👑 Plus |
| 未登录 | 可达 | 伪造 | — | ❌ 401 → 拦截器 `logout()` 清会话 |
| 已登录（免费/过期） | 阻断 | 伪造 | B | ✅ 👑 Plus（member 不被覆盖） |
| 已登录（免费/过期） | 可达 | 服务端真实数据 | **C**（补丁） | ✅ 👑 Plus（判定被改） |
| 无任何账号 | 阻断 | 自造 + 自加密 | **D** | ✅ 👑 Plus（客户端认为已登录+已同步） |

---

## 5. 修正说明（重要）

早期版本的分析把完整性校验误判为 **SHA-256**，实际为 **SHA-1**：

```
crypto-DJ4zhvIi.js:
  const te = D._createHelper(T);          // T = SHA1Algo（_hash 为 5 words / 160-bit）
  const be = D._createHmacHelper(T);
  const me = "/wasm/sha256.wasm";         // 紧随其后定义的是 SHA256Algo（8 words）
  ...
  const Kt = new Map([["MD5",Vt],["SHA1",te],["SHA256",ee]]);   // ← te 明确映射为 SHA1
  export { Ne as C, te as S };            // S = te = SHA1 helper
```

前端 `ue()` 使用的 `Ui` = 该 chunk 的 `S` 导出 = **SHA1**。故正确校验式为：

```
sign = SHA1( `${endTime}*${email}*${SHA1(publicKey)}` )
```

**影响**：
- 离线场景（路线 A/B）不受影响 —— 服务端不可达时 `ue()` 根本不会被调用；
- 登录/模拟登录场景（路线 C/D）**必须用 SHA-1**，否则签名校验失败并触发 `logout()`；
- 已修正 `poc_test.js` / `poc_fake_login.js` / `patches/poc_forge_session.js` 及评估报告。

---

## 6. 整改建议（在报告 §5 基础上的补充）

1. **废除客户端可复算的"签名"**：`SHA1(endTime*email*SHA1(publicKey))` 无密钥、可离线复算，
   必须换成**服务端私钥签名**（Ed25519/RS256），客户端仅持公钥验签。
2. **`priKey` 不应是信任锚**：当前 `priKey` 由本地后端 `repository/get-pri-key` 从密码派生，
   服务端用其对应公钥加密下发 —— 这只是传输机密性，**不提供任何授权完整性**。
   建议把会员权益做成**服务端签名令牌**（含 `memberId/plan/exp/deviceId/nonce`）。
3. **所有 VIP 功能的服务端权威化**：21 项纯客户端门禁中，
   至少云端同步/私有仓库/跨服务器传输应在**服务端或用户自有存储的凭证签发**环节校验权益，
   而不是只看客户端布尔值。
4. **设备数配额是唯一的正确示范**：服务端会话表强制 2/5 台 —— 建议把其余权益也按此模式收敛。
