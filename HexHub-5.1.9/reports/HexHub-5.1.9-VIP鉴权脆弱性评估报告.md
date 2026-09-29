# HexHub Client 5.1.9 — VIP 鉴权脆弱性白盒评估报告

| 项目 | 内容 |
| :--- | :--- |
| **评估对象** | `HexHub-Client-windows-amd64-installer-5.1.9.exe` |
| **MD5** | `75ca72bba54d7b92a189a544dbf9f28f` |
| **SHA-256** | `77f7f4faea0ea7ca9510ccdad556de8c804286e6628fe59e3e57461241869b15` |
| **文件大小** | 152,456,296 bytes (145.39 MB) |
| **安装器类型** | NSIS 3.x 自解压（LZMA solid 压缩，i386 stub） |
| **目标架构** | 解包载荷全部为 x86-64 (`IMAGE_FILE_MACHINE_AMD64`) |
| **客户端形态** | CEF (Chromium 138.0.7204.97) 壳 `HexHub.exe` + Go 插件宿主 `hexhub-backend.exe` |
| **评估类型** | 授权沙盒白盒审计（客户端鉴权脆弱性 / CWE-602） |
| **评估日期** | 2026-09-29 |

---

## 0. 结论速览（TL;DR）

> **HexHub 的会员（VIP）权益判定完全在客户端完成，且其"完整性签名"是一段不含任何服务端密钥的自证式哈希。**
> 攻击者无需账号、无需破解通信协议，只要：
> ① 让厂商授权服务器 `api.hexhub.cn` 网络不可达，② 在本地 `localStorage` 写入一个自造 `member` 对象，
> 即可在**未登录**状态下点亮「👑 Plus 终身版」，并绕过「联网服务器比对」。

| 编号 | 漏洞 | CWE | 严重级别 | 状态 |
| :--- | :--- | :--- | :--- | :--- |
| **VULN-01** | VIP 权益判定完全由客户端 `member.endTime > Date.now()` 决定 | CWE-602 | **严重 (Critical)** | 已动态验证 |
| **VULN-02** | 会员对象完整性签名可离线自算（SHA-1 自证式哈希，无密钥） | CWE-345 / CWE-472 | **严重 (Critical)** | 已动态验证 |
| **VULN-05** | 会员下发链路不构成信任锚：私钥 `priKey` 本地生成，攻击者可自建 RSA 密钥对伪造整个「登录+下发」流程 | CWE-345 / CWE-602 | **严重 (Critical)** | 已动态验证 |
| **VULN-03** | 离线宽限期无服务端锚点，网络错误与 401 分支策略不一致 | CWE-613 / CWE-636 | **中 (Medium)** | 已动态验证 |
| **VULN-04** | 隐藏 DevTools 后门（`basicDebug` 口令 = `MD5(deviceId)`，deviceId 本地可改） | CWE-489 | **低 (Low)** | 静态确认 |

**动态验证结果（A/B 对照，均在全离线 + 未登录条件下）：**

| 用例 | 注入的 member | 二进制 | 顶栏会员徽章 |
| :--- | :--- | :--- | :--- |
| A | `endTime=1700000000000`（2023 已过期）+ 伪造 `sign` | 原版 | ❌ 无徽章 |
| B | 同上（**同一份过期/伪造数据**） | **等长补丁版** | ✅ **👑 Plus** |
| C | `endTime=2524579200000`（终身）+ 自算合法 `sign` | 原版 | ✅ **👑 Plus** |
| D（负向对照） | 同上 | 原版，**服务器可达** | ❌ 会话被服务端 401 清空 |

---

## 1. 攻击面测绘与解包路径

### 1.1 NSIS 安装器静态解包（未执行安装程序）

安装器为 NSIS 3.x，载荷为**单一 LZMA1 solid 流**。手工解包路径：

```
1) 定位 NSIS firstheader 签名:   0xDEADBEEF + "NullsoftInst"  @ 文件偏移 0x64604 (411140)
   flags=0  siginfo=0xDEADBEEF  nsinst[3]="Null"|"soft"|"Inst"
   length_of_header            = 0x54BA   (21690  = 解压后头部大小)
   length_of_all_following_data= 0x090FDB66 (152,035,686 = 压缩数据块大小)

2) LZMA 参数: props=0x5D  dict=0x00800000 (8MB)  lc=3 lp=0 pb=2
   压缩流起点 = 0x64609 + 5 = 411169

3) 解压 → 485,681,983 bytes 单一 solid 流
   [0 .. 21690)          = NSIS 头部
       ├─ 0x0AC0..0x3894 = 419 条 28 字节安装条目表 (name 字段为 UTF-16 字符串表字符偏移)
       ├─ 0x3894..0x54BA = UTF-16 字符串表
   [21698 .. EOF)        = 77 个文件载荷顺序拼接

4) 按条目表 offset 差值切分文件 → 77 个文件全部校验通过（PE 为 MZ / pak 为 0x05 魔数）
```

### 1.2 载荷清单（关键项）

| 文件 | 大小 | 说明 |
| :--- | ---: | :--- |
| `libcef.dll` | 239,042,308 | Chromium Embedded Framework 138 |
| `hexhub-backend.exe` | 118,715,652 | **Go 二进制**（插件宿主，内嵌整套前端 dist） |
| `HexHub.exe` | 2,011,908 | CEF 壳进程（Go + CEF，提供 `http://127.0.0.1:35580` 静态服务） |
| `rg.exe` | 4,352,603 | ripgrep |
| `locales/*.pak` | ~0.6–1.7 MB × 60 | Chromium 语言包 |

### 1.3 信任边界还原

```
┌──────────────────────────────────────────── CEF 渲染进程 (Chromium 138) ───┐
│  Vue3 + Vite 前端 bundle（内嵌于 hexhub-backend.exe 的 .rdata，明文可搜） │
│    • pinia store "session"  persist=true → localStorage["session"]        │
│    • isMemberValid()  ← ★ VIP 唯一判据，纯客户端                          │
│    • ue(member)       ← ★ 完整性校验，SHA-1 自证式哈希（无密钥）          │
└───────────────┬──────────────────────────────────────────┬───────────────┘
                │ axios baseURL=http://127.0.0.1:35580     │ axios baseURL=https://api.hexhub.cn
                ▼                                          ▼
┌──────────────────────────────┐            ┌──────────────────────────────┐
│ HexHub.exe / hexhub-backend  │            │  api.hexhub.cn  (厂商侧)     │
│ 本地 Go HTTP :35580          │            │  client/member/currentv2 ... │
│ 仅插件路由(DB/SSH/Docker/…)  │            │  RSA 加密下发 member         │
│ ❌ 不含任何会员鉴权逻辑      │            │  ★ 唯一的服务端权威点        │
└──────────────────────────────┘            └──────────────────────────────┘
```

**关键观察**：本地 Go 后端经全量符号审计（`hexhub-agent/*` 8,500+ 符号）确认**不存在**会员/授权校验函数；
`MemberValid` 等标识全部来自内嵌 JS。**服务端权威点仅存在于远程 API，而客户端并未把服务端结论当作不可绕过的前提。**

---

## 2. 漏洞详情

### VULN-01 · VIP 权益判定完全客户端化 —— CWE-602（严重）

**位点**：内嵌前端 bundle，pinia store 定义（`hexhub-backend.exe` 偏移 `0x388B...`，两处副本）

```js
const session = defineStore("session", {
  state: () => ({ token: null, priKey: null, member: null }),
  actions: {
    isLogin() { return !!this.token },

    // ★ 全部 VIP 权益的唯一判据
    isMemberValid() {
      return this?.member != null && this.member.endTime
        ? this.member.endTime > new Date().getTime()     // ← 纯本地时间比较
        : false;
    },

    setMember(m) { this.member = m },
    setToken(t)  { this.token  = t },
    setPriKey(k) { this.priKey = k },
    logout() { this.token = null; this.priKey = null; this.member = null },
  },
  persist: true,          // ★ pinia-plugin-persistedstate
});
```

**持久化落盘**（`pinia-plugin-persistedstate` 默认配置）：

```js
const { storage: a = localStorage, key: l = t.$id, ... } = n;   // 默认 localStorage，key = store id
```

→ 会话对象明文存放于 **`localStorage["session"]`**：

```json
{"token":"...","priKey":"...","member":{"id":...,"email":"...","endTime":2524579200000,
 "isPlus":true,"publicKey":"...","sign":"..."}}
```

**影响面**（全量枚举 `isMemberValid()` 调用点，共 20+ 处）：主题包切换、SFTP 广播上传/下载、终端分屏、
新建窗口/标签、资产导出、私有仓库同步、增强 Agent 会话、移动端设备会话等**全部 VIP 门禁**均由此单一函数放行。

**危害**：客户端布尔判定 + 明文可写落盘 = 特权状态可被任意伪造，服务端无最终裁决权。

---

### VULN-02 · 会员对象"签名"可离线自算 —— CWE-345 / CWE-472（严重）

**位点**：内嵌前端 bundle（`hexhub-backend.exe` 偏移 `0x3A6B...`）

```js
ue = (m) => {
  const f = new Array(3);
  f[0] = m.endTime ? m.endTime : "";
  f[1] = m.email;
  f[2] = Ui(m.publicKey).toString();                       // Ui = CryptoJS SHA1 helper
  if (Ui(f.join("*")).toString() !== m.sign) {             // ★ 比对
      Qi().then(...).finally(() => { session.logout(); location.reload(); });
      return false;
  }
  return true;
}
```

`Ui` 的来源已确认：`import{C as $n, S as Ui} from "./crypto-DJ4zhvIi.js"`，
该 chunk 导出 `S = te`，而 `te = D._createHelper(T)` 且 `T` 为 **SHA1Algo**（`_hash` 为 5 words/160-bit），
同 chunk 内的 RSA 类映射表 `Kt = new Map([["MD5",Vt],["SHA1",te],["SHA256",ee]])` 亦明确 `te → SHA1`。
**故 `Ui` = SHA-1，而非 SHA-256**（早期版本误判，已修正；见 `VIP功能测绘与服务端依赖分析.md` §5）。

因此校验式为：

```
sign = SHA1( `${endTime}*${email}*${SHA1(publicKey)}` )
```

**这是一段纯粹的、不含任何密钥的确定性哈希。** 攻击者握有全部输入，可 100% 离线复算，
`ue()` 无法提供任何防篡改能力（它只是防"手抖改字段"，不是防伪造）。

> 附：`currentv2` 下发的 member 使用 RSA/PKCS1v15 + 客户端私钥解密 —— 那是**传输机密性**，
> 与**授权完整性**无关：私钥在客户端，攻击者可以自行生成一对并让伪造数据自洽。

---

### VULN-03 · 离线宽限期无服务端锚点，错误分支策略不一致 —— CWE-613 / CWE-636（中）

**位点**：内嵌前端 bundle（启动同步流程）

```js
me = () => {
  session.isLogin() && Xs(session.priKey)
    .then(m => { ue(m) && (session.setMember(m), state = 0) })
    .catch(e => { state = 2; console.error("err", e) })       // ★ 仅置"离线"态，不清 member
}

A = async () => {
  if (session.isLogin()) {
    try { const m = await Xs(session.priKey);
          if (!ue(m)) return;
          session.setMember(m); state = 0 }
    catch (e) { state = 2; return }                            // ★ 同上
  } else return;
  if (!session.isMemberValid()) return;                        // ★ 用本地缓存继续放行
  await xc(le) && emit("refreshAsset"); ...
}
```

对应的 axios 响应拦截器只对**服务端返回的错误码**执行 `logout()`：

```js
// 401 / token 失效分支
... .finally(() => { session.logout() }); ...
```

**由此形成一条稳定的攻击链**：

| 服务端状态 | 客户端分支 | 结果 |
| :--- | :--- | :--- |
| 返回 401（token 无效） | 响应拦截器 → `logout()` | 会话清空，VIP 失效 |
| **网络不可达**（DNS 失败 / 连接被拒 / 黑洞） | `catch` → `state=2`「网络受限，已离线」 | **member 原样保留，VIP 继续有效** |

即：**"把厂商服务器断掉"反而是维持 VIP 的最优解**。会话一旦落盘，既无过期硬校验、也无
"距上次服务端确认不得超过 N 天"的锚点，可无限期离线维持。

UI 文案已确认：`state==2 → "网络受限，已离线"`（顶栏提示，不影响权益判定）。

---

### VULN-04 · 隐藏 DevTools 后门 —— CWE-489（低）

**位点**：内嵌前端 bundle（`hexhub-backend.exe` 偏移 `0x3A6B...` 附近）

```js
case "basicDebug":
  xn.open("请输入密钥", "").then(async f => {
    f.toLowerCase() === $n.MD5(await Gi().getDeviceId()).toString().toLowerCase()
      && hexhub.showDevTools();          // ★ 口令 = MD5(deviceId)
  });
  break;
```

`deviceId` 明文存于 `localStorage["system-info"]`，本地可任意修改 —— 相当于**任何本地用户都能自行算出
口令并唤出 DevTools**，进而在渲染进程中任意执行 JS（本 PoC 的注入通道之一）。

---

---

### VULN-05 · 会员下发链路不构成信任锚（可完全离线伪造「登录+下发」）—— CWE-345 / CWE-602（严重）

**位点**：内嵌前端 bundle（`hexhub-backend.exe`，TopBar chunk + crypto chunk + 本地后端 `repository/get-pri-key`）

**链路还原**：

```js
// ① priKey 由本地后端从密码派生（客户端本地生成，非服务端下发）
const Hy = async e => (await Oe.post("repository/get-pri-key", {password: e})).data.body;

// ② 用 priKey 拉取并解密会员（TopBar chunk）
Xs = async (priKey, token) => {
  const n = await hn.get("client/member/currentv2", { headers: { Authorization: token } });
  //  axios 响应拦截器： e.data.code == 0 ? e.data.data : reject
  priKey -> `-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----`
  await new $n.algo.RSA().updateRsaKey(pem, false);          // RSA-2048 (WASM)
  let out = "";
  for (const chunk of n)
    out += new TextDecoder().decode(
      $n.RSA.decrypt(Vc.toUint8Array(chunk), { encryptPadding: "PKCS1V15", key: pem }));
  return JSON.parse(out);
};

// ③ 完整性校验（SHA-1，无密钥）
ue = m => SHA1(`${m.endTime}*${m.email}*${SHA1(m.publicKey)}`) === m.sign;
```

**攻击构造（无需任何账号）**：

| 步骤 | 做法 |
| :--- | :--- |
| ① | Node 自建 RSA-2048 密钥对；`priKey` = base64(PKCS#8 DER) |
| ② | 伪造会员：`endTime = 2524579200000`（终身哨兵）、`isPlus = true` |
| ③ | 自算签名：`sign = SHA1(`${endTime}*${email}*${SHA1(publicKey)}`)` |
| ④ | 用**自建公钥** PKCS1v15 加密会员 JSON，按 245 字节切片并 base64 |
| ⑤ | 拦截 `currentv2` → 返回 `{code:0, msg:'ok', data:[...chunks]}` |
| ⑥ | 写入 `localStorage["session"] = {token:任意, priKey:自建私钥, member:null}` |

**实测结果**（`exports/fake_login.png`）：

```json
{
  "crownCount": 1,
  "hasPlusLabel": true,
  "memberFromServer": true,      // ← 客户端自己"从服务端拉取"到了会员
  "email": "audit@hexhub.local",
  "endTime": 2524579200000,
  "isPlus": true,
  "isLifetimeSentinel": true,
  "isMemberValid": true,
  "notLoggedIn": true
}
```

**危害**：所谓"服务端加密下发会员"**不提供任何授权完整性** ——
私钥在客户端本地、签名算法与输入全部公开可复算。攻击者连"登录"这一步都不需要，
即可让客户端完整走通「拉取 → 解密 → 验签 → 落盘 → 点亮会员」全链路。

**影响面补充**：VIP 门禁共 **23 个菜单项 + 49 处 `isMemberValid()` 调用**；
其中 **21 项为纯客户端判定**（多窗口/多视图/分屏/终端广播/跨服务器传输/会话数/主题包/Docker 三项等），
旁路后立即生效；仅「官方云同步」「表数据同步」有服务端数据面依赖，
而「自定义私有储存仓库」的 **local / WebDAV / S3** 三种类型完全由客户端直连用户自有存储，
**旁路后可完全离线工作**。唯一由服务端强制的是**登录设备数配额**（Pro 2 台 / Plus 5 台）。
详见 `VIP功能测绘与服务端依赖分析.md`。

---

## 3. 复现步骤与证据链

### 3.1 环境准备（本报告实测环境）

```bash
# 1) 静态解包（无需执行安装器）
python extract.py                 # → samples/extracted/  77 个文件

# 2) 启动真实客户端（CEF + Go 后端），开启 CDP 便于取证
cd samples/extracted
./HexHub.exe --remote-debugging-port=9222
#   → 页面 http://localhost:35580/   title=HexHub
#   → CDP: http://127.0.0.1:9222/json/list
```

### 3.2 攻击链（完整可复现）

```javascript
// 步骤 1：阻断厂商授权服务器（见 patches/block_vendor_server.md）
//   hosts: 0.0.0.0 api.hexhub.cn / oss.hexhub.cn    ← 必须是"不可达"，不是"返回错误"

// 步骤 2：写入伪造会话（patches/poc_forge_session.js）
const ENDTIME = 2524579200000;                       // 2050-01-01 = 终身版哨兵值
const SIGN = SHA1(`${ENDTIME}*${EMAIL}*${SHA1(PUBKEY)}`);       // 自证式签名（无密钥）
localStorage.setItem('session', JSON.stringify({
  token: 'forged', priKey: 'forged',
  member: { email: EMAIL, endTime: ENDTIME, isPlus: true, publicKey: PUBKEY, sign: SIGN }
}));
location.reload();
```

### 3.3 实测证据

**证据 A — 正例：未登录 + 厂商服务器阻断 → 👑 Plus 终身版**

```
localStorage["session"] AFTER reload:
{"token":"forged-token-audit","priKey":"forged-prikey-audit","member":{...,
 "endTime":2524579200000,"isPlus":true,"sign":"c57a8e66...325c"}}

network log:
  REQ  https://api.hexhub.cn/client/member/currentv2   ← 被阻断（abort/connectionfailed）
  REQ  https://api.hexhub.cn/client/version/check
  REQ  https://api.hexhub.cn/client/stats/submit

UI:  顶栏 👑 Plus      左侧资产列表仍显示「暂无数据，请检查是否登录」
```

📷 `exports/poc_vip_unlocked.png` — 顶栏显示 **👑 Plus**，同时"请检查是否登录"

**证据 B — 负向对照：同一份伪造数据，服务器可达 → 会话被清空**

```
localStorage["session"] AFTER reload:
{"token":null,"priKey":null,"member":null}      ← 服务端 401 → 拦截器 logout()
```

**证据 C — A/B 二进制补丁对照（同一份"已过期 + 伪造签名"数据）**

| 用例 | member.endTime | member.sign | 二进制 | 顶栏徽章 | 截图 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| A | `1700000000000`（2023 已过期） | 伪造（不匹配） | 原版 | ❌ 无 | `exports/ab_A_original.png` |
| B | 同上 | 同上 | **等长补丁版** | ✅ **👑 Plus** | `exports/ab_B_patched.png` |

```
TEST A: {"crownCount":0,"isMemberValid":false,"endTime":1700000000000,"sessionKept":true}
TEST B: {"crownCount":1,"hasPlusLabel":true,"endTime":1700000000000,"sessionKept":true}
```

---

## 4. 二进制微创补丁（等长，已验证）

`patch_vip.py` 对 `hexhub-backend.exe` 内嵌 bundle 做**等长**替换（文件大小不变，PE 布局不变）：

| 补丁点 | 原始（123 / 300 bytes） | 补丁后 | 作用 |
| :--- | :--- | :--- | :--- |
| P1a `isMemberValid`（主 bundle） | `isMemberValid(){var r;return(r=this==null?...>new Date().getTime():!1}` | `isMemberValid(){return!0}` + 98 空格 | 绕过期判定 |
| P1b `isMemberValid`（Worker bundle） | 同上（变量名 `s`） | 同上 | 同上 |
| P2 `ue`（完整性校验） | `ue=le=>{const f=new Array(3);...:!0}` | `ue=le=>!0` + 291 空格 | 绕签名校验 |

```
[P1a isMemberValid(main)]  occurrences = 1  old_len=123  -> patched
[P1b isMemberValid(worker)]occurrences = 1  old_len=123  -> patched
[P2  ue(sign-check)]       occurrences = 1  old_len=300  -> patched
size equal: True  118715652 == 118715652
differing bytes: 499   (range 0x36f06af .. 0x3a6b927)
```

**验证结论**：打补丁后，**已过期 + 伪造签名**的会员对象仍被判定为有效，顶栏点亮 👑 Plus（证据 C 用例 B）。

> 说明：等长替换用空格填充，JS 语法合法（对象字面量中方法体后接空白再 `,`）。
> 补丁产物：`patches/hexhub-backend.patched.exe`；原始备份：`patches/hexhub-backend.original.exe`。

---

## 5. 纵深防御整改建议

### 5.1 服务端权威闭环（最高优先级，必须落地）

1. **权益发放必须服务端裁决**：所有 VIP 能力的**实际资源**（云同步存储、增强 Agent 推理、移动端会话槽位、
   主题包下载、私有仓库配额）必须在服务端按 `member_id` 实时校验并计费；
   客户端 `isMemberValid()` 只能用于 **UI 呈现**，绝不能作为功能可用性的唯一开关。
2. **废除自证式签名**：`sign = SHA1(endTime*email*SHA1(publicKey))` 必须替换为
   **服务端私钥签名**（Ed25519 / RS256），客户端仅持公钥验签；
   签名载荷须包含 `memberId + endTime + plan + deviceId + issuedAt + nonce`，并绑定设备指纹。
3. **离线宽限期锚定**：本地缓存须带 `serverIssuedAt`，强制「距上次成功服务端确认 ≤ N 天（建议 3–7 天）」
   后失效；禁止无限期离线维持特权。
4. **统一错误分支**：网络不可达与 401 **必须同构处理**（`state=offline` 时降级为免费态），
   杜绝"断网即保权"的反直觉行为。
5. **落盘加固**：`localStorage["session"]` 中的 `member` 应加密存储 + 与设备绑定（DPAPI / TPM），
   并在加载时校验 HMAC（密钥派生于设备指纹）。

### 5.2 客户端加固

6. **前端代码虚拟化 / 混淆**：关键鉴权分支（`isMemberValid` / `ue`）下沉到 Native（C++/Go）并做
   控制流平坦化（OLLVM / VMProtect），提高等长补丁与运行时 Hook 成本。
7. **完整性自检**：启动时校验内嵌 bundle 哈希（PE 资源 / rodata 段 CRC），
   与远端下发的白名单哈希比对；异常则降级为免费态而非直接崩溃。
8. **反调试 / 反注入**：检测 `--remote-debugging-port`、CDP 端点、`showDevTools` 调用，
   并对渲染进程启用 `--disable-devtools` 级别的策略（CEF `settings.javascript_access_clipboard`、
   自定义 `CefRequestHandler` 拒绝 devtools scheme）。
9. **移除隐藏口令后门**：`basicDebug` 的 `MD5(deviceId)` 门禁等效于无门禁，应改为
   服务端下发的一次性调试令牌或彻底移除。
10. **传输层收敛**：对 `client/member/*` 全链路启用请求签名（`sign + nonce + timestamp`）与
    证书绑定（SSL Pinning），防止中间人重放与响应篡改。

### 5.3 检测与运营

11. 服务端对同一 `memberId` 的**异常离线时长**、**设备指纹突变**、**异地并发会话**建立风控规则。
12. 对 `member-asset/*` 云同步等付费资源接口做**配额与速率**强校验（当前依赖客户端上报，易被绕过）。

---

## 6. 附录

### 6.1 工具链

| 工具 | 用途 |
| :--- | :--- |
| 自研 Python NSIS 解析器 | LZMA solid 流解压 + 419 条目表解析 + 77 文件切分（免安装、免 7-Zip） |
| radare2 5.9.8 / seep MCP | PE 元信息、字符串、符号 |
| Playwright (CDP) | 接入运行中 CEF 渲染进程，读写 localStorage / DOM / 网络路由拦截 |
| Node.js crypto | 复算 SHA-1 自证式签名 / 自建 RSA-2048 密钥对 + PKCS1v15 加密 |

### 6.2 交付物清单

```
cases/hexhub-5.1.9/
├── extract.py                      NSIS 解包器（LZMA solid + 条目表解析）
├── patch_vip.py                    等长二进制微创补丁生成器
├── poc_test.js                     ★ 主 PoC（正例 + 负向对照）
├── poc_fake_login.js               ★★ 完全离线模拟登录（自建 RSA + mock currentv2）
├── poc_inject.js                   正例注入（服务器可达，演示被 401 清除）
├── poc_offline_vip.js              攻击链复现（阻断服务器 + 伪造会话）
├── poc_ui_evidence.js              UI 证据 + 负向对照
├── ab_check.js                     A/B 对照检查器
├── samples/extracted/              77 个解包文件（含原始 hexhub-backend.exe）
├── exports/
│   ├── nsis_solid_stream.bin       485,681,983 bytes 解压流（取证留档）
│   ├── vip_bypass.png              证据 A：👑 Plus（未登录 + 断网）
│   ├── fake_login.png              证据 D：👑 Plus（完全离线模拟登录）
│   ├── ab_A_original.png           证据 C-A：原版无徽章
│   └── ab_B_patched.png            证据 C-B：补丁版 👑 Plus
├── patches/
│   ├── poc_forge_session.js        DevTools 一键 PoC（crypto.subtle 自算签名）
│   ├── poc_hook_runtime.js         运行时 Hook 变体
│   ├── block_vendor_server.md      厂商服务器阻断方案（hosts / 防火墙 / CDP）
│   ├── hexhub-backend.patched.exe  等长补丁产物（499 bytes diff）
│   └── hexhub-backend.original.exe 原始备份
└── reports/HexHub-5.1.9-VIP鉴权脆弱性评估报告.md   本报告
```

### 6.3 免责与范围声明

本次评估在用户自有受权沙盒环境内对公开分发的客户端安装包进行**白盒静态 + 动态**验证，
不涉及厂商服务端资产、不进行任何真实交易、未使用任何真实账号凭据。
所有 PoC 与补丁仅用于验证客户端逻辑缺陷并推动纵深防御整改。

---

**评估结论：不通过。** VIP 权益的服务端权威闭环缺失，`CWE-602` 类缺陷贯穿整个会员体系，
在"阻断厂商服务器"这一极易达成的条件下可稳定绕过，须按 §5.1 优先整改。
