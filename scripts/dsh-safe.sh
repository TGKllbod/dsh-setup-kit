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

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[ -x "$DSH_BIN" ] || die "找不到 dsh 可执行文件：$DSH_BIN"
[ -d "$PROFILE_DIR" ] || die "找不到 profile：$PROFILE_DIR"

snapshot() {
  local ts dir
  ts="$(date +%Y%m%d-%H%M%S)"; dir="$GUARD_DIR/snap-$ts"
  mkdir -p "$dir"
  for f in package.json cordis.patch.yml pnpm-lock.yaml; do
    [ -f "$PROFILE_DIR/$f" ] && cp -f "$PROFILE_DIR/$f" "$dir/" || true
  done
  ln -sfn "$dir" "$GUARD_DIR/last"
  echo "$dir"
}

restore_snapshot() {
  local dir="${1:-$GUARD_DIR/last}"
  [ -d "$dir" ] || return 1
  for f in package.json cordis.patch.yml pnpm-lock.yaml; do
    [ -f "$dir/$f" ] && cp -f "$dir/$f" "$PROFILE_DIR/$f" || true
  done
  say "已从快照恢复 profile 清单：$dir"
}

# 隔离冒烟：临时 DSH_HOME + 备用端口（--port 0 由系统分配），不写正式 profile
smoke() {
  local tmp log port pid i url
  tmp="$(mktemp -d /tmp/dsh-safe-XXXXXX)"
  mkdir -p "$tmp/profiles/$DSH_PROFILE"
  for f in package.json cordis.patch.yml pnpm-workspace.yaml pnpm-lock.yaml; do
    [ -f "$PROFILE_DIR/$f" ] && cp -f "$PROFILE_DIR/$f" "$tmp/profiles/$DSH_PROFILE/" || true
  done
  ln -sfn "$PROFILE_DIR/node_modules" "$tmp/profiles/$DSH_PROFILE/node_modules"
  ln -sfn "$PROFILE_ROOT/node_modules" "$tmp/profiles/node_modules"
  [ -f "$DSH_HOME/.credentials.yaml" ] && cp -f "$DSH_HOME/.credentials.yaml" "$tmp/" || true
  log="$tmp/boot.log"

  DSH_HOME="$tmp" "$DSH_BIN" --profile "$DSH_PROFILE" --port 0 --no-open >"$log" 2>&1 &
  pid=$!
  trap 'kill -9 $pid 2>/dev/null; rm -rf "$tmp"' EXIT

  url=""
  for i in $(seq 1 40); do
    sleep 1
    url="$(grep -oE 'http://127\.0\.0\.1:[0-9]+/\?token=[A-Za-z0-9_-]+' "$log" | head -1 || true)"
    [ -n "$url" ] && break
    kill -0 "$pid" 2>/dev/null || break
  done

  local rc=0
  if [ -z "$url" ]; then
    rc=1
  else
    port="$(printf '%s\n' "$url" | sed -E 's#http://127\.0\.0\.1:([0-9]+)/.*#\1#')"
    # 启动成功的判定：HTTP 有响应（401/200 均可）
    if ! curl -s -o /dev/null --max-time 5 "http://127.0.0.1:$port/"; then rc=1; fi
  fi

  # 致命模式：插件未激活 / pending 等待服务 / Failed to load plugins
  if grep -qE 'Failed to load plugins|entry did not activate|pending.*waiting for service' "$log"; then rc=1; fi

  if [ "$rc" = "0" ]; then
    say "✔ 隔离冒烟通过（端口 ${port:-?}）"
    if grep -qE 'registration skipped|JsonSchemaError' "$log"; then
      warn "注意：日志中仍有插件注册被跳过（功能降级但可启动）："
      grep -E 'registration skipped|JsonSchemaError' "$log" | head -3 | sed 's/^/  /'
    fi
  else
    warn "✘ 隔离冒烟失败。关键日志："
    grep -nE 'Failed to load|did not activate|pending|Error|error' "$log" | head -10 | sed 's/^/  /' || true
  fi
  kill -9 "$pid" 2>/dev/null || true
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
