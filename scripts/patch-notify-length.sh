#!/usr/bin/env bash
# patch-notify-length.sh — 放宽 dsh-notify-plugin 通知摘要长度
#
# 背景：插件把通知正文写死为「用户问题 200 字 + 助手回复 500 字」；微信 iLink
# 单条纯文本上限 2000 字。默认摘要常常截掉后半段（如长回答里的结论/建议）。
#
# 本脚本（原地、幂等）把截断阈值改为：
#   用户问题 PROMPT_MAX（默认 300）
#   助手回复 REPLY_MAX（默认 1500）
# 总长度 = 标题 + 300 + 1500 ≈ 1900 < 2000（微信单条上限），不会触发二次截断。
#
# 用法：bash scripts/patch-notify-length.sh
# 环境变量：DSH_HOME（默认 ~/.dsh）· DSH_PROFILE（默认 web）·
#           DSH_NOTIFY_PROMPT_MAX（默认 300）· DSH_NOTIFY_REPLY_MAX（默认 1500）
# 注意：插件升级/重装后 node_modules 会被替换 → 重新运行本脚本。
set -euo pipefail

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE="${DSH_PROFILE:-web}"
PROMPT_MAX="${DSH_NOTIFY_PROMPT_MAX:-300}"
REPLY_MAX="${DSH_NOTIFY_REPLY_MAX:-1500}"
TARGET="$DSH_HOME/profiles/$PROFILE/node_modules/dsh-notify-plugin/lib/service.js"

[ -f "$TARGET" ] || { echo "找不到插件文件：${TARGET}（插件未安装？）" >&2; exit 2; }

if grep -q "truncate(tidy(reply), $REPLY_MAX)" "$TARGET"; then
  echo "✔ 已是目标长度（回复 ${REPLY_MAX} / 问题 ${PROMPT_MAX}），无需重复打补丁。"
  exit 0
fi

BACKUP="$TARGET.bak-notify-patch"
[ -f "$BACKUP" ] || cp -f "$TARGET" "$BACKUP"

python3 - "$TARGET" "$PROMPT_MAX" "$REPLY_MAX" <<'PY'
import sys
path, prompt_max, reply_max = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path, encoding="utf-8").read()
old_prompt = "lines.push(`💬 ${truncate(tidy(userPrompt), 200)}`);"
new_prompt = f"lines.push(`💬 ${{truncate(tidy(userPrompt), {prompt_max})}}`);"
old_reply = "lines.push(`🤖 ${truncate(tidy(reply), 500)}`);"
new_reply = f"lines.push(`🤖 ${{truncate(tidy(reply), {reply_max})}}`);"
if old_prompt not in src or old_reply not in src:
    raise SystemExit("未找到预期的截断代码（插件版本可能变化），已中止，未修改文件。")
src = src.replace(old_prompt, new_prompt).replace(old_reply, new_reply)
open(path, "w", encoding="utf-8").write(src)
print(f"patched: {path}")
PY

echo "✔ 补丁完成：用户问题 ${PROMPT_MAX} 字 / 助手回复 ${REPLY_MAX} 字（备份：${BACKUP:-$TARGET.bak-notify-patch}）"
echo "  重启后生效：dsh-safe boot"
echo "  提示：插件升级后需重新运行本脚本。"
