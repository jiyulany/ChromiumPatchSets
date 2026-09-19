# patchsets/154 跨端 patch 同步工作流

> 本文档回答：**我改了 Chromium 源码，怎么把改动同步给 macOS / Linux / Windows 三端？**

## 1. 总览

`patchsets/154/` 现在按"平台相关性"分层：

```
patchsets/154/
├── cross/                      ★ 三端都 apply 的部分
│   └── 01-clearcote-base.patch
├── windows/                    ★ 只 Windows apply
│   └── 01-clearcote-base.patch
├── mac/                        ★ 只 macOS apply (目前仅 STUB 占位)
│   └── STUB-install-identity.cc
├── linux/                      ★ 只 Linux apply (目前仅 STUB 占位)
│   └── STUB-install-identity.cc
├── apply.sh                    Linux / macOS 一键调度
├── apply.ps1                   Windows 一键调度
└── 000-clearcote-154-all.patch   完整 snapshot (apply cross+windows 后 git diff 导出)
```

**核心原则**：95% 的改动是 `cross/`；只有 BUILD.gn 的平台分支、install_identity_*.cc、`auth_build_config.h` 的平台宏、`90x-*.patch` 这类构建修复需要 platform 分支。

## 2. 端到端流程（新增一个 fingerprint 表面举例）

假设你新增一个 `SentinelFlagXyz` fingerprint，需要在三端同步。

### 步骤 A — 在最方便的端做改动（建议 macOS/Linux，编译快）

```bash
cd /path/to/src          # 已 checkout 到 bbbfd22b... (新 chromium commit)
git status               # 必须 clean
# 编辑 fingerprint_switches.h、fingerprint_generator.cc、tests/...
git add chrome/browser/fingerprint/...
git commit -m "fingerprint: add SentinelFlagXyz surface"
NEW_SHA=$(git rev-parse HEAD)
```

### 步骤 B — 把同一改动镜像到其他端

```bash
# Windows 端
cd /path/to/src-windows
git cherry-pick $NEW_SHA           # 或 git checkout $NEW_SHA -- <files> + git commit

# Linux 端
cd /path/to/src-linux
git cherry-pick $NEW_SHA
```

> 三端的 `src/` 在同一 git repo 中，所以直接 `cherry-pick` 是最快路径。如果三端使用独立 git checkout（比如 macOS/Linux/Windows 各 checkout 一份），都用同一个远端。

### 步骤 C — 评估改动属于哪一端

| 你改了什么 | 属于哪层 |
|-----------|---------|
| 仅 fingerprint/*.h、*.cc、tests/ | `cross/` |
| 改了 BUILD.gn 的公共 sources 列表 | `cross/` |
| 改了 BUILD.gn 的 `is_win` / `is_mac` / `is_linux` 块 | 对应 `windows/` / `mac/` / `linux/` |
| 改了 `chrome/browser/r0_license/install_identity_*.cc` | 对应 `windows/` / `mac/` / `linux/` |
| 改了 `chrome/browser/r0_license/auth_build_config.h` 的平台宏 | 对应平台 |
| 新增/修改 `90x-*.patch`（构建修复） | 对应平台 |
| 新增跨端都用的小工具（如 `base/random_emoji.cc`） | `cross/` |

### 步骤 D — 导出 patch 并放到对应目录

```bash
cd /path/to/src              # 任一端都行，只要包含 commit $NEW_SHA
git format-patch -1 $NEW_SHA -o /tmp/
# /tmp/0001-fingerprint-add-SentinelFlagXyz-surface.patch

# 把 patch 复制到 patchsets/154 的对应目录：
cp /tmp/0001-*.patch /path/to/patchsets/154/cross/
# 或
cp /tmp/0001-*.patch /path/to/patchsets/154/mac/
```

**注意**：
- 三端如果有差异（比如改 BUILD.gn 的 `is_win` 块），需要为每端都生成一个 patch，分别放到 `windows/`、`mac/`、`linux/`。
- cross patch 的 hunk 必须能在三端都干净 apply，否则拆 patch 时漏了上下文。

### 步骤 E — 验证三端都能 apply

在每端的工作区里：

```bash
# Windows 端 (powershell)
cd \path\to\src
git checkout HEAD -- .   # 确保工作区干净
git status               # 确认 clean
cd \path\to\patchsets\154
.\apply.ps1

# macOS / Linux 端 (bash)
cd /path/to/src
git checkout HEAD -- .
cd /path/to/patchsets/154
./apply.sh
```

任何一个端 apply 失败，都会打印具体文件路径和行号。常见原因：
1. `cross/` patch 的 hunk context 和某端 src HEAD 不 match（chromium 上游漂移）—— 把这个 patch 改成对应端的 `platform/` patch，或者重新基于该端 HEAD 生成。
2. 跨端 git 操作没同步——某端没 `cherry-pick` 这个 commit。
3. `apply.sh` 没标 `xargs=` —— 这是个安全栏，防止 cross 端的 patch 误打到 platform 端。

### 步骤 F — 重新生成完整 snapshot（可选）

更新 `000-clearcote-154-all.patch`（供老脚本/老平台使用）：

```bash
cd /path/to/src-windows
git checkout HEAD -- .
cd \path\to\patchsets\154
.\apply.ps1
git diff > 000-clearcote-154-all.patch
```

### 步骤 G — 把 patchsets commit 到你的私有仓库

```bash
cd /path/to/patchsets
git add 154/
git commit -m "patchsets/154: add SentinelFlagXyz cross patch"
git push
```

> 私有仓库是你 `.git`-tracked 的 patchsets 目录，每次新 patch 都打一个 commit，**历史可追溯**。

## 3. 跨端出现漂移（chromium 上游版本升级）怎么办？

比如 `bbbfd22b` → `bbbfd22c`（上游几个 commit 后）：

1. 在三端各自 `git checkout <new-sha>`
2. 跑 `apply.sh` / `apply.ps1`，看哪些 hunk 失败
3. 对每个失败的 patch，在出错的端上重新做改动并 commit
4. 重新生成 patch，覆盖 patchsets/154/cross/ 或 platform/ 里的对应文件

**典型漂移位置**（chromium 高频更新区）：
- `chrome/browser/BUILD.gn` — 增减 source 文件
- `chrome/browser/chrome_browser_main.cc` — 增加新 service / 重排 init
- `content/browser/browser_main_loop.cc` — 早期 init 流程改动
- `base/version.h` 等版本头

每次跨版本升级时，**优先重新生成 cross patch**（影响最大），其次是 `chrome_browser_main.cc` 关联的 patch（hunk context 容易飘）。

## 4. macOS / Linux 端 apply 后的临时限制

⚠️ **当前限制**：cross patch 会在 BUILD.gn 里列出 `install_identity_win.cc`。macOS/Linux 上没有这个文件，编译会失败。

**当前临时方案**：
- macOS：把 `patchsets/154/mac/STUB-install-identity.cc` 复制到 `src/chrome/browser/r0_license/install_identity_win.cc`
- Linux：把 `patchsets/154/linux/STUB-install-identity.cc` 复制到 `src/chrome/browser/r0_license/install_identity_win.cc`

STUB 是"返回 false + error 提示"的占位实现，让 macOS/Linux 端**编译通过**但功能不可用（启动 `--r0-api-key=` 会失败，提示需要平台实现）。

**长期方案**（推荐尽快做）：
按 `FINGERPRINT_MODIFICATION_COMPLETE_GUIDE.md` 26.8.3 的模板：
1. 把 BUILD.gn 的 `r0_license/install_identity_win.cc` 从 sources 列表移到 `if (is_win)` 块
2. 新增 `r0_license/install_identity_mac.cc` / `_linux.cc` 的 sources 到对应 `is_mac` / `is_linux` 块
3. 重新生成 cross + windows + mac + linux 四个 patch
4. 删除 STUB 文件

## 5. 完整工作流示意

```
                  ┌─ Windows (compile slow)
                  │
源码改动 ────┬────┼─ macOS   (compile fast, primary dev)
            │    │
            │    └─ Linux   (compile fast, primary dev)
            │
            ▼
        git commit
            │
            ▼
    评估改动平台相关性
            │
   ┌────────┼────────┐
   ▼        ▼        ▼
 cross/  windows/  mac/或linux/
   │        │        │
   └────────┴────────┘
            │
            ▼
     三端 apply 验证
            │
            ▼
  git push 到 patchsets 私有仓库
```

## 6. 速查表（cheatsheet）

| 想做什么 | 命令 |
|---------|------|
| 给三端添加新 fingerprint | 见 2.A~2.G |
| 给 Windows 加 DPAPI 修复 | 在 Windows 端 commit → 放到 `windows/` |
| 给 macOS 加 Keychain 行为 | 在 macOS 端 commit → 放到 `mac/`，同步 cherry-pick 到其他两端 |
| 给 Linux 加文件权限修复 | 在 Linux 端 commit → 放到 `linux/`，同步 cherry-pick 到其他两端 |
| 跨 chromium 版本升级 | 三端分别 checkout → apply 失败 → 重新生成对应 patch |
| 重生成完整 snapshot | `git diff > 000-clearcote-154-all.patch` |

## 7. 常用排查命令

```bash
# 看 patch 涉及的文件
grep '^diff --git' patchsets/154/cross/*.patch

# 看某 patch 的具体内容
git apply --stat patchsets/154/cross/01-clearcote-base.patch

# 看 apply 后 src 状态（应干净）
git status

# 在干净 src 上 dry-run apply
git apply --check patchsets/154/cross/*.patch

# 看 patch 三端都 apply 后与 HEAD 的 diff
git diff HEAD --stat
```