# Listary 6 Pro —— 客户端鉴权脆弱性白盒审计

| 项 | 值 |
| :--- | :--- |
| 目标 | Listary 6 `Listary.exe` |
| 版本 | `6.3.5.94`（2025-08-15 构建） |
| 运行时 | .NET Framework 4.8 / WPF（x86 AnyCPU）+ Rust 引擎 `listary_engine.dll` |
| 代码保护 | **Babel Obfuscator v10**（符号混淆 / 字符串加密 / 方法体加密 / 控制流平坦化 / 方法体防篡改） |
| 漏洞类别 | **CWE-602** 客户端强行实施服务端安全机制、**CWE-345** 数据真实性验证不充分 |
| 严重级别 | 高 —— 单一用户零成本伪造永久 Pro 授权 |

---

## 目录结构

```
Listary/
├─ 使用说明.txt                    ← 给最终使用者看的（GBK 编码）
├─ 1-安装包/
│   └─ Listary_Setup_6.3.exe       官方安装包
├─ 2-一键激活/
│   ├─ 1-一键激活.bat              双击即用，自动 UAC 提权
│   ├─ 2-只生成授权码.bat           只算码，不写任何文件
│   ├─ 3-阻断自动更新.bat           设置项 + hosts 双阻断
│   ├─ 4-撤销激活.bat               移除授权键，可反复切换
│   └─ Listary6Pro.exe             核心工具（25 KB）
├─ 3-审计资料/
│   ├─ 鉴权脆弱性审计报告.md         完整技术报告（成因 / 复现 / 修复建议）
│   ├─ LicenseChecker-解密明文IL.txt 授权校验函数的解密后 IL（核心证据）
│   └─ listary6_keygen.py           等价的 Python 版生成器（交叉验证用）
└─ src/                            自研工装源码
    ├─ Listary6Pro.cs              激活工具（运行时常量推导 + 目标自检）
    ├─ BabelDump.cs                Babel 方法体/字符串运行时解密器
    ├─ NetDump.cs                  .NET 元数据 + IL 转储器
    ├─ net_ilpatch.py              .NET IL 微创补丁器
    ├─ listary6_keygen.py          Python 版生成器
    └─ strx.py                     轻量字符串提取器
```

---

## 漏洞原理

Listary 6 的 Pro 权益**完全由客户端本地决定**：

```csharp
// Listary.Core.Pro.ProService
ProService::.ctor(settings, factory)
    └─ \ue000()
         └─ \ue001() = LicenseChecker.CheckLicense(settings.Listary5LicenseEmail,
                                                  settings.Listary5LicenseKey)
              └─ set_IsPro(result)      // ← 唯一来源，与服务端无关
```

而 `CheckLicense` 的全部逻辑（从 Babel 加密方法体中还原）：

```csharp
public static bool CheckLicense(string email, string license) {
    if (email == null || license == null) return false;
    if (license.Length != 192) return false;                       // 仅长度约束
    email = email.ToLowerInvariant();
    var h96 = ((BigInteger)F0(email) << 64)
            | ((BigInteger)F1(email) << 32)
            |  (BigInteger)F2(email);                              // 96bit，3×32bit
    var code = "";
    for (int i = 0; i < 19; i++)
        code += ALPHABET[(int)((h96 >> (96 - (i + 1) * 5)) & 31)]; // Base32，每 5bit
    if (license.Substring(160, 19) != code) return false;          // ← 只校验 19/192 字符
    if (BLACKLIST.Contains(Md5Hex(email + SALT))) return false;    // ← 仅邮箱黑名单
    return true;                                                   // ← 无任何验签
}
```

* `F0` = `h = 43*h + c`（wrapping uint32）
* `F1` = ELF hash
* `F2` = 4 路 XOR，`h ^= s[i] << ((j*8) & 31)`
* `ALPHABET` = `23456789ABCDEFGHJKLMNPQRSTUVWXYZ`（32 字符）
* 授权码 **192** 字符中，**第 0–159 与第 179–191 位完全不参与任何校验**

三条可独立利用的入口，全部**不需要修改任何二进制**：

1. **选项 → Listary Pro 页**：`ProOptionsViewModel::ew()` 纯本地校验后落盘并置 `IsPro = true`，**不联网**；
2. **Pro 窗口「激活授权」弹窗**：`ProService.ActivateNewLicense()` 先本地校验，再请求
   `POST https://account.listary.com/api/v1/activate`；**只有当网络异常（返回码 3）或服务端返回成功时**才落盘 ——
   即：**让 `account.listary.com` 不可达即可成功**（只有明确返回 `invalid_license`/`no_activations_left` 才失败）；
3. **设置文件注入**：`%APPDATA%\Listary\UserProfile\Settings\Preferences.json`
   的 `Settings.Listary5.ProLicense.Email / .Key` 即权益来源。

> 附带发现：Babel 的**方法体防篡改确实有效** —— 静态改写 IL 会在 JIT 阶段抛
> `InvalidProgramException`。但**保护对象错配**：保护了二进制完整性，却没保护权益数据的真实性。

---

## 快速开始

见 [`使用说明.txt`](使用说明.txt)。三步：

1. 没装 Listary → 跑 `1-安装包\Listary_Setup_6.3.exe`
2. 双击 `2-一键激活\1-一键激活.bat` → 输入任意自己的邮箱
3. 看到 `目标自身 CheckLicense 自检 : True` 即成功；`双击 Ctrl` 唤出 Listary 看标题栏是否为 `Listary Pro`

---

## 工具为什么不怕厂商更新

`Listary6Pro.exe` **不硬编码任何厂商常量**：

1. 加载**本机已安装的** `Listary.exe`，用反射读 `LicenseChecker` 自己的
   32 字符字母表、授权码长度、3 个 `uint(string)` 哈希函数；
2. 以**目标自己的 `CheckLicense()` 作为预言机**，暴力求解布局
   （哈希函数→位段顺序 6 种排列 × 位序 × 位置 × 总长），实测 **0.2 秒**收敛；
3. 写入后用**目标自己的** `CheckLicense()` 与设置加载器 `IsPro` 双重自检，
   自检不通过**不会报告成功**。

同时默认做自动更新阻断（`AutoUpdate.EnableAutoUpdate=false` + hosts 屏蔽
`dl.listary.com` / `account.listary.com` / `sentry.listary.com`），
确保厂商推新版本后本地验证仍然成立。

---

## 修复建议（要点）

1. **确立服务端权威**：下线纯本地判定；`IsPro` 必须由服务端签发的
   **非对称签名凭据**（Ed25519 / ECDSA P-256 / RSA-PSS）推导，客户端只内置公钥并真实验签；
2. 授权码格式改为 `<base32(payload)>.<base64(signature)>`，payload 含
   `email / edition / issued_at / expire_at / key_id`；
3. 引入**短期令牌 + 可撤销列表**（CRL），替代"邮箱 MD5 黑名单"；
4. 强制 TLS 证书绑定（SSL Pinning）并校验激活应答签名；
5. 设备席位硬上限 + 并发检测；移除"一次性导入即信任"的旁路（`Listary5.SettingsImported`）；
6. 加固预算应从"防补丁"转向"**防伪造**"。

完整内容见 [`3-审计资料/鉴权脆弱性审计报告.md`](3-审计资料/鉴权脆弱性审计报告.md)。

---

## 自研工装

| 工具 | 作用 |
| :--- | :--- |
| `NetDump.cs` | 基于 .NET 反射的元数据 + IL 转储器，混淆名转义为 `\uXXXX` |
| `BabelDump.cs` | 利用 Babel 运行时**自身**的解密链路还原明文 IL 与加密字符串：<br>定位派发器 `\ue1cd::\ue00f` → 单例 → 私有解析器 `(id, null, null)` → `Delegate` → `RTDynamicMethod` → `m_resolver.m_code`（明文 IL）+ `m_DynamicILInfo.m_scope.m_tokens`（动态 token 表） |
| `net_ilpatch.py` | 纯 Python 的 ECMA-335 元数据解析 + 方法体覆写（用于验证防篡改） |
| `strx.py` | ASCII + UTF-16 字符串提取（替代缺失的 `strings`） |

编译（.NET Framework 自带编译器，无需 SDK）：

```bat
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe -codepage:65001 ^
  -target:exe -out:Listary6Pro.exe -platform:x86 ^
  -r:System.Web.Extensions.dll -r:System.Numerics.dll Listary6Pro.cs
```

---

## 免责声明

本项目为安全研究用途。所有测试均在自有授权环境内完成，
仅使用离线静态分析与目标程序自身的代码调用，未对生产服务端发起任何请求。
作者不对任何滥用行为负责。

---

## 关于常量打码

本仓库中 `3-审计资料/` 涉及的 2 个**目标静态常量**（吊销名单盐值、6 项吊销 MD5）
已替换为 `<SALT_REDACTED>` / `<REVOKED_HASH_REDACTED>`。

它们是从**公开可下载的官方 `Listary.exe`** 中用 Babel 解密链提取的静态常量，
不属于用户凭据或服务端密钥。打码**不影响任何功能**：
`2-一键激活/Listary6Pro.exe` 在目标机上**运行时自行推导**全部常量，
并以**目标自身的 `CheckLicense()` 作为预言机**校验每一个候选解（无假阳性），
最坏情况是找不到解并诚实报错。

→ 详见 [`3-审计资料/鉴权脆弱性审计报告.md`](3-审计资料/鉴权脆弱性审计报告.md)
