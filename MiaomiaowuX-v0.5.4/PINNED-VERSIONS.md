# 版本固定记录

本案例的测试结论只对下列**固定版本**成立。厂商后续发新版可能改变行为，届时需重新复测。

| 项 | 值 |
|---|---|
| 产品 | 妙妙屋X (miaomiaowuX) |
| 固定版本 | **v0.5.4**（2026-09-08 发布） |
| 平台 | Linux amd64（主控）；Windows amd64（核对用） |
| 固定件托管 | 本交付仓库 Release：`whitebox-audit-v1.0` |

## 固定件清单与哈希

| 文件 | 大小 | SHA-256 |
|---|---|---|
| `mmwx-v0.5.4-linux-amd64` | 36,605,840 | `ecc1020ad9e5448fdb04bf510f85f9eec329844809cd62f131ccbd635b0d5657` |
| `mmwx-v0.5.4-windows-amd64.exe` | 133,516,800 | `d11895aa6819b68ad61dd50cf1713556445e377d6257467dc8f1b06f01e6cc81` |
| `mmwx-v0.5.4-checksums.txt` | 621 | `8b7abd735611f6bf2e26b16b3363d84ffa2a6dca9f2aa32ae5f7ebc58616352b` |
| `mmwx-v0.5.4-master.manifest` | 415 | `7322c755071815b06ef87382f5d9f13ede78bc33c8001e53d6a2347ba101937b` |

Linux 主程序的 SHA-256 与官方 `checksums.txt`、以及官方签名清单 `mmwx-master-linux-amd64.manifest`
中的 `executable_sha256` **三方一致**，可确认是无改动的官方发行物。

## Docker 镜像锁定

| 项 | 值 |
|---|---|
| 镜像 | `ghcr.io/iluobei/miaomiaowux` |
| 固定摘要 | `sha256:5edb2de21b5a4ae6eba8094267d36c2a61bc25304c36efb9a083d698fbbde6d1` |
| 引用方式 | `ghcr.io/iluobei/miaomiaowux@sha256:5edb2de2…`（**不使用 `:latest`**） |
| 离线包 | `miaomiaowux-docker-image-v0.5.4.tar.gz`（导入后本地标签 `miaomiaowux:v0.5.4`） |

## 取用方式

```bash
BASE=https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0
curl -fL -O $BASE/mmwx-v0.5.4-linux-amd64
sha256sum mmwx-v0.5.4-linux-amd64
# 应为 ecc1020ad9e5448fdb04bf510f85f9eec329844809cd62f131ccbd635b0d5657
```

一键脚本会自动完成上述取件与校验（来源顺序：本地 `artifacts/` → 本仓库 Release → `MMWX_MIRROR`），
校验失败立即中止，不会安装未经验证的二进制。

## 为什么必须固定

妙妙屋X 是持续发版的商业软件，许可判定的实现随版本变化。若部署脚本自行去取上游
`releases/latest`、或使用 `:latest` 镜像，厂商一发新版测试对象就变了，本案例的结论与证据将无法复现。

因此约定：**只用 v0.5.4**。要升级需显式修改
`toolkit/deploy/versions.lock.json` 中的版本号与哈希。
