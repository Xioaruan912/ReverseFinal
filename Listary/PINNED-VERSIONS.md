# 版本固定记录

本案例的测试结论只对下列**固定版本**成立。厂商后续发新版可能改变行为，届时需重新复测。

| 项 | 值 |
|---|---|
| 产品 | Listary 6 |
| 固定版本 | **6.3.5.94**（构建时间 2025-08-15） |
| 平台 | Windows |
| 安装包 | `Listary-6.3.5.94-setup.exe` · 12,914,736 字节 · SHA-256 `c62249e0d4d49bd3f062d55635cf6a3ab089ea8ee7f6c03947f6febfafaa0288` |
| 主程序 | `Listary-6.3.5.94-main.exe` · 2,132,008 字节 · SHA-256 `be2aec5c06d2731cb89a9799ffeeffdb063afe0da7f1dfcdeb33c6929e7b20d9` |
| 固定件的取用地址 | 本交付仓库 Release：`whitebox-audit-v1.0`（`github.com/Xioaruan912/ReverseFinal`） |

## 取用方式

```bash
BASE=https://github.com/Xioaruan912/ReverseFinal/releases/download/whitebox-audit-v1.0
curl -fL -O $BASE/Listary-6.3.5.94-setup.exe
curl -fL -O $BASE/Listary-6.3.5.94-main.exe
sha256sum Listary-6.3.5.94-setup.exe Listary-6.3.5.94-main.exe
# 应为 c62249e0…0288 与 be2aec5c…20d9
```

安装包用于搭建干净的被测环境；主程序用于与安装后的文件做一致性核对。
校验通过后再放入 `samples/`。

## 为什么必须固定

`tools/Listary6Pro.exe` 的设计目标是**不硬编码厂商常量**、随目标机已安装的版本自适应，
因此它本身不担心版本变化。但**测试结论**（授权判定是否可被本地绕过）必须绑定到具体版本，
否则厂商一发新版，本案例的结论与证据就无法复现。

## 附：一处文档订正

`reports/Listary6-Pro-鉴权脆弱性审计报告.md` 的"哈希 (主程序)"一行，
记录的 SHA-256 `c62249e0…0288` 实际是**安装包**的哈希；主程序
（`C:\Program Files\Listary\Listary.exe`，2,132,008 字节）的 SHA-256 应是
`be2aec5c06d2731cb89a9799ffeeffdb063afe0da7f1dfcdeb33c6929e7b20d9`。
两处哈希已在本文件按实测结果更正，报告正文保持原样以便追溯。
