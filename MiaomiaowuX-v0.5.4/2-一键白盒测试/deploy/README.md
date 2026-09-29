# 版本固定 · 全自控部署

被测软件原本依赖上游的动态地址，上游一发新版本就可能让测试失效：

| 原本的做法 | 风险 |
|---|---|
| `.../releases/latest` | 上游发新版即改变被测对象，结论不可复现 |
| `ghcr.io/iluobei/miaomiaowux:latest` | 镜像被重新推送即改变被测对象 |
| `install.sh` 自动选最新版 | 同上，且会写 systemd / 改系统配置 |

本目录把上面三处全部换成**锁定版本 + 自控来源**。

---

## 锁定了什么

全部记录在 `versions.lock.json`：

| 项 | 锁定值 |
|---|---|
| 版本 | **v0.5.4**（2026-09-08） |
| Linux 二进制 sha256 | `ecc1020ad9e5448fdb04bf510f85f9eec329844809cd62f131ccbd635b0d5657` |
| Windows 二进制 sha256 | `d11895aa6819b68ad61dd50cf1713556445e377d6257467dc8f1b06f01e6cc81` |
| Docker 镜像 | `ghcr.io/iluobei/miaomiaowux@sha256:5edb2de21b5a4ae6eba8094267d36c2a61bc25304c36efb9a083d698fbbde6d1` |
| 离线镜像包 | `miaomiaowux-docker-image-v0.5.4.tar.gz` |

构件全部托管在**本仓库自己的 Release**，不依赖上游仓库/镜像仓库是否还在、是否改名。

---

## 构件来源顺序（取不到就失败，不降级到 latest）

```
1) 本地 artifacts/<文件名>            ← 已缓存则直接校验使用，零网络
2) 本仓库 Release 固定件               ← .../releases/download/whitebox-audit-v1.0/
3) MMWX_MIRROR/<文件名>                ← 你自己搭的镜像（可选）
            ↓
       sha256 校验（强制）
            ↓
      不匹配 → 立即中止，绝不安装
```

---

## 三种部署方式

### 1. 本机（命令）部署

```bash
bash deploy/deploy-native.sh
PORT=12889 DATA_DIR=/opt/mmwx-lab/data bash deploy/deploy-native.sh
MMWX_MIRROR=https://your-mirror/mmwx bash deploy/deploy-native.sh
```

- 不使用 systemd、不写 `/etc`、不改任何系统配置
- 程序与数据都在包目录下的 `run/`，删目录即彻底清理
- 启动前会把实际使用的二进制 sha256 写进 `run/DEPLOYED.txt`

### 2. Docker 部署（在线，按摘要锁定）

```bash
bash deploy/deploy-docker.sh
# 或
docker compose -f deploy/docker-compose.pinned.yml up -d
```

`docker-compose.pinned.yml` 里镜像是 `@sha256:…` 而不是 `:latest`，上游重新推镜像也不会变。

### 3. Docker 部署（离线，零外部请求）

```bash
bash deploy/deploy-docker.sh --offline
```

从本仓库 Release 取 `miaomiaowux-docker-image-v0.5.4.tar.gz`，校验后 `docker load`，
并统一打上本地标签 `miaomiaowux:v0.5.4`，完全脱离 ghcr。

---

## 想升级到新版本

不要改脚本，只改 `deploy/versions.lock.json`：

1. 把 `pinned_version` 改成新版本
2. 更新对应的 `asset` / `sha256` / `size`
3. Docker 部分更新 `pinned_digest` 与 `pinned_ref`

改完重新跑一次部署脚本即可，所有校验会自动按新值执行。

---

## 一键复核

```bash
# 本地构件是否与锁定值一致
sha256sum artifacts/mmwx-v0.5.4-linux-amd64
# 已部署的二进制是什么版本
cat run/DEPLOYED.txt
# 镜像是否确实是锁定摘要
docker image inspect ghcr.io/iluobei/miaomiaowux@sha256:5edb2de2… --format '{{.Id}}'
```
