# DSH Setup Kit — Windows (PowerShell) 安装脚本
# 用法：powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 [-Profile web]
param(
  [string]$Profile = "web"
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Plugins = @(
  "picturereader@3.3.1",
  "dsh-video-understand@0.5.2",
  "@paicat1/dsh-screenshot@1.2.0",
  "dsh-deepseek-balance@0.1.0",
  "dsh-better@0.5.5"
)

function Say($m)  { Write-Host $m }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Die($m)  { Write-Host $m -ForegroundColor Red; exit 1 }

# ── 0. 前置检查 ─────────────────────────────────────────────
$dsh = Get-Command dsh -ErrorAction SilentlyContinue
if (-not $dsh) { Die "未找到 dsh：请先安装 DeepSeek Harness（>=0.1.2-rc.1），并确保 dsh 在 PATH 中（可能需要重开终端）" }
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Die "未找到 node：需 Node >= 22（winget install OpenJS.NodeJS.LTS）" }
$pnpm = Get-Command pnpm -ErrorAction SilentlyContinue
if (-not $pnpm) { Die "未找到 pnpm：dsh plugin 依赖它。请先执行：npm i -g pnpm（或 corepack enable pnpm），再重开终端" }

$ver = (& dsh --version) 2>$null
Say "dsh 版本：$ver"

# ── 1. 安装插件 ─────────────────────────────────────────────
Say "==> 安装插件到 profile「$Profile」"
foreach ($pkg in $Plugins) {
  Say "  + $pkg"
  & dsh plugin --profile $Profile add $pkg -w
  if ($LASTEXITCODE -ne 0) { Warn "  ! $pkg 安装失败（可稍后重试：dsh plugin --profile $Profile add $pkg -w）" }
}

# ── 2. 安装 skills ─────────────────────────────────────────
$skillDir = Join-Path $env:USERPROFILE ".dsh\skills"
Say "==> 复制 skills 到 $skillDir"
New-Item -ItemType Directory -Force $skillDir | Out-Null
Copy-Item -Recurse -Force (Join-Path $Here "skills\*") $skillDir
Get-ChildItem $skillDir -Name

# ── 3. 收尾提示 ─────────────────────────────────────────────
@"

完成。请按顺序做：
  1) 重启 dsh（重启 GUI 服务），插件与 skills 才会生效；
  2) 通知：设置 → dsh-better → 开启三类通知 → 授权桌面通知；
     另请在「系统设置 → 通知」允许你的浏览器（Chrome/Edge）发送通知；页面需保持打开。
  3) 余额：在 %USERPROFILE%\.dsh\.credentials.yaml 写入 DEEPSEEK_API_KEY: sk-xxx，或设置同名环境变量；
  4) 视频理解：winget install Gyan.FFmpeg  ；并安装 Python：winget install Python.Python.3.13
     （安装后重开终端，确保 python 可用；插件首次调用会自动创建 venv）
  5) OCR：Windows 使用系统内置 OCR 引擎，无需安装；
  6) 可选视觉语义：设置 GLM_API_KEY（免费 GLM-4V-Flash）或 SEE_API_KEY 后重启。

卸载：dsh plugin --profile $Profile remove <包名> -w
"@
