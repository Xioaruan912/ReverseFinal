# 版本固定记录

本案例的测试结论只对下列**固定版本**成立。厂商后续发新版可能改变行为，届时需重新复测。

| 项 | 值 |
|---|---|
| 产品 | HexHub Client |
| 固定版本 | **5.1.9** |
| 平台 | Windows amd64 |
| 固定件托管 | 本交付仓库 Release：`whitebox-audit-v1.0`（资产名 `HexHub-Client-5.1.9-windows-amd64-setup.exe`） |

## 关于安装包哈希 —— 同版本号存在两份外壳

实测过程中发现：厂商在**同一版本号 5.1.9** 下发布过**两个不同的安装包外壳**，两者大小完全相同
（152,456,296 字节），但整体 SHA-256 不同：

| 来源 | SHA-256 | MD5 |
|---|---|---|
| 本仓库 Release 固定件（本次实测使用） | `0ce38138688455ab2452c3620861ef6c71db2316aaa49f53273d6cdd2cf3b3c6` | `4d2150b066ad863c443d44c47a42b746` |
| 早期记录（历史审计所用外壳） | `77f7f4faea0ea7ca9510ccdad556de8c804286e6628fe59e3e57461241869b15` | `75ca72bba54d7b92a189a544dbf9f28f` |

**已核实：两份外壳的载荷完全相同。** 对两个安装包分别做静态解包，得到的三个产物哈希逐一相同：

| 解包产物 | SHA-256（两包一致） |
|---|---|
| NSIS solid-LZMA 流 | `866e9acd48809ce131d03b486a3d15cdc75d8a2cb6838f1cab23b9bf6d0ff1dd` |
| `HexHub.exe` | `af9237165c6d132d548dc976bafc950f17e83cb0f1d0bddce92b5486d8776af7` |
| `hexhub-backend.exe` | `1e146344b9bb98557281f57412fe82fb075ba94e8f915b08857b588eb2ad8bd9` |

结论：厂商仅对安装器外壳重新打包，程序本体未变，**本案例的审计结论对两份外壳同样成立**。
一键脚本与文件说明以本仓库 Release 的固定件（`0ce38138…`）为准。

## 取用方式

```bash
BASE=https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0
curl -fL -O $BASE/HexHub-Client-5.1.9-windows-amd64-setup.exe
sha256sum HexHub-Client-5.1.9-windows-amd64-setup.exe
# 应为 0ce38138688455ab2452c3620861ef6c71db2316aaa49f53273d6cdd2cf3b3c6
```

下载后按 `1-安装包/说明.txt` 的说明放置，`extract.py` 会自动找到它（采用静态解包，不执行安装程序）。

## 为什么必须固定

HexHub 是持续更新的商业客户端，界面与鉴权逻辑随版本变化。若让测试脚本自行去官网取「最新版」，
下次厂商发版后测试对象就变了，本案例的结论与截图将无法复现。

因此约定：**只用 5.1.9 的安装包**；更换版本时同步更新本文件与一键脚本中的哈希。
