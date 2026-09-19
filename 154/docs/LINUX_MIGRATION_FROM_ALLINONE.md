# Linux 端从「旧 all-in-one patch」迁移到「分层 patch」操作清单

> 适用场景：Linux `src/` 之前用 `git apply 000-clearcote-154-all.patch` 打过老的全量 patch（包含 Windows 专属的 `install_identity_win.cc` DPAPI 实现和 `crypt32.lib`），现在要切换到新的分层结构：
>
> - `cross/01-clearcote-base.patch`（三端通用，11 文件）
> - `linux/STUB-install-identity.cc`（Linux 编译占位，覆盖 `install_identity_win.cc`）
> - `windows/01-clearcote-base.patch`（**Linux 不 apply**，含 DPAPI + crypt32.lib）

---

## 0. 迁移前检查（必做）

```bash
cd /path/to/chromium154/src

# 0.1 确认 baseline commit
git rev-parse HEAD
# 期望：bbbfd22b56d9df22e578e9faf55b286714b7303c
# （即老 patch 是打在这个 HEAD 上的工作区改动，没有额外 commit）
# 如果输出不是这个值，先停下来确认你的 baseline 是哪个，再继续。

# 0.2 查看当前被老 patch 污染的状态
git status --short
# 预期看到类似：
#   M  chrome/browser/BUILD.gn
#   M  chrome/browser/chrome_browser_main.cc
#   D  chrome/browser/jwt_license/jwt_license_monitor.cc
#   D  chrome/browser/jwt_license/jwt_license_monitor.h
#   M  content/browser/browser_main_loop.cc
#   ?? chrome/browser/r0_license/

# 0.3 （可选但强烈建议）备份一份当前工作区 diff，万一迁移出问题可以回退：
git diff > ~/r0-backup-before-migration.patch
# 注意：git diff 不包含 untracked 的 r0_license/，如果里面有你自己手改的内容，
# 额外备份一份目录：
cp -r chrome/browser/r0_license ~/r0-backup-license-dir/
```

⚠️ **如果老 patch 当时是 commit 过的**（`git log` 里能看到 clearcote 相关 commit，HEAD 不是 chromium 上游），先做：

```bash
# 记下老 patch commit 的 SHA（备用回退）：
git log --oneline -5

# 硬回到 chromium baseline（⚠️ 会丢弃该 commit 之后所有改动，确认已备份）：
git reset --hard bbbfd22b56d9df22e578e9faf55b286714b7303c
```

---

## 1. 清除老的 all-in-one patch

**关键点**：`git checkout HEAD -- .` 只能恢复「已跟踪文件」（被修改/删除的），**不能删除老 patch 创建的 untracked 新文件**（`r0_license/` 整个目录、`install_identity_win.cc` 等）。残留会导致新 cross patch apply 时报 "already exists in working directory"。

```bash
cd /path/to/chromium154/src

# 1.1 恢复所有被修改/删除的已跟踪文件
git checkout HEAD -- .

# 1.2 删除老 patch 创建的 untracked 文件/目录（老 patch 新增了 r0_license/）
#     先 dry-run 看会删哪些，确认只有 r0_license/ 和自己确认要删的：
git clean -nd

# 1.3 确认无误后执行（-f 强制，-d 包含目录）：
git clean -fd

# 1.4 验证工作区已完全干净
git status
# 期望输出：nothing to commit, working tree clean
# 如果还有残留，手动删除后再次确认。
```

⚠️ 如果 `git clean -nd` 列出了你不想删的文件（比如自己的调试脚本），用精确路径删：

```bash
rm -rf chrome/browser/r0_license
# 老 patch 如果还创建过其他新文件（用 git status ?? 项核对），逐个删除
```

---

## 2. 应用新的分层 patch

```bash
# 2.1 确保 patchsets 仓库是最新（含拆分后的 cross/linux/windows 目录）
cd /path/to/patchsets
git pull
ls 154/        # 应能看到 cross/ windows/ mac/ linux/ apply.sh 等

# 2.2 赋予执行权限（如果从 Windows 同步过来可能丢了 +x）
chmod +x 154/apply.sh

# 2.3 跑一键脚本（自动识别 Linux，只 apply cross/*，跳过 windows/*）
cd /path/to/patchsets/154
./apply.sh
# 期望输出：
#   [apply.sh] platform=linux
#   [apply.sh] chromium_src=/path/to/chromium154/src
#   [apply] .../cross/01-clearcote-base.patch
#   [apply.sh] done.
```

apply.sh 内部做的事：检查 src 是 git checkout → 检查工作区干净（不干净直接退出）→ 按序 `git apply --check` + `git apply` cross/ 下的所有 `.patch`。

**如果 `--check` 失败**，先看报错的具体文件和行号：

```bash
cd /path/to/chromium154/src
git apply --check --verbose /path/to/patchsets/154/cross/01-clearcote-base.patch
# 常见原因见文末「排查」一节
```

---

## 3. 放置 Linux stub（必须，否则编译失败）

cross patch 会让 `chrome/browser/BUILD.gn` 的 sources 列表引用 `r0_license/install_identity_win.cc`，但 Windows-only patch 不会在 Linux 上 apply，所以这个文件不存在，需要用 stub 顶上：

```bash
# 3.1 复制 stub 到 patch 期望的路径
cp /path/to/patchsets/154/linux/STUB-install-identity.cc \
   /path/to/chromium154/src/chrome/browser/r0_license/install_identity_win.cc

# 3.2 确认 r0_license/ 目录下的文件（7 个，全由 cross patch + stub 提供）
ls /path/to/chromium154/src/chrome/browser/r0_license/
# 期望：
#   auth_security.cc   auth_security.h   heartbeat_schedule.h
#   install_identity.h install_identity_win.cc   ← 这个内容应是 stub（开头注释有 "Linux 临时 stub"）
#   r0_license_monitor.cc   r0_license_monitor.h

# 3.3 快速确认 install_identity_win.cc 确实是 stub 而不是老 patch 的 DPAPI 版本：
head -5 /path/to/chromium154/src/chrome/browser/r0_license/install_identity_win.cc
# 期望看到 "Linux 临时 stub" 字样
# 如果看到 CryptProtectData / windows.h，说明老文件没清干净，回到第 1 步。
```

stub 的行为：`LoadOrCreateInstallId()` 直接返回 `false` 并提示 `install_identity is not yet implemented for this platform; use --r0-install-id=<uuid> to bypass.`，即 Linux 端**编译通过、授权链路占位不可用**，等后续写真正的 `install_identity_linux.cc` 再替换。

---

## 4. 验证迁移结果

```bash
cd /path/to/chromium154/src

# 4.1 工作区状态应与预期一致
git status --short
# 期望：
#   M  chrome/browser/BUILD.gn                      （cross patch）
#   M  chrome/browser/chrome_browser_main.cc        （cross patch）
#   D  chrome/browser/jwt_license/jwt_license_monitor.cc
#   D  chrome/browser/jwt_license/jwt_license_monitor.h
#   M  content/browser/browser_main_loop.cc        （cross patch）
#   ?? chrome/browser/r0_license/                  （cross patch + stub）

# 4.2 与 Windows 端交叉对比（可选，两端各跑一次对比输出）：
git diff --stat
# Windows 端在同样位置跑 git diff --stat，
# 除 install_identity_win.cc 和 BUILD.gn 的 crypt32 段外，其余应一致。

# 4.3 确认 BUILD.gn 里没有 crypt32.lib（那是 windows/ patch 的内容，Linux 不该有）：
grep -n "crypt32" chrome/browser/BUILD.gn
# 期望：无输出（Linux 端不 apply windows patch）

# 4.4 确认 jwt_license 已删除：
ls chrome/browser/jwt_license/ 2>&1
# 期望：No such file or directory
```

（可选）跑一次 GN 生成，确认构建配置层没断：

```bash
gn gen out/Linux --args='is_debug=false ...你常用的参数...'
# 只要 gn gen 不报 BUILD.gn 语法/文件缺失错误即可，不必立刻完整编译。
```

---

## 5. 提交快照（推荐）

把迁移后的状态 commit 一份，后续在此基础上叠加改动，不用每次重放 patch：

```bash
cd /path/to/chromium154/src
git add -A
git commit -m "clearcote-154: migrate to layered patchset (cross + linux stub)

- Replaced monolithic 000-clearcote-154-all.patch with:
  cross/01-clearcote-base.patch (cross-platform, 11 files)
  linux/STUB-install-identity.cc (placeholder for install_identity_win.cc)
- Windows-only code (DPAPI install identity, crypt32.lib) NOT applied on Linux.
- Baseline: bbbfd22b56d9df22e578e9faf55b286714b7303c"
```

> 也可以选择不 commit、保持 dirty 工作区。但 commit 的好处：git log 一眼能看出当前处于哪个 patchset 版本，后续 cherry-pick Windows 端新 commit 时更顺。

---

## 6. 迁移后的日常工作流（简述）

之后每次改代码、同步三端，按 `docs/PATCH_SYNC_WORKFLOW.md` 走：

1. 在最方便的端改代码并 `git commit`
2. `git format-patch -1 <sha>` 导出
3. 按改动性质放入 `cross/` 或 `linux/`（或 `windows/`/`mac/`）
4. `cd patchsets && git add 154/ && git commit && git push`
5. 其他端 `cd patchsets && git pull`，然后：
   - 已 commit 过基线的端：直接 `git cherry-pick <sha>`（最快）
   - 或 reset 后重跑 `./apply.sh`
6. `000-clearcote-154-all.patch` 保持历史快照即可，不再作为分发入口

---

## 7. 排查

| 现象 | 原因 / 处理 |
|------|------------|
| apply.sh 报 "工作区不干净，请先 git status 排查" | 第 1 步没做干净。`git checkout HEAD -- .` + `git clean -fd` 后重试。 |
| `git apply --check` 报 `already exists in working directory` | 老 patch 的 untracked 文件残留（通常是 `r0_license/`）。`rm -rf chrome/browser/r0_license` 后重跑 apply.sh。 |
| `git apply --check` 报 hunk context 不匹配（`error: patch failed: chrome/browser/BUILD.gn:850`） | src HEAD 与 patch 的 baseline 不一致。确认 `git rev-parse HEAD` 是 `bbbfd22b...`；如果上游升过级，需要重新生成 cross patch（见 PATCH_SYNC_WORKFLOW.md 第 3 节）。 |
| 编译报找不到 `r0_license/install_identity_win.cc` | 第 3 步 stub 没放。重新 `cp linux/STUB-install-identity.cc src/chrome/browser/r0_license/install_identity_win.cc`。 |
| 编译报 `CryptProtectData` / `windows.h` 未定义 | `install_identity_win.cc` 还是老 patch 的 Windows 实现残留（第 1 步没清干净）。删掉该文件后重新走第 2、3 步。 |
| 链接报 `crypt32` 未找到 | 不该发生——Linux 端不 apply windows patch。检查 BUILD.gn 是否残留 `crypt32.lib`（`grep crypt32 chrome/browser/BUILD.gn`），有则说明误 apply 了全量 patch，重做第 1 步。 |
| 运行时提示 `install_identity is not yet implemented for this platform` | 正常现象，stub 的预期行为。待实现 `install_identity_linux.cc`（文件持久化 mode 0600 方案）后替换。 |

---

## 8. 一键版本（确认理解每步含义后使用）

```bash
#!/usr/bin/env bash
set -euo pipefail

SRC="${1:?用法: $0 /path/to/chromium154/src}"
PATCHSETS="${2:?用法: $0 <src> /path/to/patchsets}"

cd "$SRC"
[[ -z "$(git status --porcelain)" ]] || { git checkout HEAD -- . ; }
git clean -fd
git status --porcelain && { echo "工作区仍有残留，中止"; exit 1; }

cd "$PATCHSETS/154"
./apply.sh

cp linux/STUB-install-identity.cc \
   "$SRC/chrome/browser/r0_license/install_identity_win.cc"

cd "$SRC"
git status --short
echo "== 迁移完成，可用第 5 节命令提交快照 =="
```
