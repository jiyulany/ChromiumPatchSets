# fingerprint_config.json 配置指南

> 适用于 Chromium 146 指纹定制浏览器  
> 配置文件通过命令行参数 `--fingerprint-config=<路径>` 加载

---

## 目录

1. [全局说明](#1-全局说明)
2. [canvas_fp — Canvas 指纹](#2-canvas_fp--canvas-指纹)
3. [webgl_fp — WebGL 指纹](#3-webgl_fp--webgl-指纹)
4. [gpu_fp — GPU 指纹](#4-gpu_fp--gpu-指纹)
5. [font_fp — 字体指纹](#5-font_fp--字体指纹)
6. [audio_fp — 音频指纹](#6-audio_fp--音频指纹)
7. [webrtc_fp — WebRTC IP 泄露防护](#7-webrtc_fp--webrtc-ip-泄露防护)
8. [useragent_fp — userAgentData (Client Hints)](#8-useragent_fp--useragentdata-client-hints)
9. [user_agent_fp — navigator.userAgent (Legacy UA)](#9-user_agent_fp--navigatoruseragent-legacy-ua)
10. [language_fp — 语言指纹](#10-language_fp--语言指纹)
11. [timezone_fp — 时区指纹](#11-timezone_fp--时区指纹)
12. [hw_fp — CPU 核心数](#12-hw_fp--cpu-核心数)
13. [device_memory_fp — 内存大小](#13-device_memory_fp--内存大小)
14. [client_rects_fp — ClientRects 指纹](#14-client_rects_fp--clientrects-指纹)
15. [screen_fp — 分辨率指纹](#15-screen_fp--分辨率指纹)
16. [webgpu_fp — WebGPU 指纹](#16-webgpu_fp--webgpu-指纹)
17. [voices_fp — TTS 语音指纹](#17-voices_fp--tts-语音指纹)
18. [geolocation_fp — 地理位置指纹](#18-geolocation_fp--地理位置指纹)
19. [do_not_track_fp — Do Not Track](#19-do_not_track_fp--do-not-track)
20. [cookie_fp — Cookie 注入](#20-cookie_fp--cookie-注入)
21. [cdp_fp — CDP 检测规避](#21-cdp_fp--cdp-检测规避)
22. [tls_fp — TLS 指纹 (JA3/JA4)](#22-tls_fp--tls-指纹-jA3ja4)
23. [tls_cipher_fp — 禁用指定 Cipher Suite](#23-tls_cipher_fp--禁用指定-cipher-suite)
24. [新增指纹的步骤](#24-新增指纹的步骤)
25. [JWT 启动校验 HS256（已移除）](#25-jwt-启动校验-hs256已移除)
26. [r0 API Key 启动授权（lease 链路）](#26-r0-api-key-启动授权lease-链路)

---

## 1. 全局说明

- 配置文件路径通过 `--fingerprint-config=<json路径>` 传入
- 每个指纹模块都有一个独立的顶级 key，以 `_fp` 结尾
- 每个模块内部都有一个 `enabled` 字段控制开关（`true` / `false`）
- `enabled: false` 的模块完全走 Chromium 原生逻辑，不做任何修改
- 除 `cookie_fp`、`cdp_fp` 外，所有模块的配置在渲染进程中由 `FingerprintManager` 单例解析
- `cookie_fp` 在浏览器进程 `StoragePartitionImpl::GetCookieManagerForBrowserProcess()` 中解析
- `cdp_fp` 在浏览器进程 `render_process_host_impl.cc` 中解析，通过 `--js-flags` 传递 V8 flag 给渲染进程生效

### 配置加载时序

```
浏览器启动
  ├─ 浏览器进程：chrome_content_browser_client.cc
  │   ├─ GetUserAgent() ← 读取 user_agent_fp（HTTP User-Agent 头）
  │   └─ GetAcceptLangs() ← 读取 useragent_fp / language_fp
  ├─ 浏览器进程：storage_partition_impl.cc
  │   └─ GetCookieManagerForBrowserProcess() ← 读取 cookie_fp
  ├─ 浏览器进程：render_process_host_impl.cc
  │   └─ 读取 cdp_fp → 追加 --js-flags 给渲染进程（V8 flag）
  └─ 渲染进程：FingerprintManager::LazyInitialize()
      ├─ ParseJsonConfig() ← 解析所有其他指纹配置
      ├─ ApplyTimezoneOverride() ← 应用时区
      └─ ApplyLanguageOverride() ← 应用 ICU locale
```

---

## 2. canvas_fp — Canvas 指纹

覆盖 `CanvasRenderingContext2D.toDataURL()` 和 `getImageData()` 的输出，注入确定性噪声。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用 Canvas 指纹随机化 |
| `canvas_noise_seed` | string | ✅ | 噪声种子字符串。相同种子产生相同指纹，不同种子产生不同指纹 |
| `noise_intensity` | int | ✅ | 噪声强度。`0`=禁用，`1`=最小，`10`=最大。推荐 `2-5` |

**生效的 JS API：**
- `canvas.toDataURL()`
- `canvas.toBlob()`
- `ctx.getImageData()`
- `ctx.getChannelData()`

**示例：**
```json
"canvas_fp": {
    "enabled": true,
    "canvas_noise_seed": "fasdfa1231234564",
    "noise_intensity": 4
}
```

---

## 3. webgl_fp — WebGL 指纹

覆盖 WebGL 上下文参数，返回伪造的 vendor/renderer/version 字符串。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用 WebGL 指纹随机化 |
| `seed` | string | ❌ | 随机种子字符串。仅当 vendor/renderer/version 为空时，用于生成随机值 |
| `vendor` | string | ❌ | 覆盖 `gl.VENDOR`。默认 `"WebKit"`（实测 N 卡 / Intel / AMD 掩码值均为 WebKit） |
| `renderer` | string | ❌ | 覆盖 `gl.RENDERER`。默认 `"WebKit WebGL"` |
| `version` | string | ❌ | 覆盖 `gl.VERSION`。如 `"WebGL 1.0 (OpenGL ES 2.0 Chromium)"` |
| `remove_extensions` | string[] | ❌ | 要从扩展列表中移除的 WebGL 扩展名 |
| `add_extensions` | string[] | ❌ | 要添加到扩展列表中的伪造扩展名 |

> `vendor`、`renderer`、`version` 三个字段：如果配置了非空值则直接使用；如果为空则根据 `seed` 随机生成（每个 seed 对应固定的随机值）。

**生效的 JS API：**
- `gl.getParameter(gl.VENDOR)`
- `gl.getParameter(gl.RENDERER)`
- `gl.getParameter(gl.VERSION)`
- `gl.getSupportedExtensions()`
- `gl.getExtension(name)`

**示例：**
```json
"webgl_fp": {
    "enabled": true,
    "seed": "webgl-random-seed-12345",
    "vendor": "WebKit",
    "renderer": "WebKit WebGL",
    "version": "WebGL 1.0 (OpenGL ES 2.0 Chromium)",
    "remove_extensions": [],
    "add_extensions": ["FAKE_ext_webgl_fingerprint_test"]
}
```

---

## 4. gpu_fp — GPU 指纹

覆盖 `WEBGL_debug_renderer_info` 扩展返回的 unmasked vendor/renderer。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用 GPU 指纹覆盖 |
| `unmasked_vendor` | string | ❌ | 覆盖 `UNMASKED_VENDOR_WEBGL`。空 = 使用真实 GPU vendor |
| `unmasked_renderer` | string | ❌ | 覆盖 `UNMASKED_RENDERER_WEBGL`。空 = 使用真实 GPU renderer |

> 与 `webgl_fp` 的区别：`webgl_fp` 覆盖基础 vendor/renderer，`gpu_fp` 覆盖 `WEBGL_debug_renderer_info` 扩展返回的 unmasked 值（这才是真正用于指纹识别的数据）。

**生效的 JS API：**
- `gl.getParameter(ext.UNMASKED_VENDOR_WEBGL)`
- `gl.getParameter(ext.UNMASKED_RENDERER_WEBGL)`

**示例：**
```json
"gpu_fp": {
    "enabled": true,
    "unmasked_vendor": "Google Inc. (NVIDIA)",
    "unmasked_renderer": "ANGLE (NVIDIA, NVIDIA GeForce GTX 1050 Direct3D11 vs_5_0 ps_5_0, D3D11-26.21.14.3630)"
}
```

---

## 5. font_fp — 字体指纹

按概率随机隐藏系统字体，防止通过字体列表识别用户。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用字体指纹随机化 |
| `seed` | string | ✅ | 随机种子字符串。相同种子下哪些字体被隐藏是确定的 |
| `remove_fonts` | string[] | ❌ | 要强制移除的字体名称列表（精确匹配） |
| `remove_probability` | float | ❌ | 随机隐藏字体的概率。`0.0`=不隐藏，`1.0`=全部隐藏。推荐 `0.1-0.3` |

**生效的 JS API：**
- `document.fonts.check()` / `document.fonts.forEach()`
- CSS `@font-face` 中的 `font-family`
- 直接通过 `measureText()` 的字体度量

**示例：**
```json
"font_fp": {
    "enabled": false,
    "seed": "font-random-seed-12345",
    "remove_fonts": [],
    "remove_probability": 0.1
}
```

---

## 6. audio_fp — 音频指纹

向 `OfflineAudioContext` 渲染的音频缓冲区注入确定性噪声。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用音频指纹随机化 |
| `seed` | string | ✅ | 随机种子字符串。相同种子产生相同音频噪声 |

**生效的 JS API：**
- `OfflineAudioContext.startRendering()`
- `AudioBuffer.getChannelData()`
- `AnalyserNode` 相关输出

**示例：**
```json
"audio_fp": {
    "enabled": true,
    "seed": "audio-random-seed-12345"
}
```

---

## 7. webrtc_fp — WebRTC IP 泄露防护

防止 WebRTC ICE 候选/SDP 泄露真实本地 IP 和公网 IP。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用 WebRTC IP 泄露防护 |
| `mode` | string | ✅ | 防护模式。见下表 |
| `ip` | string | ✅* | 替换用的 IP 地址（`mode=mask` 时必需，通常为代理/VPN 出口 IP） |

### mode 取值

| 值 | 行为 |
|----|------|
| `"mask"` | 将 ICE candidate 和 SDP 中的 IP 替换为配置的 `ip` |
| `"block"` | 丢弃所有 host/srflx/prflx 候选，仅保留 relay（TURN）候选 |
| `""` 或其他 | 不启用防护 |

**生效的 JS API：**
- `RTCPeerConnection.onicecandidate` 事件中的 candidate 字符串
- `RTCPeerConnection.createOffer()` / `createAnswer()` 返回的 SDP
- `RTCPeerConnection.onicecandidateerror` 中的地址

**示例：**
```json
"webrtc_fp": {
    "enabled": true,
    "mode": "mask",
    "ip": "212.135.42.22"
}
```

---

## 8. useragent_fp — userAgentData (Client Hints)

覆盖 `navigator.userAgentData` 和 `getHighEntropyValues()` 返回的 Client Hints 数据，以及 `Sec-CH-UA-*` HTTP 请求头。

> ⚠️ 与 `user_agent_fp` 的区别：`useragent_fp` 覆盖的是 **Client Hints**（`navigator.userAgentData`），而 `user_agent_fp` 覆盖的是 **Legacy UA String**（`navigator.userAgent`）。两者互不干扰，可同时启用。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用 userAgentData 覆盖 |
| `brands` | object[] | ❌ | 覆盖 `navigator.userAgentData.brands`。数组中每项为 `{"brand": "...", "version": "..."}` |
| `full_version_list` | object[] | ❌ | 覆盖 `getHighEntropyValues()` 返回的 `"fullVersionList"` |
| `mobile` | bool | ❌ | 覆盖 `navigator.userAgentData.mobile` |
| `platform` | string | ❌ | 覆盖 `navigator.userAgentData.platform`。如 `"Windows"`、`"macOS"` |
| `platform_version` | string | ❌ | 覆盖 `getHighEntropyValues()` 返回的 `"platformVersion"` |
| `architecture` | string | ❌ | 覆盖 `"architecture"`。如 `"x86"`、`"arm"` |
| `model` | string | ❌ | 覆盖 `"model"`。桌面端通常为 `""` |
| `ua_full_version` | string | ❌ | 覆盖 `"uaFullVersion"`。如 `"146.0.7680.253"` |
| `bitness` | string | ❌ | 覆盖 `"bitness"`。如 `"64"` |
| `wow64` | bool | ❌ | 覆盖 `"wow64"` |
| `form_factors` | string[] | ❌ | 覆盖 `"formFactors"`。如 `["Desktop"]` |

> 未配置的字段保持真实值。配置了 `enabled: true` 但某字段未设置时，该字段使用系统原始值。

**生效的 JS API：**
- `navigator.userAgentData.brands`
- `navigator.userAgentData.mobile`
- `navigator.userAgentData.platform`
- `navigator.userAgentData.getHighEntropyValues(hints)`
- `Sec-CH-UA` / `Sec-CH-UA-*` HTTP 请求头

**示例：**
```json
"useragent_fp": {
    "enabled": true,
    "brands": [
        { "brand": "Not-A.Brand", "version": "24" },
        { "brand": "Chromium", "version": "146" },
        { "brand": "Google Chrome", "version": "146" }
    ],
    "full_version_list": [
        { "brand": "Not-A.Brand", "version": "24.0.0.0" },
        { "brand": "Chromium", "version": "146.0.7680.253" },
        { "brand": "Google Chrome", "version": "146.0.7680.253" }
    ],
    "mobile": false,
    "platform": "Windows",
    "platform_version": "19.0.0",
    "architecture": "x86",
    "model": "",
    "ua_full_version": "146.0.7680.253",
    "bitness": "64",
    "wow64": false,
    "form_factors": ["Desktop"]
}
```

---

## 9. user_agent_fp — navigator.userAgent (Legacy UA)

覆盖 `navigator.userAgent` 和 HTTP `User-Agent` 请求头。与 `useragent_fp`（Client Hints）互不干扰。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用 Legacy UA 覆盖 |
| `user_agent` | string | ✅ | 自定义 UA 字符串。如 `"Mozilla/5.0 (Windows NT 10.0; Win64; x64) ..."` |

**生效的 JS API / HTTP 头：**
- `navigator.userAgent`
- `User-Agent` HTTP 请求头（导航 + 子资源）

**示例：**
```json
"user_agent_fp": {
    "enabled": true,
    "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.7680.253 Safari/537.36"
}
```

> 💡 通常应同时配置 `useragent_fp`（Client Hints）和 `user_agent_fp`（Legacy UA），确保两者的版本号一致，避免指纹矛盾。

---

## 10. language_fp — 语言指纹

覆盖 `navigator.language`、`navigator.languages`、`Accept-Language` HTTP 头，以及 `Intl.*` 的 locale。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用语言指纹覆盖 |
| `languages` | string[] | ✅ | 覆盖 `navigator.languages`。第一个元素同时作为 `navigator.language` 和 ICU 默认 locale |
| `accept_language` | string | ✅ | 覆盖 `Accept-Language` HTTP 请求头。如 `"en-US,en;q=0.9"` |

**生效的 JS API：**
- `navigator.language`（= languages[0]）
- `navigator.languages`
- `Intl.DateTimeFormat().resolvedOptions().locale`
- `Intl.NumberFormat().resolvedOptions().locale`
- `Intl.RelativeTimeFormat().resolvedOptions().locale`
- `Accept-Language` HTTP 头（导航 + 子资源）

**示例：**
```json
"language_fp": {
    "enabled": true,
    "languages": ["en-US", "en"],
    "accept_language": "en-US,en"
}
```

---

## 11. timezone_fp — 时区指纹

覆盖 `Intl.DateTimeFormat().resolvedOptions().timeZone` 和 `Date.prototype.getTimezoneOffset()`。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用时区指纹覆盖 |
| `timezone` | string | ✅ | IANA 时区 ID。如 `"Asia/Shanghai"`、`"Europe/London"`、`"America/New_York"` |

**生效的 JS API：**
- `Intl.DateTimeFormat().resolvedOptions().timeZone`
- `new Date().getTimezoneOffset()`
- `new Date().toString()` / `toLocaleString()` 中的时区部分

**示例：**
```json
"timezone_fp": {
    "enabled": true,
    "timezone": "Europe/London"
}
```

---

## 12. hw_fp — CPU 核心数

覆盖 `navigator.hardwareConcurrency`。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用 CPU 核心数覆盖 |
| `hardware_concurrency` | int | ✅ | CPU 核心数。如 `4`、`8`、`16` |

**生效的 JS API：**
- `navigator.hardwareConcurrency`

**示例：**
```json
"hw_fp": {
    "enabled": true,
    "hardware_concurrency": 8
}
```

---

## 13. device_memory_fp — 内存大小

覆盖 `navigator.deviceMemory`。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用内存大小覆盖 |
| `device_memory` | float | ✅ | 内存大小（GB）。Chrome 实际值为 `0.25`-`8`，可设任意正数 |

**生效的 JS API：**
- `navigator.deviceMemory`

**示例：**
```json
"device_memory_fp": {
    "enabled": true,
    "device_memory": 8
}
```

---

## 14. client_rects_fp — ClientRects 指纹

向 `getClientRects()` / `getBoundingClientRect()` 返回的 `DOMRect` 注入亚像素噪声，生成唯一的 ClientRects 指纹。不同浏览器因渲染引擎差异，ClientRects 的小数位数不同，hash 后即为指纹。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用 ClientRects 指纹随机化 |
| `seed` | int | ✅ | 噪声种子。`width` 噪声 = `seed % 103 / 100000.0`，`height` 噪声 = `seed % 97 / 100000.0`。仅当 `rect.x() > 0` 时生效（`x<=0` 的矩形通常是离屏或特殊布局，保持不变） |

**生效的 JS API：**
- `element.getClientRects()`
- `element.getBoundingClientRect()`
- `element.getBoundingClientRect().width` / `.height` 小数位

**示例：**
```json
"client_rects_fp": {
    "enabled": true,
    "seed": 12345
}
```

> 💡 修改 `seed` 值即可生成不同的指纹。不同 seed 下 width/height 的小数部分不同。

---

## 15. screen_fp — 分辨率指纹

覆盖 `screen.width`、`screen.height`、`screen.availWidth`、`screen.availHeight`、`screen.colorDepth`（含 `pixelDepth`），同时覆盖 `matchMedia("(device-width: ...)")` 和 `matchMedia("(device-height: ...)")`，确保两者一致不被检测。

同时在**创建时物理限制初始浏览器窗口大小**为配置的分辨率（`browser_window_state.cc`），使打开时 `window.innerWidth`/`innerHeight`/`outerWidth`/`outerHeight` 与 `screen.width`/`screen.height` 一致。用户后续拖拽或最大化窗口后，这些值会跟随实际窗口大小变化（不拦截）。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用分辨率指纹覆盖 |
| `width` | int | ✅ | `screen.width`（CSS 像素）。如 `1920`、`2560` |
| `height` | int | ✅ | `screen.height`（CSS 像素）。如 `1080`、`1440` |
| `color_depth` | int | ❌ | `screen.colorDepth`。0 = 保持原始值。通常为 `24` |

> `avail_width`/`avail_height` 未配置时（0）**按比例自动计算**：从真实屏幕获取 `avail/full` 比例，乘以配置的假分辨率。例如真实屏幕 1920x1080、avail 1040 → 比例 0.963，配置 1600x900 → avail = 900 × 0.963 ≈ 867。如需覆盖可手动配置。

**生效的 JS API：**
- `screen.width` / `screen.height`
- `screen.availWidth` / `screen.availHeight`（按比例自动计算或手动配置）
- `screen.colorDepth` / `screen.pixelDepth`
- `window.matchMedia("(device-width: ...)")` → 与 `screen.width` 一致
- `window.matchMedia("(device-height: ...)")` → 与 `screen.height` 一致
- `window.innerWidth` / `innerHeight` — 初始与 screen 一致（仅创建时限制）
- `window.outerWidth` / `outerHeight` — 初始与 screen 一致（仅创建时限制）

**防检测原理：**
`screen.width` 和 `matchMedia("device-width")` 在 Chromium 中都从 `display::ScreenInfo.rect` 读取。本实现同时覆盖 `Screen::width()` 和 `MediaValues::CalculateDeviceWidth()`，确保两者返回相同值，检测代码 `matchMedia("(device-width: ${screen.width}px)").matches` 返回 `true`。

**示例：**
```json
"screen_fp": {
    "enabled": true,
    "width": 1920,
    "height": 1080,
    "color_depth": 24
}
```

---

## 16. webgpu_fp — WebGPU 指纹

覆盖 WebGPU `adapter.features`、`device.limits`、`adapter.info.vendor`、`adapter.info.architecture`，生成唯一的 WebGPU 指纹。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用 WebGPU 指纹随机化 |
| `seed` | int | ✅ | 随机种子。用于确定性地从 features 中移除一个特性，并对 limits 值做微小扰动 |
| `vendor` | string | ❌ | 覆盖 `adapter.info.vendor`。如 `"nvidia"`、`"intel"`、`"amd"`。应与 `gpu_fp.unmasked_renderer` 中的品牌一致 |
| `architecture` | string | ❌ | 覆盖 `adapter.info.architecture`。如 `"ampere"`、`"gen-12lp"` |

**生效的 JS API：**
- `adapter.features` — 特性集合（seed 决定移除哪个特性）
- `device.limits` — 限制值（seed 决定扰动量 1-3）
- `adapter.info.vendor` — GPU 品牌
- `adapter.info.architecture` — GPU 架构
- `adapter.info.subgroupMinSize` / `subgroupMaxSize` — 不修改

**随机化方式：**
- **Features**：根据 `seed % features.size()` 确定性地移除一个特性
- **Limits**：对 `maxTextureDimension2D`、`maxComputeWorkgroupSizeX`、`maxComputeInvocationsPerWorkgroup` 减去 `seed % 3 + 1`（1-3）

**示例：**
```json
"webgpu_fp": {
    "enabled": true,
    "seed": 42,
    "vendor": "nvidia",
    "architecture": "ampere"
}
```

> 💡 修改 `seed` 即可生成不同的 WebGPU 指纹。`vendor` 应与 `gpu_fp.unmasked_renderer` 中的 GPU 品牌保持一致，避免指纹矛盾。

---

## 17. voices_fp — TTS 语音指纹

覆盖 `speechSynthesis.getVoices()` 返回的语音列表，控制暴露给网页的 TTS 语音。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用语音列表覆盖 |
| `voices` | object[] | ✅ | 自定义语音列表。空数组 = 隐藏所有语音 |

### 语音对象字段

| 字段 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| `name` | string | ✅ | — | 语音名称（如 `"Microsoft David - English (United States)"`） |
| `lang` | string | ✅ | — | BCP-47 语言标签（如 `"en-US"`、`"zh-CN"`） |
| `voiceURI` | string | ❌ | 同 `name` | 唯一语音 URI。兼容旧格式 `voice_uri` |
| `localService` | bool | ❌ | `true` | `true`=本地语音，`false`=远程/网络语音。兼容旧格式 `local_service` |
| `default` | bool | ❌ | `false` | 是否为默认语音。通常只有一个 `true`。兼容旧格式 `is_default` |

> 💡 **推荐使用浏览器格式 key**（`voiceURI`、`localService`、`default`），与 `speechSynthesis.getVoices()` 返回的 JS 对象属性名一致。旧格式 key 仍兼容。

**生效的 JS API：**
- `speechSynthesis.getVoices()` — 返回配置的语音列表
- `voiceschanged` 事件 — 正常派发

**指纹数据来源：**
- `local` — 本地语音名称列表
- `remote` — 远程语音名称列表
- `languages` — 去重的语言标签
- `defaultVoiceName` / `defaultVoiceLang` — 默认本地语音

**示例：**
```json
"voices_fp": {
    "enabled": true,
    "voices": [
        {
            "name": "Microsoft David - English (United States)",
            "lang": "en-US",
            "voiceURI": "Microsoft David - English (United States)",
            "localService": true,
            "default": true
        },
        {
            "name": "Microsoft Zira - English (United States)",
            "lang": "en-US",
            "voiceURI": "Microsoft Zira - English (United States)",
            "localService": true,
            "default": false
        },
        {
            "name": "Google US English",
            "lang": "en-US",
            "voiceURI": "Google US English",
            "localService": false,
            "default": false
        }
    ]
}
```

> 💡 不同系统的 TTS 语音列表差异很大（Windows/macOS/Linux/不同语言包），是强指纹。建议与 `language_fp` 的 `languages` 保持一致。

---

## 18. geolocation_fp — 地理位置指纹

覆盖 `navigator.geolocation.getCurrentPosition()` 和 `navigator.geolocation.watchPosition()` 返回的位置。支持自定义位置和完全禁用两种模式。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用地理位置指纹覆盖 |
| `mode` | string | ✅ | 模式。`"custom"` = 返回配置的经纬度；`"disabled"` = 始终返回权限拒绝错误 |
| `latitude` | float | ✅* | 纬度（WGS84，-90 到 90）。`mode="custom"` 时必需 |
| `longitude` | float | ✅* | 经度（WGS84，-180 到 180）。`mode="custom"` 时必需 |
| `accuracy` | float | ✅* | 水平精度（米）。`mode="custom"` 时必需 |

**生效的 JS API：**
- `navigator.geolocation.getCurrentPosition(success, error, options)`
- `navigator.geolocation.watchPosition(success, error, options)`

**自定义位置模式：**
```json
"geolocation_fp": {
    "enabled": true,
    "mode": "custom",
    "latitude": 39.9042,
    "longitude": 116.4074,
    "accuracy": 100
}
```
返回北京坐标，精度 100 米。

**禁用模式：**
```json
"geolocation_fp": {
    "enabled": true,
    "mode": "disabled"
}
```
始终返回 `kPermissionDenied` 错误。

> 💡 自定义位置模式直接短路返回配置的位置，**绕过权限请求和 Mojo 服务**，不会触发浏览器权限弹窗。

---

## 19. do_not_track_fp — Do Not Track

覆盖 `navigator.doNotTrack` 和 HTTP `DNT` 请求头。
prints "1" if DNT is enabled; "0" if the user opted-in for tracking; 

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用 DNT 覆盖 |
| `value` | bool | ✅ | `true` = 启用 DNT（`navigator.doNotTrack = "1"`，发送 `DNT: 1` 头）；`false` = 禁用 DNT（`navigator.doNotTrack = null`，无 DNT 头） |

**生效的 JS API / HTTP 头：**
- `navigator.doNotTrack` — 返回 `"1"` 或 `null`
- `DNT` HTTP 请求头 — 导航 + 子资源 + Worker 请求

**覆盖方式：**
- JS API：在 `navigator_do_not_track.cc` 中直接覆盖
- HTTP 头：在 `renderer_preferences_util.cc` 中覆盖 `RendererPreferences.enable_do_not_track`，所有 4 个 HTTP 头注入点自动生效

**示例：**
```json
"do_not_track_fp": {
    "enabled": true,
    "value": true
}
```

---

## 20. cookie_fp — Cookie 注入

浏览器启动时自动注入预配置的 Cookie。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用 Cookie 注入 |
| `cookies` | object[] | ✅ | Cookie 数组，每项包含以下字段 |

### Cookie 对象字段

| 字段 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| `name` | string | ✅ | — | Cookie 名称 |
| `value` | string | ✅ | — | Cookie 值 |
| `domain` | string | ✅ | — | 域名。支持三种格式：`https://example.com`、`.example.com`、`example.com` |
| `path` | string | ❌ | `"/"` | Cookie 路径 |
| `session` | bool | ❌ | `true` | `true`=会话 Cookie（不设过期时间），`false`=持久 Cookie（1 年有效期） |
| `httpOnly` | bool | ❌ | `false` | HttpOnly 属性。`true` 时 JS 无法通过 `document.cookie` 读取 |
| `secure` | bool | ❌ | `false` | Secure 属性。`true` 时仅通过 HTTPS 传输 |
| `sameSite` | string | ❌ | 不设 | SameSite 值：`"None"` / `"Lax"` / `"Strict"` |

> 注入时机：`StoragePartitionImpl::GetCookieManagerForBrowserProcess()` 首次被调用时（即浏览器首次需要 Cookie 时）。整个浏览器生命周期只注入一次。

**生效范围：**
- `document.cookie`（JS 可读，除非 `httpOnly: true`）
- HTTP `Cookie` 请求头

**示例：**
```json
"cookie_fp": {
    "enabled": true,
    "cookies": [
        {
            "name": "session_demo",
            "value": "abc123",
            "domain": ".example.com",
            "path": "/",
            "session": true,
            "httpOnly": false,
            "secure": false,
            "sameSite": "Lax"
        },
        {
            "name": "persistent_secure",
            "value": "xyz789",
            "domain": ".example.com",
            "path": "/api",
            "session": false,
            "httpOnly": true,
            "secure": true,
            "sameSite": "None"
        }
    ]
}
```

---

## 21. cdp_fp — CDP 检测规避

规避网站通过 CDP（Chrome DevTools Protocol）相关特征检测浏览器是否被自动化/调试。包含两个反检测子功能。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用 CDP 检测规避（同时控制下面两个子功能） |

### 子功能

| 子功能 | 作用 |
|--------|------|
| 禁用 console 上报 | 阻止 `console.log()` 等 `console.*` 输出上报到 DevTools/CDP，防止通过 console 侧信道检测调试器 |
| debugger 无效化 | 使 `debugger` 语句变为 no-op（空语句），绕过反爬虫的"无限 debugger"循环 |

### 实现原理

与其他指纹模块不同，`cdp_fp` **不在渲染进程由 FingerprintManager 解析**，而是在**浏览器进程** `render_process_host_impl.cc` 中读取配置。当 `enabled=true` 时，向渲染进程追加命令行参数：

```
--js-flags=--console_output_disabled,--debugger_keyword_disabled
```

两个 V8 flag 在 V8 初始化时（flag 冻结前）生效：

- **`console_output_disabled`**：在 `v8-console.cc` 中跳过所有 `console.*` 输出的上报。
- **`debugger_keyword_disabled`**：在 `parser-base.h` 的 `ParseDebuggerStatement()` 中检测到该 flag 时，返回空语句（`EmptyStatement`）而非 `DebuggerStatement`。`debugger` 关键字语法仍然合法，但不产生断点效果。（注意：必须用 `EmptyStatement`，不能用 `NullStatement`——后者在 `Parser` 中是 `nullptr`，会被 `ParseStatementList` 误判为解析失败而中断整个语句列表。）

> 注：V8 flag 内存初始化后会被冻结，运行时调用 `SetFlagsFromString` 会崩溃，因此必须在渲染进程启动时通过 `--js-flags` 传入。

**示例：**
```json
"cdp_fp": {
    "enabled": true
}
```

**生效条件：** `enabled: true` 时两个子功能同时生效；`enabled: false`（或缺省）时完全走原生逻辑，`debugger` 与 `console.*` 行为不变。

---

## 22. tls_fp — TLS 指纹（JA3/JA4）

让 TLS `ClientHello` 的指纹（JA3/JA4）与 UA 声称的 Chrome 版本一致，避免"UA 是 Chrome X 但 TLS 指纹是 Chrome Y"的矛盾破绽。browserscan、Cloudflare 及各类指纹库都会校验 JA3/JA4。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ➖ | 是否强制指定 TLS 版本（高级用法，一般不用） |
| `chrome_version` | string | ➖ | 目标 Chrome 主版本号（如 `"154"`、`"149"`）。**留空 `""` 时自动从 `user_agent_fp.user_agent` 提取** |

### chrome_version 填什么

- **推荐：留空 `""`**（并将 `enabled` 设为 `false`，或干脆省略整个 `tls_fp`）——自动从 UA 提取 Chrome 主版本号，TLS 指纹随 UA 自动一致，无需手动维护。
- **填具体版本号（如 `"154"`）**：仅当你想让 TLS 版本与 UA **不同**时才用（一般不推荐，会造成不一致破绽）。
- **填的值必须是一个真实存在的 Chrome 主版本号**，且通常应与 UA 一致。填一个"随机/四不像"的版本组合反而会被检测。

### 版本边界（交换哪些字段）

`network_persona` 只交换不同真实 Chrome 版本间**确实不同**的字段，其余（cipher 列表与顺序、签名算法、扩展排列）严格保持原版——这正是与"随机打乱/增删 cipher"反模式的本质区别：

| 声称版本 | post-quantum key-share 组 | ALPS codepoint | ECH GREASE |
|----------|--------------------------|----------------|------------|
| `>= 131` | X25519MLKEM768 | 新 (0x44CD) | 有 |
| `124–130` | X25519Kyber768Draft00 | 旧 (0x4469) | 有 |
| `< 124` | 无 PQ 组 | 旧 (0x4469) | 有 |

> 本构建是 Chrome 154，因此：
> - 声称 **154**（或 131–153）→ 与原版**逐字节一致**（no-op，这些版本 TLS 字段相同）。
> - 声称 **124–130** → PQ 组换成 Kyber。
> - 声称 **<124** → 去掉 PQ 组。

### 实现原理

与其他指纹模块不同，`tls_fp` 作用于 **network service 进程**（`net/ssl` 所在进程），链路为：

1. **浏览器进程** `chrome_content_browser_client.cc` 构造函数：读 `fingerprint_config.json` 的 `tls_fp.chrome_version`（缺省则从 `user_agent_fp.user_agent` 提取 `Chrome/<major>`），把 `--fingerprint-tls-profile=chrome-<major>` 追加到全局命令行。
2. **switch 转发** `utility_process_host.cc` 的 `kSwitchNames[]`：把该开关转发到 network service 进程。
3. **network service** `net/ssl/network_persona.cc`：`ComputeNetworkPersona()` 解析开关，按版本边界计算 `NetworkPersonaPlan`（PQ 组模式 / ALPS / ECH）。
4. **应用** `net/socket/ssl_client_socket_impl.cc`：设置 `supported_groups`/`key_shares`、ALPS codepoint、ECH GREASE 时按 plan 交换。

> 关键：声称版本 == 构建版本（154）时 `network_persona` 判定为 inactive（no-op），TLS 保持原版——所以 UA=154 时本模块零副作用，只有伪装成其他版本时才介入。

**示例：**
```json
"tls_fp": {
    "enabled": false,
    "chrome_version": ""
}
```

**生效条件：** 只要 `user_agent_fp.enabled: true`，就会自动从 UA 提取版本并使 TLS 与 UA 一致（UA=154 时 no-op）。`tls_fp.enabled: true` + 显式 `chrome_version` 可强制覆盖（仅高级用法）。

---

## 23. tls_cipher_fp — 禁用指定 Cipher Suite

通过显式禁用指定的 TLS cipher suite，改变 TLS `ClientHello` 的 cipher list（JA3 指纹的组成部分）。**备用功能**：日常伪装 154 建议留空不用（保持原版 cipher list 最像真实 154）。

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `enabled` | bool | ✅ | 是否启用禁用 cipher 功能 |
| `disabled_ciphers` | string[] | ✅* | 要禁用的 cipher 名数组（IANA 名 `TLS_...` 或 OpenSSL 名均可） |

### disabled_ciphers 全部选项（IANA 名称，共 25 个）

**TLS 1.3（3 个）—— ⚠️ 不要禁用**（全禁会导致 TLS 1.3 无可用 cipher、握手失败；且 TLS1.3 套件各浏览器统一，无区分度）：
- `TLS_AES_128_GCM_SHA256`
- `TLS_AES_256_GCM_SHA384`
- `TLS_CHACHA20_POLY1305_SHA256`

**TLS 1.2 — ECDHE 现代 AEAD（GCM / ChaCha20，主力）：**
- `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256`
- `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`
- `TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384`
- `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`
- `TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256`
- `TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256`

**TLS 1.2 — ECDHE CBC 模式：**
- `TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256`
- `TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256`
- `TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA`
- `TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA`
- `TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA`（默认已被 `!ECDSA+SHA1` 排除）
- `TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA`（默认已被 `!ECDSA+SHA1` 排除）

**TLS 1.2 — 纯 RSA（无 PFS，较老）：**
- `TLS_RSA_WITH_AES_128_GCM_SHA256`
- `TLS_RSA_WITH_AES_256_GCM_SHA384`
- `TLS_RSA_WITH_AES_128_CBC_SHA`
- `TLS_RSA_WITH_AES_256_CBC_SHA`

**TLS 1.2 — PSK / 3DES（Chrome 默认已排除，禁用无意义）：**
- `TLS_PSK_WITH_AES_128_CBC_SHA`（默认 `!aPSK` 排除）
- `TLS_PSK_WITH_AES_256_CBC_SHA`（默认 `!aPSK` 排除）
- `TLS_ECDHE_PSK_WITH_AES_128_CBC_SHA`（默认 `!aPSK` 排除）
- `TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA`（默认 `!aPSK` 排除）
- `TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256`（默认 `!aPSK` 排除）
- `TLS_RSA_WITH_3DES_EDE_CBC_SHA`（默认 `!3DES` 排除）

> Chrome 154 实际在 ClientHello 提供的 cipher = 全部 25 个去掉默认排除的 6 个（aPSK/ECDSA+SHA1/3DES），即 **17 个**（3 个 TLS1.3 + 14 个 TLS1.2）。只有这 17 个禁用后才有实际效果。

### 用法示例

只淘汰较老的纯 RSA 套件（保持接近真实 Chrome）：
```json
"tls_cipher_fp": {
    "enabled": true,
    "disabled_ciphers": [
        "TLS_RSA_WITH_AES_128_CBC_SHA",
        "TLS_RSA_WITH_AES_256_CBC_SHA",
        "TLS_RSA_WITH_AES_128_GCM_SHA256",
        "TLS_RSA_WITH_AES_256_GCM_SHA384"
    ]
}
```

### ⚠️ 警告

1. **会产生"四不像" JA3**：真实 Chrome 的 cipher 集合是固定的。禁用 cipher 后 JA3 不再匹配任何真实浏览器，反而更易被识别。**除非能精确复刻某个真实目标的 cipher 列表，否则不要随便禁用。**
2. **不要禁用 TLS 1.3 的 3 个 cipher**（`TLS_AES_*`、`TLS_CHACHA20_*`），否则 TLS 1.3 握手失败。
3. **无需禁用 PSK / 3DES / ECDSA+SHA1**——Chrome 默认就不发送它们，禁用没有效果。
4. **cipher 名格式**：IANA 名（`TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`）或 OpenSSL 名（`ECDHE-RSA-AES128-GCM-SHA256`）均可，引擎会自动解析；未识别的名字打 `LOG(WARNING)` 跳过，不会导致握手失败。

### 实现原理

与 `tls_fp` 共用 network service 转发链路：

1. **浏览器进程** `chrome_content_browser_client.cc` 构造函数：读 `disabled_ciphers` 数组，逗号拼接后追加 `--fingerprint-tls-disable-ciphers`。
2. **switch 转发** `utility_process_host.cc` 的 `kSwitchNames[]` 到 network service。
3. **network service** `ssl_client_socket_impl.cc`：在构建 cipher command（`ALL:!aPSK:!ECDSA+SHA1:!3DES`）时，把每个名字经 `SSL_CIPHER_standard_name`/`SSL_CIPHER_get_name` 匹配解析为 OpenSSL 名，追加 `:!名称` 排除规则，最后 `SSL_set_strict_cipher_list` 生效。

**生效条件：** `enabled: true` 且 `disabled_ciphers` 非空时生效；否则（`enabled: false` 或数组为空）完全使用原版 cipher list。

---

## 24. 新增指纹的步骤

新增一个指纹模块需要修改以下文件：

### 21.1 定义配置结构体

**文件：** `src/third_party/blink/renderer/core/html/canvas/fingerprint_manager.h`

```cpp
// ============================================================
// XXX fingerprint configuration (xxx_fp in JSON)
// ============================================================
struct XxxConfig {
  bool enabled = false;
  // ... 其他字段 ...
  bool is_valid = false;
};
```

在 `FingerprintManager` 类中添加：
- getter 方法声明
- 私有成员变量 `XxxConfig xxx_config_;`

### 21.2 JSON 解析

**文件：** `src/third_party/blink/renderer/core/html/canvas/fingerprint_manager.cc`

在 `ParseJsonConfig()` 中添加：

```cpp
const base::DictValue* xxx_fp_dict = root_dict.FindDict("xxx_fp");
if (xxx_fp_dict) {
    xxx_config_.enabled = xxx_fp_dict->FindBool("enabled").value_or(false);
    // ... 解析其他字段 ...
    xxx_config_.is_valid = true;
} else {
    xxx_config_.enabled = false;
    xxx_config_.is_valid = false;
}
```

### 21.3 添加 getter 实现

在 `fingerprint_manager.cc` 末尾：

```cpp
XxxConfig FingerprintManager::GetXxxConfig() const {
  return xxx_config_;
}
```

### 21.4 在目标 API 中注入

找到覆盖目标 API 的 Blink 源码文件，在方法开头检查配置：

```cpp
#include "third_party/blink/renderer/core/html/canvas/fingerprint_manager.h"

ReturnType SomeClass::TargetMethod() {
  FingerprintManager* fp_mgr = FingerprintManager::GetInstance();
  XxxConfig config = fp_mgr->GetXxxConfig();
  if (config.enabled && config.is_valid) {
    return config.xxx_value;  // 返回覆盖值
  }
  return OriginalMethod();     // 返回真实值
}
```

### 21.5 添加配置

**文件：** `fingerprint_config.json`

```json
"xxx_fp": {
    "enabled": true,
    "xxx_value": "..."
}
```

### 21.6 添加测试

**文件：** `test_fp.html`

```javascript
function getXxxFingerprint() {
    return { value: navigator.xxx };
}

// 在 runTests() 中添加测试 Section 和 Summary 条目
```

### 21.7 编译验证

```bat
cd src && autoninja -C out\Release_7680 chrome
```

---

## 25. JWT 启动校验 HS256（已移除）

> **2026-09-19 移除**：本节原先描述的本地 JWT（HS256）启动校验已从源码树中**整体删除**，启动授权统一收敛到第 26 节的 r0 API Key lease 链路。本节保留为迁移记录，方便管理器端同步改造。

### 25.1 移除原因

本地 JWT 校验存在无法绕过的结构性缺陷，与 lease 链路对比：

| 维度 | JWT HS256（旧，已移除） | r0 lease（现行，第 26 节） |
|------|------------------------|---------------------------|
| 信任锚 | HS256 secret 硬编码在 `browser_main_loop.cc`，逆向即可提取 | 服务端 Ed25519 私钥，客户端只内置公钥 |
| 离线伪造 | 拿到 secret 可无限签发合法 token | 不可能：没有服务端私钥就构造不出能通过验签的 token |
| 吊销/限流 | 无法吊销；token 泄露后只能等 exp 自然过期 | 服务端随时拒绝 start / 停止续租，租约 TTL 秒级失效 |
| 时效控制 | exp 写死在签发时的 token 里 | lease TTL + 心跳续租，服务端动态控制 |
| 设备绑定 | 无 | install_id + instance_id + HMAC proof |

### 25.2 已删除内容清单

| 项 | 处置 |
|----|------|
| `src/chrome/browser/jwt_license/`（`jwt_license_monitor.cc` / `.h`） | 已删除（`cross/01-clearcote-base.patch` 中体现为删除 diff） |
| `content/browser/browser_main_loop.cc` 中的 `VerifyStartupJwt()` 及其调用 | 已删除 |
| `--validate=<JWT>` 启动参数 | 不再支持；传入不会报错，但无任何作用 |
| 源码树根目录 `gen_jwt.py` 签发脚本 | 已删除 |
| BUILD.gn 中 jwt_license 相关 sources | 已删除 |

### 25.3 管理器 / 启动脚本迁移要点

1. **删除所有 `--validate=<token>` 传参**：已无任何作用。
2. **改为传 `--r0-api-key=<key>`（或给子进程设置环境变量 `R0_API_KEY`）**，链路详见 26.1。
3. **失败退出语义**：仍是退出码 1 + stderr 日志，但日志前缀变为 `[r0_license]`，诊断格式见 26.4 / 26.5。
4. **不要在管理器里缓存/复用 token**：lease token 与 install_id / instance_id 绑定且短时效，无法跨进程复用（职责划分见 26.10）。

---

## 26. r0 API Key 启动授权（lease 链路）

本源码树**唯一的启动授权机制**是接入在线授权服务 `https://api.r0browser.com`（旧的本地 JWT HS256 校验已于 2026-09-19 移除，迁移记录见第 25 节）：浏览器启动时必须携带 `--r0-api-key=<key>`，向服务端申请一个租约（lease），拿到 Ed25519 签名的 `token` 并完成验签后才能进入正常浏览流程；之后还要按服务端下发的 `heartbeat_interval_seconds` 周期续租。本节记录调试过程中踩到的坑和最终验证流程。

### 26.1 链路时序

```
启动 → 加载/创建 install_id（DPAPI）→ 生成 instance_id → POST /start
        → 200 {"valid":true, "token":..., "lease_id":..., "heartbeat_interval_seconds":10, "lease_ttl_seconds":30}
        → 用内置公钥验证 Ed25519 token 签名（包含安装/实例 ID + 序列 + nonce + HMAC proof）
        → 按心跳间隔 POST /alive（带 sequence+nonce+proof）→ 续租
        → 关闭时 POST /end（best-effort）
```

任何一步失败（含 API key 为空、被服务端 400 拒绝、Ed25519 验签不通过、心跳超时）都会 `HandleFatal` 终止浏览器。

### 26.2 ⚠️ 三个最容易踩的坑

#### 坑 1：API Key 在序列化前被清空（关键 bug，✅ 已修复）

> ✅ **2026-09-19 已修复**，落在 `patchsets/154/cross/02-r0-license-start-hardening.patch`（同补丁还包含坑 2 修复与 26.4 诊断日志）。以下为问题记录与修复说明。

`chrome/browser/r0_license/r0_license_monitor.cc` 的 `Start()` 早期版本有：

```cpp
// ① 派生 api_key_hash_
api_key_hash_ = Sha256Hex(api_key_);
// ...（其他初始化）...
// ② ⚠️ 提前清空 api_key_
OPENSSL_cleanse(...); api_key_.clear();
// ③ 才调用 StartLease() → 用 api_key_ 构造请求体
StartLease();   // 此时 dict.Set("api_key", api_key_) 实际是空串
```

服务端的 `start` 校验会判 `api_key` 非空 → 返回 400 `{"error":"输入格式无效，请检查必填字段、长度和数值范围"}`。但 Chromium 里 `SetAllowHttpErrorResults(false)` 把 4xx 也算作"网络错误"，回调 `optional<string>` 为空 → 进了 3 次重试 → 仍是 400 → 最终报**"temporarily unavailable; the API key was not rejected"**（误报，不告诉你真相）。

**修复**：把清空移到 `OnStartResponse` 收到响应体之后（确保该路径不再重发 start）：

```cpp
// r0_license_monitor.cc
void R0LicenseMonitor::Start() {
  // ... 加载 install_id、生成 instance_id ...
  // （删掉原来在这里的 OPENSSL_cleanse/api_key_.clear）
  StartLease();
}

void R0LicenseMonitor::OnStartResponse(std::optional<std<string>> body) {
  // ... 日志诊断、active_loader_.reset() ...
  if (!body || http_status == 408 || http_status == 429 || http_status >= 500) {
    // 短暂错误才重试
    ...（原有重试逻辑）...
  }
  if (http_status >= 400) { HandleFatal("rejected HTTP " + ...); return; }
  start_retries_ = 0;

  // 关键：响应到达、不会再重发 start，安全清空
  if (!api_key_.empty()) {
    OPENSSL_cleanse(const_cast<char*>(api_key_.data()), api_key_.size());
    api_key_.clear();
  }
  // ...后续：size 检查 → JSON 解析 → 验签 → 进入 alive 循环...
}
```

#### 坑 2：HTTP 状态码语义错乱

原版把所有非 2xx（包含 4xx 拒绝 + 5xx 瞬时错误 + 网络错误）统一丢到"重试 + 暂时不可用"分支。问题：

- 服务端 4xx 拒绝（如 key 无效）应**立即 fatal**，不要重试；
- 5xx / 408 / 429 应**短暂重试**，符合 RFC 7231；
- 改了 `SetAllowHttpErrorResults(false) → true` 之后，4xx/5xx 都能拿到响应体，要按状态码分流。

最终重写后的判定：

```cpp
if (!body || http_status == 408 || http_status == 429 || http_status >= 500) {
  // 短暂错误 → 重试 kMaxStartRetries 次
} else if (http_status >= 400) {
  // 4xx 拒绝 → 直接 fatal（带状态码）
} else {
  // 2xx → 正常流程
}
```

#### 坑 3：安装身份文件格式与 demo 不兼容

两套实现用同一路径 `%LOCALAPPDATA%\R0Browser\install-id-v2.dat`，但**写入格式互不兼容**：

| | demo（`install_identity.cpp`） | Chromium（`install_identity_win.cc`） |
|---|---|---|
| 文件布局 | 8 字节魔数 `R0ID\x02\0\0\0` + DPAPI 密文 | 整文件即裸 DPAPI 密文 |
| DPAPI entropy | `L"r0browser-auth-shell-install-id-v2"` | 无（`nullptr`） |

后果：谁先启动谁写入对应格式，**对方读时就报**`CryptUnprotectData failed: 数据无效 (0xD)` → 弹窗"安装身份损坏，拒绝静默生成新身份"。解法见 26.3。

### 26.3 安装身份文件兼容

**方案 A（最快）**：跑谁就删一次

```powershell
Remove-Item "$env:LOCALAPPDATA\R0Browser\install-id-v2.dat" -Force
```

然后让目标程序先启动，自己生成自己的格式。

**方案 B（一劳永逸，✅ 2026-09-19 已实现）**：把 Chromium 的 `install_identity_win.cc` 改成 demo 的格式（魔数 + entropy），双向都能读。已落在 `patchsets/154/windows/02-install-identity-shared-v2-container.patch`：写入用 v2 容器；读取兼容 v2 容器与旧 Chromium 裸 DPAPI 格式，旧格式自动迁移重写。apply 后**无需再删身份文件**，demo 与 Chromium 共用同一 `install-id-v2.dat`。

### 26.4 诊断日志模板

> ✅ **2026-09-19 已实现**（`patchsets/154/cross/02-r0-license-start-hardening.patch`）。与下述模板的差异：① 成功路径**不打印 body**——里面含 lease secret，防止敏感信息进日志；② 实际新增的 include 是 `net/base/net_errors.h` 与 `services/network/public/mojom/url_response_head.mojom.h`（`StringPrintf` 原本已有，无需 `string_number_conversions.h`）。

修 bug 之前必须能**看到**服务端究竟回了什么。原版 `!body` 既覆盖网络错误又覆盖 4xx/5xx（`SetAllowHttpErrorResults(false)`），又没打印 net_error / http_status / body，所以"temporarily unavailable"是个黑盒。建议在 `OnStartResponse` 最开头加：

```cpp
void R0LicenseMonitor::OnStartResponse(std::optional<std::string> body) {
  int http_status = 0;
  if (active_loader_) {
    const int net_error = active_loader_->NetError();
    const network::mojom::URLResponseHead* head =
        active_loader_->ResponseInfo();
    if (head && head->headers) {
      http_status = head->headers->response_code();
    }
    LOG(ERROR) << "[r0_license] start diagnostics: net_error=" << net_error
               << " http_status=" << http_status << " body="
               << (body ? *body : std::string("<null>"));
  }
  active_loader_.reset();
  if (closing_) return;
  // ...后续判定用上面的 http_status...
}
```

并把 start 请求的 `SetAllowHttpErrorResults(false)` 改为 `true`，这样 4xx/5xx 也能拿到 body。需要在文件头补两个 include：

```cpp
#include "net/base/net_errors.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
```

### 26.5 端到端验证流程

**步骤 1：先验证 API Key 本身有效**（绕开浏览器，5 秒搞定）

用 `r0browser-auth-shell` demo（`f:\chromium\chromium154\r0browser-auth-client-demo-source-20260916-220814\r0browser-auth-client-demo-source-20260916-215945\`）作为验证客户端：

```powershell
$env:Path = "E:\CodingTools\Visual Studio 2022\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;" + $env:Path
cd f:\chromium\chromium154\r0browser-auth-client-demo-source-20260916-220814\r0browser-auth-client-demo-source-20260916-215945
.\build-production.ps1
$env:R0_API_KEY = 'R0AK-XXXX-XXXX-...'
.\build-production\Release\r0browser-auth-shell.exe
Remove-Item Env:R0_API_KEY
```

- 窗口标题变 `R0 Browser (licensed)` → API Key + 服务端 + token 验签全部 OK
- 报"安装身份损坏"→ 删 `%LOCALAPPDATA%\R0Browser\install-id-v2.dat` 再试

**步骤 2：先用 curl/PS 排除网络和 JSON 内容**（避免直接上 Chromium）

```powershell
curl.exe --http1.1 -X POST "https://api.r0browser.com/api/v1/client/api-key-leases/start" `
  -H "Content-Type: application/json" `
  --data "@body.json"   # body 用文件传，避开 PS 引号转义
```

服务器 ALPN 只提供 `http/1.1`（`node tls.connect` 验证过），ALPN 协商结果不是 HTTP/2。可放心用 `http/1.1` 测试。

**步骤 3：再上 Chromium**

身份文件兼容（坑 3）已由方案 B 解决（`windows/02` 补丁）：Chromium 读写 v2 容器并把旧格式自动迁移，demo 与 Chromium 共用同一文件，**无需手动删除**。

```powershell
# 仅在未打 windows/02 补丁的旧构建上遇到身份损坏时，才需要手动删除：
# Remove-Item "$env:LOCALAPPDATA\R0Browser\install-id-v2.dat" -Force

f:\chromium\chromium154\src\out\Release\chrome.exe `
  --no-sandbox --disable-gpu `
  --user-data-dir=f:\chromium\chromium154\test_profile `
  --enable-logging=stderr --v=0 `
  --r0-api-key=R0AK-XXXX-... `
  --no-first-run about:blank
```

观察 stderr：

| 现象 | 含义 |
|------|------|
| `[r0_license] start diagnostics: ... http_status=200 body={"valid":true,...}` | start 成功，进入 alive 循环 |
| `[r0_license] start diagnostics: ... http_status=400 body={"error":"输入格式无效..."}` | 发了空 api_key（坑 1）或身份不匹配，看 26.2 |
| `[r0_license] FATAL: install identity file is corrupted or unreadable` | 身份文件格式不兼容（坑 3）|
| `[r0_license] FATAL: the authorization service is temporarily unavailable; the API key was not rejected` | 网络错误或 5xx 超过重试次数 |
| `[r0_license] FATAL: the authorization service rejected the start request (HTTP 4xx)` | 4xx 一次性拒绝（key 无效等） |
| 进程持续存活超过 `lease_ttl_seconds`（默认 30s） | alive 心跳正常 |

### 26.6 调试时 / curl 看输出的注意事项

- PowerShell 5.1 把 JSON 传给原生 exe 时**引号会丢失/转义错乱**，导致服务端收到无效 JSON → 400。务必用 `--data "@file.json"` 或 `Invoke-RestMethod -InFile`。
- 服务端响应是中文：`{"error":"输入格式无效，请检查必填字段、长度和数值范围"}` —— 这是**应用层字段校验**（非网络层），说明 body 解析成功但字段值不合规。
- TLS 握手是正常的，不要去查证书 / 代理 / WAF——服务端把请求**正常处理完了**，是字段被拒。

### 26.7 改动文件清单（修 Chromium 端 r0_license 的最小集）

| 文件 | 改动 |
|------|------|
| `chrome/browser/r0_license/r0_license_monitor.cc` | ① 删除 `Start()` 中 `OPENSSL_cleanse` + `api_key_.clear()`；② `StartLease()` 把 `SetAllowHttpErrorResults(false)` 改为 `true`；③ `OnStartResponse` 开头加诊断日志（成功路径不打印 body）；④ 判定改为按 net_error/http_status 分流；⑤ 在收到响应体后安全清空 api_key_；⑥ 顶部加 `#include "net/base/net_errors.h"` 和 `#include "services/network/public/mojom/url_response_head.mojom.h"`（✅ 全部已落在 `patchsets/154/cross/02-r0-license-start-hardening.patch`） |
| `chrome/browser/r0_license/install_identity_win.cc` | （方案 B，✅ 已落在 `patchsets/154/windows/02-install-identity-shared-v2-container.patch`）写入 = 8 字节魔数 `R0ID\x02\0\0\0` + entropy `L"r0browser-auth-shell-install-id-v2"` 的 DPAPI；读取兼容 v2 容器与旧裸 DPAPI 格式，旧格式自动迁移重写 |

只动 1~2 个文件，增量编译约 60 秒（`autoninja -C out/Release chrome`）。

### 26.8 跨平台移植（macOS / Linux）

#### 26.8.1 文件分布清点

`r0_license/` 目录共 8 个文件，**只有 2 个是 Windows 专属**，其余都是平台无关的：

| 文件 | 平台 | 说明 |
|------|------|------|
| `auth_build_config.h` | 跨平台 | 仅定义平台字符串宏，需要按平台差异化 |
| `auth_security.cc` / `.h` | 跨平台 | 仅用 BoringSSL（`SHA256` / `HMAC` / `ED25519` / `base64url`） |
| `heartbeat_schedule.h` | 跨平台 | 纯算法头文件 |
| `install_identity.h` | 跨平台 | 仅声明 `LoadOrCreateInstallId()` 接口 |
| **`install_identity_win.cc`** | **仅 Windows** | `CryptProtectData` / `CryptUnprotectData`（DPAPI） |
| `r0_license_monitor.cc` / `.h` | 跨平台 | 只用 `services/network` + `base/json` + `base/timer` |

`chrome/browser/chrome_browser_main.cc` 里的 `Start()` / `Shutdown()` 调用也是平台无关的。

**结论：6/8 文件可直接同步，只需新增 2 个平台实现。**

#### 26.8.2 需要新增的文件

| 文件 | 大小估计 | 依赖 API |
|------|---------|----------|
| `chrome/browser/r0_license/install_identity_mac.cc` | ~110 行 | Keychain Services（`SecKeychainAddGenericPassword` / `SecKeychainFindGenericPassword`，或新版 `SecItemAdd` / `SecItemCopyMatching` over Data Protection） |
| `chrome/browser/r0_license/install_identity_linux.cc` | ~90 行 | 不依赖额外库：`XDG_DATA_HOME`/回退 `~/.local/share` + `base::PathService::Get(base::DIR_HOME)` + 文件 mode 0600 |

> 不推荐 Linux 上接 libsecret/`secret-tool`：会引入 `libsecret-1-dev` / `dbus` 依赖，远比一个 mode 0600 的 JSON 文件重。

#### 26.8.3 `BUILD.gn` 改造模板

把当前的：

```gn
sources += [
  ...
  "r0_license/auth_security.cc",
  "r0_license/auth_security.h",
  "r0_license/heartbeat_schedule.h",
  "r0_license/install_identity.h",
  "r0_license/install_identity_win.cc",
  "r0_license/r0_license_monitor.cc",
  "r0_license/r0_license_monitor.h",
  ...
]
```

改为：

```gn
sources += [
  ...
  "r0_license/auth_security.cc",
  "r0_license/auth_security.h",
  "r0_license/heartbeat_schedule.h",
  "r0_license/install_identity.h",
  "r0_license/r0_license_monitor.cc",
  "r0_license/r0_license_monitor.h",
  ...
]

# ★ Fingerprint: r0_license install_identity 平台分流
sources += [ "r0_license/install_identity_mac.cc" ]    # 默认 mac
sources += [ "r0_license/install_identity_linux.cc" ]  # 默认 linux
if (is_win) {
  sources -= [ "r0_license/install_identity_mac.cc" ]
  sources -= [ "r0_license/install_identity_linux.cc" ]
  sources += [ "r0_license/install_identity_win.cc" ]
}
```

> 警告不要在 macOS 下把 `install_identity_mac.cc` 命名为 `.mm`：本文件不调用 Objective-C / Cocoa，纯 C++ + Keychain C API，`.cc` 即可，避免引入 `objc` 链接依赖并让 patch 简洁。Chrome 内的 `os_crypt_mac.mm` 因为用了 `NSString` 才必须 `.mm`，本场景没必要。

把 `patches/900-windows-build-fixes.patch` 中 `crypt32.lib` 那一段留在 `is_win` 块内即可；不要搬到公共区。

#### 26.8.4 `auth_build_config.h` 平台字符串化

当前硬编码：

```cpp
#define R0_AUTH_PLATFORM "windows-x64"
#define R0_AUTH_CLIENT_VERSION "r0-chromium-154-1.0.0"
```

改为按 `BUILDFLAG` 切换：

```cpp
#include "build/build_config.h"

#if BUILDFLAG(IS_WIN)
#define R0_AUTH_PLATFORM "windows-x64"
#elif BUILDFLAG(IS_MAC)
#if defined(ARCH_CPU_ARM64)
#define R0_AUTH_PLATFORM "macos-arm64"
#else
#define R0_AUTH_PLATFORM "macos-x64"
#endif
#elif BUILDFLAG(IS_LINUX)
#define R0_AUTH_PLATFORM "linux-x64"
#else
#define R0_AUTH_PLATFORM "unknown"
#endif

#define R0_AUTH_CLIENT_VERSION "r0-chromium-154-1.0.0"
```

`build/build_config.h` 是 Chromium 自身的标准头，可直接 include。

#### 26.8.5 macOS Keychain 实现骨架（复制即用）

```cpp
// chrome/browser/r0_license/install_identity_mac.cc
#include "chrome/browser/r0_license/install_identity.h"

#include <Security/Security.h>

#include <CoreFoundation/CoreFoundation.h>
#include <string>

#include "base/apple/scoped_cftyperef.h"
#include "base/files/file_path.h"
#include "base/logging.h"
#include "base/uuid.h"

namespace r0_license {
namespace {

constexpr char kServiceName[] = "R0Browser";
constexpr char kAccountName[] = "install-id-v2";

bool LooksLikeCanonicalUuid(const std::string& s) { /* 同 win */ }

bool LoadFromKeychain(std::string* out) {
  NSDictionary* query = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : [NSString stringWithUTF8String:kServiceName],
    (__bridge id)kSecAttrAccount : [NSString stringWithUTF8String:kAccountName],
    (__bridge id)kSecReturnData : @YES,
    (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitOne,
  };
  CFTypeRef result = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
  if (status != errSecSuccess || result == NULL) return false;
  NSData* data = (__bridge_transfer NSData*)result;
  *out = std::string(reinterpret_cast<const char*>(data.bytes), data.length);
  return LooksLikeCanonicalUuid(*out);
}

bool SaveToKeychain(const std::string& plaintext) {
  NSDictionary* delete_query = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : [NSString stringWithUTF8String:kServiceName],
    (__bridge id)kSecAttrAccount : [NSString stringWithUTF8String:kAccountName],
  };
  SecItemDelete((__bridge CFDictionaryRef)delete_query);

  NSDictionary* add_query = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : [NSString stringWithUTF8String:kServiceName],
    (__bridge id)kSecAttrAccount : [NSString stringWithUTF8String:kAccountName],
    (__bridge id)kSecValueData : [NSData dataWithBytes:plaintext.data()
                                              length:plaintext.size()],
    (__bridge id)kSecAttrAccessible :
        (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
  };
  OSStatus status = SecItemAdd((__bridge CFDictionaryRef)add_query, NULL);
  return status == errSecSuccess;
}

}  // namespace

bool LoadOrCreateInstallId(std::string* install_id, std::string* error) {
  std::string existing;
  if (LoadFromKeychain(&existing)) {
    *install_id = existing;
    return true;
  }
  base::Uuid uuid = base::Uuid::GenerateRandomV4();
  std::string plaintext = uuid.AsLowercaseString();
  if (!SaveToKeychain(plaintext)) {
    if (error) *error = "unable to persist new install identity to Keychain";
    return false;
  }
  *install_id = plaintext;
  return true;
}

}  // namespace r0_license
```

> 该实现需要在 `chrome/browser/BUILD.gn` 公共 deps 里加 `//base/apple`，以及在 macOS `libs` 块加 `"-framework Security"`、`"-framework CoreFoundation"`。

#### 26.8.6 Linux 文件持久化实现骨架（无需 libsecret）

```cpp
// chrome/browser/r0_license/install_identity_linux.cc
#include "chrome/browser/r0_license/install_identity.h"

#include <sys/stat.h>

#include <string>

#include "base/base64.h"
#include "base/files/file.h"
#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/logging.h"
#include "base/path_service.h"
#include "base/uuid.h"

namespace r0_license {
namespace {

constexpr char kIdentityDirectory[] = "r0browser";
constexpr char kIdentityFileBasename[] = "install-id-v2.dat";

bool LooksLikeCanonicalUuid(const std::string& s) { /* 同 win */ }

base::FilePath IdentityFilePath() {
  base::FilePath data_home;
  if (base::PathService::Get(base::DIR_HOME, &data_home)) {
    return data_home.Append(".local/share")
        .AppendASCII(kIdentityDirectory)
        .AppendASCII(kIdentityFileBasename);
  }
  return {};
}

}  // namespace

bool LoadOrCreateInstallId(std::string* install_id, std::string* error) {
  base::FilePath path = IdentityFilePath();
  if (path.empty()) {
    if (error) *error = "unable to resolve HOME directory";
    return false;
  }
  if (base::PathExists(path)) {
    std::string contents;
    if (!base::ReadFileToString(path, &contents)) {
      if (error) *error = "install identity file is unreadable";
      return false;
    }
    if (!LooksLikeCanonicalUuid(contents)) {
      if (error) *error = "install identity file has unexpected format";
      return false;
    }
    *install_id = contents;
    return true;
  }
  base::Uuid uuid = base::Uuid::GenerateRandomV4();
  std::string plaintext = uuid.AsLowercaseString();
  if (!base::CreateDirectory(path.DirName())) {
    if (error) *error = "unable to create identity directory";
    return false;
  }
  if (!base::WriteFile(path, plaintext)) {
    if (error) *error = "unable to persist new install identity";
    return false;
  }
  // 0600：仅本用户可读写。
  chmod(path.value().c_str(), S_IRUSR | S_IWUSR);
  *install_id = plaintext;
  return true;
}

}  // namespace r0_license
```

> 注意 Linux 版**没有机密性**：DPAPI / Keychain 提供的是"本机绑定"，Linux 用文件 mode 仅能挡住其他用户。如需提升到 Linux 上的同等保护，可加一层"用 `getuid` + 安装时随机 salt XOR 字符串"的混淆；这超出了当前 Windows 端的能力对比，保持原方案即可。

#### 26.8.7 跨平台一致性

是「跨平台共享同一份 install-id-v2.dat」。本次服务端已验证：

| 端 | 存储位置 | 推荐方案 |
|----|----------|----------|
| Windows | `%LOCALAPPDATA%\R0Browser\install-id-v2.dat`（DPAPI） | 现有 |
| macOS | Keychain (`kSecClassGenericPassword`) | 26.8.5 |
| Linux | `~/.local/share/r0browser/install-id-v2.dat` (mode 0600) | 26.8.6 |
| demo 客户端 | `%LOCALAPPDATA%\R0Browser\install-id-v2.dat`（DPAPI+entropy+魔数） | 现有 |

> 注意 demo 客户端**只跑在 Windows**，不需同步其他端；Windows 端 Chromium 与 demo 的兼容性参见 26.3。

#### 26.8.8 端到端跨平台验证清单

1. macOS / Linux 端 `autoninja -C out/Default chrome` 无新增错误；
2. macOS 端：`security find-generic-password -s "R0Browser" -a "install-id-v2" -w` 能输出 UUID；
3. Linux 端：`ls -la ~/.local/share/r0browser/install-id-v2.dat` 显示 `-rw-------`；
4. 用 `--r0-api-key=<key>` 启动，sterr 出现 `[r0_license] start diagnostics: ... http_status=200 body={"valid":true,...}`；
5. macOS 端 Keychain 解锁后能保留 install_id，重启浏览器仍是同一 ID；
6. Linux 端跨用户切换后新生成（因原文件不可读）。

### 26.9 三端 patch 分层与同步流程

#### 26.9.1 现状与痛点

`patchsets/154/000-clearcote-154-all.patch` 是一个**单文件全量 patch**（83 KiB / 12 文件 / 32 个 git commit 串联）。它在 Windows 上能做到「`git apply` 一次 + `autoninja`」。

但当 `install_identity_mac.cc` / `install_identity_linux.cc` 各自落地后：

- **BUILD.gn** 必须在 `is_win` / `is_mac` / `is_linux` 分支里挂不同的源文件——一段 patch 文本无法同时在三端的 BUILD.gn 上正确 apply。
- **`auth_build_config.h`** 的 `R0_AUTH_PLATFORM` 宏要按平台取值——同上。
- **未来的 fingerprint 改动**如果同时改了三端，单 patch 三套 `+++`/`---` 段会互相冲突。

**所以结论是：单 patch 一键 apply 不再可取，正确的做法是「按平台分层 + 一键脚本调度」。**

#### 26.9.2 新的 patchsets 目录结构

```
patchsets/154/
├── UPSTREAM_REVISION                       # 325cea974198c8a6ecd931598856c0a63ec8c230
├── README.md                               # 重写说明
├── series                                  # 改成 quilt 风格：跨平台 + 当前平台分支
├── apply.sh                                # Linux/macOS 平台自动调度
├── apply.ps1                               # Windows 调度
│
├── cross/                                  # ★ 三端都要 apply 的部分
│   ├── 00-clearcote-base.patch             # 把原 32 个 fingerprint patch 顺序串联
│   ├── 01-r0_license-common.patch          # r0_license 6 个跨平台文件 + chrome_browser_main.cc
│   └── 02-build-gn-base.patch              # BUILD.gn 里把 install_identity 改为按 is_xxx 分支
│
├── windows/                                # ★ 只在 Windows 上 apply
│   ├── 03-install-identity-win.patch
│   ├── 04-build-gn-win.patch               # 在 is_win 块加 crypt32.lib
│   └── 05-build-config-win.patch           # auth_build_config.h 的 windows-x64 段
│
├── mac/
│   ├── 03-install-identity-mac.patch
│   ├── 04-build-gn-mac.patch               # 在 is_mac 块加 Security framework + base/apple dep
│   └── 05-build-config-mac.patch           # macos-arm64 / macos-x64 段
│
└── linux/
    ├── 03-install-identity-linux.patch
    ├── 04-build-gn-linux.patch             # is_linux 块无额外链接（base:: 足够）
    └── 05-build-config-linux.patch         # linux-x64 段
```

每个子目录下的 patch 都用 `git format-patch -1 <sha>` 风格，**互不重叠**。

#### 26.9.3 series 文件与平台过滤

`series` 不再是单平台列表，改成**「跨平台 + 当前平台分支」**，并提供 `series.linux` / `series.mac` / `series.windows`：

```
# patchsets/154/series.linux
cross/00-clearcote-base.patch
cross/01-r0_license-common.patch
cross/02-build-gn-base.patch
linux/03-install-identity-linux.patch
linux/04-build-gn-linux.patch
linux/05-build-config-linux.patch
900-windows-build-fixes.patch        # 用于 Linux 交叉编译 Windows 版本时
905-rc-invoked-guard.patch
```

Windows 与 mac 的 `series.windows` / `series.mac` 类同。

#### 26.9.4 一键 apply 脚本

**Linux / macOS (`apply.sh`)**：

```bash
#!/usr/bin/env bash
# patchsets/154/apply.sh — 按当前平台选合适 patch 子集
set -euo pipefail

CHROMIUM_SRC="${CHROMIUM_SRC:-${1:-../src}}"
PATCHSET_DIR="$(cd "$(dirname "$0")" && pwd)"

case "$(uname -s)" in
    Linux*)   PLATFORM=linux   ;;
    Darwin*)  PLATFORM=mac     ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM=windows ;;
    *)        echo "Unknown OS: $(uname -s)" >&2; exit 1 ;;
esac
echo "[apply.sh] platform=$PLATFORM"

cd "$CHROMIUM_SRC"
[[ -d .git ]] || { echo "must be inside a git checkout" >&2; exit 1; }

# 1. 跨平台层（强制）
for f in "$PATCHSET_DIR"/cross/*.patch; do
    echo "[apply] $f"
    git apply --check "$f" || { echo "FAILED on $f" >&2; exit 1; }
    git apply "$f"
done

# 2. 平台分支
for f in "$PATCHSET_DIR/$PLATFORM"/*.patch; do
    echo "[apply] $f"
    git apply --check "$f" || { echo "FAILED on $f" >&2; exit 1; }
    git apply "$f"
done

# 3. 构建修复（仅 Windows / Linux 交叉编译需要）
if [[ "$PLATFORM" != "mac" ]]; then
    for f in "$PATCHSET_DIR/900-windows-build-fixes.patch" \
             "$PATCHSET_DIR/905-rc-invoked-guard.patch"; do
        [[ -f "$f" ]] || continue
        echo "[apply] $f"
        git apply --check "$f" || { echo "FAILED on $f" >&2; exit 1; }
        git apply "$f"
    done
fi

echo "[apply.sh] done"
```

**Windows (`apply.ps1`)**：

```powershell
# patchsets/154/apply.ps1
$ErrorActionPreference = 'Stop'
$ChromiumSrc = if ($env:CHROMIUM_SRC) { $env:CHROMIUM_SRC } else { '..\src' }
$PatchsetDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Platform = 'windows'

Push-Location $ChromiumSrc
try {
    Get-ChildItem "$PatchsetDir\cross\*.patch" | ForEach-Object {
        Write-Host "[apply] $($_.Name)"
        git apply --check $_.FullName
        git apply $_.FullName
    }
    Get-ChildItem "$PatchsetDir\$Platform\*.patch" | ForEach-Object {
        Write-Host "[apply] $($_.Name)"
        git apply --check $_.FullName
        git apply $_.FullName
    }
    Get-ChildItem "$PatchsetDir\90[05]-*.patch" | ForEach-Object {
        Write-Host "[apply] $($_.Name)"
        git apply --check $_.FullName
        git apply $_.FullName
    }
    Write-Host "[apply.ps1] done"
} finally {
    Pop-Location
}
```

调用方式：

```bash
# Linux / macOS
cd patchsets/154 && ./apply.sh /absolute/path/to/chromium154/src

# Windows
cd patchsets\154 && .\apply.ps1
```

#### 26.9.5 新 fingerprint 改动如何三端同步

按改动的「平台相关性」分类，按表放到对应目录：

| 改动性质 | 放在哪 | 是否需在所有端 commit | 未来 apply 次数 |
|---------|--------|---------------------|----------------|
| 全新 fingerprint 表面（与平台无关） | `cross/0x-*.patch` 或追加到 `00-clearcote-base.patch` | **是**（三端代码完全相同） | 三端都 apply 一次 |
| BUILD.gn 的公共 deps（如新增 base 组件） | `cross/02-build-gn-base.patch` | **是** | 三端都 apply 一次 |
| BUILD.gn 的平台 libs（如新增 macOS framework） | `mac/04-build-gn-mac.patch` | 仅 macOS | 仅 mac apply |
| `auth_build_config.h` 的平台宏 | 对应平台目录 `05-build-config-*.patch` | 仅该平台 | 仅该端 apply |
| Windows-only 构建/链接修复 | `windows/0x-*.patch` 或 `900-*.patch` 系列 | 仅 Windows | 仅 Windows apply |
| macOS-only 构建/链接修复 | `mac/0x-*.patch` 或新建 `901-mac-build-fixes.patch` 系列 | 仅 macOS | 仅 mac apply |
| Linux-only 构建/链接修复 | `linux/0x-*.patch` 或新建 `902-linux-build-fixes.patch` 系列 | 仅 Linux | 仅 Linux apply |

#### 26.9.6 跨端 patch 同步的工作流（实操步骤）

例：新增一个 fingerprint 表面（完全跨平台）。

```bash
# 1. 在某个端（哪个都行，建议 Linux/macOS 编译快）的 src 上做改动并 commit。
cd $CHROMIUM_SRC
git checkout -b feature/new-fingerprint-surface
# ... 改若干文件 + git add + git commit -m "fingerprint: xxx" ...

# 2. 在另外两端同样 checkout 该 commit 或 cherry-pick，让三端 mirror 一致。
git log -1 --format='%H'    # 拿到 sha
# 在 macOS、Linux 的 src 中 git cherry-pick <sha>

# 3. 导出为 git format-patch。
git format-patch -1 <sha> -o /tmp/

# 4. 放到 patchsets/154/cross/ 下：
#    - 若需要保持分片，命名 cross/0X-new-fingerprint-surface.patch
#    - 或追加到 cross/00-clearcote-base.patch 的对应 hunk（罕见）
mv /tmp/00*.patch ../patchsets/154/cross/0X-new-fingerprint-surface.patch

# 5. 验证三端都能 apply：
for PLAT in linux mac windows; do
    bash patchsets/154/apply.sh $CHROMIUM_SRC --dry-run-platform=$PLAT
done

# 6. 重新生成 000-clearcote-154-all.patch（可选，仅作 snapshot）：
git checkout main
bash patchsets/154/apply.sh $CHROMIUM_SRC
git diff > patchsets/154/000-clearcote-154-all.patch
```

#### 26.9.7 跨端冲突的预防

- **BUILD.gn 的 hunk 必须拆分到三个 patch**：`cross/02-build-gn-base.patch` 改公共 `sources +=`，`windows/04-build-gn-win.patch`、`mac/04-build-gn-mac.patch`、`linux/04-build-gn-linux.patch` 各自只在 `is_xxx` 块内追加。
- **不要在跨平台 patch 里改平台分支文本**——否则三端中两端的 BUILD.gn 会看到「这个 hunk 我不需要」的文本，反而被 `git apply` 当作无关 hunks 报告 noise。
- **`auth_build_config.h` 必须只生成 3 个独立的 hunk**（每个 patch 改各自平台的 `#elif BUILDFLAG` 段），不要做"统一改 1 个 hunk"。

#### 26.9.8 升级到 Chromium 155+ 的迁移

新版本号下**重新建立** `patchsets/155/`，把 `cross/` 内容**整目录复制**过去，再针对新 HEAD 重新生成各端专属 patch：

```bash
cp -r patchsets/154/{cross,windows,mac,linux} patchsets/155/
sed -i 's/325cea974198c8a6ecd931598856c0a63ec8c230/<new-sha>/' \
    patchsets/155/UPSTREAM_REVISION

cd patchsets/155
# 让各端在新 HEAD 上重新生成
for d in cross windows mac linux; do
    echo "==> rebase $d on new HEAD in each platform checkout"
done
```

每个端在自己的 chromium-src checkout 里：
1. checkout new sha
2. 按 `cross/` 内容打 git apply（**应当全部通过，因为 cross/ 已经是平台无关**）
3. 把已 working 的端专属 patch 重新用 `git diff` 抓出来，覆盖原文件

#### 26.9.9 关键经验

- **不要图省事维护一份大 patch**：跨端开发时同步成本远高于分片收益。
- **每个 patch 文件 < 200 行**：单端 review < 5 分钟，跨端三方 diff 对比 < 1 分钟。
- **`git apply --check` 是必须的**：分片后单 patch 之间可能会有上下文依赖，一次 `--check` 失败说明前序 patch 没打上。
- **`git format-patch` 输出天然支持拆片**：永远不要 `diff -ruN > xxx.patch`，否则重构困难。
- **新平台（如 ChromeOS、Android）时**：直接 `mkdir patchsets/154/<新平台>` + 复用 `cross/` + 新平台专属 3 个 patch 即可，老平台完全不动。

### 26.10 管理器与内核的授权职责划分（推荐架构）

**结论：授权校验的唯一权威位置在 Chromium 内核（浏览器进程内）；管理器（launcher / 管理进程）只做 UX 级预检与错误呈现，不做、也不能做安全决策。**

#### 为什么不能靠管理器预校验做安全

1. **可绕过**：管理器不在信任边界内。用户/攻击者可以绕过管理器直接运行 `chrome.exe --r0-api-key=...`。任何只存在于管理器里的校验都不是安全边界，只是第一道体验门槛。
2. **密钥暴露面更大**：管理器若把 key 拼在命令行里，同机任何进程都能通过 `Win32_Process.CommandLine`（WMI）读到完整 key。Chromium 端在 start 阶段结束后立即 `OPENSSL_cleanse` 清掉内存副本；管理器长期持有 key 反而是更弱的一环。
3. **lease 无法跨进程复用**：`/start` 返回的 token 绑定 install_id + instance_id + api_key_hash + sequence + nonce，并由 Chromium 内置 Ed25519 公钥验签。管理器替 Chromium 申请的 lease，Chromium 用不了；反之亦然。
4. **双份校验 = 双份攻击面**：管理器自己再实现一遍 lease 协议（nonce/proof/验签）极易出错（26.2 的三个坑就是前车之鉴），出错还会误导排障方向。

#### 内核做校验的真实强度

- 心跳 + 租约 TTL 意味着**服务端可秒级吊销**（拒绝续租 → 浏览器自行终止），这是本地 JWT 做不到的（也是删除第 25 节的根本原因）。
- 信任锚是**服务端私钥 + 客户端内置公钥**：客户端二进制被逆向也拿不到私钥，伪造不出能通过验签的 token。
- 注意上限：内核校验的强度 = **Chromium 二进制本身的防篡改强度**。管理器加多少校验都不改变这一点；真正的配套防线是发布带签名的二进制 + 服务端只服务合法客户端版本。

#### 管理器的正确角色（推荐做法）

| 职责 | 具体做法 |
|------|---------|
| 启动前 UX 预检（可选） | 本地格式检查（`R0AK-` 前缀、分组长度）；如需在线预检，调用**只读**的 key 状态查询端点，失败给友好提示、不拉起浏览器。**仅 UX，不是安全边界** |
| 传递 key | 优先用**环境变量 `R0_API_KEY`**（Chromium 已支持，26.1），避免命令行暴露；`--r0-api-key=` 作为兜底 |
| 启动后监视 | 监视子进程退出码（授权失败 = 1）与 stderr 中 `[r0_license]` 前缀日志（含 26.4 的 `start diagnostics`），翻译成用户可读的错误提示 |
| 绝对不做 | ① "预检通过就跳过内核校验" / 缓存 lease / 缓存"本机已授权"标记；② key 明文落盘；③ 自行实现验签/续租逻辑 |

#### 反例（不要这样做）

```text
管理器: key 预校验通过 → 本地标记"已授权" → 之后裸启动 chrome.exe（不带 --r0-api-key）
```

一旦这么做，授权就从"每次启动验证 + 心跳持续验证"退化成"装机时验证一次"，服务端吊销完全失效。

#### 时序图（现行架构）

```text
管理器                            Chromium（内核）                  api.r0browser.com
  │  设置 R0_API_KEY / --r0-api-key     │                                │
  │ ──────────── 启动子进程 ──────────► │                                │
  │                                    │ 加载/创建 install_id（DPAPI）   │
  │                                    │ POST /start ─────────────────► │
  │                                    │ ◄───── token + lease ──────────│
  │                                    │ Ed25519 验签 → 清空 api_key     │
  │                                    │ POST /alive（周期心跳）──────► │
  │ ◄── 退出码 1 + [r0_license] 日志 ── │（任一环失败 → 终止进程）         │
  │  翻译成用户可读提示                  │                                │
```
