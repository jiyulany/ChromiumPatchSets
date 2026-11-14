# R0 三端品牌图标资源

## 目录结构

```text
branding/
├── app_icon.png                 三端共用的全分辨率透明母图
├── generate_icons.ps1           Windows ICO 生成脚本
├── generate_icons_macos.sh      macOS ICNS / Assets.car 生成脚本
├── generate_icons_linux.sh      Linux PNG / XPM 生成脚本
└── win/
    ├── chromium.ico             已生成的 Windows 浏览器图标
    └── mini_installer.ico       已生成的 Windows 安装包图标
```

图片以独立文件保存，**不再嵌入 `.patch`**。因此不会再出现 Git 二进制补丁的大段不可读编码，后续换图也不需要重新生成二进制 patch。

`windows/04-r0-branding-worker-icon.patch` 只包含 Windows Worker 数字角标和 Profile 图标版本的文本代码改动。

## 更换图标

用新的正方形 PNG 覆盖：

```text
patchsets/154/branding/app_icon.png
```

建议尺寸 1024×1024 或更大。推荐直接使用透明背景 PNG。

Windows 脚本也支持不透明白底的圆形图标：它会识别彩色圆形区域并清除圆外背景，同时保留圆内白色圆环、分隔线和文字。macOS/Linux 脚本只负责缩放与格式转换，**换图时应提供已经透明的母图**。

## Windows

在 Windows / PowerShell 中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File patchsets\154\branding\generate_icons.ps1
```

指定 Chromium 源码目录或其他源图：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File patchsets\154\branding\generate_icons.ps1 `
  -ChromiumSrc F:\chromium\chromium154\src `
  -Source D:\icons\new_r0_icon.png
```

生成：

```text
chrome/app/theme/chromium/win/chromium.ico
chrome/installer/mini_installer/mini_installer.ico
```

根目录的 `branding/generate_icons.ps1` 是便捷入口，会调用本目录的正式脚本，不需要维护两份实现。

## macOS

在 macOS 上运行：

```bash
bash patchsets/154/branding/generate_icons_macos.sh /path/to/chromium/src
```

也支持通过环境变量指定源码目录，第二个参数可指定其他 PNG：

```bash
CHROMIUM_SRC=/path/to/chromium/src \
  bash patchsets/154/branding/generate_icons_macos.sh /path/to/chromium/src /path/to/new_icon.png
```

依赖 macOS 自带的 `sips`、`iconutil`；存在 Xcode `actool` 时还会重建 `Assets.car`。

生成或更新：

```text
chrome/app/theme/chromium/mac/app.icns
chrome/app/theme/chromium/mac/Assets.xcassets/
chrome/app/theme/chromium/mac/Assets.car
```

`AppIcon.icon` 是 Chromium 为新版 macOS Liquid Glass 图标准备的矢量分层资源，本脚本不修改它。如果目标系统仍显示该矢量图标，需要后续单独用 Icon Composer 替换，不能用普通 ICNS 转换替代。

## Linux

先安装 ImageMagick：

```bash
sudo apt install imagemagick
```

运行：

```bash
bash patchsets/154/branding/generate_icons_linux.sh /path/to/chromium/src
```

生成或更新：

```text
chrome/app/theme/chromium/linux/product_logo_{24,48,64,128,256}.png
chrome/app/theme/chromium/linux/product_logo_32.xpm
chrome/app/theme/chromium/product_logo_{16,24,48,64,128,256}.png
chrome/app/theme/default_100_percent/chromium/linux/product_logo_{16,32}.png
```

`product_logo_22_mono.png` 是专用单色资源，不使用彩色母图覆盖。

## 随 apply 自动执行

三端 apply 流程已在文本补丁应用完成后调用相应脚本：

- `apply.ps1`：调用 `generate_icons.ps1`
- macOS `apply.sh`：调用 `generate_icons_macos.sh`
- Linux `apply.sh`：调用 `generate_icons_linux.sh`

因此标准流程是：

1. 替换 `app_icon.png`
2. 执行对应平台的 apply 或图标生成脚本
3. 重新编译浏览器/安装包

`--worker-id` 数字角标目前仅在 Windows 实现；macOS/Linux 脚本当前只更新基础品牌图标。
