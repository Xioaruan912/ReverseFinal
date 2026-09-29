# Agent.md — ReverseFinal 交付仓库作业规范

> **这份文件给谁看**：接手本仓库继续做案例、或基于本仓库开发**一键安装 / 部署 / 分发**工具的开发者与 AI Agent。
> **它约束什么**：目录怎么放、脚本怎么写、安装包怎么定版、一键安装长什么样、交互怎么做、Linux 产品默认怎么跑、怎么部署、怎么分发、怎么上传 GitHub。
> 本仓库所有已交付案例（`HexHub-5.1.9/`、`Listary/`、`MiaomiaowuX-v0.5.4/`、`oneclick/`）都是按本规范做的，可直接当范例读。

---

## 0. 一句话原则

> **一条命令装好、产出就是能用的程序、缺什么自己装什么、版本永远固定、默认持久化、跑完不留垃圾、上传前先自检。**

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
├── README.md            一页说明：这是什么 / 怎么用
├── PINNED-VERSIONS.md   固定版本与 sha256（必填）
├── installer/           安装包放置说明（大件不入库）、官方校验清单、上游脚本留档
├── toolkit/             工装源码：取件、解包、打补丁、激活、页面行为脚本、deploy/
├── reports/             分析报告与证据（**仅仓库留档用，一键脚本不读、不写**）
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
跨平台目标给两个入口，语义与参数命名保持一致。

### 2.2 PowerShell 脚本三条硬约束

| # | 约束 | 原因 |
| :--- | :--- | :--- |
| 1 | **不用 `param()` / `[CmdletBinding()]`** | 这两者只在「脚本文件入口」合法，`irm … \| iex` 会报 `UnexpectedAttribute` |
| 2 | **必须无 BOM，且整文件纯 ASCII** | BOM 经 `irm` 会变成杂字符把首行打断；无 BOM 时 PowerShell 5.1 按 ANSI 读，中文会把解析撑坏 |
| 3 | **中文输出用 base64 内嵌，运行时解码** | 兼得「源码纯 ASCII」与「输出中文」 |

```powershell
function T($b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) }
Write-Host (T '5p6E5Lu25LuOR2l0SHVi...') -ForegroundColor Yellow
```

生成 base64：`python -c "import base64;print(base64.b64encode('中文'.encode()).decode())"`

> 理想状态是脚本**全部英文输出**——省掉 base64 这一步，也没有编码风险。
> 已知三份 oneclick 脚本都是全英文，新脚本优先照做；确实需要中文输出时再用上面的办法。

### 2.3 选项一律走环境变量

```powershell
$OutDir = if ($env:XXX_OUTDIR) { $env:XXX_OUTDIR } else { <default> }
$Auto   = ($env:XXX_YES -eq '1')
```

命名前缀与目标一致（`HEXHUB_` / `LISTARY_` / `MMWX_`）。

| 变量后缀 | 含义 |
| :--- | :--- |
| `_OUTDIR` / `_INSTALLDIR` | 输出目录 / 安装目录（跳过询问） |
| `_YES=1` | 非交互，全部用默认值 |
| `_MIRROR` | 自建镜像前缀 |
| `_SKIP_INSTALL=1` | 已装好，跳过安装步骤 |
| `_RESTORE=1` | 回滚（撤销激活 / 删除授权） |

### 2.4 bash 脚本约定

- `set -euo pipefail` 开头，`mktemp -d` + `trap cleanup EXIT` 保证临时件必清
- 交互读取见 §5（**这是本仓库踩过最深的坑**）
- **补丁类写入必须用 `printf "$2"`（格式串写法）**：
  `printf '%s'` 不解释 `\xHH`，会写入字面文本把二进制写坏。

```bash
p(){ printf "$2" | dd of="$out" bs=1 seek=$(( $1 )) conv=notrunc status=none; }
p 0x13b4180 '\xb0\x01\xc3'
```

### 2.5 依赖自举 ★ 一句话原则

> **本脚本需要什么，就自己装什么 —— 检测 → 自动安装 → 装不上才报错退出。**
> **绝不把「你先去装个 upx」这种活推回给用户。**

实战教训：`mmwx` 脚本把 `upx` 当可选依赖只 `warn`，用户机器上没装，
结果补丁全打进了 UPX 压缩数据 → 服务 `status=127` 死循环（详见 §3.5）。
如果当时能自己装上，这个故障根本不会发生。

#### bash：覆盖 6 种包管理器 + sudo 降级

```bash
as_root(){
  if [ "$(id -u)" = "0" ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else return 1; fi
}

PM=""; PM_UPDATED=0
pm_detect(){
  local m
  for m in apt-get:apt apk:apk dnf:dnf yum:yum pacman:pacman zypper:zypper; do
    if command -v "${m%%:*}" >/dev/null 2>&1; then PM="${m##*:}"; return 0; fi
  done
  return 1
}

pm_install(){   # pm_install <包名>...
  [ -z "$PM" ] && { pm_detect || return 1; }
  case "$PM" in
    apt)    [ "$PM_UPDATED" = "0" ] && { as_root apt-get update -qq >/dev/null 2>&1 || true; PM_UPDATED=1; }
            as_root apt-get install -y -qq "$@" ;;
    apk)    as_root apk add --no-cache "$@" ;;
    dnf)    as_root dnf install -y -q "$@" ;;
    yum)    as_root yum install -y -q "$@" ;;
    pacman) as_root pacman -Sy --noconfirm --needed "$@" ;;
    zypper) as_root zypper -n install "$@" ;;
    *)      return 1 ;;
  esac
}

# ensure_dep <命令> <用途> <候选包名...>   一个个试，装到能跑为止
ensure_dep(){
  local bin="$1" why="$2"; shift 2
  command -v "$bin" >/dev/null 2>&1 && return 0
  warn "缺少 $bin（$why），正在自动安装…"
  pm_detect || true
  if [ -n "$PM" ]; then
    local p
    for p in "$@"; do
      if pm_install "$p" >/dev/null 2>&1; then
        hash -r 2>/dev/null || true          # 清 bash 命令哈希缓存，否则新装的命令可能找不到
        command -v "$bin" >/dev/null 2>&1 && { ok "$bin 已自动安装（$PM: $p）"; return 0; }
      fi
    done
  fi
  die "无法自动安装 $bin（$why）……给出六种发行版的手动命令"
}

ensure_dep curl '下载构件' curl
ensure_dep unzip '解压工具包' unzip
ensure_dep upx   '解包 UPX 压缩构件，必须' upx-ucl upx     # 包名按发行版不同，依次试
```

**要点**：`apt-get update` 只跑一次（`PM_UPDATED` 标记）；包名在不同发行版不一样就**传多个候选**依次试；
`hash -r` 必加；装不上才 `die`，且要给出**六种发行版的手动命令**。

#### PowerShell：先跑一遍再信任

```powershell
# Windows 商店的 python3.exe 是个假壳，运行就 exit 49 —— 绝不能只看路径存在
function Test-PythonUsable($exe) {
    if (-not (Test-Path $exe)) { return $false }
    try {
        $out = & $exe -c "print('ok')" 2>$null
        return ($LASTEXITCODE -eq 0 -and (($out -join '') -match 'ok'))
    } catch { return $false }
}

function Ensure-Python {
    $py = Find-Python                      # PATH -> 已知安装路径，每一个都过 Test-PythonUsable
    if ($py) { return $py }
    Warn 'Python not found - installing it automatically'
    if (Get-Command winget.exe -EA SilentlyContinue) {      # ① winget（用户级，免管理员）
        & winget.exe install -e --id Python.Python.3.12 --scope user --silent `
            --accept-package-agreements --accept-source-agreements
        Refresh-Path                                       # 重读注册表 PATH，否则本会话看不见
        $py = Find-Python; if ($py) { return $py }
    }
    if (Get-Command choco.exe -EA SilentlyContinue) { ... } # ② choco
    return (Install-PythonPortable)                         # ③ 官方 embeddable zip，免安装免管理员
}
```

> **兜底优先用免安装包**：HexHub 那两个脚本（`extract.py` / `patch_vip.py`）**只用标准库**，
> 所以官方 embeddable zip（解到 `%LOCALAPPDATA%` 直接用）永远是最可靠的一层。
> 先看一眼待执行的脚本 import 了什么，再决定兜底要不要真的装完整环境。

**要点**：安装器装完 Python 后**当前会话的 PATH 不会自动更新**，必须
`Refresh-Path` 从注册表重读；唯有 `Get-Command` + **实跑一次**双验，才敢用。

#### 内置依赖也要显式声明

即使某个脚本什么都不缺（如 Listary 只用 Windows 自带的 `Expand-Archive` / `Get-FileHash`），
也要有一个 `Ensure-Deps` 显式检查并打印 `dependencies OK` ——**四个脚本口径一致**，
用户不需要猜哪个脚本要装东西。

### 2.6 安全与幂等

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
- **自愈历史故障**：写 unit / 注册服务前，先 `disable --now` + 删旧 unit，
  这样历史遗留的坏配置会被自动修掉（范例：`mmwx.service` 的 `ExecStart` 曾指向一个坏路径）
- **启动后要验证**：`systemctl is-active` 不为真就打印最近 10 行日志并 `exit 非零`，
  **不能只报"已注册"就结束**

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
1) 本地已有构件（<安装目录>/artifacts/ 或 installer/）
2) 本仓库 Release 固定件
3) 自建镜像 *_MIRROR
        ↓   sha256 强制校验
     不匹配 → 立即中止，绝不安装
```

### 3.4 构件缓存复用

主程序类构件（几十 MB 的）缓存到 **`<安装目录>/artifacts/`**，
重跑时命中即直接复用，避免二次下载。缓存本身不进 git、不入包。

### 3.5 构件形态必须与打补丁方式配对 ★ 血泪条款

**构件是压缩态，而补丁偏移是解包后的偏移 —— 这两件事必须配对，否则装出来的东西是坏的。**

实战案例（`mmwx-v0.5.4-linux-amd64`）：

```
Release 构件     36,605,840 字节  含 "UPX!"  -> 是 UPX 压缩包
upx -d 之后     132,604,030 字节  不含 "UPX!"  -> 补丁偏移按这个算
```

脚本当时把 `upx` 当**可选依赖只 warn**，而上游又写了 `upx -d ... || true`。
于是没装 upx 的机器：补丁全部写进了**压缩数据**里 → UPX stub 解压失败 →
进程 `exit 127` → systemd 变成 `activating (auto-restart) + status=127` 的死循环。

**三条硬要求**

1. **解包工具是硬依赖，不能只 warn**

```bash
command -v upx >/dev/null || die '缺少依赖 upx（固定构件是 UPX 压缩的，必须先解包才能打补丁）
        安装: apt-get update && apt-get install -y upx-ucl
              apk add upx
              dnf install upx'
```

2. **解包后必须验真解开了，且绝不写 `|| true`**

```bash
if grep -qa 'UPX!' "$out"; then
  upx -d -qq "$out" >/dev/null 2>&1 || die "upx 解包失败"
  grep -qa 'UPX!' "$out" && die "解包后仍为压缩态，拒绝打补丁"
fi
```

3. **必须钉「打补丁后的黄金哈希」**

> 回读校验只能证明「**写进去了**」，证明不了「**写对了地方**」。
> 只有黄金哈希能同时锁死：偏移算错 / 补丁表被改动 / 构件漂移。

```bash
PREP_SHA256="1c1a5597…6e1c"     # 与 toolkit 里的参考实现逐字节一致
[ "$(sha256sum "$out" | cut -d' ' -f1)" = "$PREP_SHA256" ] || die "与黄金哈希不符，拒绝安装"
```

> 取黄金哈希务必用**正确顺序**产出的那份文件。教训：曾直接 hash 了测试目录里的残留产物，
> 那份其实是「故意改错偏移」的坏文件，结果把坏哈希钉了进去。
> 正解是**独立构造一次参考实现**，两处结果互相印证。

4. **装前冒烟测试**：真跑一次再注册服务，别把坏 unit 留给用户

```bash
# 必须在临时目录里跑！程序会按 CWD 生成 data/ 与 rule_templates/，
# 不 cd 就会在用户当前目录（甚至交付仓库根目录）拉出一堆运行数据。
mkdir -p "$WORKDIR/smoke"
( cd "$WORKDIR/smoke" && PORT=$sp MMWX_LISTEN_PORT=$sp MMWX_DATA_DIR="$WORKDIR/smoke" \
    timeout 10 "$out" >"$WORKDIR/smoke.out" 2>&1 ) &
sleep 5
kill -0 "$spid" 2>/dev/null || { sed 's/^/      /' "$WORKDIR/smoke.out"; die "可执行文件无法启动"; }
```

> ⚠️ **冒烟测试一定要 `cd` 到临时目录**。实战事故：没 cd，程序把 `data/`、`rule_templates/`
> 写到了交付仓库根目录，直接 `git add -A` 提交进了 git。
> 把程序会写的目录名（`data/`、`rule_templates/`、`subscribes/`）都加进 `.gitignore` 作为第二层保险。

> ⚠️ 这类函数常被 `PREP="$(prepare_binary ...)"` 调用，**函数内所有提示必须写 stderr**，
> 否则提示文字会被拼进返回的路径里（与 §5 的 `ask()` 完全同一个坑）。

#### 失败形态对照表（看到现象直接定位）

| systemd 现象 | 真因 |
| :--- | :--- |
| `activating (auto-restart)` + `status=127`，且有 Mem peak / CPU 占用 | 补丁打在了**压缩态**构件上，UPX stub 解压失败 |
| `status=203/EXEC` | 路径不存在，或不是可执行文件 |
| `status=200/CHDIR` | `WorkingDirectory` 不存在 |
| `status=1` + 日志里有业务报错 | 程序真跑起来了，是业务/配置问题 |

---

### 3.6 必须产出的记录

- 每个目标根目录一份 **`PINNED-VERSIONS.md`**：产品、版本、大小、sha256、（容器类外加镜像摘要）
- **同一版本号出现多份外壳时**：各自哈希都记下，并给出「解包产物是否一致」的实测结论
  （范例：HexHub 5.1.9 有两份外壳，`0ce38138…` / `77f7f4fa…`，解包产物逐字节相同）

### 3.7 大件不入库

- 单文件 > 10 MB 一律不上 git，走 **Release 资产**
- 目标目录写 `.gitignore` 忽略可再生的大件：

```
samples/
exports/*.bin
patches/*.exe
tmp/
__pycache__/
*.pyc
```

---

## 4. 一键脚本 = 纯安装器 ★ 核心条款

> **一键脚本的产出物，是一个「可以直接使用的目标程序」，不是一份报告。**
> 用户跑完之后，机器上应该多出一个能用的软件，而不是一堆 .md。

### 4.1 产出物定义

| 目标类型 | 产出物 | 用户拿到后 |
| :--- | :--- | :--- |
| 便携式客户端 | 一个程序目录，内含全部文件 | 双击主程序即可用 |
| 安装式桌面软件 | 装好的程序 + 激活状态 | 托盘/开始菜单启动，功能已解锁 |
| 服务端产品 | 常驻服务 + 开机自启 | 直接访问面板 |
| 容器化产品 | 运行中的容器 + 数据卷 | 直接访问面板 |

### 4.2 硬性禁止（违反即返工）

| 禁止 | 说明 |
| :--- | :--- |
| ✗ 生成 `.md` 文件 | 不在用户机器上写任何说明文档 |
| ✗ 生成报告目录 | 不 `cp -r reports/`、不建 `REPORT.md` |
| ✗ 生成证据目录 | 不建 `ReverseAudit-Evidence/`、不抓验证截图 |
| ✗ 把中间产物留在机器上 | 下载包、解包副本、临时工装目录全部清理 |
| ✗ 只输出"审计结论" | 脚本必须交付可运行的程序，不是结论 |

> **报告在哪？** 报告属于**仓库的 `reports/` 目录**，是仓库留档物，由开发者提交进 git。
> 一键脚本**既不读取也不生成**它。

### 4.3 保留规则

- **产出目录长期保留**，不被清理（用户就是要用它）
- 只清理**中间件**：下载的 zip / exe、解包临时目录、工装 stage 目录
- 构件缓存放 `<安装目录>/artifacts/`，保留（利于重跑与升级）

```
清理前                         清理后
├── 下载的 installer.exe   →    （删除）
├── stage/ 解包副本        →    （删除）
└── <产出目录>/            →    ✅ 保留，可直接运行
    <产出目录>/artifacts/  →    ✅ 保留（构件缓存）
```

### 4.4 输出规范

结尾必须给出**可执行的三件事**：

```
============================================================
 done
============================================================
 HexHub   : C:\Users\...\Desktop\HexHub-5.1.9\HexHub.exe
 version  : 5.1.9
 launch   : double-click HexHub.exe (portable, no installer needed)
 remove   : just delete the folder C:\Users\...\Desktop\HexHub-5.1.9
```

即：**产物路径 / 怎么启动 / 怎么删除**。

### 4.5 四个必备阶段

| 阶段 | 必须做的事 |
| :--- | :--- |
| **① 开场告知** | 打印「构件来自 GitHub，中国大陆网络可能较慢（并给出体积）」+ 两条备选（自建镜像、手动放置后重跑） |
| **② 自选目录** | 交互询问产出目录，回车用默认；**校验绝对路径 + 可写性**（见 §5） |
| **③ 取件校验** | 按 §3.3 三级取件 + sha256 强制校验 |
| **④ 安装即持久化** | 见 §6；结束时清理中间件，产出物保留 |

### 4.6 默认目录 = 桌面

Windows 侧产出目录默认放在**桌面**，不要用 `%USERPROFILE%\ReverseAudit\...` 这类隐蔽路径：

```powershell
$Desktop = [Environment]::GetFolderPath('Desktop')
$DefaultOut = Join-Path $Desktop 'HexHub-5.1.9'      # 便携式：直接产品名+版本
$DefaultInstall = Join-Path $Desktop 'Listary'       # 安装式：产品名
```

Linux 服务端产品默认 `/opt/<产品>`（服务本体放桌面没有意义，见 §6.2）。

---

## 5. 交互规范（硬性）★ 血泪条款

> 这一节的两个坑都在实测中真实触发过，务必照抄。

### 5.1 坑一：提示不能写 stdout（bash）

交互函数通常这样用：`DIR="$(ask '选择目录' '/opt/x')"`。
**命令替换会捕获函数内所有 stdout**。若提示用 `printf` 打到 stdout，
提示文字会被当成返回值拼进目录名——实测产生了名为
`/root/选择安装目录（程序与数据都放这里，长期保留）\n    default [/opt/mmwx]` 的目录，
并让 systemd 报 `status=203/EXEC`。

```bash
# ❌ 错：提示进 stdout，被 $( ) 捕获
ask(){ printf '输入目录: '; read -r v; printf '%s' "$v"; }

# ✅ 对：提示全部 >&2，stdout 只输出答案
ask(){
  local label="$1" default="$2" v=""
  if ! is_tty; then printf '%s' "$default"; return 0; fi
  { printf '%s\n' "$label"
    printf '    default [%s]\n' "$default"
    printf '    input (Enter = default): '; } >&2
  read -r -t 300 v </dev/tty 2>/dev/null || v=""
  v="$(printf '%s' "$v" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')"
  [ -z "$v" ] && v="$default"
  printf '%s' "$v"
}
```

> PowerShell 天然安全：`Write-Host` 走 host 流，不会被 `$x = Func` 捕获。
> 但**绝对不要**在交互函数里用 `Write-Output` / 裸字符串输出提示。

### 5.2 坑二：`[ -r /dev/tty ]` 不能用来判断「有人能输入」

管道 / 自动化执行时，`/dev/tty` **可能可打开但无人输入**，
此时 `read -r v </dev/tty` 会**永久阻塞**（实测卡死）。

```bash
# ❌ 错：判据太弱，会卡死
if [ -t 0 ] || [ -r /dev/tty ]; then read -r v </dev/tty; fi

# ✅ 对：必须真终端 + 超时兜底
is_tty(){
  [ "${AUTO:-0}" = "1" ] && return 1
  [ -t 0 ] && return 0                 # stdin 是终端
  [ -t 2 ] && [ -c /dev/tty ] && return 0   # stderr 是终端且有 tty 设备
  return 1
}
# ...并且 read 一律带 -t
read -r -t 300 v </dev/tty 2>/dev/null || v=""
```

### 5.3 PowerShell 对应写法

```powershell
function Test-Interactive {
    if ($Auto) { return $false }
    if (-not [Environment]::UserInteractive) { return $false }
    try { if ([Console]::IsInputRedirected) { return $false } } catch { return $false }
    return $true
}

function Ask-Dir($label, $default) {
    if (-not (Test-Interactive)) { return $default }
    while ($true) {
        Write-Host $label -ForegroundColor White
        Write-Host ("    default [" + $default + "]") -ForegroundColor DarkGray
        Write-Host -NoNewline "    input (Enter = default): " -ForegroundColor DarkGray
        $v = $null
        try { $v = Read-Host } catch { return $default }
        if ([string]::IsNullOrWhiteSpace($v)) { return $default }
        $v = $v.Trim().Trim('"')
        try {
            New-Item -ItemType Directory -Force -Path $v | Out-Null
            $probe = Join-Path $v ('.w-' + [guid]::NewGuid().ToString('N').Substring(0,8))
            Set-Content -Path $probe -Value 'ok' -ErrorAction Stop
            Remove-Item $probe -Force
            return $v
        } catch { Warn "cannot write to '$v', try another path" }
    }
}
```

### 5.4 输入校验三件套

1. **形态校验**：bash 要求绝对路径（`case "$v" in /*)`），Windows 拒绝非法字符
2. **可写性探测**：真写一个随机探针文件再删掉，不要只判断 `Test-Path`
3. **循环重问**：不合法就重问；`*_YES=1` 时直接报错退出，不要静默用错值

### 5.5 非交互时要有交代

```bash
if ! is_tty; then
  c '90' ' (非交互执行：全部使用默认值；想自选目录请设置 MMWX_INSTALLDIR)'
fi
```

不能静默吞掉提问，否则用户以为脚本坏了。

---

## 6. 部署形态

### 6.1 形态矩阵

| 形态 | 适用 | 默认目录 | 启动方式 | 卸载方式 |
| :--- | :--- | :--- | :--- | :--- |
| **Windows 便携** | 免安装客户端 | `桌面\<产品>-<版本>` | 双击主程序 | 删目录 |
| **Windows 安装** | 需服务/驱动/托盘的桌面软件 | `桌面\<产品>` | 托盘 / 开始菜单 | `<目录>\unins000.exe /VERYSILENT` |
| **Linux 服务** | 服务端产品 | `/opt/<产品>` | systemd 常驻 + 开机自启 | `disable --now` + 删 unit + 删目录 |
| **容器** | 需隔离/依赖复杂的产品 | 数据卷 | `docker compose up -d` | `docker compose down -v` |

### 6.2 Linux 产品默认持久化

> **规则**：Linux/服务端类目标，一键脚本**默认生产模式**，装完即常驻 + 开机自启，**不做临时测试运行**。

```
<安装目录>/            默认 /opt/<产品>
├── <binary>           可执行文件（0755）
├── artifacts/         固定版本构件缓存（重跑复用，避免重复下载）
└── data/              数据目录（长期保留）
```

**systemd 单元模板**

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

部署流程：`disable --now` 清旧 unit → 写 unit → `daemon-reload` → `enable --now` → `sleep 4` → **校验 active** → 打印管理命令。

**无 systemd 时降级**：WSL / 容器里自动降级为安装目录下的 `start.sh` / `stop.sh` + `nohup` + `<产品>.log`，并提示如何启用 WSL systemd 后重跑。

**必须打印的管理命令**

```
查看状态 : systemctl status <svc>      重启 : systemctl restart <svc>
停止     : systemctl stop <svc>        取消自启 : systemctl disable <svc>
实时日志 : journalctl -u <svc> -f
卸载     : systemctl disable --now <svc> && rm -f /etc/systemd/system/<svc>.service && rm -rf <安装目录>
```

### 6.3 Windows 安装式软件

- 静默安装：Inno Setup 用 `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR="<目录>"`
- 安装前后要判断：**已装且哈希等于固定版本 → 跳过**；已装但版本不同 → 提示并重装
- 安装完 `Start-Sleep 3` 再执行后续步骤（服务/托盘需要起来）
- 必须给出回滚与卸载命令

### 6.4 升级路径

重跑同一条命令即升级：覆盖可执行文件 / 重装程序，**`data/` 与用户配置不动**。

---

## 7. 分发规范

### 7.1 三条分发通道（脚本必须都支持）

| 通道 | 用什么 | 说明 |
| :--- | :--- | :--- |
| **主通道** | 本仓库 Release（固定 tag） | 默认走这里，URL 写死在脚本里 |
| **镜像通道** | `*_MIRROR` 环境变量 | 中国大陆加速；脚本把镜像 URL 与官方 URL 一起放进候选列表逐个试 |
| **离线通道** | `<安装目录>/artifacts/` | 用户手动放构件，脚本命中即用，不下载 |

```bash
urls=("$official")
[ -n "${XXX_MIRROR:-}" ] && urls+=("${XXX_MIRROR%/}/$(basename "$official")")
for u in "${urls[@]}"; do ... done
```

### 7.2 开场必须提示网络状况

```
 [!] artifacts are downloaded from GitHub; in mainland China this can be slow (installer ~145 MB).
     if that is a problem, either:
       - use a mirror:  $env:HEXHUB_MIRROR='https://your-mirror/xxx'
       - download the installer manually and put it into the temp folder, then re-run
```

三条信息缺一不可：**从哪下 / 多大 / 慢怎么办**。

### 7.3 离线分发包（可选）

需要完全离线时，打一份自包含分发包：

```
<产品>-offline-v<版本>/
├── artifacts/         全部固定构件
├── install.ps1 / .sh  一键脚本
└── install-offline.*  把 *_MIRROR 指向本地目录的包装脚本
```

### 7.4 资产命名（ASCII）

- 主程序：`<产品>-<版本>-<平台>.<扩展名>`
- 测试/工装包：`<产品>-whitebox-audit-pack-v<版本>.zip`
- 离线镜像：`<产品>-docker-image-<版本>.tar.gz`
- 校验清单：`SHA256SUMS.txt`

> **必须 ASCII**：中文名经 GitHub API 上传会被转义成 `.`，需要改名。

---

## 8. 文档规范

### 8.1 首页 `README.md` —— 只放三块

1. **声明**（一两句话，仅首页有）
2. **一键命令**（各目标一条 + 固定版本表 + Release 链接）
3. **项目树**（目录结构）

> 首页**不写**漏洞细节、不写整改建议、不写技术章节。

### 8.2 目标目录 `README.md` —— 一页讲完

```
# <产品> <版本>              ← 标题只留名字，不加「· 测试包」「· 白盒鉴权」之类后缀
一、这是什么软件            产品用途 + 免费档/付费档差异
二、跑完能用什么            ★ 装完/跑完能用哪些功能（表格）
三、环境要求
四、一条命令跑通            只保留一键方式，不铺开方式 B/C
五、产物与运维              产出目录 / 启动 / 管理命令 / 卸载
六、目录说明                目录树 + 报告索引
```

**禁止**：`第 N 步：记录基线`、`方式 B/C：分步执行`、`第 N 步：对比结论`、`这个测试包要验证什么` 这类冗余章节。

### 8.3 子页不放声明

声明只在首页。**子目录 README 一律不写免责声明**。

### 8.4 技术细节下沉

成因分析、逆向位点、加固建议 → 全部放 `reports/`；
README 只保留「是什么 / 怎么用 / 用完能用什么 / 去哪找报告」。

---

## 9. 上传 GitHub 规范

### 9.1 提交信息：短

- 一律 `update` / `remove` / `fix` 这类**单词级**信息
- **不要**长篇 commit message
- 一次提交只做一类事（改脚本 / 改文档 / 换构件）

### 9.2 行尾与属性

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

> 用脚本改文件时注意：Python 在 Windows 上默认把 `\n` 写成 `\r\n`，
> 必须 `open(..., newline='')` 或 `newline='\n'`，否则 `.sh` 带 CRLF 直接跑不起来。

### 9.3 大件走 Release

- 单文件 > 10 MB → Release 资产
- 每次 Release 必带 **`SHA256SUMS.txt`**
- 需要替换资产时：先 DELETE 旧 asset（按 id），再 POST 新资产

### 9.4 上传后必做

1. 用 API 校验资产清单与哈希（**不要只看网页**）
2. 与脚本内嵌哈希逐一对齐
3. **注意 CDN 边缘缓存**：`raw.githubusercontent.com` 在推送后约 1–2 分钟仍可能返回旧版；
   验证时可加 `?cb=<随机数>` 绕缓存，确认无误后再按默认 URL 复测

---

## 10. 交付前检查清单

**脚本**

- [ ] PowerShell：无 `param()`、无 BOM、纯 ASCII、`irm | iex` 与 `-File` 双通
- [ ] bash：`bash -n` 通过、LF 行尾、无 CRLF
- [ ] **交互提示走 stderr / Write-Host**（不得进 stdout）
- [ ] **交互性判定用 `is_tty` / `Test-Interactive`，`read` 带 `-t`**
- [ ] **非交互执行不卡死**（`bash script.sh < /dev/null` 实测通过）
- [ ] 目录有效性校验（绝对路径 + 写探针）
- [ ] 危险删除有浅路径保护
- [ ] 重复执行幂等；能自愈历史坏 unit
- [ ] 服务启动后校验 `is-active`，失败要打日志并非零退出
- [ ] **依赖自举**：脚本需要的外部命令（curl / unzip / upx / python…）都能**自己装上**
- [ ] 覆盖 6 种包管理器（apt / apk / dnf / yum / pacman / zypper），自动 `sudo` 降级
- [ ] 包名跨发行版不同时，传多个候选**依次试**
- [ ] 装完 `hash -r`（bash）/ `Refresh-Path`（PowerShell），否则本会话看不见
- [ ] Windows 侧探测 Python 要**实跑一次**，识别商店假壳（exit 49）
- [ ] 实在装不上才 `die`，且必须给出**六种发行版的手动命令**

**构件形态与打补丁（§3.5）**

- [ ] 确认构件是**压缩态**还是**已解包态**，补丁偏移与它配对
- [ ] 需要解包时，解包工具是**硬依赖**（`die`，不是 `warn`）
- [ ] 解包后**验证真解开了**（`grep -qa 'UPX!'` 必须为假）
- [ ] **没有任何 `|| true` 吞掉解包失败**
- [ ] **补丁后钉了黄金哈希**，且该哈希来自**正确顺序**的参考实现
- [ ] 装前**冒烟测试**通过（真跑一次再注册服务）
- [ ] 冒烟测试**已 `cd` 到临时目录**（否则程序会把 `data/` 等写进用户当前目录 / 仓库根目录）
- [ ] 程序会写的目录名已加入 `.gitignore`
- [ ] 补丁函数的提示**全部走 stderr**（否则污染 `$()` 返回值）

**产出物（纯安装器）**

- [ ] **不生成任何 `.md` / 报告 / 证据目录**
- [ ] 产出目录 = 可直接运行的程序目录，**长期保留**
- [ ] 中间件（下载包 / stage / 解包副本）全部清理
- [ ] 结尾打印：产物路径 / 启动方式 / 删除方式

**版本与取件**

- [ ] 无 `latest`、无 `:latest`
- [ ] 被测软件 sha256 写死在脚本
- [ ] 三级取件（本地缓存 / Release / 镜像）+ 强制校验
- [ ] `<安装目录>/artifacts/` 缓存复用生效
- [ ] `PINNED-VERSIONS.md` 齐全

**分发与部署**

- [ ] 开场提示「从哪下 / 多大 / 慢怎么办」
- [ ] Linux 产品默认持久化（systemd + 开机自启）
- [ ] Windows 默认产出目录在**桌面**
- [ ] 打印完整卸载方法

**仓库**

- [ ] 顶层只有目标名目录 + `oneclick/` + `README.md` + `Agent.md`
- [ ] 目录名全英文
- [ ] 大件不入库、`.gitignore` 就位
- [ ] 首页三块（声明 / 一键命令 / 项目树）
- [ ] 子页无声明、无冗余章节
- [ ] 提交信息为单词级
- [ ] Release 资产 + `SHA256SUMS.txt` 已更新且哈希对齐

---

## 11. 已有案例的固定版本（速查）

| 目标 | 固定版本 | 一键入口 | 产出物 | 默认目录 |
| :--- | :--- | :--- | :--- | :--- |
| HexHub | **5.1.9** | `oneclick/hexhub-vip-test.ps1` | 便携式 HexHub 目录（已打补丁） | `桌面\HexHub-5.1.9` |
| Listary 6 | **6.3.5.94** | `oneclick/listary-pro-test.ps1` | 正常安装的 Listary Pro | `桌面\Listary` |
| 妙妙屋X | **v0.5.4** | `oneclick/miaomiaowux-license-test.sh` / `.ps1` | systemd 常驻服务 | `/opt/mmwx` |

> 所有构件托管于本仓库 Release：
> `https://github.com/Xioaruan912/ReverseFinal/releases/tag/whitebox-audit-v1.0`

---

## 12. 免责声明

本仓库仅用于**已完成授权的自有资产 / 沙盒环境**的安全验证与防御加固研究。
使用者须自行确认测试目标处于合法授权范围内。
