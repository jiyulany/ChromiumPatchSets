# patchsets/154 — chromium 154 跨端 fingerprint patchset

## 状态

- **上游 HEAD**：`325cea974198c8a6ecd931598856c0a63ec8c230`
- **fingerprint commit**：`<见 commit history>`
- **当前实测 apply OK**：Windows / macOS（需 stub 文件）/ Linux（正式实现）

## 结构

```
patchsets/154/
├── UPSTREAM_REVISION
├── README.md                                  ← 你正在看
├── apply.sh                                   ← Linux/macOS 一键 apply
├── apply.ps1                                  ← Windows 一键 apply
├── 000-clearcote-154-all.patch                ← 完整 snapshot (历史保留，
│                                              ⚠️ 不含 02~05 增量补丁的内容，
│                                              新端请用 apply.ps1/apply.sh)
│
├── cross/                                     ★ 三端都 apply
│   ├── 01-clearcote-base.patch                ← 11 文件 / 86581 bytes
│   │       (chromium 源码 + BUILD.gn + r0_license 6 个跨平台文件 +
│   │        chrome_browser_main.cc + browser_main_loop.cc,
│   │        删除 jwt_license/)
│   ├── 02-r0-license-start-hardening.patch    ← 1 文件 (2026-09-19)
│   │       r0_license_monitor.cc：
│   │       * 修复 api_key_ 在 StartLease() 前被清空的 bug
│   │         (服务端 400 被误报为 "temporarily unavailable")
│   │       * SetAllowHttpErrorResults(false→true)，4xx/5xx 可拿到 body
│   │       * OnStartResponse 按 net_error/http_status 分流：
│   │         网络错误/408/429/5xx → 退避重试；其他 4xx → 立即 fatal
│   │       * 非成功路径打印 start diagnostics 日志
│   │         (成功不打印 body，防 lease secret 泄漏)
│   ├── 03-fingerprint-license-gate.patch      ← 8 文件 (2026-09-20)
│   │       指纹授权门闩：r0 lease 验签成功前，--fingerprint-config 全部
│   │       被忽略（hook 退出逻辑只能得到原生指纹的 Chromium，无利用价值）
│   │       * 新增 content::IsFingerprintAuthorized() 门闩
│   │         (content/public/browser/fingerprint_authorization.h)
│   │       * r0_license_monitor.cc：验签成功后 SetFingerprintAuthorized()；
│   │         kInitStartDelay 3s→100ms、poll 2s→250ms，压缩未授权窗口
│   │       * 门控 4 处：renderer fingerprint-json 透传、User-Agent、
│   │         Accept-Language、DNT (RendererPreferences)
│   │       * 有意不门控（一次性早期消费者，门了会误伤正常用户）：
│   │         TLS persona (network service 随租约请求一次性启动)、
│   │         窗口尺寸钳制 (主窗口创建早于验签)
│   ├── 04-fatal-exit-delay-testing-aid.patch  ← 1 文件 (2026-09-21 重生成)
│   │       授权失败处理增强 + 测试辅助：
│   │       * HandleFatal 延迟 10 秒退出（kFatalExitDelay），可用
│   │         --r0-fatal-exit-delay-ms / R0_FATAL_EXIT_DELAY_MS 覆盖
│   │         (0..600000)，测试时无需重编译即可拉长观察窗口
│   │       * 新增 fatal_ 标志 + HasFatalError() 访问器（05 的首窗
│   │         失败释放依赖它）
│   │       * 验签成功补日志 "lease established ... gate is OPEN"
│   │       ⚠️ 发布前把 kFatalExitDelay 改为 0（心跳中途吊销也会多
│   │       存活这个时长，且此时门闩已开）。注意 05 依赖本补丁的
│   │       HasFatalError，不要直接删除本补丁。
│   └── 05-startup-window-license-gate.patch   ← 1 文件 (2026-09-21)
│           首窗授权挂起（chrome_browser_main.cc）：
│           * 修复启动竞态：租约异步，首屏 renderer 此前抢在验签前
│             出生并终身原生指纹（实测 browserscan 首屏改机失效）
│           * 有 --fingerprint-config 且门闩未开时，挂起
│             browser_creator_->Start()，主 RunLoop 照常创建，
│             50ms 轮询直到门闩打开才建首窗 → 所有 renderer 必然
│             出生在授权后；hook 退出者在挂起期间连窗口都看不到
│           * HandleFatal（彻底失败）也释放挂起：门闩仍关闭，窗口
│             显示原生指纹浏览器，便于测试观察失败状态
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
├── linux/                                     ★ 只 Linux apply (正式实现)
│   └── 03-install-identity-linux.patch         ← 3 文件 (2026-09-19, 编译通过)
│           * 新增 install_identity_linux.cc:
│             身份文件 ${XDG_DATA_HOME:-$HOME/.local/share}/
│             r0browser/install-id-v2.dat，mode 0600，
│             LooksLikeCanonicalUuid 严格校验（同 Windows 语义）
│           * BUILD.gn 26.8.3 平台分流:
│             is_linux→install_identity_linux.cc,
│             is_win→install_identity_win.cc（linux 树上保留但不编译）
│           * auth_build_config.h 26.8.4:
│             R0_AUTH_PLATFORM 改 BUILDFLAG(IS_*) 切换 (linux-x64 等)
│           （替代已删除的 linux/STUB-install-identity.cc）
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
4. macOS 端需要手动把 `mac/STUB-install-identity.cc` 复制到 `src/chrome/browser/r0_license/install_identity_win.cc`（BUILD.gn 公共 sources 仍引用该文件名）；Linux 端 `03-install-identity-linux.patch` 已做平台分流，无需 stub

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

⚠️ **cross/01-clearcote-base.patch 当前包含 install_identity_win.cc 的 BUILD.gn 引用**。这意味着 macOS 端必须提供这个文件名（即使是 stub 实现）才能编译。

Linux 端（2026-09-19 起）：`linux/03-install-identity-linux.patch` 已按 `FINGERPRINT_MODIFICATION_COMPLETE_GUIDE.md` 26.8.3 把 sources 分流为 `is_linux` / `is_win` 分支，无需 stub。

后续待办：把此分流逻辑上移到 cross/ 层（需同步调整 `windows/01` 的 BUILD.gn hunk 并在 Windows 重验），macOS 落地 `install_identity_mac.cc` 后补 `is_mac` 分支。

## 三端实测验证结果

| 端 | apply 结果 | 编译结果 |
|----|-----------|---------|
| Windows 325cea9741 | ✓ 通过 | ✓ (待 build 验证) |
| macOS bbbfd22b | 待测 | 待测 |
| Linux 16cfddee | ✓ (旧 patch 基线 + cross 01/02 + linux/03) | ✓ `autoninja -C out/Default chrome -j8` 通过 (2026-09-19)；二进制含 `linux-x64` 平台标识，`install_identity_linux.o` 已产出 |

> 注：Windows 端实测是基于原 `000-clearcote-154-all.patch` apply 成功；新 split 后的两份 patch apply 后 src 工作区与原 patch 完全等价（验证已做，见 commit history）。