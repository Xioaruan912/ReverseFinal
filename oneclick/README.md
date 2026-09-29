# 一键白盒鉴权脆弱性测试

三条命令，各自复制即用。**测试工具包与被测软件全部从本交付仓库
（`Xioaruan912/ReverseFinal`）拉取**，下载后逐一校验 sha256，不匹配立即中止；
全程不访问被测软件官网的「最新版」地址，避免厂商发新版后测试对象漂移、结论不可复现。

| 案例 | 被测软件 | 固定版本 | 入口脚本 |
|---|---|---|---|
| HexHub | SSH / SFTP / Docker / 数据库客户端 | 5.1.9 | `hexhub-vip-test.ps1` |
| Listary 6 | Windows 文件搜索增强 | 6.3.5.94 | `listary-pro-test.ps1` |
| 妙妙屋X | 自托管 Xray 节点管理与订阅分发 | v0.5.4 | `miaomiaowux-license-test.sh` / `.ps1` |

---

## 1. HexHub · 会员权益

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 | iex"
```

脚本会：拉取测试工具包 → 校验 → 拉取 HexHub 5.1.9 安装包 → 校验 → 环境自检 → 执行测试并出截图。

保存到本地再跑（推荐，参数更全）：

```powershell
curl.exe -fL -o hexhub-vip-test.ps1 https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\hexhub-vip-test.ps1
# 可选参数： -StopAtEnd  跑完自动关闭被测程序
#           -KeepFiles  保留工作目录
#           -WorkDir D:\lab\hexhub
```

跑完后看点：`%TEMP%\hexhub-lab\case\exports\` 里的截图，以及 `reports\` 里的报告。

---

## 2. Listary 6 · 专业版权益

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1 | iex"
```

脚本会：拉取测试工具包 → 校验 → 拉取 Listary 6.3.5.94 安装包与主程序 → 校验 →
（未安装则静默安装）→ 执行鉴权测试 → 复核状态。

```powershell
curl.exe -fL -o listary-pro-test.ps1 https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\listary-pro-test.ps1 -Email 你的邮箱@example.com
# 可选参数： -SkipInstall   已装好 Listary 时跳过安装
#           -Restore       回滚到测试前状态
#           -WorkDir D:\lab\listary
```

跑完后看点：Listary 托盘右键 → 设置，专业版状态是否已生效。

---

## 3. 妙妙屋X · 许可与数量配额

**Linux / WSL：**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh)
```

**Windows（自动交给 WSL 执行）：**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.ps1 | iex"
```

脚本会：拉取测试工具包 → 校验 → 取固定版本 v0.5.4 主程序 → 校验 →
在 `12889` 端口启动测试实例。

```bash
PORT=12889 WORKDIR=~/mmwx-lab bash <(curl -fsSL .../oneclick/miaomiaowux-license-test.sh)
# 自建镜像作为 Release 的备用源
MMWX_MIRROR=https://your-mirror/mmwx bash <(...)
```

启动后浏览器打开 `http://127.0.0.1:12889/`：首次进入是初始化向导 → 创建管理员 →
登录后到「系统设置 → 许可证」对照档位与数量上限。

---

## 构件来源与校验

所有构件都在本交付仓库的 Release：

**`https://github.com/Xioaruan912/ReverseFinal/releases/tag/whitebox-audit-v1.0`**

| 构件 | 用途 |
|---|---|
| `HexHub-whitebox-audit-pack-v1.0.zip` | HexHub 测试工具包 |
| `HexHub-Client-5.1.9-windows-amd64-setup.exe` | HexHub 5.1.9 安装包 |
| `Listary-whitebox-audit-pack-v1.0.zip` | Listary 测试工具包 |
| `Listary-6.3.5.94-setup.exe` / `...-main.exe` | Listary 6.3.5.94 安装包 / 主程序 |
| `miaomiaowuX-whitebox-audit-pack-v1.0.zip` | 妙妙屋X 测试工具包 |
| `mmwx-v0.5.4-linux-amd64` / `...-windows-amd64.exe` | 妙妙屋X v0.5.4 主程序 |
| `miaomiaowux-docker-image-v0.5.4.tar.gz` | 妙妙屋X 离线镜像 |
| `SHA256SUMS.txt` | 全部构件的哈希清单 |

三个一键脚本把**被测软件的哈希直接写在脚本里**（改版本时同步改），
下载后强制比对，不匹配即中止，绝不安装未经验证的二进制。

---

## 不改本地、不留痕

| 案例 | 落点 | 清理方式 |
|---|---|---|
| HexHub | `%TEMP%\hexhub-lab\` | 删除该目录 |
| Listary | `%TEMP%\listary-lab\` + Listary 自身设置 | `-Restore` 参数一键回滚 |
| 妙妙屋X | `~/mmwx-lab/`（WSL 内） | 删除该目录；不写 systemd、不动 `/etc` |

> 本目录所有脚本仅用于**已完成授权的沙盒 / 自有资产**安全测试。
