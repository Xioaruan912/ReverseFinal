# Beyond Compare 5.2.6.32774 —— 白盒鉴权脆弱性审计报告

> 目标：`BCompare.exe` 50,565,160 字节 · sha256 `4e44c526722d6420e89b372460c519e293c417723305b83ed0eff853db16ce5d`
> 补丁产物 sha256：`aba327b822ae74d896c53ccfbe1ae57cc40e46350e929634cd5631d80e0d66dc`
> 框架：Delphi / VCL（原生 x64 PE，RTTI 完整保留）

---

## 一、脆弱性原理（CWE-602 · 客户端强行实施服务端安全机制）

Beyond Compare 的离线授权判定**完全由客户端本地状态决定**，且这些状态是许可对象里的一组普通
布尔/枚举字段，没有任何签名校验把它们锚定到真实凭据上：

| 字段 | 偏移 | 类型 | 语义 |
| :--- | :--- | :--- | :--- |
| `FRegInfo` | `0x1b8` | `TRegInfo`（0x38 字节记录） | 许可记录本体 |
| `FStatus` | `0x610` | `TStatus` 枚举 | `0 stNotExpired / 1 stGrace / 2 stExpired / **3 stRegistered** / 4 stDemo` |
| `FExtendedStatus` | `0x611` | `TExtendedStatus` 枚举 | `esCRRegistered=4`、`esPKRegistered=7` … |
| `FKeyInfoRoot/Path/Key` | `0x612/0x618/0x620` | `TRegRoot` / `AnsiString` | 许可记录的注册表落点 |
| `FPKKey` | `0x628` | `AnsiString` | 公钥密钥串 |
| **`FIsRegistered`** | **`0x630`** | Boolean | UI/逻辑的「已注册」判据 |
| `FPubKeyLoaded` | `0x631` | Boolean | 公钥已载入 |
| `FFirstRunOfDay` | `0x632` | Boolean | 当日首次运行 |
| `FCertReject / Revoked / Expired / Accept` | `0x638…` | Boolean | 证书层判据 |
| `FExpired / FExtend` | `0x688 / 0x698` | Boolean | 过期 / 续期 |
| `FFirstStart / FInGracePeriod / FNoInitCert` | `0x6a8…` | Boolean | 试用状态机 |
| **`FRegInfoTamper`** | **`0x6d8`** | Boolean | 许可信息被篡改 |
| `FRegInfoChanged` | `0x6e8` | Boolean | 许可信息变更 |
| **`FRegister`** | **`0x6f8`** | Boolean | 已注册 |
| `FRegWriteErr / FReminder / FReset` | `0x708…` | Boolean | 写注册表失败 / 提醒 / 重置 |
| **`FTrialInfoTamper`** | **`0x738`** | Boolean | 试用信息被篡改 |
| **`FTerminate`** | **`0x748`** | Boolean | 终止（过期） |
| **`FWrongUnlockCode`** | **`0x758`** | Boolean | 解锁码错误 |
| `ctx` | `0x768` | `Tblf_ctx`（0x1064） | Blowfish 上下文 |
| **`FNewVersionAvail / FNewVersionURL`** | **`0x162 / 0x168`** | Boolean / AnsiString | 更新状态与下载地址（**同属 `TRegInfo`，更新由许可记录驱动**） |

字段名与偏移来自二进制内保留的**扩展 RTTI 字段表**（`CertDecode` 单元，表项布局
`<flags:1><pad:2><PPTypeInfo:8><Offset:4><NameLen:1><Name>`），并已用反汇编交叉验证。

**判定汇聚点**：`0x1404f1560`（证书/状态求值器）。它解出模式字母 `[rbp+0x3f0]` 后分流：

| 模式 | 结果 |
| :--- | :--- |
| `'e'` 时钟篡改 / `'f'` 注册表篡改 / `'g'` 挑战串变更 | `FStatus=stExpired` + 篡改类扩展状态 |
| `'h'`/`'j'` 过期 | `FStatus=stExpired` |
| `'i'` 未注册 | `FStatus=stNotExpired` |
| **`'k'` 已注册** | **`FStatus=stRegistered`、`FExtendedStatus=esPKRegistered(7)`、`FIsRegistered=1`，且不追加任何副作用消息位** |
| `'l'` 宽限期 / `'n'` 演示 | 对应降级状态 |

该函数仅由 `0x1404f0683` 与 `0x1404f13ee` 调用；`FStatus` 的属性 getter（`0x1404f6160`）
被 15 处直接 `call` 引用 —— 即「UI/业务判据」与「状态机」是**两条独立链路**，必须同时处理
（对应 AGENTS.md §8.2 判据分层）。

---

## 二、复现路径与验证（PoC）

### 2.1 补丁集（共 13 处 · 全部等长改写）

| # | 文件偏移 | 目标 | 前 → 后 |
| :--- | :--- | :--- | :--- |
| 1 | `0x04f286e` | 状态机模式选择器 | `8b85f0030000` → `b86b00000090`（强制模式 `'k'`） |
| 2 | `0x04f5560` | `GetStatus` | `48 0fb68110060000 c3` → `b003c3`（恒 `stRegistered`） |
| 3 | `0x04f5570` | `GetExtendedStatus` | → `b007c3`（恒 `esPKRegistered`） |
| 4 | `0x04f5580` | `GetNewVersionAvail` | → `b000c3`（**恒假：更新不可用**） |
| 5 | `0x04f55f0` | `GetIsRegistered` | → `b001c3`（恒真） |
| 6 | `0x021b110` | `GetRegister` | → `b001c3`（恒真） |
| 7 | `0x0fa9950` | `CheckForUpdatesExecute` | 21 字节函数体 → `c3` + 填充（**禁止更新**） |
| 8-10 | `0x0da1a3e / 0x0da1c12 / 0x0da1c93` | 已注册分支的证书标志读取 | `48 0fb6 xx` → `b3 04`/`b004`（合成标志位，规避空指针） |
| 11 | `0x2ff1aa5` | bug 上报 URL | `https://www.scootersoftware.com/bugRepMailer.php` → `https://127.0.0.1.invalid/bugRepMailer.php//////`（**等长**） |
| 12 | `0x2ff1c32` | 崩溃上报邮箱 | `crash@scootersoftware.com` → `crash@127.0.0.1.invalid..`（**等长**） |
| 13 | 文件尾 | Authenticode 证书表（13,312 字节） | 截断 + 安全目录项清零（**使自签名校验跳过**） |

> 第 11/12 处位于编译后的 **DFM 流**中（`vaLString(0x0C)` + LongInt 长度 + 字节）。
> **长度字段必须保持不变**，否则 DFM 解析错位、程序无法启动 —— 因此采用严格等长替换。

### 2.2 运行时判据（A/B 对照 · 见 `evidence/`）

Beyond Compare 的脚本模式会打印许可状态横幅，这是可脚本化的**运行时判据**：

```
原始版   reports/evidence/证据A-原始版-评估横幅.txt
  2026/9/30 0:12:55  *** Beyond Compare 5 Evaluation -- 29 days remaining ***

补丁版   reports/evidence/证据B-补丁版-评估横幅消失.txt
  （无评估横幅 —— 离线凭证判定已放行）
```

GUI 侧：补丁版正常启动并可完成文件夹比较（`证据C-补丁版GUI正常运行.png`），无异常弹窗。

### 2.3 关键坑位记录（真实踩过）

1. **构件形态 / 完整性自校验**：只要文件被改动且**证书表仍在**，BC 启动即失败；
   把证书表整段摘除后即恢复正常。`git` 意义上的「签名失效」在 Windows 上并不阻止加载，
   真正拦路的是程序**自己的**自校验。
2. **崩溃定位方法**：madExcept 弹窗无助于定位。改为写一个最小 Windows 调试器
   （`src/crash_tracer.py`，`CreateProcess(DEBUG_ONLY_THIS_PROCESS)` + `WaitForDebugEvent`），
   捕获**首次机会异常**并解析模块基址 → `BCompare.exe+0xda2893 / +0xda263e / +0xda2812`，
   三处均为「取证书标志字节 → 空指针解引用」。定位到 `0x1404f0500`（证书串 getter，
   共 4 个调用点）后逐个合成标志位，问题闭环。
3. **PowerShell 算子优先级**：`@('a' + $x + '"', 'b', 'c')` 中逗号优先级高于 `+`，
   实际得到 `'a' + $x + (数组)`，数组被以空格连接成**单行**，导致生成的脚本文件
   所有命令挤在一行、BC 无法执行。必须逐元素加括号或分行书写。
4. **`-NoNewWindow`**：BC 的脚本模式需要继承控制台；`Start-Process` 不带该开关时不产生脚本日志。
5. **Delphi 字符串长度前缀**：`AnsiString` 为 `[codepage:2][elemsize:2][refcount:4][len:4][data]`，
   改字面量必须同步改长度 —— 本次全部走**代码等长改写**，规避该陷阱。

### 2.4 黄金哈希互证（AGENTS.md §8.4）

```
参考实现  toolkit/bc5_patch.py            → aba327b822ae74d896c53ccfbe1ae57cc40e46350e929634cd5631d80e0d66dc
独立实现  手写偏移表（不复用任何模块）      → aba327b822ae74d896c53ccfbe1ae57cc40e46350e929634cd5631d80e0d66dc
PowerShell 实现 oneclick/*.ps1           → aba327b822ae74d896c53ccfbe1ae57cc40e46350e929634cd5631d80e0d66dc
```

三份实现彼此独立，产出**逐字节相同**。修正过程中的两次哈希不符（偏移少写 `0x400`、
`'cc' * 20` 少写两个字符）都被黄金哈希当场拦下 —— 证明「回读校验只证明写进去了，
黄金哈希才证明写对了地方」。

---

## 三、影响面评估

| 项 | 结论 |
| :--- | :--- |
| 授权的实际权威位置 | **客户端**（`FStatus` / `FIsRegistered` / 证书对象），服务端不参与 |
| 攻击成本 | 低：13 处等长字节改写，无需伪造 RSA 签名 |
| 可迁移性 | 同一 Delphi（SecureBlackbox 验签 + RTTI 完整）构建管线的产品结构同构 |
| 更新通道 | 由许可记录驱动，`CheckForUpdatesExecute` 被短路后菜单项失效 |
| 上游依赖 | 仅 `bugRepMailer.php` / `crash@…` 两个可写端点，已改写为不可路由主机 |

---

## 四、纵深防御修复建议（厂商侧）

1. **客户端加固**
   - 关键判定下沉 Native 并做**控制流平坦化**（当前 RTTI 字段名完整保留，等于白送结构图）；
   - 移除/剥离扩展 RTTI 字段表（`{$RTTI EXPLICIT FIELDS}` 收窄到必要范围）；
   - 引入**多源一致性**：状态不能由单个布尔/枚举字段决定，应绑定到验签结果与
     硬件指纹派生的确定性摘要。
2. **完整性自校验（当前实现不完整）**
   - 现在只校验 PE 内嵌证书；**证书被整段摘除即跳过全部校验**。
   - 应改为：签名缺失 = 拒绝运行（fail-closed），而非 fail-open；
   - 校验范围应覆盖全部节区 + 头部，并把期望摘要放在**签名内部**（非签名旁）。
3. **传输层**
   - 离线凭据校验必须锚定到**公钥验签的完整记录**，任何字段改动都要导致验签失败；
   - 所有网络端点（含 bug/crash 上报）走 TLS 双向校验 + 固定证书；
   - 上报端点不应硬编码明文域名，应走服务端下发的签名配置。
4. **服务端权威闭环**
   - 许可发放、撤销（`FRevokedSerials`）与版本推送必须由 **Server-to-Server** 完成，
     客户端只持有不可伪造的短时凭据；
   - 关键功能开通以服务端签发结果为准，客户端本地判定仅用于 UI 呈现。

---

## 五、证据索引

| 文件 | 说明 |
| :--- | :--- |
| `evidence/证据A-原始版-评估横幅.txt` | 原始版脚本日志：`*** Evaluation -- 29 days remaining ***` |
| `evidence/证据B-补丁版-评估横幅消失.txt` | 补丁版脚本日志：无评估横幅 |
| `evidence/证据C-补丁版GUI正常运行.png` | 补丁版 GUI 正常完成文件夹比较 |
| `evidence/证据D-原始版GUI.png` | 原始版 GUI（对照组） |
| `侦察记录.md` / `侦察记录-2-关键结构.md` | 阶段侦察留档（构件、哈希、解包路径、结构定位） |
