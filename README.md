# 软件功能实测（一键运行）

这里收了几款常用软件的实测包。每个都能一键跑起来，跑完直接打开软件看效果，
用来确认这些功能能不能正常使用。

不需要懂技术。

---

## 开始之前

- 电脑：Windows 10 / 11
- 有些步骤需要管理员权限，系统弹窗时点「是」
- 会联网下载文件，国内网络可能慢一点，多等一会儿

---

## 怎么跑

**方式一：双击（最简单）**

在本文件夹里双击下表中对应的 `.cmd` 文件，然后按提示操作即可。
跑完窗口会停住，看结果就好。

**方式二：复制一行命令**

1. 点开始菜单 → 输入 `PowerShell` → 右键「以管理员身份运行」
2. 把对应软件的那一行命令复制进去，回车
3. 等屏幕上出现「完成」

---

## 五个软件

| 软件 | 干什么用的 | 双击这个文件 | 跑完能看到什么 |
| :--- | :--- | :--- | :--- |
| **HexHub** | 连服务器、传文件的工具 | `安装-HexHub.cmd` | 桌面出现免安装文件夹，打开后会员功能可用 |
| **Listary** | 电脑文件快速搜索 | `安装-Listary.cmd` | 以专业版打开，标题显示 Pro |
| **Beyond Compare** | 文件、文件夹对比工具 | `安装-BeyondCompare.cmd` | 打开后不再提示试用到期 |
| **Quicker** | 快捷操作、效率工具 | `安装-Quicker.cmd` | 任务栏出现图标，会员等级显示专业版 |
| **妙妙屋X** | 服务器节点管理面板 | `安装-妙妙屋X.cmd` | 浏览器打开面板，显示专业版 |

### 对应的命令行（和双击等效）

**① HexHub**

```powershell
powershell -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub.ps1 | iex"
```

**② Listary**

```powershell
powershell -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/listary.ps1 | iex"
```

**③ Beyond Compare**

```powershell
powershell -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/beyondcompare.ps1 | iex"
```

**④ Quicker**

```powershell
powershell -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/quicker.ps1 | iex"
```

**⑤ 妙妙屋X**

Windows：

```powershell
powershell -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux.ps1 | iex"
```

Linux：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux.sh)
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
- **提示权限不足**：用「以管理员身份运行」打开 PowerShell；或右键 `.cmd` 选「以管理员身份运行」。
- **想装到别的盘**：用命令行方式，先在 PowerShell 里设置对应变量（见各软件文件夹里的《使用说明.txt》）。
- **报错了**：把屏幕上红色的文字截图，发给技术人员。

每个软件文件夹里都有一份更细的《使用说明.txt》。
