#!/usr/bin/env bash
# DSH safe-upgrade helper (macOS / Linux)
# 用法：bash scripts/safe-upgrade.sh [目标版本]     默认 0.2.1-rc.2
# 责任边界：仅升级 runtime 的 @deepseek-ai/dsh；不碰 profiles 下的受管符号链接。
set -euo pipefail

VERSION="${1:-0.2.1-rc.2}"
RUNTIME="${DSH_RUNTIME:-$HOME/deepseek-harness-runtime}"
BACKUP_DIR="${DSH_BACKUP_DIR:-$HOME/.dsh-backups}"
MIRROR="${NPM_MIRROR:-https://registry.npmmirror.com}"
TS="$(date +%Y%m%d-%H%M%S)"

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ── 0. 前置检查 ─────────────────────────────────────────────
[ -d "$RUNTIME/node_modules/@deepseek-ai/dsh" ] || die "未找到 runtime：$RUNTIME（可用 DSH_RUNTIME=... 覆盖）"
command -v node >/dev/null || die "未找到 node（需 ≥22）"
command -v npm  >/dev/null || die "未找到 npm"
if pgrep -fl "npm install" >/dev/null 2>&1; then
  die "检测到正在运行的 npm install，请先等它结束（或 kill）再升级"
fi
CUR="$(node -e "console.log(require('$RUNTIME/node_modules/@deepseek-ai/dsh/package.json').version)")"
say "当前 dsh：$CUR → 目标：$VERSION"

# ── 1. 备份（会话必须先备份；V3 迁移后旧版本无法读取新会话）──────────
mkdir -p "$BACKUP_DIR"
say "==> 备份会话到 $BACKUP_DIR/dsh-sessions-$TS.tar.gz（可能较大）"
tar -czf "$BACKUP_DIR/dsh-sessions-$TS.tar.gz" -C "$HOME" .dsh/sessions 2>/dev/null || warn "  ! 会话备份出错，请检查磁盘空间"
cp -f "$RUNTIME/package.json" "$BACKUP_DIR/runtime-package-$TS.json"
for f in "$HOME/.dsh/settings.yaml" "$HOME/.dsh/profiles/web/package.json" "$HOME/.dsh/profiles/web/cordis.patch.yml"; do
  [ -f "$f" ] && cp -f "$f" "$BACKUP_DIR/$(basename "$f")-$TS.bak"
done
say "备份完成：$BACKUP_DIR"

# ── 2. 改版本（只改 runtime，不碰 profiles 符号链接）────────────────
say "==> 修改 runtime/package.json → @deepseek-ai/dsh@$VERSION"
node -e "
const fs=require('fs');const p='$RUNTIME/package.json';const j=JSON.parse(fs.readFileSync(p,'utf8'));
j.dependencies=j.dependencies||{};j.dependencies['@deepseek-ai/dsh']='$VERSION';
fs.writeFileSync(p,JSON.stringify(j,null,2)+'\n');"

# ── 3. 镜像安装（慢网络是卡死主因）──────────────────────────────
say "==> npm install（镜像 + prefer-offline；可能需要几分钟）"
cd "$RUNTIME"
npm install --registry="$MIRROR" --cache "${NPM_CACHE:-/tmp/npm-cache-run}" \
  --no-audit --no-fund --prefer-offline \
  --fetch-retries=3 --fetch-timeout=120000 --maxsockets=8

# ── 4. 安装脚本：先批准，再 rebuild（避免编译阻塞安装）─────────────
say "==> 批准常见安装脚本并 rebuild"
npm install-scripts approve @deepseek-ai/dsh-subprocess-local koffi node-pty @google/genai protobufjs 2>/dev/null || true
npm rebuild --cache "${NPM_CACHE:-/tmp/npm-cache-run}" 2>&1 | tail -2

# ── 5. 启动预检 ─────────────────────────────────────────────
say "==> 启动预检（组合 profile 配置）"
if command -v dsh >/dev/null 2>&1; then
  dsh --profile "${DSH_PROFILE:-web}" --dump-config >/tmp/dsh-preflight.log 2>&1 \
    && say "预检通过（输出见 /tmp/dsh-preflight.log）" \
    || { warn "预检失败，请查看 /tmp/dsh-preflight.log 并按备份回滚"; exit 1; }
else
  warn "PATH 中没有 dsh，跳过预检（请确认 launcher 指向 $RUNTIME）"
fi

# ── 6. 完成提示 ─────────────────────────────────────────────
NEW="$(node -e "console.log(require('$RUNTIME/node_modules/@deepseek-ai/dsh/package.json').version)")"
cat <<EOF

✔ 升级完成：$CUR → $NEW

后续：
  1) 重启 GUI（重新运行 dsh web），按提示打开带 token 的新 URL；
  2) 首次打开旧会话会做 V3 迁移（原文件保留，但新会话旧版本无法读取）；
  3) 检查模型下拉（如 DeepSeek-V4.1-Flash / deepseek-flash）与插件是否正常。

回滚：
  cd "$RUNTIME" && node -e "改回 package.json 版本" && npm install --registry="$MIRROR" --prefer-offline
  tar -xzf "$BACKUP_DIR/dsh-sessions-$TS.tar.gz" -C "\$HOME"
EOF
