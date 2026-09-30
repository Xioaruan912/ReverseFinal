# Quicker 1.45.5.0

## 一、这是什么软件

Quicker 是 Windows 上的效率触发工具：把鼠标中键、Ctrl、轮盘菜单、扩展热键、悬浮按钮、
文本指令等触发方式绑到「动作」上，一键执行组合操作（打开软件、发按键、跑脚本、
处理文件、OCR、翻译…）。常驻托盘运行，是本机使用频率很高的效率中枢。

免费档与专业档的差异全部由客户端本地的一份授权对象决定：

| 维度 | 免费档 | 专业档 |
| :--- | :--- | :--- |
| 会员等级 | `Free` | `Pro` |
| 功能位（6 项） | 全 `False` | 全 `True` |
| 数量配额（6 项） | 全 `0`（部分有很小的硬编码预设） | 大幅放开 |
| 动作页/动作数量 | 受限 | 放开 |

---

## 二、跑完能用什么

一条命令装完即为专业档客户端授权状态：

| 能力 | 免费档 | 本包跑完 |
| :--- | :--- | :--- |
| 会员等级 | Free | **Pro** |
| 到期时间 | 空 | **长期（公元 3651 年）** |
| 手机端（CanUseMobileApp） | ✗ | **✓** |
| 动作历史（EnableActionHistory） | ✗ | **✓** |
| 扩展热键（EnableActionHotKey） | ✗ | **✓** |
| 快速启动器（EnableStarter） | ✗ | **✓** |
| 悬浮按钮（EnableFloatButton） | ✗ | **✓** |
| 搜索（EnableSearching） | ✗ | **✓** |
| 动作页上限 / 动作上限 / 每页动作上限 | 0 | **999 / 999 / 999** |
| 单页文件上限 / 总文件上限 | 0 | **102400 / 1048576** |
| 图标数量上限 | 0 | **9999** |
| 版本更新 | 会检查并提示 | **通道已切断** |
| 上游连通 | getquicker.net / .cn 全通 | **19 个主机不可路由** |

功能位与配额一律以客户端实际读出的值为准，可用 `toolkit\verify_dto.ps1` 当场复核。

---

## 三、环境要求

| 项 | 要求 |
| :--- | :--- |
| 操作系统 | Windows 10 / 11 x64 |
| 运行时 | .NET Framework 4.7.2+（MSI 自带引导） |
| 权限 | 管理员（安装 MSI + 写 hosts 需要） |
| PowerShell | 5.1（系统自带） |
| 外部依赖 | **无**。不需要 Python / Java / .NET SDK / radare2 |

---

## 四、一条命令跑通

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/quicker-vip-test.ps1 | iex"
```

安装包与补丁产物全部从本仓库 Release 固定件拉取，逐个校验 sha256，不匹配立即中止。
全程约 1～2 分钟（含 24 MB 安装包下载）。

| 环境变量 | 作用 |
| :--- | :--- |
| `QK_INSTALLDIR` | 指定安装目录（默认 `桌面\Quicker-1.45.5.0`） |
| `QK_YES=1` | 全程不再询问，使用默认值 |
| `QK_MIRROR` | 安装包镜像前缀（下载慢时用） |
| `QK_SKIP_INSTALL=1` | 已装好，跳过安装 |
| `QK_KEEP_ARTIFACTS=1` | 保留下载的安装包 |
| `QK_NO_HOSTS=1` | 不改 hosts（不做上游切断） |

> **首次使用需先登录一次**：Quicker 需要登录（或点登录窗的「体验」）才会实例化授权对象，
> 而登录依赖上游。顺序是 `hosts_block.ps1 -Mode off` → 登录 → `hosts_block.ps1 -Mode on`。
> 登录之后客户端授权状态由已打补丁的程序集决定，与服务端下发什么无关。

---

## 五、产物与运维

| 项 | 值 |
| :--- | :--- |
| 产出目录 | `桌面\Quicker-1.45.5.0\`（可直接运行的程序目录，长期保留） |
| 启动 | 双击 `Quicker.exe`，常驻托盘 |
| 授权判据 | `powershell -File toolkit\verify_dto.ps1 "<安装目录>\Quicker.Common.dll"` → `VERDICT: PRO` |
| 原始对照 | 同目录 `Quicker.Common.dll.orig` → `VERDICT: FREE` |
| 上游沉洞状态 | `powershell -File toolkit\hosts_block.ps1 -Mode status` |
| 临时放行（登录用） | `powershell -File toolkit\hosts_block.ps1 -Mode off` |
| 重新阻断 | `powershell -File toolkit\hosts_block.ps1 -Mode on` |
| 卸载 | 控制面板 → 程序和功能 → Quicker → 卸载；再删安装目录；再 `hosts_block.ps1 -Mode off` |

原 hosts 自动备份为 `hosts.quickerlab.bak`，`-Mode off` 会移除整块并保留备份。

---

## 六、目录说明

```
Quicker-1.45.5.0/
├── PINNED-VERSIONS.md          固定版本与全部哈希（含 14 处补丁站点）
├── README.md                   本文件
├── 使用说明.txt                 面向使用者的操作说明
├── installer/                  安装包说明（MSI 走 Release，不入库）
├── toolkit/
│   ├── Quicker.Common.patched.dll  VIP 补丁产物（sha256 已钉）
│   ├── verify_dto.ps1             A/B 反射判据（原始 vs 补丁）
│   ├── hosts_block.ps1            上游沉洞 开/关/查（可逆）
│   └── hosts_block.txt            沉洞清单（19 个主机）
├── reports/
│   └── Quicker-1.45.5.0-鉴权脆弱性审计记录.md   ← 成因 / 位点 / 证据 / 整改建议
└── src/
    ├── peil.py    PE / CLR 元数据 / IL 方法体读写库
    ├── ild.py     CIL 反汇编器（自带 opcode 表，零外部依赖）
    ├── xrefs.py   token 调用点定位
    └── qk_patch.py 补丁驱动（含独立回读复验 + 黄金哈希）
```

报告索引：`reports/Quicker-1.45.5.0-鉴权脆弱性审计记录.md`
（授权模型、`ret` 必须置末的 IL 规则、`Quicker.exe` 签名硬边界、冒烟判据、厂商整改建议）
