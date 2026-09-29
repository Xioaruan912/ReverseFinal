# HexHub Client 5.1.9 —— 客户端鉴权脆弱性白盒审计（CWE-602）

> **目标**：HexHub Client `windows-amd64-installer-5.1.9.exe`（CEF + Go 架构的数据库/SSH/Docker 客户端）
> **结论**：会员（VIP）权益判定**完全在客户端**，且"完整性签名"是不含任何服务端密钥的**自证式哈希**。
> 无需账号、无需破解通信协议，只要让厂商授权服务器不可达并写入本地会话，即可点亮 **👑 Plus 终身版**。
>

---

## 目录

| 目录 | 说明 |
| :--- | :--- |
| [`installer/`](installer/) | 目标安装包放置说明（145MB 超 GitHub 限制，不入库） |
| [`toolkit/`](toolkit/) | ★ 一键测试工装（静态解包 / 启动 / 断网注入 / 取证 / 二进制补丁） |
| [`reports/`](reports/) | ★ 评估报告 + VIP 功能测绘 + 通用方法论 SOP + evidence |
| [`src/`](src/) | 自研分析工装源码（NSIS 解析器 / bundle 定位 / JS 美化 / VIP 门禁测绘） |

---

## 一、漏洞清单

| 编号 | 漏洞 | CWE | 级别 | 验证方式 |
| :--- | :--- | :--- | :--- | :--- |
| **VULN-01** | VIP 判定 = `member.endTime > Date.now()`，状态落盘 `localStorage["session"]` 明文可写 | **CWE-602** | 严重 | 动态 |
| **VULN-02** | 会员完整性签名 = `SHA1(endTime*email*SHA1(publicKey))` —— **自证式哈希，零密钥** | CWE-345 / CWE-472 | 严重 | 动态 |
| **VULN-03** | 断网 → 保留会员；401 → 清会话（**断网反而保权**），无离线锚点 | CWE-613 / CWE-636 | 中 | 动态 |
| **VULN-04** | 隐藏 DevTools 后门：口令 = `MD5(deviceId)`，deviceId 本地可改 | CWE-489 | 低 | 静态 |
| **VULN-05** | 会员下发链路不构成信任锚：私钥 `priKey` 本地生成，可**自建 RSA 密钥对完全离线伪造「登录+下发」** | CWE-345 / CWE-602 | 严重 | 动态 |

---

## 二、核心位点（逆向自内嵌前端 bundle）

```js
// ① VIP 权益的唯一判据（pinia store，persist=true -> localStorage["session"]）
isMemberValid() {
  return this?.member != null && this.member.endTime
    ? this.member.endTime > new Date().getTime()      // ← 纯本地时间比较
    : false;
}

// ② 会员完整性校验（自证式哈希，无密钥）
ue = m => SHA1(`${m.endTime}*${m.email}*${SHA1(m.publicKey)}`) === m.sign;

// ③ 会员下发链路：私钥在客户端本地（本地后端 repository/get-pri-key 从密码派生）
Xs = async (priKey, token) => {
  const n = await hn.get("client/member/currentv2", { headers: { Authorization: token } });
  priKey -> PEM -> RSA-2048 (WASM)
  return JSON.parse(concat(RSA_PKCS1v15_decrypt(chunk) for chunk in n));
};
```

**终身版哨兵值**：`endTime >= 2524579200000`（2050-01-01）
**套餐档位**：专业版 Pro / 增强版 Plus

---

## 三、动态验证（A/B/C/D 四组对照）

| 用例 | 数据 | 二进制 / 网络 | 顶栏徽章 | 截图 |
| :--- | :--- | :--- | :--- | :--- |
| **A** | 伪造终身会员 | 原版 · **厂商服务器阻断** | ✅ 👑 Plus（未登录） | [`证据A`](reports/evidence/证据A-未登录断网仍显示Plus.png) |
| **B** | 伪造 token | 原版 · 服务器可达 | ❌ 会话被 401 拦截器清空 | — |
| **C1** | **已过期** + 伪造签名 | 原版 | ❌ 无徽章 | [`证据C1`](reports/evidence/证据C1-原版无徽章.png) |
| **C2** | 同 C1（**同一份过期/伪造数据**） | **等长补丁版** | ✅ 👑 Plus | [`证据C2`](reports/evidence/证据C2-补丁版Plus.png) |
| **D** | 自建 RSA 密钥对 + mock 响应 | 原版 · 服务器阻断 | ✅ 👑 Plus（客户端认为已登录+已同步） | [`证据D`](reports/evidence/证据D-完全离线模拟登录Plus.png) |

> **C 组意义**：同一份「2023 已过期 + 伪造签名」数据，仅换二进制 → 结果翻转，证明判定被绕过。
> **D 组意义**：连"登录"都不需要 —— 客户端用**自建密钥**解出**伪造会员**并完整走通「拉取 → 解密 → 验签 → 落盘 → 点亮会员」。

---

## 四、影响面

* VIP 门禁共 **23 个菜单项 `vip:!0` + 49 处 `isMemberValid()` 调用**
* **21 项为纯客户端判定**（多窗口 / 多视图 / 分屏 / 终端广播 / 跨服务器文件传输 / 解除 6 会话上限 /
  主题包 / Docker 自选镜像仓库 · 本地网络拉取 · 容器文件管理 / 压缩解压 / ssh-copy-id 等）→ 旁路即生效
* 仅「官方云同步」「表数据同步」有服务端数据面依赖；
  而「自定义私有储存仓库」的 **local / WebDAV / S3** 三类**完全由客户端直连用户自有存储**，旁路后可**完全离线工作**
* 唯一由服务端强制的是**登录设备数配额**（Pro 2 台 / Plus 5 台）

详见 [`reports/VIP功能测绘与服务端依赖分析.md`](reports/VIP功能测绘与服务端依赖分析.md)

---

## 五、一键使用

```powershell
cd HexHub-5.1.9

# ① 环境自检（13 项）
powershell -ExecutionPolicy Bypass -File .\toolkit\preflight.ps1

# ② 主测试：静态解包 -> 启动客户端 -> 页面级断网 + 伪造会话 -> 取证
powershell -ExecutionPolicy Bypass -File .\toolkit\run_test.ps1 -NegativeControl

# ③ 路线 D：完全离线模拟登录（无需任何账号）
cd toolkit
$env:NODE_PATH="C:\Users\Administrator\.pi\agent\npm\node_modules"
node poc_fake_login.js
```

**测试不做什么**：不改 hosts / 防火墙 / 注册表；不执行安装器；不碰已安装的 HexHub。
断网走 **Playwright 页面级 route abort**（仅拦截本页面请求，零系统改动）。

---

## 六、二进制微创补丁（登录场景首选）

```powershell
cd toolkit
python patch_vip.py
#  P1a/P1b  isMemberValid(){...}  ->  isMemberValid(){return!0}   (主 bundle + worker bundle)
#  P2       ue=le=>{...}          ->  ue=le=>!0                   (完整性校验)
#  等长替换：文件大小不变（118,715,652 == 118,715,652），仅 499 字节差异
```

---

## 七、整改建议（摘要，完整 12 条见评估报告 §5）

1. **服务端权威闭环**：VIP 能力的**实际资源**必须服务端按 `member_id` 实时校验；
   客户端 `isMemberValid()` 只能用于 UI 呈现。
2. **废除自证式签名**：`SHA1(endTime*email*SHA1(publicKey))` 无密钥、可离线复算，
   必须换**服务端私钥签名**（Ed25519 / RS256），载荷绑定 `memberId + exp + deviceId + nonce`。
3. **`priKey` 不应是信任锚**：它由本地后端从密码派生，只提供传输机密性，**不提供授权完整性**。
4. **离线宽限期锚定**：本地缓存带 `serverIssuedAt`，强制「距上次成功确认 ≤ 3–7 天」后失效。
5. **统一错误分支**：网络不可达与 401 必须同构处理，杜绝"断网即保权"。

---

## 八、免责声明

本项目为安全研究用途，作者不对任何滥用行为负责。
使用者须自行确认其测试目标处于合法授权范围内。
所有样本均来自公开可获取的官方安装包，测试全程未对厂商服务端发起真实业务请求。
