# 阻断厂商授权服务器（离线化）—— 验证用

> 目的：让 `api.hexhub.cn` / `oss.hexhub.cn` **网络不可达**，而不是返回 HTTP 错误。
> 关键差异：
> - **网络不可达**（connection failed / DNS 失败）→ 前端 `catch` 分支 → `state=2`「网络受限，已离线」，**本地 member 保留**，VIP 继续有效。
> - **HTTP 401** → axios 响应拦截器调用 `logout()` → `token/priKey/member` 全部清空，VIP 失效。
>
> 这正是「阻断联网服务器比对」能拿到 VIP 的原因。

## 方式一：hosts 黑洞（推荐，最贴近真实场景）

以管理员身份编辑 `C:\Windows\System32\drivers\etc\hosts`，追加：

```
0.0.0.0 api.hexhub.cn
0.0.0.0 oss.hexhub.cn
0.0.0.0 www.hexhub.cn
0.0.0.0 hexhub.cn
```

刷新 DNS：`ipconfig /flushdns`

## 方式二：Windows 防火墙出站规则

```powershell
New-NetFirewallRule -DisplayName "Block HexHub License Server" -Direction Outbound `
  -Action Block -RemoteAddress (Resolve-DnsName api.hexhub.cn).IPAddress
```

批量解除：`Remove-NetFirewallRule -DisplayName "Block HexHub License Server"`

## 方式三：仅验证用（不改系统）—— Playwright/CDP 路由拦截

见 `../poc_offline_vip.js`：

```js
await page.route('**://api.hexhub.cn/**', r => r.abort('connectionfailed'));
await page.route('**://oss.hexhub.cn/**', r => r.abort('connectionfailed'));
```

## 涉及的厂商端点（逆向自内嵌前端 bundle）

| 端点 | 用途 |
| :--- | :--- |
| `GET  https://api.hexhub.cn/client/member/currentv2` | 拉取当前会员（RSA 加密分片，客户端私钥解密） |
| `GET  https://api.hexhub.cn/client/member/current`   | 会员信息（兼容旧版） |
| `POST https://api.hexhub.cn/client/member/pre-check` | 会员前置校验 |
| `POST https://api.hexhub.cn/client/pay/member-package` | 购买会员套餐 |
| `POST https://api.hexhub.cn/client/member-asset/sync`  | 会员资产云同步 |
| `GET  https://api.hexhub.cn/client/version/check`      | 版本检查 |
| `POST https://api.hexhub.cn/client/stats/submit`       | 统计上报 |

> 本地后端 `http://127.0.0.1:35580`（CEF 壳进程内的 Go HTTP 服务）**不承载**会员鉴权逻辑，
> 仅提供插件路由（DB/SSH/Docker/Redis/Repository）与静态资源。
