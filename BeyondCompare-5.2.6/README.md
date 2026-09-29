# Beyond Compare 5.2.6.32774

## 一、这是什么软件

Beyond Compare 是 Scooter Software 出品的文件/文件夹比对与同步工具
（文件夹比较、文本合并、十六进制比对、压缩包比对、注册表比对等）。

免费档（Evaluation）为 30 天全功能试用；到期后需要离线许可密钥
（`--- BEGIN LICENSE KEY ---` 文本块）才能继续使用。

## 二、跑完能用什么

| 能力 | 说明 |
| :--- | :--- |
| 离线凭证判定 | 判定通过（运行时不再出现 `Evaluation … days remaining` 横幅） |
| 全功能比对 | 文件夹比较 / 文本合并 / 十六进制 / 压缩包 / 注册表比对均可用 |
| 试用到期 | 不再触发到期拦截（`FStatus=stRegistered`、`FIsRegistered=1`） |
| 检查更新 | 菜单项失效，且 `FNewVersionAvail` 恒假 —— 不会再提示新版本 |
| 上游连通 | bug 上报 URL 与崩溃上报邮箱改写为不可路由主机，不再回连厂商 |

## 三、环境要求

- Windows 10 / 11 x64
- PowerShell 5.1+（仅用内置 cmdlet，**不需要 Python / Java**）
- 静默安装阶段需要一次管理员授权（UAC）

## 四、一条命令跑通

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Xioaruan912/ReverseFinal/main/oneclick/beyondcompare-license-test.ps1 | iex"
```

可选环境变量：

| 变量 | 作用 |
| :--- | :--- |
| `BC_INSTALLDIR` | 指定产出目录（默认桌面 `BeyondCompare-5.2.6`） |
| `BC_YES=1` | 全程非交互 |
| `BC_MIRROR` | 构件镜像前缀 |
| `BC_SKIP_INSTALL=1` | 已装好，跳过安装 |
| `BC_KEEP_ARTIFACTS=1` | 保留下载的安装包 |

## 五、产物与运维

```
path     : <桌面>\BeyondCompare-5.2.6\BCompare.exe
launch   : 双击 BCompare.exe
remove   : 删除该目录
```

脚本收尾会打印实际路径；产出目录长期保留，只清理下载的安装包。

## 六、目录说明

```
BeyondCompare-5.2.6/
├── README.md                本文件
├── PINNED-VERSIONS.md       固定版本、构件哈希、黄金哈希
├── 使用说明.txt              一键命令速查
├── installer/               安装包放置说明（大件不入库）
├── toolkit/                 工装源码
│   ├── bc5_patch.py         参考实现：校验 → 打补丁 → 回读 → 黄金哈希
│   └── bc5_patch.ps1        便携实现：对已安装的 BCompare.exe 就地打补丁
├── reports/                 审计报告与证据
│   ├── BeyondCompare-5.2.6-鉴权脆弱性审计报告.md
│   ├── 侦察记录.md / 侦察记录-2-关键结构.md
│   └── evidence/            运行时判据与截图
└── src/                     自研分析工装（RTTI 解析 / 字段引用 / 崩溃定位）
```
