# Quicker 1.45.5.0 — 客户端鉴权脆弱性白盒审计（授权测试）

> 目标：`Quicker.exe` / `Quicker.Common.dll`（.NET Framework 4.x · C# / WPF）
> 类型：**CWE-602 客户端强行实施服务端安全机制**
> 范围：自有授权环境内的客户端逻辑验证与防御加固研究

---

## 一键命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/quicker-vip-test.ps1 | iex"
```

固定版本 `1.45.5.0`，安装包与补丁产物**全部从本仓库 Release 拉取**并逐一校验 sha256，
不访问被测软件官网的「最新版」，厂商发新版不会改变测试对象。

---

## 这个包做了什么

| 能力 | 实现层 | 判据 |
| :--- | :--- | :--- |
| **VIP 放行** | `Quicker.Common.dll` 14 处 IL 等长改写 | `MemberLevel=Pro` + 6 项功能位 True + 6 项配额放开 |
| **禁止更新** | DNS 沉洞切断版本/下载通道 | 19 个上游主机 → `0.0.0.0` |
| **脱离上游** | hosts 可逆管控块 | `Resolve-DnsName` 全部返回 `0.0.0.0` |

`Quicker.exe` **保持字节完全原样**——原因见下。

---

## ★ 关键发现一：`ret` 必须是方法体最后一个字节

上一轮把「常量 IL 改写必抛 `InvalidProgramException`」判成了**方法体完整性守卫**。这是误判。

```
02 7B xx xx 00 04 2A     ldarg.0; ldfld; ret        ← 原版，合法
20 03 00 00 00 2A 00     ldc.i4 3; ret; nop          ← ❌ InvalidProgramException
00 20 03 00 00 00 2A     nop; ldc.i4 3; ret          ← ✅ 正常返回 3
```

`ret` 之后不能再有任何字节。用**自编译的 scratch 程序集**做同样的改写会复现同一错误，
证明这与任何保护机制无关，是纯 IL 结构问题。

配套反证（用来锁死结论，不是推测）：

| 变体 | 结果 |
| :--- | :--- |
| 原样写回 | ✅ 正常 |
| 只改 `ldfld` token 一个字节 | ✅ **正常编译并执行**（抛 `FieldAccessException`） |
| 方法体外翻字节（DOS stub / MVID / 文件尾） | ✅ 正常 → **不存在全文件哈希校验** |
| `ret` 不在末字节 | ❌ `InvalidProgramException` |

---

## ★ 关键发现二：`Quicker.exe` 是不可二进制补丁的硬边界

```
Authenticode : Valid（CN=Beijing LiErHeXun Tech Co., Ltd.）
嵌入式清单    : <requestedExecutionLevel level="asInvoker" uiAccess="true" />
```

`uiAccess="true"` 的进程，Windows **只授予签名有效的映像**。8 组变量二分定位：

| 变体 | 内容 | 结果 |
| :--- | :--- | :--- |
| V1 | 原版 exe + 原版 dll | ✅ ALIVE |
| V2 | 原版 exe + **补丁 dll** | ✅ ALIVE |
| V3 | **仅改清单** `uiAccess="true"` → `"false"` | ❌ 启动即崩 |
| V4~V6 | 清单 + 上游字符串 / 更新入口短路 | ❌ 崩溃 |
| V7~V8 | 全量补丁 exe | ❌ 崩溃 |

- 保持 `uiAccess="true"` 改字节 → `CreateProcess` 直接失败（`ERROR_ELEVATION_REQUIRED`）
- 放宽成 `uiAccess="false"` → 进程能创建，但 log4net 初始化前抛未处理 CLR 异常
  （事件日志 `Application Error 0xe0434352`）
- 放到**非安全路径**同样崩溃 → 与位置无关
- Quicker.exe 内含 `X509Certificate` / `VerifyHash` 字符串 → 存在签名/哈希校验路径

**结论**：`Quicker.Common.dll` 未签名（`NotSigned`）所以可改；`Quicker.exe` 已签名所以不可改。
「禁止更新 / 脱离上游」因此下沉到 DNS 层实现——等价且更彻底，且零回归。

> 已定位但未启用的更新入口（保留为证据）：`SoftVersionHelper.CheckVersionUpdateAfterFirstSync`、
> `<MenuCheckUpdate_OnClick>d__216::MoveNext`、`<MenuUpdateVersion_OnClick>d__207::MoveNext`、
> `<BtnCheckVersion_OnClick>d__5::MoveNext`。
> ⚠️ `IsVersionNewer` **不要改**——它有 20+ 调用点，其中包含共享动作版本比较。

---

## 判据（A/B）

```powershell
# 补丁产物
powershell -NoProfile -ExecutionPolicy Bypass -File toolkit\verify_dto.ps1 toolkit\Quicker.Common.patched.dll

# 安装目录里的实际文件
powershell -NoProfile -ExecutionPolicy Bypass -File toolkit\verify_dto.ps1 "C:\path\to\Quicker.Common.dll"
```

| 属性 | 原始 | 补丁后 |
| :--- | :--- | :--- |
| `MemberLevel` | `Free` | **`Pro`** |
| `MemberExpireTimeUtc` | `<null>` | `<null>`（消费者按 `DateTime.MaxValue` 处理） |
| `CanUseMobileApp` / `Enable*` | `False` | **`True`** |
| `MaxPcCount` / `MaxExeCount` / `MaxPagePerExe` | `0` | **`999`** |
| `MaxPageFileSize` / `TotalPageFileSize` / `MaxIconCount` | `0` | **`102400` / `1048576` / `9999`** |

---

## 上游沉洞（可逆）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File toolkit\hosts_block.ps1 -Mode status
powershell -NoProfile -ExecutionPolicy Bypass -File toolkit\hosts_block.ps1 -Mode off   # 临时放行（登录用）
powershell -NoProfile -ExecutionPolicy Bypass -File toolkit\hosts_block.ps1 -Mode on    # 重新阻断
```

覆盖 19 个主机：`getquicker.net` / `getquicker.cn` 全部子域（授权、同步、推送、更新、帮助），
以及 `*.aliyuncs.com` / `*.bcebos.com` 云状态与临时文件桶。原 hosts 自动备份为 `hosts.quickerlab.bak`。

> ⚠️ 首次使用需登录（或点「体验」）。登录依赖上游，请先 `-Mode off`，登录成功后再 `-Mode on`。
> 登录后客户端授权状态由**已补丁的 `Quicker.Common.dll`** 决定，与服务端无关。

---

## 目录

```
Quicker-1.45.5.0/
├── PINNED-VERSIONS.md          固定版本与全部哈希
├── README.md                   本文件
├── 使用说明.txt                 面向使用者的操作说明
├── installer/                  安装包说明（MSI 走 Release，不入库）
├── toolkit/
│   ├── Quicker.Common.patched.dll  VIP 补丁产物（sha256 已钉）
│   ├── verify_dto.ps1             A/B 反射判据
│   ├── hosts_block.ps1            上游沉洞 开/关/查（可逆）
│   └── build/hosts_block.txt      沉洞清单
├── reports/
│   └── Quicker-1.45.5.0-鉴权脆弱性审计记录.md
└── src/
    ├── peil.py    PE / CLR 元数据 / IL 方法体读写库
    ├── ild.py     CIL 反汇编器（自带 opcode 表，零外部依赖）
    ├── xrefs.py   token 调用点定位
    └── qk_patch.py 补丁驱动（含独立回读复验 + 黄金哈希）
```

---

## 防御加固建议（厂商侧）

1. **服务端权威**：`MemberLevel` / `UserLimitation` 不得作为唯一门禁；特权动作与配额扣减必须服务端二次鉴权。
2. **授权 DTO 下沉**：本例已证明签名 + `uiAccess` 足以阻止主程序被改，但未签名的伴生程序集仍可被改写 →
   授权模型应下沉到已签名程序集或 Native 层，并对关键方法体加运行时哈希校验。
3. **判据分离**：后端门禁 / 前端展示 / 数量配额三层都会被同一份 DTO 带着走，单点汇聚 = 单点失效。
4. **传输层**：全部 API 强制 `Nonce + Timestamp + Sign` + 证书绑定。
5. **强名 + 完整性**：对未签名程序集启用强名并校验方法体完整性。
