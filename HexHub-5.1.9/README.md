# HexHub Client 5.1.9 · 白盒鉴权测试包

> **目标**：HexHub Client `windows-amd64-installer-5.1.9.exe`
> （CEF + Go 架构的 SSH / SFTP / Docker / 数据库一体化客户端）
> **一句话结论**：会员（👑 Plus）权益判定完全在客户端完成。未登录 + 厂商服务器不可达时，
> 顶栏仍会点亮会员徽章，21 项会员能力随即可用。

---

## 测试后可用功能

只要完成一次测试（无需账号、无需联网），下列能力即解锁：

| 能力 | 测试后 | 备注 |
| :--- | :---: | :--- |
| 终端广播（一条命令批量执行） | ✅ | 纯客户端判定 |
| 批量上传文件 / 文件夹 | ✅ | 纯客户端判定 |
| 跨服务器文件传输（SFTP ↔ SFTP） | ✅ | 客户端直连两端 |
| 多窗口 / 多视图 / 视图拆分 | ✅ | 纯客户端判定 |
| 垂直分屏 / 水平分屏 / 标签重命名 | ✅ | 纯客户端判定 |
| 解除会话数上限（社区版 6 会话） | ✅ | 纯客户端判定 |
| 保存为日志 / 通过服务器代理打开浏览器 | ✅ | 纯客户端判定 |
| 压缩 / 解压缩（tar.gz · zip · 7z 等） | ✅ | 纯客户端判定 |
| 上传 SSH 公钥（ssh-copy-id） | ✅ | 纯客户端判定 |
| Docker：自选镜像仓库 | ✅ | 客户端直连 registry |
| Docker：本地网络拉取（SSH 隧道） | ✅ | 走 SSH 隧道 |
| Docker：容器文件管理 | ✅ | 纯客户端判定 |
| 自定义私有储存仓库 —— **local / WebDAV / S3** | ✅ | 完全离线可用（用户自有存储） |
| 官方云同步 / 表数据同步 | ⚠️ | 该功能本身依赖厂商服务端数据面 |
| 登录设备数配额（Pro 2 台 / Plus 5 台） | ❌ | 由服务端强制，测试无法改变 |

> 合计 23 个会员菜单项门禁，其中 **21 项为纯客户端判定**，测试后立即生效；
> 完整清单与服务端依赖分级见 [`reports/VIP功能测绘与服务端依赖分析.md`](reports/VIP功能测绘与服务端依赖分析.md)。

---

## 目录

| 目录 | 说明 |
| :--- | :--- |
| [`installer/`](installer/) | 目标安装包放置说明（145 MB 超 GitHub 限制，不入库） |
| [`toolkit/`](toolkit/) | ★ 一键测试工装（静态解包 / 启动 / 断网注入 / 取证 / 二进制补丁） |
| [`reports/`](reports/) | ★ 评估报告 + 会员功能测绘 + 方法论 SOP + 证据截图 |
| [`src/`](src/) | 自研分析工装源码（NSIS 解析器 / bundle 定位 / JS 美化 / 门禁测绘） |

---

## 一键使用

```powershell
# 推荐：一条命令跑完（自动取件 + 校验 + 执行）
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 | iex"
```

或在本目录手动分步：

```powershell
cd HexHub-5.1.9

# ① 环境自检（13 项）
powershell -ExecutionPolicy Bypass -File .\toolkit\preflight.ps1

# ② 主测试：静态解包 -> 启动客户端 -> 页面级断网 + 写入会员状态 -> 取证
powershell -ExecutionPolicy Bypass -File .\toolkit\run_test.ps1 -NegativeControl

# ③ 完全离线模拟登录（无需任何账号）
cd toolkit
$env:NODE_PATH="<你的 node_modules 路径>"
node poc_fake_login.js
```

**测试不做什么**：不改 hosts / 防火墙 / 注册表；不执行安装器；不碰已安装的 HexHub。
断网走 **Playwright 页面级 route abort**（仅拦截本页面请求，零系统改动）。

---

## 二进制微创补丁（登录场景首选）

```powershell
cd toolkit
python patch_vip.py
#  P1a/P1b  isMemberValid(){...}  ->  isMemberValid(){return!0}   (主 bundle + worker bundle)
#  P2       ue=le=>{...}          ->  ue=le=>!0                   (完整性校验)
#  等长替换：文件大小不变（118,715,652 == 118,715,652），仅 499 字节差异
```

---

## 动态验证（A/B/C/D 四组对照）

| 用例 | 数据 | 二进制 / 网络 | 顶栏徽章 | 截图 |
| :--- | :--- | :--- | :--- | :--- |
| **A** | 写入会员状态 | 原版 · **厂商服务器阻断** | ✅ 👑 Plus（未登录） | [`证据A`](reports/evidence/证据A-未登录断网仍显示Plus.png) |
| **B** | 伪造 token | 原版 · 服务器可达 | ❌ 会话被 401 拦截器清空 | — |
| **C1** | **已过期** + 伪造签名 | 原版 | ❌ 无徽章 | [`证据C1`](reports/evidence/证据C1-原版无徽章.png) |
| **C2** | 同 C1（**同一份过期/伪造数据**） | **等长补丁版** | ✅ 👑 Plus | [`证据C2`](reports/evidence/证据C2-补丁版Plus.png) |
| **D** | 自建密钥对 + mock 响应 | 原版 · 服务器阻断 | ✅ 👑 Plus（客户端认为已登录+已同步） | [`证据D`](reports/evidence/证据D-完全离线模拟登录Plus.png) |

---

## 报告与工装源码

| 文件 | 内容 |
| :--- | :--- |
| [`reports/HexHub-5.1.9-VIP鉴权脆弱性评估报告.md`](reports/HexHub-5.1.9-VIP鉴权脆弱性评估报告.md) | 评估结论、成因、复现与整改建议 |
| [`reports/VIP功能测绘与服务端依赖分析.md`](reports/VIP功能测绘与服务端依赖分析.md) | 会员功能全量清单与服务端依赖分级 |
| [`reports/HOWTO-白盒鉴权脆弱性测试-SOP.md`](reports/HOWTO-白盒鉴权脆弱性测试-SOP.md) | 通用白盒鉴权测试方法论 |
| [`src/`](src/) | 自研工装源码（NSIS 解析器 / bundle 定位 / JS 美化 / 门禁测绘） |
