# Reverse_OK

授权范围内的**客户端鉴权脆弱性白盒审计**成果仓库。

> ⚠️ 本仓库仅用于**用户自有授权环境**下的安全验证与防御加固研究。
> 所有样本均来自公开可获取的官方安装包，未对任何生产服务端发起请求。
> 请勿用于商业侵权或非法用途。

---

## 目录

| 目录 | 目标 | 说明 |
| :--- | :--- | :--- |
| [`Listary/`](Listary/) | Listary 6 Pro (6.3.5.94) | .NET/WPF 客户端 VIP 鉴权脆弱性 —— **CWE-602 / CWE-345** |
| [`HexHub-5.1.9/`](HexHub-5.1.9/) | HexHub Client 5.1.9 (CEF + Go) | 会员权益判定完全客户端化 + 自证式签名 + 可完全离线伪造「登录+下发」 —— **CWE-602 / CWE-345** |

| [`MiaomiaowuX-v0.5.4/`](MiaomiaowuX-v0.5.4/) | 妙妙屋X (miaomiaowuX) v0.5.4 | 自托管 Xray 节点管理与订阅分发 —— 许可门禁与服务器/节点/用户数量配额 —— **CWE-602** |
| [`oneclick/`](oneclick/) | —— | ★ **一键命令**：三个案例各自一条命令，全部从本仓库 Release 拉取并校验 sha256 |
---

## 项目一览

### Listary 6 Pro

* **漏洞**：Pro（VIP）权益完全由客户端本地函数
  `LicenseChecker.CheckLicense(email, license)` 决定；
* **192** 字符的授权码中**只有第 160–178 位被校验**，且校验值是邮箱经
  3 个**可逆非密码学哈希**拼成 96 bit 后做 Base32 的结果；
* **无任何签名 / 非对称验签**，服务端从不下发被客户端验证的凭据；
* 因此**只要知道自己的邮箱就能离线生成合法授权码**。

**成果**：

* `Listary/2-一键激活/` —— 一键激活工具（**常量在目标机运行时推导，不硬编码，随版本自适应**）+ 自动更新阻断；
* `Listary/3-审计资料/` —— 审计报告 + 授权校验函数的**解密后明文 IL**（核心证据）；
* `Listary/src/` —— 自研工装源码（.NET 元数据/IL 转储器、Babel 方法体运行时解密器、IL 微创补丁器）。

---

### HexHub Client 5.1.9

* **架构**：CEF (Chromium 138) 壳 + Go 插件宿主，前端为内嵌 Vue3 bundle；
  经 8,500+ Go 符号全量审计确认**本地后端不含任何会员鉴权逻辑**；
* **漏洞**：VIP 权益的唯一判据是客户端 `isMemberValid() { return member.endTime > Date.now() }`，
  特权状态明文落盘于 `localStorage["session"]`；
* **签名可离线自算**：完整性校验为 `SHA1(endTime*email*SHA1(publicKey))`，
  **零密钥、可完全离线复算**，不构成任何防篡改能力；
* **下发链路非信任锚**：`priKey` 由本地后端 `repository/get-pri-key` 从密码派生，
  攻击者可**自建 RSA-2048 密钥对**并伪造 `client/member/currentv2` 响应，
  让客户端完整走通「拉取 → RSA 解密 → 验签 → 落盘 → 点亮会员」；
* **影响面**：23 个 `vip:!0` 菜单项 + 49 处 `isMemberValid()` 调用；
  其中 21 项为纯客户端判定（多窗口/多视图/分屏/终端广播/跨服务器传输/解除 6 会话上限/
  主题包/Docker 三项等），旁路即生效；
  私有储存仓库的 local/WebDAV/S3 三类**可完全离线工作**；
  唯一服务端强制项为登录设备数配额（Pro 2 台 / Plus 5 台）。

**成果**：

* `HexHub-5.1.9/2-一键白盒测试/` —— 一键工装（NSIS 静态解包 + 启动 + 页面级断网注入 + 取证 + 等长二进制补丁）；
* `HexHub-5.1.9/3-审计资料/` —— 评估报告（12 条整改建议）+ VIP 功能测绘与服务端依赖分级 + 通用方法论 SOP + 四组证据截图；
* `HexHub-5.1.9/src/` —— 自研工装源码（NSIS solid-LZMA 解包器、内嵌 bundle 定位器、VIP 门禁测绘器）。

**四组动态对照**：

| 用例 | 数据 | 二进制/网络 | 结果 |
| :--- | :--- | :--- | :--- |
| A | 伪造终身会员 | 原版 · 厂商服务器阻断 | ✅ 👑 Plus（未登录） |
| B | 伪造 token | 原版 · 服务器可达 | ❌ 401 拦截器清空会话 |
| C1 → C2 | **已过期 + 伪造签名** | 原版 → **等长补丁版** | ❌ → ✅ 👑 Plus（仅换二进制即翻转） |
| D | 自建 RSA + mock 响应 | 原版 · 服务器阻断 | ✅ 👑 Plus（客户端认为已登录+已同步） |

---

## 一键命令（三个案例通用）

测试工具包与被测软件**全部从本交付仓库的 Release 拉取**，下载后逐一校验 sha256，
不匹配立即中止；不访问被测软件官网的「最新版」，厂商发新版不会改变测试对象。

```powershell
# HexHub —— 会员权益
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 | iex"

# Listary 6 —— 专业版权益
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1 | iex"
```

```bash
# 妙妙屋X —— 许可门禁与数量配额（Linux / WSL）
bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh)

# 同案例的 Windows 入口（自动交给 WSL 执行）
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.ps1 | iex"
```

| 案例 | 固定版本 | 入口脚本 |
| :--- | :--- | :--- |
| HexHub | **5.1.9** | `oneclick/hexhub-vip-test.ps1` |
| Listary 6 | **6.3.5.94** | `oneclick/listary-pro-test.ps1` |
| 妙妙屋X | **v0.5.4** | `oneclick/miaomiaowux-license-test.sh` / `.ps1` |

**Release（全部固定构件 + `SHA256SUMS.txt`）**
→ https://github.com/Xioaruan912/ReverseFinal/releases/tag/whitebox-audit-v1.0

每个案例根目录都有 `PINNED-VERSIONS.md`，记录版本号与 sha256；
**落点隔离**：HexHub / Listary 在 `%TEMP%\<case>-lab\`，妙妙屋X 在 WSL 的 `~/mmwx-lab/`；
Listary 提供 `-Restore` 一键回滚，妙妙屋X 不写 systemd、不动 `/etc`。

完整说明与参数见 [`oneclick/README.md`](oneclick/README.md)。

---

## 免责声明

本项目为安全研究用途，作者不对任何滥用行为负责。
使用者须自行确认其测试目标处于合法授权范围内。
