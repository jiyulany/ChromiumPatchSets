param(
  [string]$Source = (Join-Path $PSScriptRoot 'app_icon.png'),
  [string]$ChromiumSrc,
  [string]$TransparentPngOutput
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Detect the colored circular icon and clear only pixels outside its boundary.
# This preserves white rings and separators that touch the outer background.
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class IconBackgroundRemoval {
  public static void Apply(Bitmap bitmap) {
    int width = bitmap.Width;
    int height = bitmap.Height;
    Rectangle rect = new Rectangle(0, 0, width, height);
    BitmapData data = bitmap.LockBits(rect, ImageLockMode.ReadWrite,
                                      PixelFormat.Format32bppArgb);
    int stride = data.Stride;
    byte[] pixels = new byte[stride * height];
    Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);

    bool alreadyTransparent = false;
    for (int x = 0; x < width; x++) {
      if (pixels[3] == 0 || pixels[(height - 1) * stride + x * 4 + 3] == 0)
        alreadyTransparent = true;
    }
    for (int y = 0; y < height; y++) {
      if (pixels[y * stride + 3] == 0 ||
          pixels[y * stride + (width - 1) * 4 + 3] == 0)
        alreadyTransparent = true;
    }
    if (alreadyTransparent) {
      bitmap.UnlockBits(data);
      return;
    }

    int minX = width, minY = height, maxX = -1, maxY = -1;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int offset = y * stride + x * 4;
        int blue = pixels[offset];
        int green = pixels[offset + 1];
        int red = pixels[offset + 2];
        int max = Math.Max(red, Math.Max(green, blue));
        int min = Math.Min(red, Math.Min(green, blue));
        if (max - min > 50 || max < 170) {
          minX = Math.Min(minX, x);
          minY = Math.Min(minY, y);
          maxX = Math.Max(maxX, x);
          maxY = Math.Max(maxY, y);
        }
      }
    }
    if (maxX < 0) {
      bitmap.UnlockBits(data);
      return;
    }

    double centerX = (minX + maxX) / 2.0;
    double centerY = (minY + maxY) / 2.0;
    double radiusX = (maxX - minX + 1) / 2.0 + 1.0;
    double radiusY = (maxY - minY + 1) / 2.0 + 1.0;
    double feather = 1.0 / Math.Min(radiusX, radiusY);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double dx = (x - centerX) / radiusX;
        double dy = (y - centerY) / radiusY;
        double distance = Math.Sqrt(dx * dx + dy * dy);
        int offset = y * stride + x * 4 + 3;
        if (distance >= 1.0) {
          pixels[offset] = 0;
        } else if (distance > 1.0 - feather) {
          double scale = (1.0 - distance) / feather;
          pixels[offset] = (byte)(pixels[offset] * scale);
        }
      }
    }

    Marshal.Copy(pixels, 0, data.Scan0, pixels.Length);
    bitmap.UnlockBits(data);
  }
}
'@ -ReferencedAssemblies System.Drawing

if (-not $ChromiumSrc) {
  $workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
  $ChromiumSrc = Join-Path $workspaceRoot 'src'
}
$targets = @(
  (Join-Path $ChromiumSrc 'chrome\app\theme\chromium\win\chromium.ico'),
  (Join-Path $ChromiumSrc 'chrome\installer\mini_installer\mini_installer.ico')
)
$sizes = @(16, 24, 32, 48, 64, 128, 256)

if (-not (Test-Path -LiteralPath $Source)) {
  throw "Source icon not found: $Source"
}

$sourceImage = [System.Drawing.Image]::FromFile($Source)
try {
  if ($sourceImage.Width -ne $sourceImage.Height) {
    throw "Source icon must be square, got $($sourceImage.Width)x$($sourceImage.Height)"
  }

  $processedImage = New-Object System.Drawing.Bitmap($sourceImage.Width, $sourceImage.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $preprocessGraphics = [System.Drawing.Graphics]::FromImage($processedImage)
  $preprocessGraphics.DrawImage($sourceImage, 0, 0, $sourceImage.Width, $sourceImage.Height)
  $preprocessGraphics.Dispose()
  [IconBackgroundRemoval]::Apply($processedImage)
  if ($TransparentPngOutput) {
    New-Item -ItemType Directory -Force (Split-Path $TransparentPngOutput -Parent) | Out-Null
    $processedImage.Save($TransparentPngOutput, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output "transparent master: $TransparentPngOutput"
  }

  $frames = @()
  foreach ($size in $sizes) {
    $bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.Clear([System.Drawing.Color]::Transparent)
      $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
      $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $graphics.DrawImage($processedImage, 0, 0, $size, $size)
    } finally {
      $graphics.Dispose()
    }
    $stream = New-Object System.IO.MemoryStream
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $frames += ,@{
      Size = $size
      Bytes = $stream.ToArray()
    }
    $stream.Dispose()
    $bitmap.Dispose()
  }

  foreach ($target in $targets) {
    $directory = Split-Path $target -Parent
    New-Item -ItemType Directory -Force $directory | Out-Null
    $file = [System.IO.File]::Create($target)
    $writer = New-Object System.IO.BinaryWriter($file)
    try {
      $writer.Write([uint16]0)
      $writer.Write([uint16]1)
      $writer.Write([uint16]$frames.Count)
      $offset = 6 + 16 * $frames.Count
      foreach ($frame in $frames) {
        $dimension = if ($frame.Size -ge 256) { 0 } else { $frame.Size }
        $writer.Write([byte]$dimension)
        $writer.Write([byte]$dimension)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$frame.Bytes.Length)
        $writer.Write([uint32]$offset)
        $offset += $frame.Bytes.Length
      }
      foreach ($frame in $frames) {
        $writer.Write($frame.Bytes)
      }
    } finally {
      $writer.Dispose()
      $file.Dispose()
    }
    Write-Output "generated: $target"
  }
} finally {
  if ($null -ne $processedImage) {
    $processedImage.Dispose()
  }
  $sourceImage.Dispose()
}
