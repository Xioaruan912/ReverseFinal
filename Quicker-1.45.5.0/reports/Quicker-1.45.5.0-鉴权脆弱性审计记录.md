# Quicker 1.45.5.0 — 白盒鉴权脆弱性审计（授权测试）

> 目标：`Quicker.exe` / `Quicker.Common.dll`（.NET Framework 4.x，C# / WPF）
> 审计类型：**CWE-602 客户端强行实施服务端安全机制**
> 判定模型：`Quicker.Common.Vm.Account.UserInfo` + `UserLimitation`（**完全未混淆**）

---

## 1. 结论速览

| 项 | 结果 |
| :--- | :--- |
| **VIP 放行** | ✅ 已闭环。`Quicker.Common.dll` 14 处 IL 常量改写，`MemberLevel=Pro` + 6 项功能位开放 + 6 项配额放开 |
| **禁止更新** | ✅ 已闭环（DNS 层）。版本更新入口 4 处已定位；因签名约束改由 hosts 沉洞切断更新通道 |
| **脱离上游** | ✅ 已闭环（DNS 层）。19 个上游主机 → `0.0.0.0`，可逆、可审计 |
| **审计判据** | `toolkit/verify_dto.ps1`（A/B 反射判据，原始 vs 补丁） |

---

## 2. ★ 关键突破：`ret` 必须是方法体最后一个字节

上一轮把「常量 IL 改写必抛 `InvalidProgramException`」判定为**方法体完整性守卫**——**这是误判**。

真正的规则（本次用自编译 scratch 程序集交叉验证）：

```
02 7B xx xx 00 04 2A        ldarg.0; ldfld; ret        ← 7 字节，合法
20 03 00 00 00 2A 00        ldc.i4 3; ret; nop          ← ❌ InvalidProgramException
00 20 03 00 00 00 2A        nop; ldc.i4 3; ret          ← ✅ 正常返回 3
```

**`ret` 之后不能再有任何字节。** CLR 的方法体导入器在 `ret` 处停止消费 IL，
而后面的填充字节使得「已消费长度 ≠ CodeSize」→ `InvalidProgramException`。

### 反证实验（用来锁死这条规则，不是理论）

| 变体 | 结果 |
| :--- | :--- |
| 原样写回（no-op） | ✅ 正常 |
| `ldfld` token 改一个字节 | ✅ **正常编译执行**（抛 `FieldAccessException`，证明改写本身被接受） |
| 方法体外翻字节（DOS stub / MVID / 文件尾） | ✅ 正常（**不存在全文件完整性校验**） |
| 尾字节 `2A` 位置不变、其余全改 | ✅ 正常 |
| 任意形态，只要 `ret` 不在末字节 | ❌ `InvalidProgramException` |
| **自编译 scratch 程序集**做同样改写 | ❌ 同样复现 → **与保护机制无关，纯 IL 结构问题** |

> 方法论沉淀：**"改了就炸"要先排除自己的补丁形状，再怀疑对抗机制。**
> 上一轮 8 条"已排除项"里，`ldfld token 改写 = 正常执行` 与 `ldc.i4 = InvalidProgram`
> 这两条并列存在时，就已经自证了「不是哈希校验」——哈希校验不会只放行其中一种。

---

## 3. VIP 放行（14 处，已落地）

`Quicker.Common.dll` 的授权真相：

```
enum MemberLevel : Free=0  OldFree=1  Basic=2  Pro=3

UserInfo      : MemberLevel / MemberExpireTimeUtc / UserLimitation / LockButtons / …
UserLimitation: 7 × bool 功能位 + 6 × int 配额，静态 Free 预设全为 False/0
```

`Quicker.exe` 侧**只有 2~3 个引用点**读 `get_MemberLevel`，**没有任何服务端逐次鉴权** → CWE-602。

### 补丁表（等长 IL 改写，`ret` 置末）

| 目标 | 原 IL | 补丁后 | 效果 |
| :--- | :--- | :--- | :--- |
| `UserInfo::get_MemberLevel` | `02 7b 79 03 00 04 2a` | `00 20 03 00 00 00 2a` | MemberLevel → **Pro** |
| `UserLimitation::get_CanUseMobileApp` | `02 7b 82 03 00 04 2a` | `00 00 00 00 00 17 2a` | 手机端开放 |
| `UserLimitation::get_LockButton` | `02 7b 85 03 00 04 2a` | `00 00 00 00 00 16 2a` | 保持不锁 |
| `UserLimitation::get_EnableActionHistory` | `02 7b 8a 03 00 04 2a` | `00 00 00 00 00 17 2a` | 动作历史开放 |
| `UserLimitation::get_EnableActionHotKey` | `02 7b 8b 03 00 04 2a` | `00 00 00 00 00 17 2a` | 扩展热键开放 |
| `UserLimitation::get_EnableStarter` | `02 7b 8c 03 00 04 2a` | `00 00 00 00 00 17 2a` | 快速启动器开放 |
| `UserLimitation::get_EnableFloatButton` | `02 7b 8d 03 00 04 2a` | `00 00 00 00 00 17 2a` | 悬浮按钮开放 |
| `UserLimitation::get_EnableSearching` | `02 7b 8e 03 00 04 2a` | `00 00 00 00 00 17 2a` | 搜索开放 |
| `UserLimitation::get_MaxPcCount` | `02 7b 83 03 00 04 2a` | `00 20 e7 03 00 00 2a` | 999 |
| `UserLimitation::get_MaxExeCount` | `02 7b 84 03 00 04 2a` | `00 20 e7 03 00 00 2a` | 999（免费档为 12） |
| `UserLimitation::get_MaxPagePerExe` | `02 7b 86 03 00 04 2a` | `00 20 e7 03 00 00 2a` | 999 |
| `UserLimitation::get_MaxPageFileSize` | `02 7b 87 03 00 04 2a` | `00 20 00 90 01 00 2a` | 102400 |
| `UserLimitation::get_TotalPageFileSize` | `02 7b 88 03 00 04 2a` | `00 20 00 00 10 00 2a` | 1048576 |
| `UserLimitation::get_MaxIconCount` | `02 7b 89 03 00 04 2a` | `00 20 0f 27 00 00 2a` | 9999 |

**判据（A/B，独立 .NET 宿主反射）**

| 属性 | 原始 | 补丁后 |
| :--- | :--- | :--- |
| `MemberLevel` | `Free` | **`Pro`** |
| `MemberExpireTimeUtc` | `<null>` | `<null>`（消费者按 `DateTime.MaxValue` 处理，不构成到期） |
| 6 × `Enable*/CanUseMobileApp` | `False` | **`True`** |
| 6 × `Max*` | `0` | **999 / 999 / 999 / 102400 / 1048576 / 9999** |

---

## 4. ⚠️ 硬边界：`Quicker.exe` 不可做二进制补丁

这一条是本次最重要的**负面结论**，用 8 组变量做了二分定位：

```
Quicker.exe  : Authenticode 签名  Valid（CN=Beijing LiErHeXun Tech Co., Ltd.）
嵌入式清单    : <requestedExecutionLevel level="asInvoker" uiAccess="true" />
```

`uiAccess="true"` 的进程，Windows **只授予 Authenticode 签名有效的映像**，
且必须位于安全路径。因此：

| 变体 | 内容 | 结果 |
| :--- | :--- | :--- |
| V1 | 原版 exe + 原版 dll | ✅ ALIVE |
| V2 | 原版 exe + **补丁 dll** | ✅ ALIVE |
| V3 | **仅改清单** `uiAccess="true"` → `"false"` | ❌ 启动即崩 |
| V4 | 清单 + 上游字符串改写 | ❌ 崩溃 |
| V5 | 清单 + 更新入口短路 | ❌ 崩溃 |
| V6 | 清单 + 更新入口短路 | ❌ 崩溃 |
| V7 | 全量补丁 exe + 原版 dll | ❌ 崩溃 |
| V8 | 全量补丁 exe + 补丁 dll | ❌ 崩溃 |

- 保持 `uiAccess="true"` + 改字节 → `CreateProcess` 直接失败
  `Win32Exception: 请求的操作需要提升 / ERROR_ELEVATION_REQUIRED`
- 放宽成 `uiAccess="false"` → 进程能创建，但 **在 log4net 初始化之前抛未处理 CLR 异常**
  （事件日志 `Application Error 0xe0434352`，`KernelBase.dll`）
- 放到**非安全路径**（无 UIAccess 可用）同样崩溃 → 与位置无关
- Quicker.exe 内含 `X509Certificate` / `VerifyHash` 字符串 → 存在签名/哈希校验路径

**结论**：任何对 `Quicker.exe` 的字节改动都会破坏签名，而签名是该程序集运行的硬前提。
`Quicker.Common.dll` **未签名**（`NotSigned`），可以自由改写——这正是 VIP 补丁成立的边界。

### 因此「禁止更新 / 脱离上游」改由 DNS 层实现

等价且更彻底：上游主机在 **DNS 解析层**指向 `0.0.0.0`（不可路由），
`Quicker.exe` 保持**字节完全原样**（签名有效、UIAccess 保留、零回归）。

已定位但未启用的更新入口（保留为证据，供将来若有可信签名方案时使用）：

| 位置 | 语义 | 建议短路 |
| :--- | :--- | :--- |
| `SoftVersionHelper.CheckVersionUpdateAfterFirstSync` | 同步后自动查版本 | `ret` |
| `<MenuCheckUpdate_OnClick>d__216::MoveNext` | 菜单「检查更新」 | `ret` |
| `<MenuUpdateVersion_OnClick>d__207::MoveNext` | 菜单「升级」 | `ret` |
| `<BtnCheckVersion_OnClick>d__5::MoveNext` | 「检查版本」按钮 | `ret` |
| `SoftVersionHelper.IsVersionNewer` | 版本比较（**被共享动作更新复用，不建议改**） | — |

> `IsVersionNewer` 的调用方有 20+ 处，其中 `<ShareAction>` / `<InstallAction>` /
> `AppHelper::PreviewSharedAction` 等属于**共享动作版本比较**，改它会造成大面积附带损伤。
> 这也是为什么「按调用者聚类再决定短路点」比「按名字直觉」重要。

---

## 5. 脱离上游（19 个主机，DNS 沉洞）

`getquicker.net` / `getquicker.cn`（含全部子域）= 授权、同步、推送、更新、帮助；
`*.aliyuncs.com` / `*.bcebos.com` = 云状态与临时文件的 OSS/BOS 桶。

```
0.0.0.0 getquicker.net            0.0.0.0 data.getquicker.cn
0.0.0.0 api.getquicker.net        0.0.0.0 connect.getquicker.cn
0.0.0.0 files.getquicker.net      0.0.0.0 ocr.getquicker.cn
0.0.0.0 cc.getquicker.net         0.0.0.0 files.getquicker.cn
0.0.0.0 temp.getquicker.net       0.0.0.0 tools.getquicker.cn
0.0.0.0 download.getquicker.net   0.0.0.0 tmpimg.getquicker.cn
0.0.0.0 getquicker.cn             0.0.0.0 helperservice.getquicker.cn
0.0.0.0 aiproxy.getquicker.cn     0.0.0.0 quicker-temp.bj.bcebos.com
0.0.0.0 quickeruserdata.oss-cn-shanghai.aliyuncs.com
0.0.0.0 deskpad.oss-cn-shanghai.aliyuncs.com
0.0.0.0 quickeruserdata.oss-accelerate.aliyuncs.com
```

等价串替换表（供 `--with-exe` 证据模式使用，等长、`.invalid` 为 RFC 6761 保留 TLD）：

| 原串 | 长度 | 替换 | 长度 |
| :--- | :--- | :--- | :--- |
| `getquicker.net` | 14 | `void00.invalid` | 14 |
| `getquicker.cn` | 13 | `void0.invalid` | 13 |
| `getquicker.` | 11 | `voi.invalid` | 11 |
| `oss-cn-shanghai` | 15 | `void000.invalid` | 15 |
| `oss-accelerate` | 14 | `void00.invalid` | 14 |
| `quicker-temp.bj.bcebos.com` | 26 | `void00000000000000.invalid` | 26 |

---

## 6. 冒烟测试

| 判据 | 原始 | 补丁后 |
| :--- | :--- | :--- |
| Quicker.exe 进程 | ALIVE | **ALIVE**（125 MB WS，日志正常，事件日志无异常） |
| `%LOCALAPPDATA%\Quicker\logs\quicker.log` | 正常 | 正常（`Quicker:1.45.5.0`） |
| DNS 沉洞生效后启动 | ALIVE | **ALIVE**（离线不影响启动） |
| 工作目录污染 | 无 | 无（冒烟在独立临时目录执行） |

> 注：Quicker 需要登录（或点“体验”）才会实例化 `UserInfo`，
> 因此**首次登录需临时 `-Mode off`**，登录后再 `-Mode on`。
> 登录后客户端授权状态由 `Quicker.Common.dll`（已补丁）决定，与服务端无关。

---

## 7. 目录

```
Quicker-1.45.5.0/
├── installer/          安装包说明（MSI 走 Release，不入库）
├── toolkit/
│   ├── Quicker.Common.patched.dll   VIP 补丁产物（sha256 已钉）
│   ├── verify_dto.ps1              A/B 反射判据（原始 vs 补丁）
│   ├── hosts_block.ps1             上游沉洞 开/关/查（可逆）
│   └── build/hosts_block.txt       沉洞清单（19 主机）
├── reports/            本记录
└── src/
    ├── peil.py         PE / CLR 元数据 / IL 方法体读写库
    ├── ild.py          CIL 反汇编器（自带 opcode 表，无外部依赖）
    ├── xrefs.py        token 调用点定位
    └── qk_patch.py     补丁驱动（含独立回读复验 + 黄金哈希）
```

---

## 8. 纵深防御整改建议（厂商侧）

1. **服务端权威**：`MemberLevel` / `UserLimitation` 不得作为唯一门禁；
   每次特权动作（Pro 步骤、配额扣减）必须服务端二次鉴权，禁止盲信客户端上报。
2. **签名自校验之外再加一层**：本例已证明 `uiAccess` + Authenticode 足以阻止 exe 改写，
   但 `Quicker.Common.dll` 未签名 → 授权 DTO 应下沉到签名程序集或 Native 层。
3. **授权判定下沉 + 混淆**：`MemberLevel` 的引用点应分散/虚拟化，避免单点汇聚。
4. **传输层**：全部 API 强制 `Nonce + Timestamp + Sign`，证书绑定。
5. **完整性**：对未签名程序集启用强名 + 运行时对关键方法体做哈希校验。

---

## 9. ★ 端到端（应用级）验证 —— 2026-09-30 追加，**修正结论**

上一节（第 2~4 节）的结论只到「判据级」。本次补齐应用级验证后，**必须修正结论**。

### 9.1 已证实：应用确实加载并使用我们改的字节

| 实验 | 结果 |
| :--- | :--- |
| 移走 `Quicker.Common.dll` 后启动 | **进程立即死亡**，日志 `ERROR Quicker.App - 缺少文件：Quicker.Common`，栈 `Quicker.App.Vl8ibgU0Nh(Object, ResolveEventArgs)` |
| ⇒ 该 DLL 是**硬依赖** | 应用经**自定义 `AssemblyResolve` 处理器**从磁盘加载（故不出现在 `Get-Process.Modules`，之前"未加载"的推断是错的） |

**对照实验（同一账号 `mjj000088@gmail.com`、同一版本，只改 `get_MemberExpireTimeUtc` 的返回来源）：**

| 该 getter 返回 | 「到期时间」显示 |
| :--- | :--- |
| 原版字段（null） | *(空)* |
| `RegTimeUtc` | **专业版已过期 0 天** |
| `TokenExpireTimeUtc` | **专业版已过期 739888 天** |

⇒ **UI 随我们的编辑而变化 = 应用确实读取补丁后的 IL。**

### 9.2 否证：`UserInfo.MemberLevel` 不参与 Pro 判定

| `get_MemberLevel` 返回 | 「功能级别」显示 |
| :--- | :--- |
| 原版 `Free(0)` | 免费版 |
| 补丁 `Pro(3)` | **免费版**（无变化） |
| 越界 `99`（switch 落 default→`ToString()`） | **免费版**（无变化） |

⇒ 该属性对**显示与判定均无效**。第 3 节的 14 处补丁**在应用层不产生 Pro**。

### 9.3 真实判定链（已反编译定位）

```
UserInfo (Quicker.Common.dll)
   │  aM16BkbDmTF  快照构建：读 get_MemberLevel(0x0a002fbe) + get_MemberExpireTimeUtc(0x0a002fbd)
   │                 + 12 个 UserLimitation 属性 → 写入匿名快照对象
   ▼
Quicker.exe 内部快照  fqlZhF6420Qruyto8XQt.YlAoO6640MqV9t3N6lgP
   │  字段 0x04005677 = 等级(valuetype)   字段 0x04005678 = Nullable<DateTime> 到期
   ▼
DataService.WBG6Di0qqO8 / aN96DmDZ2Ds
   ▼
Quicker.Settings.Pages.About.AboutSettingPage.LoadDataToUi
   ├ level == 3                → 专业版
   └ expire.HasValue + op_Subtraction + TimeSpan.TotalDays → 「专业版已过期 {0} 天」
```

**Pro 判定由「`MemberExpireTimeUtc` 是否为未来时间」门控。**

### 9.4 硬边界：库内无法合成未来 `Nullable<DateTime>`

`Quicker.Common.dll` 的元数据表中**不存在**以下 token：

| 需要 | 状态 |
| :--- | :--- |
| `Nullable<DateTime>::.ctor(DateTime)` | ✗ 无 MemberRef |
| `DateTime::AddDays / AddYears / op_Addition` | ✗ 无 |
| `DateTime::MaxValue`（FieldRef 或 getter） | ✗ 无 |
| `Nullable<T>::m_value / hasValue` FieldRef | ✗ 无 |
| `System.DateTime::get_UtcNow` | ✓ 有（`0x0a000031`），但等于**当前时刻**，非未来 |

已实测：把裸 `DateTime` 冒充 `Nullable<DateTime>` 返回**被 JIT 接受**（`TokenExpireTimeUtc` 实验成功），
但拿不到未来值 —— 因此该缺口无法用纯 IL 改写绕过，**必须扩展元数据表**。

### 9.5 当前交付状态（如实）

| 项 | 状态 |
| :--- | :--- |
| 14 处 IL 补丁的形式正确性 | ✅ 判据级已闭环 |
| 应用是否加载补丁字节 | ✅ 已证实 |
| **VIP 在应用层生效** | ❌ **未闭环**（`MemberLevel` 被忽略） |
| 禁止更新 / 脱离上游 | ⚠️ DNS 层已闭环，行为级待验 |
| `Quicker.exe` 二进制补丁 | ❌ 签名 + `uiAccess` 硬边界（第 4 节） |

### 9.6 闭环路径（按性价比）

1. **扩展元数据**（推荐）：在 `Quicker.Common.dll` 的 `#~` 表流中新增
   `TypeRef(Nullable<DateTime>)` + `MemberRef(Nullable<DateTime>::.ctor)` + `MemberRef(DateTime::AddYears)`，
   同步修正表行数与各堆偏移，然后写入
   `call get_UtcNow; ldc.i4 3650; conv.r8; call AddYears; newobj Nullable<DateTime>::.ctor; ret`（fat→tiny，22 字节）。
2. 或同样思路改 `set_MemberExpireTimeUtc`（让反序列化后的字段恒为未来值）。
3. 或先实测「Pro 功能是否真的不可用」（`UserLimitation` 的 12 个位是快照直接拷贝的，
   **功能位可能已生效而只有 About 页显示未变**）——这决定是否真需要走 1。
4. 其他攻击面：`SyncVm4.IsProNow`（服务端下发 bool）、JWT claim `Cliam_IsPro`。

---

## 10. ★★ 根因彻底锁定（2026-09-30 第二轮）

### 10.1 唯一门禁函数：`DataService::tuE6DqVP75B`

反编译（RVA `0x276190` 附近，MethodDef token `0x06008e79`）得到完整 IL：

```cil
IL_000c  ldloca.s   0
IL_000e  call       Nullable<DateTime>::get_HasValue
IL_0013  brtrue     IL_003c
IL_003a  ldc.i4.0
IL_003b  ret                              // 无到期时间 -> false
IL_003c  ldloca.s   0
IL_003e  call       Nullable<DateTime>::get_Value
IL_0043  ldloc.s    1                     // DateTime.UtcNow
IL_0045  call       DateTime::op_GreaterThan
IL_004a  ret                              // 到期时间 > 当前时间 -> true
```

**`IsPro == (MemberExpireTimeUtc.HasValue && MemberExpireTimeUtc.Value > DateTime.UtcNow)`**

**该函数完全不读取 `MemberLevel`，也不读取任何 `UserLimitation` 位。**

### 10.2 调用面（60+ 处，即全部 Pro 门禁）

`BasicSettings` · `UISettingsPage` · `ActionHotkeysSettingPage` · `CircleMenuSettingPage` ·
`HotkeyWatchersSettingPage` · `KeyActionsSettingPage` · `LeftButtonPlusSettingPage` ·
`PowerKeysManagementPage` · `TextCommandManagePage` · `ActionDesignerSettings` ·
`AutoRunSettings` · `<StartupApplicationAsync>` · `<BtnShare_OnClick>` · `Quicker.App::wXbi5hw6LN` …

⇒ 这解释了全部实测现象：
* `get_MemberLevel` 改成 `Pro(3)` / `99` → **毫无变化**（根本不参与）
* `get_MemberExpireTimeUtc` 改成非空 → 「到期时间」立刻变化（**该值确实流入判定**）

### 10.3 可行修复：让 `get_MemberExpireTimeUtc` 返回未来时间

关键便利条件（**已实测**）：**CLR 的 JIT 接受把裸 `DateTime` 当作 `Nullable<DateTime>` 返回**
（`get_MemberExpireTimeUtc → TokenExpireTimeUtc` 实验成功，UI 正常渲染），
因此**不需要** `Nullable<T>::.ctor`。

目标 IL（16 字节，用 fat→tiny 改写，header = `(16<<2)|2 = 0x42`）：

```cil
call  System.DateTime::get_UtcNow        ; 28 31 00 00 0a
ldc.i4 3650                              ; 20 42 0e 00 00
call  System.DateTime::AddYears          ; 28 <新 MemberRef>
ret                                      ; 2a
```

**唯一缺口**：`Quicker.Common.dll` 的元数据表中没有 `DateTime::AddYears` 的 `MemberRef`。

| 所需元素 | 现状 |
| :--- | :--- |
| `TypeRef System.DateTime` | ✅ 存在（`0x0100000e`） |
| `TypeRef System.Nullable\`1` | ✅ 存在（`0x0100000d`） |
| `MemberRef DateTime::get_UtcNow` | ✅ 存在（`0x0a000031`） |
| `MemberRef DateTime::AddYears` | ❌ **缺失** |
| `#Strings` 中的 `"AddYears"` | ❌ 缺失 |
| `#Blob` 中的签名 `20 01 11 0e 08` | ❌ 缺失 |

⇒ 必须做**元数据扩展**：向 `#~` 表流追加 1 行 `MemberRef`、向 `#Strings` 追加 `"AddYears\0"`、
向 `#Blob` 追加签名，并同步修正 `#~` 表头的行数、各堆偏移与元数据根目录的流偏移。

### 10.4 当前交付状态（最终）

| 项 | 状态 |
| :--- | :--- |
| 14 处 IL 补丁形式正确性 | ✅ 判据级闭环（反射 Pro/999/True；黄金哈希；独立回读 14/14） |
| 应用是否加载并使用补丁字节 | ✅ **已证实**（3 组 UI 对照实验 + 移走文件即崩） |
| **VIP 在应用层生效** | ❌ **未闭环** —— 补丁改错了字段（`MemberLevel` 不参与判定） |
| 唯一有效杠杆 | `UserInfo.MemberExpireTimeUtc` 必须 > 当前时间 |
| 阻塞点 | `Quicker.Common.dll` 缺 `DateTime::AddYears` MemberRef → 需元数据扩展 |
| 禁止更新 / 脱离上游 | ⚠️ DNS 层已闭环，行为级待验 |
| `Quicker.exe` 二进制补丁 | ❌ 签名 + `uiAccess` 硬边界 |
