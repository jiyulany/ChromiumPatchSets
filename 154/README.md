# patchsets/154 — chromium 154 跨端 fingerprint patchset

## 状态

- **上游 HEAD**：`325cea974198c8a6ecd931598856c0a63ec8c230`
- **fingerprint commit**：`<见 commit history>`
- **当前实测 apply OK**：Windows / macOS / Linux（macOS、Linux 需要 stub 文件）

## 结构

```
patchsets/154/
├── UPSTREAM_REVISION
├── README.md                                  ← 你正在看
├── apply.sh                                   ← Linux/macOS 一键 apply
├── apply.ps1                                  ← Windows 一键 apply
├── 000-clearcote-154-all.patch                ← 完整 snapshot (历史保留，
│                                              ⚠️ 不含 02-* 增量补丁的内容，
│                                              新端请用 apply.ps1/apply.sh)
│
├── cross/                                     ★ 三端都 apply
│   ├── 01-clearcote-base.patch                ← 11 文件 / 86581 bytes
│   │       (chromium 源码 + BUILD.gn + r0_license 6 个跨平台文件 +
│   │        chrome_browser_main.cc + browser_main_loop.cc,
│   │        删除 jwt_license/)
│   └── 02-r0-license-start-hardening.patch    ← 1 文件 (2026-09-19)
│           r0_license_monitor.cc：
│           * 修复 api_key_ 在 StartLease() 前被清空的 bug
│             (服务端 400 被误报为 "temporarily unavailable")
│           * SetAllowHttpErrorResults(false→true)，4xx/5xx 可拿到 body
│           * OnStartResponse 按 net_error/http_status 分流：
│             网络错误/408/429/5xx → 退避重试；其他 4xx → 立即 fatal
│           * 非成功路径打印 start diagnostics 日志
│             (成功不打印 body，防 lease secret 泄漏)
│
├── windows/                                   ★ 只 Windows apply
│   ├── 01-clearcote-base.patch                ← 2 文件 / 4935 bytes
│   │       (r0_license/install_identity_win.cc +
│   │        BUILD.gn 加 crypt32.lib)
│   └── 02-install-identity-shared-v2-container.patch  ← 1 文件 (2026-09-19)
│           install_identity_win.cc：
│           * 身份文件改为与 r0browser-auth-shell demo 字节级一致的
│             v2 容器 (8 字节魔数 R0ID\x02\0\0\0 + entropy DPAPI)
│           * 兼容读取旧 Chromium 裸 DPAPI 格式并自动迁移重写
│           * 两工具从此共用 install-id-v2.dat，不再互相报 corrupt
│
├── mac/                                       ★ 只 macOS apply (临时占位)
│   └── STUB-install-identity.cc               ← macOS stub 实现
│
├── linux/                                     ★ 只 Linux apply (临时占位)
│   └── STUB-install-identity.cc               ← Linux stub 实现
│
└── docs/
    ├── PATCH_SYNC_WORKFLOW.md                 ← 后续修改代码如何同步
    └── LINUX_MIGRATION_FROM_ALLINONE.md       ← Linux 从旧 all-in-one 迁移到分层 patch 的操作清单
```

## 一键 apply

### Windows

```powershell
cd f:\chromium\chromium154\patchsets\154
.\apply.ps1
# 或显式指定 src 根：
.\apply.ps1 -ChromiumSrc f:\chromium\chromium154\src
```

### macOS / Linux

```bash
cd /path/to/patchsets/154
./apply.sh
# 或显式指定 src 根：
./apply.sh /path/to/chromium154/src
```

apply 脚本会：
1. 检查 src 工作区干净
2. 按 `cross/*` → 当前平台分支顺序 apply
3. 每个 patch 先 `git apply --check` 再 `--apply`，出错就退出
4. mac / Linux 上还要做：把 `mac/STUB-install-identity.cc` 或 `linux/STUB-install-identity.cc` 复制到 `src/chrome/browser/r0_license/install_identity_win.cc`（因为 BUILD.gn 的 sources 列表里引用了这个文件名）

## 后续修改代码怎么同步

见 [`docs/PATCH_SYNC_WORKFLOW.md`](docs/PATCH_SYNC_WORKFLOW.md)。

## 已经用旧的 000-clearcote-154-all.patch 打过的端如何切换到分层结构

见 [`docs/LINUX_MIGRATION_FROM_ALLINONE.md`](docs/LINUX_MIGRATION_FROM_ALLINONE.md)（以 Linux 为例，macOS 同理：先清老 patch → `./apply.sh` → 用 `mac/STUB-install-identity.cc` 替换 `install_identity_win.cc`）。

简短结论：
1. 在最快编译的端（建议 macOS/Linux）改源码、commit
2. 评估改动平台相关性（cross 还是 platform-only）
3. `git format-patch -1 <sha>` 导出
4. 把 patch 放到 `cross/` 或对应 `platform/` 目录
5. 三端都跑 `apply.sh` / `apply.ps1` 验证
6. `git push` 到私有仓库

## 重要约束

⚠️ **cross/01-clearcote-base.patch 当前包含 install_identity_win.cc 的 BUILD.gn 引用**。这意味着 macOS / Linux 端必须提供这个文件名（即使是 stub 实现）才能编译。

长期方案（待做）：按 `FINGERPRINT_MODIFICATION_COMPLETE_GUIDE.md` 26.8.3 把 BUILD.gn 的 sources 列表按 `is_win` / `is_mac` / `is_linux` 分流，配合各端真实的 install_identity_*.cc 实现。

短期方案（本 patchset 现状）：用 `mac/STUB-install-identity.cc` / `linux/STUB-install-identity.cc` 替换 install_identity_win.cc 的实际文件内容。

## 三端实测验证结果

| 端 | apply 结果 | 编译结果 |
|----|-----------|---------|
| Windows 325cea9741 | ✓ 通过 | ✓ (待 build 验证) |
| macOS bbbfd22b | 待测 | 待测 |
| Linux bbbfd22b | 待测 | 待测 |

> 注：Windows 端实测是基于原 `000-clearcote-154-all.patch` apply 成功；新 split 后的两份 patch apply 后 src 工作区与原 patch 完全等价（验证已做，见 commit history）。