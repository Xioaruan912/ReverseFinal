# Agent.md — ReverseFinal 交付仓库作业规范

> **这份文件给谁看**：接手本仓库继续做案例、或基于本仓库开发一键安装/部署工具的开发者与 AI Agent。
> **它约束什么**：目录怎么放、脚本怎么写、安装包怎么定版、一键命令长什么样、Linux 产品默认怎么跑、怎么上传 GitHub。
> 本仓库所有已交付案例（`HexHub-5.1.9/`、`Listary/`、`MiaomiaowuX-v0.5.4/`、`oneclick/`）都是按本规范做的，可直接当范例读。

---

## 0. 一句话原则

> **一条命令可用、版本永远固定、默认持久化、跑完不留垃圾、上传前先自检。**

---

## 1. 仓库结构与命名

### 1.1 顶层只放「目标名」

```
ReverseFinal/
├── README.md            首页：声明 + 一键命令 + 项目树
├── Agent.md             本文件（作业规范）
├── oneclick/            一键命令入口（所有目标共用一处）
├── HexHub-5.1.9/        目标目录：目录名 = 产品名 + 版本号
├── Listary/             目标目录（无小版本差异时可只留产品名）
└── MiaomiaowuX-v0.5.4/  目标目录
```

**规则**

- 顶层**只允许**出现目标名目录、`oneclick/`、`README.md`、`Agent.md`；
  **不允许**出现 `1-安装包/`、`2-一键白盒测试/`、`3-审计资料/` 这类中文分层目录。
- 目标目录名用**英文 + 版本号**（`MiaomiaowuX-v0.5.4`），不用中文、不用空格。

### 1.2 目标目录内部固定四段式

```
<目标>/
├── README.md            一页说明：这是什么 / 怎么用 / 跑完能用什么
├── PINNED-VERSIONS.md   固定版本与 sha256（必填）
├── 使用说明.txt          纯文本速查（面向最终使用者）
├── installer/           安装包放置说明（大件不入库）、官方校验清单、上游脚本留档
├── toolkit/             一键工装：取件 + 准备 + 启动/安装 + 页面行为脚本 + deploy/
├── reports/             评估报告、证据截图（evidence/）、前端资源等
└── src/                 自研分析工装源码
```

**英文目录名对照（历史中文名一律不再使用）**

| 旧 | 现 |
| :--- | :--- |
| `1-安装包/` | `installer/` |
| `2-一键白盒测试/`、`2-一键激活/` | `toolkit/` |
| `3-审计资料/` | `reports/` |
| `证据截图/` | `reports/evidence/` |
| `上游脚本留档/` | `installer/upstream-scripts/` |
| `前端资源/` | `reports/frontend-assets/` |

> 只有**文档内容**与**文件名**可以用中文；**目录名一律英文小写**。

---

## 2. 脚本要求

### 2.1 双入口：bash + PowerShell

Linux/服务端类目标给 **bash**，Windows 类目标给 **PowerShell**；
跨平台目标（Linux 服务 + Windows 前端工具）给两个入口，语义保持一致。

### 2.2 PowerShell 脚本三条硬约束

| # | 约束 | 原因 |
| :--- | :--- | :--- |
| 1 | **不用 `param()` / `[CmdletBinding()]`** | 这两者只在「脚本文件入口」合法，`irm … \| iex` 会报 `UnexpectedAttribute` |
| 2 | **必须无 BOM，且整文件纯 ASCII** | BOM 经 `irm` 会变成杂字符把首行注释打断；无 BOM 时 PowerShell 5.1 按 ANSI 读，中文会把解析撑坏 |
| 3 | **中文输出用 base64 内嵌，运行时解码** | 兼得「源码纯 ASCII」与「输出中文」；模板见下 |

```powershell
function T($b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) }
Write-Host (T '5p6E5Lu25LuOR2l0SHVi...') -ForegroundColor Yellow
```

生成 base64：`python -c "import base64;print(base64.b64encode('中文'.encode()).decode())"`

### 2.3 选项一律走环境变量

```powershell
$WorkDir = if ($env:XXX_WORKDIR) { $env:XXX_WORKDIR } else { Join-Path $env:USERPROFILE 'ReverseAudit\xxx' }
$Auto    = ($env:XXX_YES -eq '1')
```

命名前缀与目标一致（`HEXHUB_` / `LISTARY_` / `MMWX_`），常用变量：

| 变量 | 含义 |
| :--- | :--- |
| `*_WORKDIR` / `*_INSTALLDIR` | 工作目录 / 安装目录（跳过询问） |
| `*_YES=1` | 非交互，全部用默认值 |
| `*_KEEP_FILES=1` | 保留中间产物 |
| `*_MIRROR` | 自建镜像前缀 |

### 2.4 bash 脚本约定

- `set -euo pipefail` 开头
- 交互读取优先 `/dev/tty`，取不到就用默认值，**绝不因无终端而中断**
- **补丁类写入必须用 `printf "$2"`（格式串写法）**：
  `printf '%s'` 不解释 `\xHH`，会写入字面文本把二进制写坏；`%b` 虽可用但与之不一致，统一用格式串。
- 交互函数模板：

```bash
ask(){
  local label="$1" default="$2" v=""
  if [ "$AUTO" = "1" ]; then printf '%s' "$default"; return 0; fi
  if [ -t 0 ] || [ -r /dev/tty ]; then
    printf '%s\n    default [%s]\n    input (Enter = default): ' "$label" "$default"
    read -r v </dev/tty 2>/dev/null || v=""
  fi
  v="$(printf '%s' "$v" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')"
  [ -z "$v" ] && v="$default"
  printf '%s' "$v"
}
```

### 2.5 安全与幂等

- **危险删除必须保护**：拒绝删除盘根 / 层级 < 3 的路径

```powershell
function Safe-Remove($path) {
    $full = [IO.Path]::GetFullPath($path)
    $parts = $full.TrimEnd('\').Split('\') | Where-Object { $_ -ne '' }
    if ($parts.Count -lt 3) { Warn "refusing to delete shallow path: $full"; return }
    if (Test-Path $full) { Remove-Item $full -Recurse -Force -ErrorAction SilentlyContinue }
}
```

- **幂等可重入**：重复执行应升级/覆盖而不是报错
- **失败即中止**：校验不过、下载失败，一律 `exit 非零` 并给出「期望值 / 实际值 / 补救办法」

---

## 3. 安装包与版本固定要求

### 3.1 禁止动态地址

| 禁止 | 替代 |
| :--- | :--- |
| `.../releases/latest` | 锁定 tag 的固定构件 |
| `ghcr.io/...:latest` | `@sha256:<摘要>` |
| 「自动选最新版」的安装脚本 | 显式版本号 + 哈希校验 |

### 3.2 被测软件哈希**写死在脚本里**

不是从网络读哈希表。下载后强制比对，不匹配立即中止：

```powershell
$PACK_SHA256 = '87b4efd7…650a'
if ((Get-FileHash $f -Algorithm SHA256).Hash.ToLower() -ne $PACK_SHA256) { Die '…' }
```

### 3.3 取件顺序（严格三级，不降级到 latest）

```
1) 本地已有构件（<工作目录>/artifacts/ 或 installer/）
2) 本仓库 Release 固定件
3) 自建镜像 *_MIRROR
        ↓   sha256 强制校验
     不匹配 → 立即中止，绝不安装
```

### 3.4 必须产出的记录

- 每个目标根目录一份 **`PINNED-VERSIONS.md`**：产品、版本、大小、sha256、（Docker 目标还要摘要）
- 构建产物哈希对照（如 `BUILD_FINGERPRINTS.txt`）
- **同一版本号出现多份外壳时**：各自哈希都记下，并给出「解包产物是否一致」的实测结论
  （范例：HexHub 5.1.9 有两份外壳，`0ce38138…` / `77f7f4fa…`，解包产物逐字节相同）

### 3.5 大件不入库

- 单文件 > 10 MB 一律不上 git，走 **Release 资产**
- 每个目标目录写 `.gitignore` 忽略可再生的大件：

```
samples/
exports/*.bin
patches/*.exe
tmp/
__pycache__/
*.pyc
```

---

## 4. 一键安装要求

### 4.1 形态：一条命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/<case>.ps1 | iex"
```
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/<case>.sh)
```

入口脚本统一放 **`oneclick/`**，一个目标一个文件，文件名 `目标-用途.ps1/.sh`。

### 4.2 四个必备阶段

| 阶段 | 必须做的事 |
| :--- | :--- |
| **① 开场告知** | 打印「构件来自 GitHub，中国大陆网络可能较慢」+ 两条备选（自建镜像、手动放置后重跑） |
| **② 自选目录** | 交互询问安装/工作目录，回车用默认；**做可写性探测**，不可写让用户重输 |
| **③ 取件校验** | 按 §3.3 三级取件 + sha256 强制校验 |
| **④ 安装即持久化** | 见 §5；结束时**中间产物自动清理、证据另存** |

### 4.3 结束行为

```
=== cleanup ===
  [+] evidence kept : %USERPROFILE%\ReverseAudit-Evidence\<案例>\<时间戳>\
  [+] intermediates removed: <工作目录>
```

- **证据先另存**再删中间产物
- 只留存**真证据**：`*.png` 截图 + `reports/` 文档；**绝不**把几百 MB 的中间流文件当证据留下
- `*_KEEP_FILES=1` 可关闭清理

### 4.4 必须给出卸载/回滚路径

| 目标类型 | 回滚 |
| :--- | :--- |
| Windows 桌面软件 | 撤销授权 `*_RESTORE=1`；卸载 `unins000.exe /VERYSILENT` |
| Linux 服务 | `systemctl disable --now <svc>` + 删 unit + 删安装目录 |
| 纯测试 | 删工作目录即可 |

---

## 5. Linux 产品默认持久化

> **规则**：Linux/服务端类目标，一键脚本**默认生产模式**，装完即常驻 + 开机自启，**不做临时测试运行**。

### 5.1 目录规划

```
<安装目录>/            默认 /opt/<产品>
├── <binary>           可执行文件（0755）
├── artifacts/         固定版本构件缓存（可复用，避免重复下载）
└── data/              数据目录（长期保留）
```

### 5.2 systemd 单元模板

```ini
[Unit]
Description=<产品> <版本>
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=<安装目录>
Environment=PORT=<端口>
Environment=<产品>_DATA_DIR=<安装目录>/data
ExecStart=<安装目录>/<binary>
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
```

安装流程：写 unit → `systemctl daemon-reload` → `systemctl enable --now <svc>` → `sleep 4` → 打印管理命令。

### 5.3 无 systemd 时降级

WSL / 容器里没有可用的 systemd 时，**自动降级**为安装目录下的 `start.sh` / `stop.sh` + `nohup` + `mmwx.log`，并提示如何启用 WSL systemd 后重跑。

### 5.4 必须打印的管理命令

```
查看状态 : systemctl status <svc>      启动/重启 : systemctl start|restart <svc>
停止     : systemctl stop <svc>        取消自启 : systemctl disable <svc>
实时日志 : journalctl -u <svc> -f
卸载     : systemctl disable --now <svc> && rm -f /etc/systemd/system/<svc>.service && rm -rf <安装目录>
```

---

## 6. 文档规范

### 6.1 首页 `README.md` —— 只放三块

1. **声明**（一两句话，仅首页有）
2. **一键命令**（各目标一条 + 固定版本表 + Release 链接）
3. **项目树**（目录结构）

> 首页**不写**漏洞细节、不写整改建议、不写技术章节。

### 6.2 目标目录 `README.md` —— 一页讲完

```
# <产品> <版本>              ← 标题只留名字，不加「· 测试包」「· 白盒鉴权」之类后缀
一、这是什么软件            产品用途 + 免费档/付费档差异
二、测试后可用功能          ★ 跑完能用哪些功能（表格）
三、环境要求
四、一条命令跑通            只保留一键方式，不铺开方式 B/C
五、跑完看到什么            观察项对照表
六、使用方式（可选）        持久化部署 / 容器部署
七、目录说明                目录树 + 报告索引
```

**禁止**：`第 N 步：记录基线`、`方式 B/C：分步执行`、`第 N 步：对比结论`、`这个测试包要验证什么` 这类冗余章节。

### 6.3 子页不放声明

声明只在首页。**子目录 README 一律不写免责声明**。

### 6.4 技术细节下沉

成因分析、逆向位点、整改建议 → 全部放 `reports/`；
README 只保留「是什么 / 怎么用 / 用完能用什么 / 去哪找报告」。

---

## 7. 上传 GitHub 规范

### 7.1 提交信息：短

- 一律 `update` / `remove` / `fix` 这类**单词级**信息
- **不要**长篇 commit message
- 一次提交只做一类事（改脚本 / 改文档 / 换构件）

### 7.2 行尾与属性

`.gitattributes` 固定：

```
* text=auto
*.md        text eol=lf
*.sh        text eol=lf
*.json      text eol=lf
*.yml       text eol=lf
*.yaml      text eol=lf
*.py        text eol=lf
*.cs        text eol=crlf
*.bat       -text -diff
*.txt       -text -diff
*.exe       -text -diff
*.dll       -text -diff
*.png       -text -diff
```

> 用脚本改文件时注意：Python 在 Windows 上默认会把 `\n` 写成 `\r\n`，
> 必须 `open(..., newline='')` 或显式 `newline='\n'`，否则 `.sh` 带 CRLF 直接跑不起来。

### 7.3 大件走 Release

- 单文件 > 10 MB → Release 资产，命名 `<产品>-<版本>-<平台>.<扩展名>`
- 测试包 → `<产品>-whitebox-audit-pack-v<版本>.zip`
- 每次 Release 必带 **`SHA256SUMS.txt`**
- 资产名**用 ASCII**：中文名经 API 上传会被转义成 `.`，需要改名

### 7.4 Release 内容清单（模板）

| 资产 | 说明 |
| :--- | :--- |
| `<产品>-<版本>-<平台>` | 被测软件固定版本 |
| `<产品>-whitebox-audit-pack-v<版本>.zip` | 测试工具包 |
| `<产品>-docker-image-<版本>.tar.gz` | 离线镜像（容器类目标） |
| `SHA256SUMS.txt` | 全部构件哈希 |

### 7.5 上传后必做

1. 用 API 校验资产清单与哈希（**不要只看网页**）
2. 与脚本内嵌哈希逐一对齐
3. **注意 CDN 边缘缓存**：`raw.githubusercontent.com` 在推送后约 1–2 分钟仍可能返回旧版；
   验证时可用 `?cb=<随机数>` 绕缓存，确认无误后再按默认 URL 复测

---

## 8. 交付前检查清单

**脚本**

- [ ] PowerShell：无 `param()`、无 BOM、纯 ASCII、`irm | iex` 与 `-File` 双通
- [ ] bash：`bash -n` 通过、LF 行尾、无 CRLF
- [ ] 交互询问目录 + 可写性探测
- [ ] 危险删除有浅路径保护
- [ ] 重复执行幂等

**版本与取件**

- [ ] 无 `latest`、无 `:latest`
- [ ] 被测软件 sha256 写死在脚本
- [ ] 三级取件 + 强制校验
- [ ] `PINNED-VERSIONS.md` 齐全

**一键体验**

- [ ] 开场提示 GitHub 国内慢 + 两条备选
- [ ] 默认持久化（Linux 产品）
- [ ] 证据另存 / 中间产物自动清理
- [ ] 打印管理命令与卸载方法

**仓库**

- [ ] 顶层只有目标名目录 + `oneclick/` + `README.md` + `Agent.md`
- [ ] 目录名全英文
- [ ] 大件不入库、`.gitignore` 就位
- [ ] 首页三块（声明 / 一键命令 / 项目树）
- [ ] 子页无声明、无冗余章节
- [ ] 提交信息为单词级
- [ ] Release 资产 + `SHA256SUMS.txt` 已更新且哈希对齐

---

## 9. 已有案例的固定版本（速查）

| 目标 | 固定版本 | 一键入口 | 默认行为 |
| :--- | :--- | :--- | :--- |
| HexHub | **5.1.9** | `oneclick/hexhub-vip-test.ps1` | 静态解包副本运行 + 取证，结束清理 |
| Listary 6 | **6.3.5.94** | `oneclick/listary-pro-test.ps1` | 安装固定版本 + 授权验证，保留安装 |
| 妙妙屋X | **v0.5.4** | `oneclick/miaomiaowux-license-test.sh/.ps1` | **持久化部署**（systemd 常驻 + 开机自启） |

> 所有构件托管于本仓库 Release：
> `https://github.com/Xioaruan912/ReverseFinal/releases/tag/whitebox-audit-v1.0`

---

## 10. 免责声明

本仓库仅用于**已完成授权的自有资产 / 沙盒环境**的安全验证与防御加固研究。
使用者须自行确认测试目标处于合法授权范围内。
