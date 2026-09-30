# PINNED-VERSIONS — Quicker 1.45.5.0

所有哈希为 **小写 sha256**。安装器与补丁器在写入前逐项校验，不匹配即中止。

---

## 1. 上游构件

| 文件 | 大小 | sha256 |
| :--- | ---: | :--- |
| `Quicker.x64.1.45.5.0.msi` | 24,371,200 | `97418d96c00e25c8811b3c5fe3d7df6bb07a9b7be0849a6a1e41d9a1b8896a95` |

- 直链：`https://getquicker.net/download/DownloadVersion?version=1.45.5.0&isX64=true`
- 实际：`https://download.getquicker.net/_productfiles/202604/Quicker.x64.1.45.5.0.msi`
- 打包器：WiX Toolset 3.14（标准 MSI）
- 安装目录属性：**`INSTALLFOLDER`**（不是 `INSTALLDIR` —— 该 MSI 未定义 `INSTALLDIR`）
- 静默安装：`msiexec /i "<msi>" /qn /norestart INSTALLFOLDER="<dir>"`
- Release 固定件：`whitebox-audit-v1.0` → `Quicker.x64.1.45.5.0.msi`

## 2. 出厂（未修改）二进制

| 文件 | 大小 | sha256 |
| :--- | ---: | :--- |
| `Quicker.exe` | 10,641,976 | `ac815c9280dee1ff2e476da5f6035a0451d07d3c0c4e12a02f0861f19fd4d8bd` |
| `Quicker.Common.dll` | 207,872 | `838e949d15b376c087b2bf0d00bf14f3c6c1b0e122a06ffea4213c800f71a594` |

- `Quicker.exe`：Authenticode **Valid**（`CN=Beijing LiErHeXun Tech Co., Ltd.`）
  嵌入式清单 `<requestedExecutionLevel level="asInvoker" uiAccess="true" />`
  → **不可做二进制补丁**（见 `reports/`）
- `Quicker.Common.dll`：**NotSigned**、未混淆 → 可自由改写

## 3. 补丁产物（黄金哈希）

| 文件 | 大小 | sha256 |
| :--- | ---: | :--- |
| `Quicker.Common.patched.dll` | 207,872 | `3924e21d208fb2a90c0c241a2806365979fe1838a9ea297e3f874fd6c45c421c` |

Release 固定件：`whitebox-audit-v1.0` → `Quicker.Common.patched.dll`

> 该哈希由 `src/qk_patch.py` 生成，并由 **独立回读复验**（重新解析原始程序集、按语义重建
> 期望字节、再从产物文件中读回比对，14/14 站点）交叉确认，非单点自证。

## 4. 补丁站点（14 处，等长 IL 改写，`ret` 置于末字节）

| 文件偏移 | 原 IL | 补丁后 | 目标 |
| :--- | :--- | :--- | :--- |
| `0x004563` | `027b790300042a` | `0020030000002a` | `UserInfo::get_MemberLevel` → Pro |
| `0x00461a` | `027b820300042a` | `0000000000172a` | `UserLimitation::get_CanUseMobileApp` |
| `0x00464d` | `027b850300042a` | `0000000000162a` | `UserLimitation::get_LockButton` |
| `0x0046a2` | `027b8a0300042a` | `0000000000172a` | `UserLimitation::get_EnableActionHistory` |
| `0x0046b3` | `027b8b0300042a` | `0000000000172a` | `UserLimitation::get_EnableActionHotKey` |
| `0x0046c4` | `027b8c0300042a` | `0000000000172a` | `UserLimitation::get_EnableStarter` |
| `0x0046d5` | `027b8d0300042a` | `0000000000172a` | `UserLimitation::get_EnableFloatButton` |
| `0x0046e6` | `027b8e0300042a` | `0000000000172a` | `UserLimitation::get_EnableSearching` |
| `0x00462b` | `027b830300042a` | `0020e70300002a` | `UserLimitation::get_MaxPcCount` → 999 |
| `0x00463c` | `027b840300042a` | `0020e70300002a` | `UserLimitation::get_MaxExeCount` → 999 |
| `0x00465e` | `027b860300042a` | `0020e70300002a` | `UserLimitation::get_MaxPagePerExe` → 999 |
| `0x00466f` | `027b870300042a` | `0020009001002a` | `UserLimitation::get_MaxPageFileSize` → 102400 |
| `0x004680` | `027b880300042a` | `0020000010002a` | `UserLimitation::get_TotalPageFileSize` → 1048576 |
| `0x004691` | `027b890300042a` | `00200f2700002a` | `UserLimitation::get_MaxIconCount` → 9999 |

补丁器还额外把 `Quicker.Common.dll` 内的 `getquicker.net`（UTF-16 字面量，1 处）
等长改写为 `void00.invalid`，使该程序集内不再残留可解析的上游主机名。

## 5. 未修改

| 文件 | 说明 |
| :--- | :--- |
| `Quicker.exe` | **字节完全原样**（签名与 `uiAccess` 均需保持有效） |
| 其余 96 个伴生文件 | 不做任何改动 |

## 6. 上游沉洞清单（19 个主机 → `0.0.0.0`）

```
getquicker.net                      data.getquicker.cn
api.getquicker.net                  connect.getquicker.cn
files.getquicker.net                ocr.getquicker.cn
cc.getquicker.net                   files.getquicker.cn
temp.getquicker.net                 tools.getquicker.cn
download.getquicker.net             tmpimg.getquicker.cn
getquicker.cn                       helperservice.getquicker.cn
aiproxy.getquicker.cn               quicker-temp.bj.bcebos.com
quickeruserdata.oss-cn-shanghai.aliyuncs.com
deskpad.oss-cn-shanghai.aliyuncs.com
quickeruserdata.oss-accelerate.aliyuncs.com
```

等长串替换表（`--with-exe` 证据模式使用；`.invalid` 为 RFC 6761 保留 TLD，永不解析）：

| 原串 | 长度 | 替换 | 长度 |
| :--- | ---: | :--- | ---: |
| `getquicker.net` | 14 | `void00.invalid` | 14 |
| `getquicker.cn` | 13 | `void0.invalid` | 13 |
| `getquicker.` | 11 | `voi.invalid` | 11 |
| `oss-cn-shanghai` | 15 | `void000.invalid` | 15 |
| `oss-accelerate` | 14 | `void00.invalid` | 14 |
| `quicker-temp.bj.bcebos.com` | 26 | `void00000000000000.invalid` | 26 |
