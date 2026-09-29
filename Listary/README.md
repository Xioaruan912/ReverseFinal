# Listary 6 Pro · 白盒鉴权测试包

| 项 | 值 |
| :--- | :--- |
| 目标 | Listary 6 `Listary.exe` |
| 版本 | `6.3.5.94`（2025-08-15 构建） |
| 运行时 | .NET Framework 4.8 / WPF（x86 AnyCPU）+ Rust 引擎 `listary_engine.dll` |
| 一句话结论 | 专业版（Pro）权益完全由客户端本地判定，任意自有邮箱即可离线获得 Pro |

---

## 测试后可用功能

完成一次测试（无需购买记录、不访问厂商账号服务器）后，下列 Pro 能力即解锁：

| 能力 | 测试后 | 备注 |
| :--- | :---: | :--- |
| 标题栏 `Listary Pro` 标识 | ✅ | 界面即刻刷新 |
| `ProBadge` 点亮 | ✅ | — |
| 高级搜索语法 | ✅ | Pro 功能门解锁 |
| 自定义过滤器 | ✅ | Pro 功能门解锁 |
| 工作区（Workspace） | ✅ | Pro 功能门解锁 |
| 主题 | ✅ | Pro 功能门解锁 |
| 自定义动作 / 自定义命令 | ✅ | Pro 功能门解锁 |
| 索引增强 | ✅ | Pro 功能门解锁 |
| 自动更新 | 默认已阻断 | 防止厂商新版覆盖本地结果（可选开关） |

> 权益落地链路：`ProService.IsPro` 一旦为 `true`，全部 Pro 特性同步生效。
> 详细清单与实测记录见 [`reports/鉴权脆弱性审计报告.md`](reports/鉴权脆弱性审计报告.md)。

---

## 一键使用

```powershell
# 推荐：一条命令跑完（自动取件 + 校验 + 安装 + 激活 + 复核）
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1 | iex"
```

或在本目录手动操作：

1. 未安装 Listary → 运行 [`installer/`](installer/) 内的官方安装包
2. 双击 `toolkit\1-一键激活.bat` → 输入任意自有邮箱
3. 看到 `目标自身 CheckLicense 自检 : True` 即成功；
   按 `双击 Ctrl` 唤出 Listary，标题栏应显示 `Listary Pro`

其它工具（都在 [`toolkit/`](toolkit/)）：

| 文件 | 作用 |
| :--- | :--- |
| `1-一键激活.bat` | 双击即用，自动 UAC 提权 |
| `2-只生成授权码.bat` | 只算码，不写任何文件 |
| `3-阻断自动更新.bat` | 设置项 + hosts 双阻断 |
| `4-撤销激活.bat` | 移除授权键，可反复切换 |

---

## 目录结构

```
Listary/
├─ 使用说明.txt                       给最终使用者看的速查
├─ installer/                         官方安装包放置说明
├─ toolkit/                           一键激活工装
│   ├─ 1-一键激活.bat
│   ├─ 2-只生成授权码.bat
│   ├─ 3-阻断自动更新.bat
│   ├─ 4-撤销激活.bat
│   └─ Listary6Pro.exe                核心工具（25 KB）
├─ reports/                           审计报告 / 解密明文 IL（核心证据）
└─ src/                               自研工装源码
    ├─ Listary6Pro.cs                 激活工具（运行时常量推导 + 目标自检）
    ├─ BabelDump.cs                   Babel 方法体 / 字符串运行时解密器
    ├─ NetDump.cs                     .NET 元数据 + IL 转储器
    ├─ net_ilpatch.py                 .NET IL 微创补丁器
    ├─ listary6_keygen.py             Python 版生成器
    └─ strx.py                        轻量字符串提取器
```

---

## 工具为什么不怕厂商更新

`Listary6Pro.exe` **不硬编码任何厂商常量**：

1. 加载**本机已安装的** `Listary.exe`，用反射读 `LicenseChecker` 自己的
   字母表、授权码长度与哈希函数；
2. 以**目标自己的校验函数作为预言机**暴力求解布局，实测 **0.2 秒**收敛；
3. 写入后用**目标自己的**校验函数与设置加载器双重自检，
   自检不通过**不会报告成功**。

同时默认做自动更新阻断，确保厂商推新版本后本地验证仍然成立。

---

## 自研工装

| 工具 | 作用 |
| :--- | :--- |
| `NetDump.cs` | 基于 .NET 反射的元数据 + IL 转储器，混淆名转义为 `\uXXXX` |
| `BabelDump.cs` | 利用 Babel 运行时**自身**的解密链路还原明文 IL 与加密字符串 |
| `net_ilpatch.py` | 纯 Python 的 ECMA-335 元数据解析 + 方法体覆写（用于验证防篡改） |
| `strx.py` | ASCII + UTF-16 字符串提取 |

编译（.NET Framework 自带编译器，无需 SDK）：

```bat
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe -codepage:65001 ^
  -target:exe -out:Listary6Pro.exe -platform:x86 ^
  -r:System.Web.Extensions.dll -r:System.Numerics.dll Listary6Pro.cs
```

---

## 关于常量打码

`reports/` 涉及的 2 个**目标静态常量**（吊销名单盐值、6 项吊销 MD5）已替换为
`<SALT_REDACTED>` / `<REVOKED_HASH_REDACTED>`。它们是从公开可下载的官方
`Listary.exe` 中提取的静态常量，不属于用户凭据或服务端密钥。

打码**不影响任何功能**：`toolkit/Listary6Pro.exe` 在目标机上**运行时自行推导**全部常量，
并以目标自身的校验函数作为预言机校验每一个候选解（无假阳性）。
