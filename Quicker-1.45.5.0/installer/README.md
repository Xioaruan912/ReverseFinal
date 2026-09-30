# installer

本目录不存放二进制。安装包体积 24 MB，按仓库约定走 Release 固定件。

| 文件 | 来源 |
| :--- | :--- |
| `Quicker.x64.1.45.5.0.msi` | Release `whitebox-audit-v1.0` |

sha256 `97418d96c00e25c8811b3c5fe3d7df6bb07a9b7be0849a6a1e41d9a1b8896a95`（24,371,200 字节）

一键安装脚本会自动下载并校验；也可手动放到 `<安装目录>\artifacts\` 下，脚本会直接复用。

静默安装参数（WiX 3.14）：

```
msiexec /i "Quicker.x64.1.45.5.0.msi" /qn /norestart INSTALLFOLDER="<dir>"
```

> 注意：该 MSI **没有** `INSTALLDIR` 属性。可配置的目录属性是 WiX 使用的 `INSTALLFOLDER`。
