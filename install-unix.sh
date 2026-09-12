#!/usr/bin/env bash
# DSH Setup Kit — macOS / Linux 安装脚本
# 用法：bash install-unix.sh [profile]     （profile 默认 web）
set -euo pipefail

PROFILE="${1:-web}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS=(
  "picturereader@3.3.1"
  "dsh-video-understand@0.5.2"
  "@paicat1/dsh-screenshot@1.2.0"
  "dsh-deepseek-balance@0.1.0"
  "dsh-better@0.5.5"
)

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ── 0. 前置检查 ─────────────────────────────────────────────
command -v dsh  >/dev/null 2>&1 || die "未找到 dsh：请先安装 DeepSeek Harness（≥0.1.2-rc.1），并确保 dsh 在 PATH 中"
command -v node >/dev/null 2>&1 || die "未找到 node：需 Node ≥22"
if ! command -v pnpm >/dev/null 2>&1; then
  warn "未找到 pnpm —— dsh plugin 依赖它。建议先执行：npm i -g pnpm（或 corepack enable pnpm）"
  die  "缺少 pnpm，已停止。"
fi
say "dsh 版本：$(dsh --version 2>/dev/null || echo '未知')"

# ── 1. 安装插件 ─────────────────────────────────────────────
say "==> 安装插件到 profile「${PROFILE}」"
for pkg in "${PLUGINS[@]}"; do
  say "  + ${pkg}"
  if ! dsh plugin --profile "${PROFILE}" add "${pkg}" -w; then
    warn "  ! ${pkg} 安装失败（可稍后重试：dsh plugin --profile ${PROFILE} add ${pkg} -w）"
  fi
done

# ── 2. 安装 skills ─────────────────────────────────────────
SKILL_DIR="${HOME}/.dsh/skills"
say "==> 复制 skills 到 ${SKILL_DIR}"
mkdir -p "${SKILL_DIR}"
cp -R "${HERE}/skills/." "${SKILL_DIR}/"
ls -1 "${SKILL_DIR}"

# ── 3. 收尾提示 ─────────────────────────────────────────────
cat <<EOF

✔ 完成。请按顺序做：
  1) 重启 dsh（重启 GUI 服务），插件与 skills 才会生效；
  2) 通知：设置 → dsh-better → 开启三类通知 → 授权桌面通知（浏览器需允许通知，页面保持打开）；
  3) 余额：确认 ~/.dsh/.credentials.yaml 里有 DEEPSEEK_API_KEY（或设同名环境变量）；
  4) 视频理解：安装 ffmpeg —— macOS: brew install ffmpeg ；Linux: sudo apt install ffmpeg ；
  5) OCR（仅 macOS）：node "<dsh 安装目录>/node_modules/picturereader/scripts/setup-macos.mjs"（需 Xcode 命令行工具）
  6) 可选视觉语义：设置 GLM_API_KEY（免费 GLM-4V-Flash）或 SEE_API_KEY 后重启。

卸载：dsh plugin --profile ${PROFILE} remove <包名> -w
EOF
