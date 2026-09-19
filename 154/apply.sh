#!/usr/bin/env bash
# patchsets/154/apply.sh
# 按当前平台自动挑选 cross/* + 当前平台专属/* 的 patch，按序 apply。
#
# 用法:
#   ./apply.sh                    # 默认取 ../src (相对 patchsets/154)
#   ./apply.sh /path/to/chromium  # 指定 src 根
#   CHROMIUM_SRC=/path/to/chromium ./apply.sh
#
# 平台识别:
#   uname -s → Linux | Darwin | MINGW* / MSYS* / CYGWIN
#
# 设计原则:
#   * cross/* 是三端都要 apply 的部分；platform/* 只在该端 apply。
#   * 各 patch 必须相互独立（无 BUILD.gn 跨 patch 文本冲突）。
#   * 顺序很重要：先 cross/* 再 platform/*，最后是遗留的 90x-*.patch（构建修复）。
#   * 每个 patch 都会先 --check 再 --apply，确保问题定位到具体文件。

set -euo pipefail

CHROMIUM_SRC="${CHROMIUM_SRC:-${1:-$(cd "$(dirname "$0")/../.." && pwd)/src}}"
PATCHSET_DIR="$(cd "$(dirname "$0")" && pwd)"

case "$(uname -s)" in
    Linux*)                       PLATFORM=linux   ;;
    Darwin*)                      PLATFORM=mac     ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
                                  PLATFORM=windows ;;
    *)  echo "[apply.sh] Unknown OS: $(uname -s)" >&2; exit 2 ;;
esac

echo "[apply.sh] platform=$PLATFORM"
echo "[apply.sh] chromium_src=$CHROMIUM_SRC"
echo "[apply.sh] patchset_dir=$PATCHSET_DIR"

[[ -d "$CHROMIUM_SRC/.git" ]] || {
    echo "[apply.sh] $CHROMIUM_SRC 不是 git checkout" >&2
    exit 2
}

cd "$CHROMIUM_SRC"

# 必须先 HEAD 干净，否则 patch 与工作区冲突难调试。
if [[ -n "$(git status --porcelain)" ]]; then
    echo "[apply.sh] 工作区不干净，请先 git status 排查：" >&2
    git status --short >&2
    exit 3
fi

apply_one() {
    local f="$1"
    echo "[apply] $f"
    if ! git apply --check "$f"; then
        echo "[apply.sh] --check 失败: $f" >&2
        exit 1
    fi
    git apply "$f"
}

# 1. 跨平台层 (强制)
for f in "$PATCHSET_DIR"/cross/*.patch; do
    [[ -f "$f" ]] || continue
    apply_one "$f"
done

# 2. 平台分支 (windows | mac | linux)
case "$PLATFORM" in
    mac)
        for f in "$PATCHSET_DIR/mac"/*.patch; do
            [[ -f "$f" ]] || continue
            apply_one "$f"
        done
        # mac 上跑 90x-windows-build-fixes.patch 没有任何意义 (crypt32 等链接器
        # 标记只在 is_win 块里), 跨端编译 Windows 时才需要, 这里跳过。
        ;;
    linux)
        for f in "$PATCHSET_DIR/linux"/*.patch; do
            [[ -f "$f" ]] || continue
            apply_one "$f"
        done
        # Linux 上要 cross-compile Windows 才需要 90x-windows-build-fixes.patch,
        # 日常本机构建跳过。
        ;;
    windows)
        for f in "$PATCHSET_DIR/windows"/*.patch; do
            [[ -f "$f" ]] || continue
            apply_one "$f"
        done
        # 平台级构建修复 (crypt32 链接、RC 调用保护等)。
        for f in "$PATCHSET_DIR"/90[05]-*.patch "$PATCHSET_DIR"/901-*.patch "$PATCHSET_DIR"/902-*.patch; do
            [[ -f "$f" ]] || continue
            apply_one "$f"
        done
        ;;
esac

echo "[apply.sh] done."
echo "[apply.sh] 当前 src 工作区状态:"
git status --short | sed 's/^/  /'