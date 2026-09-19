# patchsets/154/apply.ps1
# Windows 一键 apply 脚本 (PowerShell 5+)。
#
# 用法:
#   .\apply.ps1                                  # 默认取 ..\src\src
#   .\apply.ps1 -ChromiumSrc C:\path\to\src
#   $env:CHROMIUM_SRC='C:\path\to\src'; .\apply.ps1

[CmdletBinding()]
param(
    [string]$ChromiumSrc = $env:CHROMIUM_SRC
)

$ErrorActionPreference = 'Stop'

if (-not $ChromiumSrc) {
    $ChromiumSrc = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
}

$PatchsetDir = $PSScriptRoot
$Platform    = 'windows'

Write-Host "[apply.ps1] platform=$Platform"
Write-Host "[apply.ps1] chromium_src=$ChromiumSrc"
Write-Host "[apply.ps1] patchset_dir=$PatchsetDir"

if (-not (Test-Path (Join-Path $ChromiumSrc '.git'))) {
    throw "$ChromiumSrc 不是 git checkout"
}

Push-Location $ChromiumSrc
try {
    $dirty = & git status --porcelain
    if ($dirty) {
        Write-Host "[apply.ps1] 工作区不干净，请先 git status 排查：" -ForegroundColor Yellow
        & git status --short
        exit 3
    }

    function Apply-One($Path) {
        if (-not (Test-Path $Path)) { return }
        Write-Host "[apply] $Path"
        & git apply --check $Path
        if ($LASTEXITCODE -ne 0) {
            throw "--check 失败: $Path"
        }
        & git apply $Path
        if ($LASTEXITCODE -ne 0) {
            throw "apply 失败: $Path"
        }
    }

    # 1. 跨平台层
    Get-ChildItem -Path (Join-Path $PatchsetDir 'cross') -Filter '*.patch' -ErrorAction SilentlyContinue | ForEach-Object {
        Apply-One $_.FullName
    }

    # 2. Windows 专属层
    Get-ChildItem -Path (Join-Path $PatchsetDir 'windows') -Filter '*.patch' -ErrorAction SilentlyContinue | ForEach-Object {
        Apply-One $_.FullName
    }

    # 3. 平台级构建修复 (crypt32, RC 调用保护等)
    foreach ($name in '900-*.patch','901-*.patch','902-*.patch','905-*.patch') {
        Get-ChildItem -Path $PatchsetDir -Filter $name -ErrorAction SilentlyContinue | ForEach-Object {
            Apply-One $_.FullName
        }
    }

    Write-Host "[apply.ps1] done." -ForegroundColor Green
    Write-Host "[apply.ps1] 当前 src 工作区状态:"
    & git status --short
} finally {
    Pop-Location
}