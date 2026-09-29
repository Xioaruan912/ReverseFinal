# 妙妙屋X (miaomiaowux) · 白盒鉴权测试包 —— 使用说明

> 本说明只讲两件事：**这是什么软件**、**怎么跑测试**。
> 结论、证据与整改建议在 `reports/` 里。

---

## 零、一条命令跑通（从本仓库拉取，固定版本）

**Linux / WSL：**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh)
```

**Windows（自动交给 WSL 执行）：**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.ps1 | iex"
```

测试工具包与 **v0.5.4 主程序**都从本仓库 Release 拉取并校验 sha256，不访问上游 `releases/latest`。

脚本与参数说明见 `oneclick/README.md`；下面第四节的命令是**手动分步**版本，供需要逐步观察时使用。

---

## 一、这是什么软件

**妙妙屋X（miaomiaowux）** 是一套**自托管的代理节点管理与订阅分发系统**，装上之后由你自己运营，用来把多台境外服务器上的代理节点统一管起来、并把订阅链接发给用户。

它的主要用途：

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
- 专业版另解锁一批**进阶能力**，例如节点测速、节点限速、分享服务器、内嵌 Xray、REALITY 域名池，以及高级主题与自定义样式

---

## 二、这个测试包要验证什么

只验证一件事：**这个软件的数量上限与专业版权益，是否真的由服务端说了算。**

具体看三件事：

1. 面板上显示为"未付费"时，专业版能力是否真的用不了
2. 达到免费档上限后，是否真的无法继续添加服务器 / 节点 / 用户
3. 上述限制是不是只在浏览器界面里生效

测试在**自建实例**上进行，不涉及任何第三方系统。

---

## 三、环境要求

| 项 | 要求 |
|---|---|
| 操作系统 | Windows（配合 WSL2）或 Linux |
| 运行环境 | WSL2 + Debian，或任意 Linux 发行版 |
| 依赖 | 系统自带 `curl`；解包工具 `upx`（`patches/` 内脚本会自动调用）；`python3`；`node`（可选，仅方式 C 需要） |
| 磁盘 | 约 300 MB |
| 端口 | 面板默认 `12889` |

> 本测试包面向**你自建的实例**。请勿对他人部署的实例执行测试。

---

## 四、怎么跑

### 第 1 步：把被测软件跑起来（版本固定，不跟随上游更新）

本包**锁死 v0.5.4**。构件来源依次为：**本地 `artifacts/` → 本仓库 Release 固定件 → 自建镜像 `MMWX_MIRROR`**；
取到后强制校验 sha256，不匹配立即中止。**全程不访问上游 `releases/latest`，也不使用 `:latest` 镜像。**

**方式一：本机（命令）部署**

```bash
bash deploy/deploy-native.sh
# 自定义端口 / 数据目录 / 自建镜像：
# PORT=12889 DATA_DIR=/opt/mmwx-lab/data MMWX_MIRROR=https://your-mirror/mmwx bash deploy/deploy-native.sh
```

**方式二：Docker 部署（按 sha256 摘要锁定镜像）**

```bash
bash deploy/deploy-docker.sh              # 在线：按摘要拉取锁定镜像
bash deploy/deploy-docker.sh --offline    # 离线：用包内镜像 tar 导入，零外部请求
```

**方式三：完全手动**（不想跑脚本时）

```bash
mkdir -p ~/mmwx/run/artifacts && cd ~/mmwx/run
# 从本仓库 Release 下载固定件：
curl -fL -O https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0/mmwx-v0.5.4-linux-amd64
sha256sum mmwx-v0.5.4-linux-amd64   # 必须等于 ecc1020a…5657
chmod +x mmwx-v0.5.4-linux-amd64
mkdir -p data && PORT=12889 MMWX_LISTEN_PORT=12889 MMWX_DATA_DIR=$PWD/data ./mmwx-v0.5.4-linux-amd64
```

> 版本锁定清单（版本号、sha256、镜像摘要、禁止使用的地址）都在 `deploy/versions.lock.json`。
> 上游一旦发布新版本，本包行为**不会改变**；要升级需显式修改该文件。

浏览器打开 `http://127.0.0.1:12889/`：

1. 首次进入是初始化向导 → 创建管理员账号
2. 用刚创建的账号登录
3. 进入 **系统设置 → 许可证（License）**，这里能看到当前档位与各项数量上限

### 第 2 步：记录基线

| 记录什么 | 在哪里看 |
|---|---|
| 当前档位、到期时间 | 系统设置 → 许可证 |
| 服务器 / 节点 / 用户 的"已用 / 上限" | 系统设置 → 许可证（或用户页顶部） |
| 专业版能力是否可用 | 用户页、服务器页、节点页上带标记的按钮 |

### 第 3 步：执行测试

**方式 A：一键归零（推荐）**

```bash
cd patches
bash oneliner.sh          # 锁定版本取件 → 校验 → 处理 → 启动测试实例（端口 12889）
```

启动后把地址换成测试实例的端口（默认 12889），重复第 2 步的记录项。

**方式 B：分步执行（便于观察每一步）**

```bash
# 先按 deploy/fetch.sh 的规则取到锁定版本，再处理
python3 patches/mmwx-crack.py artifacts/mmwx-v0.5.4-linux-amd64 -o mmwx-tested
PORT=12889 MMWX_DATA_DIR=$PWD/data ./mmwx-tested
```

**方式 C：只看界面行为（不改程序）**

```bash
cd poc
node verify_crack_theme.js      # 高级主题能否生效
node verify_quota_api.js        # 读取档位与数量上限
node verify_quota_server.js     # 反复添加用户，观察是否被拦
node verify_quota_servers2.js   # 反复添加服务器，观察是否被拦
```

> 方式 C 需要先 `npm i playwright` 并准备 Chromium。

### 第 4 步：对比结论

把第 3 步的结果与第 2 步的基线逐项对照。

---

## 五、跑完看到什么

| 观察项 | 基线（未处理） | 跑完测试后 |
|---|---|---|
| 档位显示 | 试用 / 免费档 | 显示为专业版 |
| 高级主题 | 不可选 / 选了也不生效 | 生效 |
| 反复添加用户 | 到达上限后被拦回，提示"已达上限" | 可持续添加 |
| 反复添加服务器 | 到达上限后被拦回 | 可持续添加 |
| 面板上的专业版标记 | 显示为未解锁 | 显示为已解锁 |

> 各步骤的完整数值与截图见 `reports/FINAL_VERIFICATION.txt`。

---

## 六、想看得更深

本说明只覆盖"是什么 + 怎么跑"。完整结论、证据与整改建议都在 `reports\`：

| 文件 | 内容 |
|---|---|
| `reports\miaomiaowuX-mmwx-v0.5.4-license_security_assessment_report.md` | 正式评估报告 |
| `reports\FINAL_VERIFICATION.txt` | 最终验证输出（逐项对照） |
| `reports\ADDENDUM_VIP_REMOVAL.md` | 补充结论与整改建议 |
| `reports\DEPLOY_AND_AUDIT_NOTES.md` | 部署与测试过程记录 |
| `reports\screens\` | 界面取证截图 |

---

## 七、目录说明

```
miaomiaowuX-v0.5.4-white-box-audit/
├── README.md        ← 本文件（使用说明）
├── deploy/          ← ★ 版本固定 + 自控部署（本机 / Docker / 离线镜像）
├── patches/         ← 一键归零工具
├── poc/             ← 界面行为自动化脚本
├── reports/         ← 结论、证据、截图
├── scripts/         ← 测试过程辅助脚本
├── exports/         ← 界面资源导出
├── samples/         ← 官方发布清单与配置样例
├── artifacts/       ← （运行后生成）本地锁定的构件缓存
└── dist/            ← 本测试包压缩件
```

---

*本测试包仅用于已完成授权的沙盒 / 自有资产测试。*
