# 一键安装

三条命令，各自复制即用。**工具包与被测软件全部从本交付仓库
（`Xioaruan912/ReverseFinal`）拉取**，下载后逐一校验 sha256，不匹配立即中止；
全程不访问被测软件官网的「最新版」地址，避免厂商发新版后对象漂移、结果不可复现。

**脚本是安装器，不是报告生成器**：跑完给你一个**可直接使用的目标程序**，
不在机器上生成任何 `.md` / 报告 / 证据目录，下载包与临时文件自动清理。

| 目标 | 被测软件 | 固定版本 | 入口脚本 | 跑完得到 | 默认目录 |
|---|---|---|---|---|---|
| HexHub | SSH / SFTP / Docker / 数据库客户端 | 5.1.9 | `hexhub-vip-test.ps1` | 便携式 HexHub（免安装） | `桌面\HexHub-5.1.9` |
| Listary 6 | Windows 文件搜索增强 | 6.3.5.94 | `listary-pro-test.ps1` | 正常安装的 Listary Pro | `桌面\Listary` |
| 妙妙屋X | 自托管 Xray 节点管理与订阅分发 | v0.5.4 | `miaomiaowux-license-test.sh` / `.ps1` | systemd 常驻服务 + 开机自启 | `/opt/mmwx` |

---

## 0. 关于下载速度

三个脚本开场都会提示：

```
 [!] 构件从 GitHub 下载，中国大陆网络可能较慢（主程序约 35 MB / 安装包约 145 MB）。
     若下载困难，可任选其一：
       - 自建镜像：  MMWX_MIRROR=https://your-mirror/xxx 重跑
       - 先手动下载 <构件> 放进 <安装目录>/artifacts/ 后重跑
```

## 0.1 关于目录选择

脚本会**询问安装目录**，直接回车用默认值。非交互执行（管道 / 自动化）时自动用默认值，
此时想自选目录请用环境变量。

---

## 1. HexHub · 会员权益

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 | iex"
```

脚本会：拉测试工具包 → 校验 → 拉 HexHub 5.1.9 安装包 → 校验 →
**静态解包（不执行安装程序）** → 打等长字节补丁 → 产出便携目录。

跑完得到 `桌面\HexHub-5.1.9\HexHub.exe`，双击即可用；卸载就是删掉这个文件夹。

```powershell
# 自选目录 + 非交互
$env:HEXHUB_OUTDIR='D:\hexhub'; $env:HEXHUB_YES='1'
irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 | iex
```

| 环境变量 | 说明 |
|---|---|
| `HEXHUB_OUTDIR` | 输出目录（跳过询问） |
| `HEXHUB_YES=1` | 非交互，全部用默认值 |
| `HEXHUB_MIRROR` | 自建镜像前缀 |

---

## 2. Listary 6 · 专业版权益

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1 | iex"
```

脚本会：拉测试工具包 → 校验 → 拉 Listary 6.3.5.94 安装包与主程序 → 校验 →
（未装则静默安装到指定目录）→ 写入自洽权益 → 复核状态。

跑完得到**正常安装、已激活的 Listary Pro**；卸载走官方卸载器。

```powershell
$env:LISTARY_INSTALLDIR='D:\Listary'; $env:LISTARY_EMAIL='you@example.com'
irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1 | iex
```

| 环境变量 | 说明 |
|---|---|
| `LISTARY_INSTALLDIR` | 安装目录（跳过询问） |
| `LISTARY_EMAIL` | 权益邮箱，默认 `%USERNAME%@lab.local` |
| `LISTARY_YES=1` | 非交互，全部用默认值 |
| `LISTARY_SKIP_INSTALL=1` | 已装好，跳过安装步骤 |
| `LISTARY_RESTORE=1` | 删除权益，回到未激活状态 |
| `LISTARY_MIRROR` | 自建镜像前缀 |

---

## 3. 妙妙屋X · 授权与配额

**Linux / WSL（默认持久化：装成 systemd 服务 + 开机自启）**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh)
```

**Windows**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.ps1 | iex"
```

跑完得到**常驻服务**，直接访问面板即可；安装目录（程序 + `data/`）长期保留。

```bash
# 自选安装目录
MMWX_INSTALLDIR=/srv/mmwx bash <(curl -fsSL .../miaomiaowux-license-test.sh)
```

| 环境变量 | 说明 |
|---|---|
| `MMWX_INSTALLDIR` | 安装目录，默认 `/opt/mmwx` |
| `MMWX_YES=1` | 非交互，全部用默认值 |
| `MMWX_NO_SERVICE=1` | 只安装，不注册 systemd 服务 |
| `MMWX_MIRROR` | 自建镜像前缀 |
| `PORT` | 面板端口，默认 `12889` |

---

## 4. 跑完发生什么

```
清理前                              清理后
├── 下载的安装包 / 工具包        →   （删除）
├── stage 解包副本 / 临时工装    →   （删除）
└── <产出目录>/                  →   ✅ 保留，可直接运行
    <产出目录>/artifacts/        →   ✅ 保留（构件缓存，重跑不再下载）
```

- **不生成** `.md`、报告目录、证据目录
- 重跑同一条命令即**升级**：覆盖可执行文件，`data/` 与用户配置不受影响
- 每个脚本结尾都会打印：**产物路径 / 怎么启动 / 怎么删除**

---

## Beyond Compare 5 —— 离线凭证判定（CWE-602）

目标：Beyond Compare **5.2.6.32774**（Delphi / VCL 原生 x64 PE）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/beyondcompare-license-test.ps1 | iex"
```

产物：`桌面\BeyondCompare-5.2.6\BCompare.exe`（双击即用，离线凭证判定通过）

| 环境变量 | 作用 |
| :--- | :--- |
| `BC_INSTALLDIR` | 产出目录（默认桌面） |
| `BC_YES=1` | 非交互 |
| `BC_MIRROR` | 构件镜像前缀 |
| `BC_SKIP_INSTALL=1` | 已装好，跳过安装 |
| `BC_KEEP_ARTIFACTS=1` | 保留下载的安装包 |

细则见 `../BeyondCompare-5.2.6/README.md`。
