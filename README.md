# Reverse_OK

授权范围内的客户端鉴权脆弱性白盒审计成果仓库。仅用于自有授权环境的安全验证与防御加固研究。

---

## 一键命令

四条命令，各自复制即用。测试工具包与被测软件**全部从本仓库 Release 拉取**，
下载后逐一校验 sha256，不匹配立即中止；不访问被测软件官网的「最新版」，
厂商发新版不会改变测试对象。

```powershell
# HexHub —— 会员权益（SSH / SFTP / Docker / 数据库客户端）
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 | iex"

# Listary 6 —— 专业版权益（Windows 文件搜索增强）
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1 | iex"
```

```powershell
# Beyond Compare 5 —— 离线凭证判定（Delphi / VCL 原生 PE）
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/beyondcompare-license-test.ps1 | iex"
```

```powershell
# Quicker 1.45.5.0 —— 客户端鉴权状态（.NET / C# WPF 托盘工具）
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/quicker-vip-test.ps1 | iex"
```

```bash
# 妙妙屋X —— 许可门禁与数量配额（Linux / WSL）
bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh)

# 同案例的 Windows 入口（自动交给 WSL 执行）
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.ps1 | iex"
```

| 目标 | 固定版本 | 入口脚本 |
| :--- | :--- | :--- |
| HexHub | 5.1.9 | `oneclick/hexhub-vip-test.ps1` |
| Listary 6 | 6.3.5.94 | `oneclick/listary-pro-test.ps1` |
| 妙妙屋X | v0.5.4 | `oneclick/miaomiaowux-license-test.sh` / `.ps1` |
| Beyond Compare | 5.2.6.32774 | `oneclick/beyondcompare-license-test.ps1` |
| Quicker | 1.45.5.0 | `oneclick/quicker-vip-test.ps1` |

构件来源：<https://github.com/Xioaruan912/ReverseFinal/releases/tag/whitebox-audit-v1.0>
（全部固定构件 + `SHA256SUMS.txt`）

---

## 项目树

```
Reverse_OK/
├── README.md
├── Agent.md                     作业规范（脚本 / 安装包 / 一键 / 上传）
├── oneclick/                    一键命令入口（四条命令的脚本）
│   ├── README.md
│   ├── hexhub-vip-test.ps1
│   ├── listary-pro-test.ps1
│   ├── miaomiaowux-license-test.sh
│   ├── miaomiaowux-license-test.ps1
│   └── quicker-vip-test.ps1
│
├── HexHub-5.1.9/                HexHub Client 5.1.9 · 会员权益
│   ├── README.md
│   ├── PINNED-VERSIONS.md
│   ├── 使用说明.txt
│   ├── installer/               安装包放置说明
│   ├── toolkit/                 一键白盒测试工装
│   ├── reports/                 评估报告 / 功能测绘 / SOP / 证据截图
│   └── src/                     自研分析工装源码
│
├── BeyondCompare-5.2.6/         Beyond Compare 5 · 离线凭证判定
├── Quicker-1.45.5.0/            Quicker 1.45.5.0 · 客户端鉴权状态 + 上游切断
│   ├── README.md
│   ├── PINNED-VERSIONS.md
│   ├── 使用说明.txt
│   ├── installer/               安装包放置说明
│   ├── toolkit/                 补丁产物 / A-B 判据 / 上游沉洞开关
│   ├── reports/                 审计记录
│   └── src/                     PE-CLR-IL 读写库 / 反汇编器 / 补丁驱动
├── Listary/                     Listary 6.3.5.94 · 专业版权益
│   ├── README.md
│   ├── PINNED-VERSIONS.md
│   ├── 使用说明.txt
│   ├── installer/               安装包放置说明
│   ├── toolkit/                 一键激活工装
│   ├── reports/                 审计报告 / 解密明文 IL · 证据截图
│   └── src/                     自研工装源码
│
└── MiaomiaowuX-v0.5.4/          妙妙屋X v0.5.4 · 许可门禁与数量配额
    ├── README.md
    ├── PINNED-VERSIONS.md
    ├── 使用说明.txt
    ├── installer/               固定件说明 / 官方校验清单 / 上游脚本留档
    ├── toolkit/                 一键白盒测试 / 版本固定部署 / PoC
    ├── reports/                 评估报告 / 证据截图 / 前端资源
    └── src/                     逆向与取证脚本
```

各目标的成因、复现步骤、验证证据与整改建议，见对应子目录下的 `README.md`。

要基于本仓库继续开发，请先读 **[`Agent.md`](Agent.md)** —— 脚本要求、安装包要求、一键安装要求、Linux 产品默认持久化、上传 GitHub 规范都在里面。
