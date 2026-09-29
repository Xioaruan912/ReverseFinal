# 妙妙屋X v0.5.4

> **妙妙屋X（miaomiaowux）** 是一套自托管的代理节点管理与订阅分发系统。
> 本包用于在**自建实例**上检查它的「专业版能力」与「数量上限」是服务端说了算，还是页面自己说了算。
> 固定版本 **v0.5.4**，构件全部来自本仓库 Release，取件后强制校验 sha256。

---

## 一、这是什么软件

装上妙妙屋X 之后由你自己运营，用来把多台服务器上的代理节点统一管起来、并把订阅链接发给用户。

| 模块 | 功能 |
|---|---|
| **服务器管理** | 把多台远程服务器接入主控，统一查看在线状态、心跳、系统指标 |
| **节点管理** | 导入 / 批量管理节点，给节点打标签、分组、排序、改名 |
| **订阅分发** | 生成订阅链接，输出 Clash / Surge / Loon / SingBox / V2Ray 等多种客户端格式 |
| **用户与套餐** | 用户账号、套餐、流量额度、到期时间、续费、流量重置 |
| **流量统计** | 实时速率、每台服务器 / 每个用户的流量统计与 30 天趋势图 |
| **证书与域名** | ACME 自动申请续期证书、DDNS、多域名与反代 |
| **探针页** | 对外展示的伪装 / 状态页，可自定义外观 |
| **面板外观** | 多套主题、面板壁纸、登录页壁纸、自定义样式 |
| **其他** | 公告、TG 机器人、订阅备份、数据库备份迁移、日志 |

系统分**试用 / 免费档**与**付费档（专业版）**：

- 免费档有**数量上限**：可管理的服务器数、节点数、用户数都有上限
- 专业版另解锁一批**进阶能力**：节点测速、节点限速、分享服务器、内嵌 Xray、REALITY 域名池，以及高级主题与自定义样式

---

## 二、测试后可用功能

跑完一次测试（无需购买记录、不访问厂商许可服务器）后，下列能力即解锁：

| 能力 | 测试后 | 说明 |
| :--- | :---: | :--- |
| 专业版档位显示 | ✅ | 面板档位由「试用版」变为「专业版」 |
| 高级主题（高级黑金）/ 液态玻璃 | ✅ | 已实测：服务端放行，主题真正生效 |
| 自定义 CSS | ✅ | 同上 |
| 节点测速 | ✅ | 能力判定放行 |
| 节点限速 | ✅ | 能力判定放行 |
| 分享服务器 | ✅ | 能力判定放行 |
| 内嵌 Xray | ✅ | 能力判定放行 |
| REALITY 域名池 | ✅ | 能力判定放行 |
| 用户数量上限（试用档 3） | ✅ | 已实测：可继续添加；官方版会被「已达到用户数量上限」拦回 |
| 服务器数量上限（试用档 1） | ✅ | 已实测：可继续添加；官方版止步于 1 台 |
| 节点数量上限（试用档 5） | ✅ | 判定已归零 |
| 许可密钥在线激活 | ❌ | 仍由厂商许可服务器裁决，本测试不改变这一点 |

> 逐项对照与截图见 [`reports/最终验证-AB对照.txt`](reports/最终验证-AB对照.txt) 与 [`reports/evidence/`](reports/evidence/)。

---

## 三、环境要求

| 项 | 要求 |
|---|---|
| 操作系统 | Windows（配合 WSL2）或 Linux |
| 运行环境 | WSL2 + Debian，或任意 Linux 发行版 |
| 依赖 | `curl`、`unzip`、解包工具 `upx`、`python3`（一键脚本会自动调用，缺失时会提示安装命令） |
| 磁盘 | 约 300 MB（测试结束会自动清理） |
| 网络 | 构件从 GitHub 下载，中国大陆可能较慢；支持自建镜像 |
| 端口 | 面板默认 `12889` |

---

## 四、一条命令跑通（推荐）

**Linux / WSL：**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh)
```

**Windows（自动交给 WSL 执行）：**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.ps1 | iex"
```

脚本会依次完成：

```
[1] 提示构件来自 GitHub，中国大陆可能较慢（可自建镜像 / 手动放置）
[2] 询问安装目录（回车用默认 /opt/mmwx）
[3] 取测试包 + 取固定版本 v0.5.4 主程序 → 逐个校验 sha256
[4] 安装到指定目录 + 注册 systemd 服务 + 设为开机自启
[5] 证据与报告另存到 ~/ReverseAudit-Evidence/，临时文件自动清理
    （安装目录长期保留，不做临时测试运行）
```

**GitHub 下载慢时**：

```bash
# 自建镜像作为备用源
MMWX_MIRROR=https://your-mirror/mmwx bash <(curl -fsSL .../miaomiaowux-license-test.sh)

# 或先手动下载 mmwx-v0.5.4-linux-amd64 放进 <工作目录>/artifacts/ 后重跑
```

**常用环境变量**：

| 变量 | 作用 |
| :--- | :--- |
| `PORT` | 面板端口（默认 12889） |
| `MMWX_INSTALLDIR` | 安装目录（跳过询问，默认 `/opt/mmwx`） |
| `MMWX_YES=1` | 非交互，全部用默认值 |
| `MMWX_NO_SERVICE=1` | 只安装，不注册 systemd 服务 |
| `MMWX_MIRROR` | 自建镜像前缀 |

---

## 五、跑完看到什么

启动后浏览器打开 `http://127.0.0.1:12889/`：

1. 首次进入是初始化向导 → 创建管理员账号
2. 用刚创建的账号登录
3. 进入 **系统设置 → 许可证（License）**，对照下表

| 观察项 | 未测试 | 测试后 |
| :--- | :--- | :--- |
| 档位显示 | 试用 / 免费档 | 专业版 |
| 高级主题 | 不可选 / 选了不生效 | 生效 |
| 反复添加用户 | 到上限后被拦回，提示「已达到用户数量上限」 | 可持续添加 |
| 反复添加服务器 | 到上限后被拦回 | 可持续添加 |
| 面板上的专业版标记 | 显示未解锁 | 显示已解锁 |

---

## 六、部署与运维

安装完成后即为常驻服务（systemd + 开机自启），日常用这几条命令：

```bash
systemctl status  mmwx      # 查看状态
systemctl restart mmwx      # 重启
systemctl stop    mmwx      # 停止
systemctl disable mmwx      # 取消开机自启
journalctl -u mmwx -f       # 实时日志
```

数据与程序都在安装目录：

```
/opt/mmwx/
├── mmwx            可执行文件
├── artifacts/      固定版本构件缓存（重跑可直接复用）
└── data/           数据目录（长期保留）
```

升级：重跑同一条命令即可（会覆盖可执行文件，`data/` 不受影响）。

卸载：

```bash
systemctl disable --now mmwx && rm -f /etc/systemd/system/mmwx.service && rm -rf /opt/mmwx
```

> **WSL 未启用 systemd？** 脚本会自动降级为安装目录下的 `start.sh` / `stop.sh` + `mmwx.log`。
> 想用 systemd：在 `/etc/wsl.conf` 写入 `[boot]` + `systemd=true` 后重启 WSL，再重跑本脚本。
>
> **只想安装不注册服务**：`MMWX_NO_SERVICE=1`。

### 前端与 Docker 部署

`toolkit/deploy/` 下另有三条部署路径，均按 sha256 摘要/哈希锁定版本：

| 脚本 | 用途 |
| :--- | :--- |
| `deploy/deploy-native.sh` | 本机部署（不写 systemd、不改 `/etc`，目录可控） |
| `deploy/deploy-docker.sh` | Docker 部署，按 `@sha256` 摘要锁定镜像 |
| `deploy/deploy-docker.sh --offline` | 离线部署，用包内镜像 tar 导入，零外部请求 |

---

## 七、目录说明

```
MiaomiaowuX-v0.5.4/
├── README.md                 本文件
├── 使用说明.txt               纯文本速查
├── PINNED-VERSIONS.md        固定版本与 sha256
├── installer/                固定件说明 / 官方校验清单 / 上游脚本留档
├── toolkit/                  一键测试 / 版本固定部署 / 页面行为脚本
│   ├── run.sh                一键取件 + 准备副本 + 启动
│   ├── mmwx-crack.py         带原始字节校验的补丁器
│   └── deploy/               本机 / Docker / 离线镜像部署（按摘要锁定）
├── reports/                  评估报告 / 证据截图 / 前端资源
└── src/                      测试过程辅助脚本
```

| 报告 | 内容 |
| :--- | :--- |
| [`reports/许可与配额评估报告.md`](reports/许可与配额评估报告.md) | 成因、复现与整改建议 |
| [`reports/最终验证-AB对照.txt`](reports/最终验证-AB对照.txt) | 官方版 vs 测试版逐项对照 |
| [`reports/部署与审计记录.md`](reports/部署与审计记录.md) | 部署与测试过程记录 |
