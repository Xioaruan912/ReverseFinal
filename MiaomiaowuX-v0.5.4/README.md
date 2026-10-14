# 妙妙屋X —— 一键运行说明

## 这是什么

妙妙屋X 是一套自己部署的服务器节点管理面板：把多台服务器上的节点集中管理，
并把订阅链接分发给用户。免费版对可管的服务器数、节点数、用户数有上限，
专业版会放开这些上限并解锁一批进阶功能。

## 怎么跑

Windows：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.ps1 | iex"
```

Linux：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/miaomiaowux-license-test.sh)
```

跑完会装成一个常驻服务，并自动开机启动。

## 跑完能看到什么

打开浏览器访问 `http://127.0.0.1:12889/`：

1. 第一次进入是初始化向导 → 创建管理员账号
2. 用刚创建的账号登录
3. 进「系统设置 → 许可证」，能看到档位变成**专业版**

| 看这里 | 没跑之前 | 跑完 |
| :--- | :--- | :--- |
| 档位显示 | 试用 / 免费 | 专业版 |
| 高级主题 | 不可用 | 生效 |
| 添加用户 | 到上限就被拦 | 可以继续加 |
| 添加服务器 | 到上限就被拦 | 可以继续加 |
| 专业版标记 | 显示未解锁 | 显示已解锁 |

> 「许可密钥在线激活」这项仍由厂商服务器决定，本测试不改变它。

## 不想要了怎么删

执行下面这行命令即可彻底删除：

```bash
systemctl disable --now mmwx && rm -f /etc/systemd/system/mmwx.service && rm -rf /opt/mmwx
```

## 常见问题

- **下载慢**：换网络，或过一会儿重跑同一条命令。
- **想换端口**：Windows 上先在 PowerShell 里执行 `$env:PORT='12889'`，再跑命令。
- **想装到别的目录**：Linux 上执行
  `MMWX_INSTALLDIR=/srv/mmwx bash <(curl -fsSL .../miaomiaowux-license-test.sh)`。
