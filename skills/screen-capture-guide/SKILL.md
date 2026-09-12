---
name: screen-capture-guide
description: 当用户要求截屏/截图/"看看屏幕/当前窗口/桌面"时使用：优先调用已注册的截屏工具，否则用系统自带截屏命令（macOS screencapture / Windows PowerShell / Linux gnome-screenshot 等）截取屏幕，再交给本地图像工具解读；禁止用 Chrome/无头浏览器自动化截屏。Triggers when the user asks for a screenshot, "look at the screen", describing the current window/desktop layout, or asks what is on screen. Cross-platform (macOS / Windows / Linux).
---

# 屏幕截取指引（Screen Capture Guide）

## 适用
用户说"截个屏 / 截屏 / 截图 / 看看当前窗口 / 说说桌面 / 屏幕上是啥"之类时，按本指引执行。**跨平台**：先判断操作系统，再选对应命令。

## 正确做法（按优先级）

### 1. 工具优先
若工具列表里有截屏类工具（如 `modlens_screenshot`，或描述含 screenshot/capture 者）→ 直接调用它。

### 2. 否则用系统截屏

**macOS**
```bash
mkdir -p ./captures
OUT=./captures/screen-$(date +%Y%m%d-%H%M%S).png
screencapture -x "$OUT" 2>&1 || {
  # 沙箱禁止直接写工作区时，先写系统临时目录再复制
  TMPF=/tmp/screen-$(date +%s).png
  screencapture -x "$TMPF" && mkdir -p ./captures && cp "$TMPF" ./captures/ && rm -f "$TMPF"
}
ls -la ./captures | tail -2
```
若报 `could not create image from display` / 权限错误 → 告诉用户到 **系统设置 → 隐私与安全性 → 屏幕录制** 授权后重试一次，**不要反复硬试**。
若报 `cannot write file` → 属沙箱写限制：改用上面的临时目录方案，或对该命令申请一次更宽权限。

**Windows（PowerShell）**
```powershell
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$b   = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$dir = Join-Path (Get-Location) "captures"
New-Item -ItemType Directory -Force $dir | Out-Null
$out = Join-Path $dir ("screen-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".png")
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output $out
```
（Windows 一般无需额外授权；远程桌面/无交互会话下可能失败，此时如实告知用户。）

**Linux**
```bash
mkdir -p ./captures && OUT=./captures/screen-$(date +%Y%m%d-%H%M%S).png
gnome-screenshot -f "$OUT" 2>/dev/null || import -window root "$OUT" 2>/dev/null || grim "$OUT"
```
（Wayland 常用 `grim`，X11 常用 `import`/`gnome-screenshot`。）

### 3. 截到图后：本地解读
- 用本地图像工具分析：`image_scan`（布局/颜色/结构）、`image_ocr`（文字）、必要时 `vision_analyze`（有 VLM 才有语义）。
- **OCR 引擎按平台选**：macOS 用 `engine="macos"`（需先用 `scripts/setup-macos.mjs` 编译）；Windows 用 `engine="windows"`（系统内置，免装）；跨平台回退 `rapid`/`paddle`。
- **格式注意**：图像工具只支持 PNG/JPEG/GIF/BMP；遇到 **WebP/HEIC** 先转码再读——
  macOS：`sips -s format png in.webp --out out.png`；Windows：`magick in.webp out.png`（ImageMagick）或系统"画图"另存为 PNG。
- 向用户说明屏幕/窗口布局与关键内容，并给出截图保存路径。

## 禁止

- ❌ 不要用 Chrome / 无头浏览器（headless CDP）自动化去"截屏"——常因沙箱/GPU（`GPU process isn't usable`）失败，白耗轮次。
- ❌ 不要在不告知用户的情况下反复重试同一失败命令。
- ❌ 不要使用第三方云截图/云 OCR 服务处理屏幕内容。

## 注意

- 屏幕内容属隐私：**只在本机处理**（落盘路径 + 本地解读），不把图片或其内容上传到任何外部服务；确需外发时先按 `upload-consent-guard` 征得同意。
- 默认整屏截取；需要"单窗口精准截取"而环境不支持时，先截整屏再用 `image_crop` 裁剪，并如实说明限制。
- 沙箱环境下若系统截屏被拦，走"临时目录 + 复制回工作区"或申请一次放宽权限，别停在中途。
