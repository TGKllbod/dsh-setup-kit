#!/usr/bin/env bash
# dsh-safe — DSH 启动守护 + 插件安全变更 + 快照/回滚
#
# 子命令：
#   dsh-safe boot [web 参数...]     快照 → 隔离冒烟 → 通过后 exec 正式 dsh web（失败自动回滚）
#   dsh-safe check                  只做隔离冒烟检查（不动正式 profile）
#   dsh-safe snapshot               保存当前 profile 清单快照
#   dsh-safe rollback [快照目录]     恢复最近（或指定）快照的 profile 清单
#   dsh-safe plugin add|remove <包>  快照 → 执行插件变更 → 冒烟检查 → 失败自动回滚
#
# 环境变量：DSH_BIN（默认 ~/.local/bin/dsh 或 PATH 里的 dsh）、DSH_PROFILE（默认 web）、
#           DSH_HOME（默认 ~/.dsh）、DSH_GUARD_DIR（快照根，默认 $DSH_HOME/backups）
set -euo pipefail

DSH_PROFILE="${DSH_PROFILE:-web}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
DSH_BIN="${DSH_BIN:-$(command -v dsh || echo "$HOME/.local/bin/dsh")}"
GUARD_DIR="${DSH_GUARD_DIR:-$DSH_HOME/backups}"
PROFILE_DIR="$DSH_HOME/profiles/$DSH_PROFILE"
PROFILE_ROOT="$DSH_HOME/profiles"
REQUIRED_FILES=(package.json cordis.patch.yml)

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[ -x "$DSH_BIN" ] || die "找不到 dsh 可执行文件：$DSH_BIN"
[ -d "$PROFILE_DIR" ] || die "找不到 profile：$PROFILE_DIR"

snapshot() {
  local ts dir
  ts="$(date +%Y%m%d-%H%M%S)"; dir="$GUARD_DIR/snap-$ts"
  mkdir -p "$dir"
  for f in "${REQUIRED_FILES[@]}" pnpm-lock.yaml; do
    if [ -f "$PROFILE_DIR/$f" ]; then
      cp -f "$PROFILE_DIR/$f" "$dir/" || die "快照失败：无法读取 $PROFILE_DIR/$f"
    elif printf '%s\n' "${REQUIRED_FILES[@]}" | grep -qx "$f"; then
      die "快照失败：缺少必需文件 $PROFILE_DIR/$f"
    fi
  done
  ln -sfn "$dir" "$GUARD_DIR/last"
  echo "$dir"
}

restore_snapshot() {
  local dir="${1:-$GUARD_DIR/last}"
  [ -d "$dir" ] || return 1
  local restored=0
  for f in "${REQUIRED_FILES[@]}" pnpm-lock.yaml; do
    if [ -f "$dir/$f" ]; then cp -f "$dir/$f" "$PROFILE_DIR/$f" || die "回滚失败：无法写 $PROFILE_DIR/$f"; restored=1; fi
  done
  [ "$restored" = "1" ] || return 1
  say "已从快照恢复 profile 清单：$dir"
}

# 隔离冒烟：临时 DSH_HOME + 备用端口（--port 0 由系统分配），不写正式 profile
smoke() {
  local tmp log port pid i url rc=0
  tmp="$(mktemp -d /tmp/dsh-safe-XXXXXX)"
  cleanup_smoke() { [ -n "${pid:-}" ] && kill -9 "$pid" 2>/dev/null; rm -rf "$tmp"; }
  trap cleanup_smoke EXIT

  mkdir -p "$tmp/profiles/$DSH_PROFILE"
  for f in "${REQUIRED_FILES[@]}" pnpm-workspace.yaml pnpm-lock.yaml; do
    if [ -f "$PROFILE_DIR/$f" ]; then
      cp -f "$PROFILE_DIR/$f" "$tmp/profiles/$DSH_PROFILE/" || { warn "冒烟准备失败：拷贝 $f 失败"; rc=1; }
    elif printf '%s\n' "${REQUIRED_FILES[@]}" | grep -qx "$f"; then
      warn "冒烟准备失败：缺少必需文件 $f"; rc=1
    fi
  done
  ln -sfn "$PROFILE_DIR/node_modules" "$tmp/profiles/$DSH_PROFILE/node_modules"
  ln -sfn "$PROFILE_ROOT/node_modules" "$tmp/profiles/node_modules"
  [ -d "$PROFILE_DIR/node_modules" ] || { warn "冒烟准备失败：node_modules 不存在"; rc=1; }
  [ -d "$PROFILE_ROOT/node_modules" ] || { warn "冒烟准备失败：profiles/node_modules 不存在"; rc=1; }
  [ -f "$DSH_HOME/.credentials.yaml" ] && cp -f "$DSH_HOME/.credentials.yaml" "$tmp/" || true
  if [ "$rc" != "0" ]; then trap - EXIT; rm -rf "$tmp"; return 1; fi

  log="$tmp/boot.log"

  # 1) 配置预检：dump-config 必须 exit 0（能捕获未知 bundle / YAML / 配置错误）
  DSH_HOME="$tmp" "$DSH_BIN" --profile "$DSH_PROFILE" --dump-config >"$tmp/dump.log" 2>&1 || rc=1
  if [ "$rc" != "0" ]; then
    warn "配置预检失败（--dump-config）："; tail -8 "$tmp/dump.log" | sed 's/^/  /'
    trap - EXIT; rm -rf "$tmp"; return 1
  fi

  # 1a) 未解析的 bundle（dsh 只打 stderr 不报错，必须显式检测）
  if grep -qE 'cannot resolve profile bundle|skipping profile bundle' "$tmp/dump.log"; then
    warn "配置预检发现无法解析的 bundle："
    grep -E 'cannot resolve profile bundle|skipping profile bundle' "$tmp/dump.log" | head -5 | sed 's/^/  /'
    trap - EXIT; rm -rf "$tmp"; return 1
  fi

  # 1b) bundle 全量核对：package.json 里声明的每个 bundle 都必须出现在组合结果中
  if ! PROFILE_JSON="$PROFILE_DIR/package.json" DUMP_LOG="$tmp/dump.log" node -e '
    const fs = require("fs");
    const pkg = JSON.parse(fs.readFileSync(process.env.PROFILE_JSON, "utf8"));
    const dump = fs.readFileSync(process.env.DUMP_LOG, "utf8");
    const bundles = (pkg.dsh && pkg.dsh.profile && pkg.dsh.profile.bundles) || [];
    const missing = bundles.filter((b) => !dump.includes(b));
    if (missing.length) { console.error(missing.join("\n")); process.exit(1); }
  ' 2>"$tmp/missing-bundles.txt"; then
    warn "配置预检失败：以下 bundle 未出现在组合结果中："
    sed 's/^/  /' "$tmp/missing-bundles.txt"
    trap - EXIT; rm -rf "$tmp"; return 1
  fi

  # 2) 真实启动冒烟
  DSH_HOME="$tmp" "$DSH_BIN" --profile "$DSH_PROFILE" --port 0 --no-open >"$log" 2>&1 &
  pid=$!
  url=""
  for i in $(seq 1 40); do
    sleep 1
    url="$(grep -oE 'http://127\.0\.0\.1:[0-9]+/\?token=[A-Za-z0-9_-]+' "$log" | head -1 || true)"
    [ -n "$url" ] && break
    kill -0 "$pid" 2>/dev/null || break
  done
  if [ -z "$url" ]; then
    rc=1
  else
    port="$(printf '%s\n' "$url" | sed -E 's#http://127\.0\.0\.1:([0-9]+)/.*#\1#')"
    if ! curl -s -o /dev/null --max-time 5 "http://127.0.0.1:$port/"; then rc=1; fi
  fi
  if grep -qE 'Failed to load plugins|entry did not activate|pending.*waiting for service' "$log"; then rc=1; fi

  if [ "$rc" = "0" ]; then
    say "✔ 隔离冒烟通过（端口 ${port:-?}）"
    if grep -qE 'registration skipped|JsonSchemaError' "$log"; then
      warn "注意：日志中仍有插件注册被跳过（功能降级但可启动）："
      grep -E 'registration skipped|JsonSchemaError' "$log" | head -3 | sed 's/^/  /'
    fi
  else
    warn "✘ 隔离冒烟失败。关键日志："
    grep -nE 'Failed to load|did not activate|pending|Error|error' "$log" 2>/dev/null | head -10 | sed 's/^/  /' || true
    [ -z "$url" ] && tail -6 "$log" | sed 's/^/  /'
  fi
  kill -9 "$pid" 2>/dev/null || true
  pid=""
  trap - EXIT
  rm -rf "$tmp"
  return "$rc"
}

case "${1:-}" in
  boot)
    shift
    snap="$(snapshot)"
    say "快照：$snap"
    if ! smoke; then
      warn "冒烟失败：不启动正式 GUI，并回滚到快照。"
      restore_snapshot "$snap" || true
      exit 2
    fi
    say "冒烟通过 → 启动正式 GUI"
    exec "$DSH_BIN" --profile "$DSH_PROFILE" "$@"
    ;;
  check)
    smoke ;;
  snapshot)
    snapshot ;;
  rollback)
    restore_snapshot "${2:-}" ;;
  plugin)
    shift
    [ $# -ge 2 ] || die "用法: dsh-safe plugin add|remove <包> [pnpm 参数...]"
    snap="$(snapshot)"
    say "快照：$snap"
    say "执行：dsh plugin --profile $DSH_PROFILE $*"
    if ! "$DSH_BIN" plugin --profile "$DSH_PROFILE" "$@" ; then
      warn "插件命令失败；回滚清单。"
      restore_snapshot "$snap" || true
      exit 2
    fi
    if ! smoke; then
      warn "变更后冒烟失败：自动回滚 profile 清单。"
      restore_snapshot "$snap" || true
      exit 2
    fi
    say "✔ 插件变更完成且冒烟通过。"
    ;;
  *)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
