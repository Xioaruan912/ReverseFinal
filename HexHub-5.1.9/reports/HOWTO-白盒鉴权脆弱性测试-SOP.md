# 白盒鉴权脆弱性测试（CWE-602）—— 通用方法论 + HexHub 实操手册

> 配套案例：`HexHub-Client-windows-amd64-installer-5.1.9.exe`
> 适用场景：**授权沙盒内**的客户端鉴权逻辑走查（会员/订阅/许可/激活/试用）
> 核心命题：**客户端是不是特权的最终裁决者？** 如果是 → CWE-602 成立。

---

## 第一部分 · 通用六步法（可复用到任何客户端）

### Step 0 · 授权门（不可跳过）

```
确认三件事，缺一不做：
  ① 目标资产归属与测试授权（书面/工单）
  ② 隔离沙盒（快照可回滚，禁止触碰生产账号/真实支付）
  ③ 凭据红线：拿到真实 token/salt/私钥 → 停，只报告，不落盘到任何外部输出
```

### Step 1 · 载荷还原（Installer / 壳 / 打包器 → 真实文件）

不要直接双击安装。**先静态解包**，得到干净载荷再分析：

| 打包器 | 识别特征 | 解包手段 |
| :--- | :--- | :--- |
| **NSIS** | overlay 中 `EF BE AD DE` + `NullsoftInst` | 本案例 `extract.py`（LZMA solid + 419 条目表） |
| Inno Setup | `Inno Setup Setup Data` | `innounp -x` |
| InstallShield | `InstallShield` | `unshield` |
| MSI | OLE 复合文档 | `msiexec /a` / `lessmsi` |
| 7z SFX | 7z 魔数 `37 7A BC AF 27 1C` | `7z x` |

> 解包后**必须校验**：PE 以 `4D 5A` 开头、pak/资源魔数正确、总大小与条目表 offset 差值自洽。
> 本案例第一次解包时 base 差 8 字节导致全部文件错位 —— 用魔数自检立刻发现。

### Step 2 · 技术栈判定 + 信任边界测绘

**信号 → 结论**：

| 信号 | 结论 |
| :--- | :--- |
| `Go build ID` / `goroutine` / `.go` 符号 | Go 二进制 |
| `libcef.dll` + `*.pak` + `v8_context_snapshot.bin` | CEF/Chromium 壳 |
| `app.asar` / `electron` | Electron |
| `libflutter.so` / `dart` | Flutter |
| `webview2` / `wails` | Wails |

**信任边界表（必填）**：把每个"决策点"标上它跑在哪一侧

```
┌─ 客户端进程 ─────────────────────────┐   ┌─ 服务端 ──────────────┐
│  UI 判定函数 (isMemberValid 等)      │   │  真实权益数据源        │
│  本地持久化 (localStorage/SQLite/注册表)│   │  签名/密钥             │
│  本地 HTTP/RPC 后端 (是否含鉴权逻辑?)  │   │  配额/计费             │
└──────────────────────────────────────┘   └───────────────────────┘
```

> **判定技巧**：把客户端二进制的符号表全量 dump 一遍，搜 `Member|Vip|Licen|Auth|Token|Session`。
> 若全部命中都在**前端 JS / UI 层**，本地后端只有插件路由 → 服务端权威点只在远程 → 客户端必然可绕。

### Step 3 · 定位鉴权决策链

按"**入口 → 决策 → 数据**"三段式定位：

```bash
# 3.1 先找 UI 门禁（禁用/置灰/弹窗）
grep -a "isMemberValid\|isVip\|isPro\|checkLicense" <bundle>

# 3.2 反查决策函数定义（不是调用点！）
#     minified JS 用正则:  name\s*=\s*(async\s*)?\(|function
#     或搜 isMemberValid(){ / isMemberValid:function

# 3.3 再找数据来源（HTTP 端点 / 本地存储）
grep -a "https\?://\|localStorage\|create({baseURL"
```

**关键提问清单**：
- [ ] 判定用的是**本地时间**还是**服务端签发时间**？
- [ ] 特权状态存在哪里？**明文可写**吗？
- [ ] 有没有"完整性签名"？签名的**密钥在哪一侧**？
- [ ] 签名输入是否全部由客户端可控？（自证式哈希 = 无效）

### Step 4 · 数据面定位（持久化 + 网络）

| 存储 | 落盘位置（Windows） |
| :--- | :--- |
| CEF/Chromium localStorage | `%APPDATA%\<App>\cache\Default\Local Storage\leveldb\` |
| Electron localStorage | `%APPDATA%\<App>\Local Storage\leveldb\` |
| IndexedDB | `...\IndexedDB\` |
| 本地 SQLite | `%APPDATA%\<App>\*.db` |

> 落盘明文 + 客户端可写 = **特权状态可伪造**。这是 CWE-602 的物理证据。

### Step 5 · 动态验证（必须做 A/B 对照）

**三条接入通道**（按成本排序）：

| 通道 | 方法 | 适用 |
| :--- | :--- | :--- |
| **CDP** | 启动参数 `--remote-debugging-port=9222` | CEF / Electron（首选） |
| **隐藏口令** | 逆向出的调试快捷键 | 厂商自带后门 |
| **Frida** | Hook native `isMemberValid` 对应函数 | 无 JS 层 / 强混淆 |

**A/B 对照表（报告必备）**：

| 用例 | 数据 | 二进制/网络 | 期望 |
| :--- | :--- | :--- | :--- |
| A | 已过期 + 伪造签名 | 原版 | 应拒绝 |
| B | 同 A | 补丁版 | 若放行 → 判定被绕过 |
| C | 合法终身数据 | 原版 + **断网** | 若放行 → 离线无锚点 |
| D | 同 C | 原版 + **服务器可达** | 若拒绝 → 说明只有服务端在把关 |

> ⚠️ **A/B 的价值**：只有"同一份数据 + 只改一个变量"的对照，才能排除"其实是服务端放行"的误判。

### Step 6 · 微创补丁 + 证据固化

**优先等长补丁**（不改 PE 布局、不改文件大小、可 diff 审计）：

```python
# 等长替换 + 空格填充（JS/C 字符串内合法）
new = b"isMemberValid(){return!0}"
assert len(new) <= len(old)
patched = new + b" " * (len(old) - len(new))
```

**证据链四件套**：
1. 静态：偏移 + 反汇编/反编译截图 + 原始字节 vs 补丁字节
2. 动态：CDP 抓取的 localStorage 内容 + 网络请求日志
3. 视觉：UI 前后截图（含负向对照）
4. 复现：可一键运行的 PoC 脚本

---

## 第二部分 · HexHub 实操手册

### 0. 前置

- 授权沙盒（快照可回滚）
- 不需要真实账号，**不需要任何凭据**
- 工作目录：`C:\Users\Administrator\Desktop\Reverse\cases\hexhub-5.1.9\`

### 1. 准备运行环境（两条路线）

#### 路线甲：直接用解包目录跑（推荐，零安装、零污染系统）

```bash
cd cases/hexhub-5.1.9
python extract.py                       # NSIS 解包 → samples/extracted/（77 文件，约 485MB）

cd samples/extracted
./HexHub.exe --remote-debugging-port=9222
#  → CEF 窗口打开，页面 http://localhost:35580/
#  → CDP 就绪： curl http://127.0.0.1:9222/json/list
```

> 数据目录会自动落在 `%APPDATA%\HexHub\`（含 `cache\Default\Local Storage\leveldb\`）。
> 想隔离到案例目录，可先启动 `hexhub-backend.exe -hexhub-home-dir-base64 <b64(路径)>`。

#### 路线乙：真实安装版

```bash
HexHub-Client-windows-amd64-installer-5.1.9.exe    # 安装到 %ProgramFiles%\HexHub
```

⚠️ **先确认后端到底跑在哪份副本**——HexHub 有热更新机制：

```
%APPDATA%\HexHub\.hexhub-cn\runtime\        ← 热更新运行时目录
   ├─ 空  → 后端直接跑安装目录 %ProgramFiles%\HexHub\hexhub-backend.exe
   └─ 非空 → 实际运行的是 runtime\<版本>\hexhub-backend.exe（补丁要打这一份！）
```

用任务管理器/Process Explorer 确认 `hexhub-backend.exe` 的**可执行路径**再动手。

### 2. 打开调试通道（三选一）

| 方式 | 操作 | 备注 |
| :--- | :--- | :--- |
| **A. CDP 启动参数** | `HexHub.exe --remote-debugging-port=9222` | 最稳，推荐 |
| **B. 厂商隐藏口令** | 快捷键触发 `basicDebug` → 输入 `MD5(localStorage["system-info"].deviceId)` | 见报告 VULN-04 |
| **C. 直接写 leveldb** | 见 §5 | 完全离线、无需调试通道 |

方式 B 的口令计算（浏览器控制台 / Node）：

```js
// 设备 ID 在 localStorage["system-info"] 里，本地可任意改 → 口令等同无门禁
const id = JSON.parse(localStorage['system-info']).deviceId;
// MD5(id) 十六进制小写即为 DevTools 口令
```

### 3. 路线 A —— DevTools 一键注入（最快）

1. 按 §2 打开 DevTools
2. **先断网**（见 §4），否则伪造 token 会被服务端 401 清空
3. 粘贴 `patches/poc_forge_session.js` 全文 → 回车
4. 页面自动重载 → 顶栏出现 **👑 Plus**

```javascript
// poc_forge_session.js 核心（自算 SHA-256，无需任何密钥）
const ENDTIME = 2524579200000;                    // 2050-01-01 = 终身版哨兵值
const SIGN = await sha256hex(`${ENDTIME}*${EMAIL}*${await sha256hex(PUBKEY)}`);
localStorage.setItem('session', JSON.stringify({
  token: 'forged', priKey: 'forged',
  member: { email: EMAIL, endTime: ENDTIME, isPlus: true, publicKey: PUBKEY, sign: SIGN }
}));
location.reload();
```

### 4. 路线 B —— 断网 + 持久化伪造（对应"阻断联网服务器比对"）

> **这是本任务的核心诉求。** 必须让服务器**网络不可达**，而不是"返回错误"。

| 服务端状态 | 客户端分支 | 结果 |
| :--- | :--- | :--- |
| HTTP 401 | axios 响应拦截器 → `logout()` | ❌ 会话清空 |
| **网络不可达** | `catch` → `state=2`「网络受限，已离线」 | ✅ **member 保留，VIP 有效** |

```powershell
# hosts 黑洞（管理员）
Add-Content C:\Windows\System32\drivers\etc\hosts @"
0.0.0.0 api.hexhub.cn
0.0.0.0 oss.hexhub.cn
"@
ipconfig /flushdns
```

然后执行 `poc_offline_vip.js`（Playwright 全自动版）：

```bash
cd cases/hexhub-5.1.9
NODE_PATH="C:\Users\Administrator\.pi\agent\npm\node_modules" node poc_offline_vip.js
```

**实测输出**（会话存活 + 判定通过）：

```
localStorage["session"] AFTER reload:
{"token":"forged-token-audit","member":{...,"endTime":2524579200000,"isPlus":true,...}}
evaluated: { "isMemberValid_js": true, "isLifetime": true }
network log: REQ https://api.hexhub.cn/client/member/currentv2   ← 被阻断
UI: 顶栏 👑 Plus（同时左侧仍显示"请检查是否登录"）
```

### 5. 路线 C —— 直接改 leveldb（无调试通道、完全离线）

localStorage 落盘位置：

```
%APPDATA%\HexHub\cache\Default\Local Storage\leveldb\
   ├─ 000003.log        ← 明文可读，能看到 session / global / system-info
   ├─ MANIFEST-000001
   └─ CURRENT
```

**操作**：关闭 HexHub → 用 leveldb 工具（或按 log 格式追加记录）写入
`key = "session"`、`value = {"token":...,"priKey":...,"member":{...}}` → 重新启动。

> 验证读取：`strings 000003.log | findstr session` 能看到明文 JSON。
> ⚠️ 写入前务必备份整个 `leveldb` 目录；写入格式错误会导致 CEF 丢弃整库。

### 6. 路线 D —— 二进制微创补丁（等长，已验证）

**适用场景**：你有一个**已过期/免费的真实账号**。此时服务端会下发真实 member 覆盖本地，
伪造 localStorage 会被冲掉 —— 直接改判定函数。

```bash
cd cases/hexhub-5.1.9
python patch_vip.py
#  [P1a isMemberValid(main)]  old_len=123 -> isMemberValid(){return!0}  (+98 空格)
#  [P1b isMemberValid(worker)]old_len=123 -> 同上
#  [P2  ue(sign-check)]       old_len=300 -> ue=le=>!0                 (+291 空格)
#  size equal: True  118715652 == 118715652   differing bytes: 499

# 部署（务必先停进程 + 备份）
taskkill /IM HexHub.exe /F & taskkill /IM hexhub-backend.exe /F
copy /Y patches\hexhub-backend.patched.exe "<实际运行路径>\hexhub-backend.exe"
```

**A/B 验证结果**（同一份"2023 已过期 + 伪造签名"的数据）：

| 二进制 | 顶栏徽章 | 截图 |
| :--- | :--- | :--- |
| 原版 | ❌ 无 | `exports/ab_A_original.png` |
| 补丁版 | ✅ 👑 Plus | `exports/ab_B_patched.png` |

### 7. 复原

```powershell
taskkill /IM HexHub.exe /F ; taskkill /IM hexhub-backend.exe /F
copy /Y patches\hexhub-backend.original.exe "<实际运行路径>\hexhub-backend.exe"
# 清 hosts / 防火墙规则
Remove-NetFirewallRule -DisplayName "Block HexHub License Server" -ErrorAction SilentlyContinue
# 清会话
Remove-Item "$env:APPDATA\HexHub\cache\Default\Local Storage\leveldb" -Recurse -Force
```

---

## 第三部分 · 踩坑清单（血泪版）

| # | 坑 | 现象 | 解法 |
| :--- | :--- | :--- | :--- |
| 1 | 只断"返回错误" | 伪造 token 立刻被清空 | 必须**网络不可达**（hosts 黑洞 / abort），不是 403/401 |
| 2 | 解包 base 差 8 字节 | 所有文件都不是 PE | 用魔数自检：`MZ` / `05 00 00 00`（pak） |
| 3 | 补丁打在错的副本上 | 改了没效果 | 先确认 `hexhub-backend.exe` **实际运行路径**（热更新 runtime 目录优先） |
| 4 | 只 patch 一处 `isMemberValid` | 主进程好了，Worker 里仍失效 | 全量正则搜 `isMemberValid\(\)\{`，本案例有 **2 处** |
| 5 | `browser.close()` 关掉被连接的应用 | CEF 进程退出 | connectOverCDP 时**不要**调 `browser.close()`，直接 `process.exit(0)` |
| 6 | 页面 dialog 打断脚本 | `No dialog is showing` | `page.on('dialog', d => d.accept().catch(()=>{}))` |
| 7 | 判定函数"看起来"是服务端 | 静态分析误判 | 必做 A/B：同一数据 + 只改网络 → 看结果是否翻转 |
| 8 | 等长补丁破坏 JS 语法 | 白屏 | 填充用**空格**（对象字面量中合法），不要用 `;` |
| 9 | 直接双击安装器 | 系统被污染、产生残留 | 先静态解包，用解包目录直跑 |
| 10 | 把厂商端点/真实 token 写进报告 | 合规红线 | 只写端点用途；真实凭据 → 停、上报、不落盘 |

---

## 第四部分 · 报告必填字段（对照本案例）

```
漏洞编号 / 名称
CWE 编号（CWE-602 客户端强行实施服务端安全机制）
严重级别（CVSS 向量可选）
位点：二进制名 + 文件偏移 + 函数名 + 原始字节
成因：为什么这是"客户端在替服务端做决定"
影响面：全量枚举所有调用点（本案例 20+ 处 VIP 门禁）
复现：环境 + 步骤 + PoC 脚本路径
证据：A/B 对照表 + 截图 + 网络日志
修复：服务端权威闭环 / 密钥签名 / 离线锚点 / 客户端加固（四条必写）
```

---

## 附：一键复现脚本

### 方式一：PowerShell 全自动（推荐）

```powershell
cd C:\Users\Administrator\Desktop\Reverse\cases\hexhub-5.1.9

# ① 全自动：解包 → 启动(开CDP) → 断网注入 → 取证截图
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_hexhub_audit.ps1

# ② 额外做二进制补丁 A/B（生成补丁 → 部署 → 重启 → 复测）
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_hexhub_audit.ps1 -ApplyPatch

# ③ 验证完毕复原环境（还原原始二进制 + 清空会话）
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_hexhub_audit.ps1 -Restore
```

**实测输出（脚本执行完毕 exit=0）**：

```
=== [3] 启动客户端并开启 CDP 调试端口 ===
  [+] CDP 就绪: Chrome/138.0.7204.97
=== [5] 断网 + 伪造会话注入 + 取证 ===
[+] blocked api.hexhub.cn / oss.hexhub.cn at network layer
[+] injected forged session
localStorage["session"] AFTER reload:
  {"token":"forged-token-audit",...,"member":{...,"endTime":2524579200000,"isPlus":true,...}}
evaluated: { "isMemberValid_js": true, "isLifetime": true }
network log: REQ https://api.hexhub.cn/client/member/currentv2   ← 被阻断
[+] screenshot -> exports/poc_offline_vip.png
```

> ⚠️ 若 PowerShell 报中文乱码或语法错误，说明 `.ps1` 缺少 **UTF-8 BOM**（Windows PowerShell 5.1 按 ANSI 解析）。
> 修复：`python -c "p='run_hexhub_audit.ps1';d=open(p,'rb').read();open(p,'wb').write(b'\xef\xbb\xbf'+d)"`

### 方式二：手动分步（便于取证与讲解）

```bash
cd cases/hexhub-5.1.9
python extract.py                                          # ① 解包
cd samples/extracted && ./HexHub.exe --remote-debugging-port=9222 &   # ② 启动
sleep 15
cd ../..
NODE_PATH="C:\Users\Administrator\.pi\agent\npm\node_modules" node poc_offline_vip.js   # ③ 断网注入+取证
```

产物：`exports/poc_offline_vip.png`（👑 Plus evidence）
