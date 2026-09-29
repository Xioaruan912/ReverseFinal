# 固定版本清单 — Beyond Compare 5

> 规则：**禁止动态地址**，构件一律锁 tag / 固定版本号 + sha256 强制校验。

## 主安装包（Windows）

| 项 | 值 |
| --- | --- |
| 产品 | Beyond Compare 5 |
| 版本 | **5.2.6.32774** |
| 官方直链 | `https://www.scootersoftware.com/files/BCompare-5.2.6.32774.exe` |
| 大小 | 28,692,792 字节（27.36 MB） |
| sha256 | `a28a1eb43551999e499a8a16af328e0eff1b9a6d45b7dc479682852701b7bb97` |
| md5 | `eba9d680cd0f3f116bd064ba9059d1e6` |
| 打包器 | **Inno Setup**（新版格式） |
| 侦察时间 | 2026-09-29 |

### 同版本其它可选外壳

| 版本 | 直链 | 状态 |
| --- | --- | --- |
| 5.0.4.30422 | `https://www.scootersoftware.com/files/BCompare-5.0.4.30422.exe` | HTTP 200（26.9 MB） |
| 5.0.3.30247 | 同上模式 | HTTP 404 |
| 5.0.0.29726 | 同上模式 | HTTP 404 |

> ⚠️ **必须钉 5.2.6.32774**（当前官方页版本）。若上游发新版，直链仍在但版本漂移 —— 审计结论会失效。

## 侦察结论

| 项 | 结果 |
| --- | --- |
| 安装包可读串 | 极少（LZMA 压缩），`license/trial/update` 等**明文 0 次** |
| 打包器 | Inno Setup（`Inno Setup` 字符串 3 次） |
| `innoextract 1.9` | ❌ 失败：`Unexpected setup loader revision: 2` / `Setup loader checksum mismatch` |
| `7z 25.01` | ⚠️ 仅解出**安装器 PE 资源**（30 个文件：图标 / MANIFEST / RCDATA），**未拿到应用载荷** |

## 待解决：静态解包

优先级从高到低：

1. **`innounp`**（Windows 工具，对新版 Inno 支持最好）—— 静态解包，不执行安装器，符合「纯安装器不执行安装程序」原则
2. **新版 innoextract（≥1.10/1.11）** —— 1.9 认不出 loader revision 2
3. **静默安装提取**（`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=<dir>`）—— 会写注册表，需配套清理
4. **`wine` + 安装器**（WSL 侧）—— 同样会写 wine prefix

## BC5 许可机制已知情报（待逐项验证）

| 项 | 预期 |
| --- | --- |
| 许可形式 | **`BC5Key.txt`**（离线密钥文件：用户名 / 组织 / 序列号 / 数量 / 版本） |
| 验证方式 | **RSA 签名验证**（公钥内嵌主程序） |
| 存放位置 | 安装目录 或 `%APPDATA%\Scooter Software\Beyond Compare 5\` |
| 试用机制 | 30 天试用，首次运行时间戳（注册表 / 文件） |
| 离线凭证 | **支持 key 文件离线激活** ← 本次审计核心目标 |
| 更新检查 | 安装包内 `Update` 出现 7 次；主程序待解包后定位 |

---

## 补丁产物

| 项 | 值 |
| :--- | :--- |
| 补丁后 `BCompare.exe` | 50,551,848 字节 |
| 补丁后 sha256（**黄金哈希**） | `aba327b822ae74d896c53ccfbe1ae57cc40e46350e929634cd5631d80e0d66dc` |
| 补丁处数 | 13（10 处代码 + 2 处等长字符串 + 移除 Authenticode 证书表 13,312 字节） |
| 构建脚本 | `toolkit/bc5_patch.py`（参考实现）/ `toolkit/bc5_patch.ps1`（便携）/ `oneclick/beyondcompare-license-test.ps1`（安装器内置） |
| 互证 | 三份互相独立的实现产出**逐字节相同**（见审计报告 §2.4） |

> 校验纪律：任何装机流程都必须先校验**原始构件 sha256**，打补丁后再校验**黄金哈希**。
> 回读校验只证明「写进去了」，黄金哈希才证明「写对了地方」。

## 构件获取

| 构件 | 位置 |
| :--- | :--- |
| `BCompare-5.2.6.32774.exe`（28,692,792 B） | 本仓库 Release 固定件：<https://github.com/Xioaruan912/ReverseFinal/releases/tag/whitebox-audit-v1.0> |
| 解包产物 `BCompare.exe` | 由安装包静默安装产出（`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOICONS /SP- /DIR=<dir>`） |

> 静态解包在本构件上不可用：`innoextract 1.9` 报 `Unexpected setup loader revision: 2`；
> `7z 25.01` 只能取出安装器资源，载荷 `[0]` 是 Inno `zlb` 压缩块（魔数 `7a 6c 62 1a`）。
