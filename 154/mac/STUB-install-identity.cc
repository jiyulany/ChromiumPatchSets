// patchsets/154/mac/STUB-install-identity.cc
// ============================================================================
// macOS 临时 stub — 仅在 Windows-only patch 拆分场景下使用。
// ============================================================================
//
// 背景:
//   cross/01-clearcote-base.patch 会把 BUILD.gn 的 source_set("core") 的
//   sources 列表里追加 r0_license/* 共 8 个文件。其中包含
//   "r0_license/install_identity_win.cc" — 这是 Windows 专属实现。
//   当 macOS 上只 apply cross patch 时，BUILD.gn 会去编译这个
//   .cc 文件，但 macOS 端没有该文件，导致 autoninja 失败。
//
//   解决方案：把本 stub 文件放到 src/chrome/browser/r0_license/
//   install_identity_win.cc 位置（覆盖 Windows-only patch 没有被 apply 的
//   缺失）。也可以在 macOS 上使用 install_identity_mac.cc 替代。
//
// ============================================================================

#include "chrome/browser/r0_license/install_identity.h"

#include <string>

namespace r0_license {

bool LoadOrCreateInstallId(std::string* install_id, std::string* error) {
    if (error) {
        *error = "install_identity is not yet implemented for this platform; "
                 "use --r0-install-id=<uuid> to bypass.";
    }
    return false;
}

}  // namespace r0_license