#!/usr/bin/env bash
# patch-notify-source.sh — 按消息来源决定微信通知长度
#
# 目标行为：
#   · 用户消息来自微信（ClawBot 注入）→ 最多 2 条消息（约 3600 字），
#     问题 200 字 + 回复最多 3800 字；超过 2 条时截断并附"完整内容请在 Mac 查看"；
#   · 用户消息来自 Mac/PC（Web GUI）→ 不截断（回复最多 12000 字，微信端按
#     1800 字分片发送多条）。
#
# 原理（原地、幂等）：
#   1) host-interaction.js：记录插件注入的聊天 prompt（sessionId → {text, at}）；
#   2) service.js：生成通知时把"本轮最后一条用户消息"与记录比对：
#      文本一致 → 判为聊天来源（最多 2 条）；否则按 Web 来源（全文分片）；
#   3) wechat.js：聊天来源最多 CHAT_MAX_CHUNKS 条（默认 2），超出截断并提示。
#
# 依赖：先跑 scripts/patch-notify-fulltext.sh（提供分片发送）；本脚本可单独应用，
#       但若插件升级后重建 node_modules，需先重跑 fulltext 再跑本脚本。
#
# 用法：bash scripts/patch-notify-source.sh
# 环境变量：DSH_HOME（默认 ~/.dsh）· DSH_PROFILE（默认 web）·
#           DSH_NOTIFY_CHAT_REPLY_MAX（默认 3800）· DSH_NOTIFY_CHAT_MAX_CHUNKS（默认 2）
# 注意：插件升级/重装后需重新运行。
set -euo pipefail

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE="${DSH_PROFILE:-web}"
CHAT_REPLY_MAX="${DSH_NOTIFY_CHAT_REPLY_MAX:-3800}"
CHAT_MAX_CHUNKS="${DSH_NOTIFY_CHAT_MAX_CHUNKS:-2}"
PLUGIN="$DSH_HOME/profiles/$PROFILE/node_modules/dsh-notify-plugin/lib"
HOST="$PLUGIN/host-interaction.js"
SERVICE="$PLUGIN/service.js"
WECHAT="$PLUGIN/adapters/wechat.js"

for f in "$HOST" "$SERVICE" "$WECHAT"; do
  [ -f "$f" ] || { echo "找不到插件文件：${f}" >&2; exit 2; }
  [ -f "$f.bak-notify-source" ] || cp -f "$f" "$f.bak-notify-source"
done

python3 - "$HOST" "$SERVICE" "$WECHAT" "$CHAT_REPLY_MAX" "$CHAT_MAX_CHUNKS" <<'PY'
import re
import sys

host_path, service_path, wechat_path, chat_reply_max, chat_max_chunks = sys.argv[1:6]

# ── 1) host-interaction.js：导出注入记录表 + prompt() 时写入 ──
h = open(host_path, encoding="utf-8").read()
if "[dsh-patch:notify-source]" not in h:
    old_import = "import { randomUUID } from 'node:crypto';"
    new_import = (
        "import { randomUUID } from 'node:crypto';\n"
        "/** [dsh-patch:notify-source] Prompts injected by chat channels (WeChat/Telegram),\n"
        " * keyed by session; consumed by notification summaries to pick a length profile. */\n"
        "export const chatInjectedPrompts = new Map();"
    )
    if old_import not in h:
        raise SystemExit("host-interaction.js 未找到 import 锚点，已中止。")
    h = h.replace(old_import, new_import, 1)

    old_controller = """                }, new AbortController().signal);
                return { ok: true };"""
    new_controller = """                }, new AbortController().signal);
                chatInjectedPrompts.set(sessionId, { text: text_, at: Date.now() }); // [dsh-patch:notify-source]
                return { ok: true };"""
    if old_controller not in h:
        raise SystemExit("host-interaction.js 未找到 controller.prompt 锚点，已中止。")
    h = h.replace(old_controller, new_controller, 1)

    old_fallback = """            agent.followup(makeUserMessage(text_));
            return { ok: true };"""
    new_fallback = """            agent.followup(makeUserMessage(text_));
            chatInjectedPrompts.set(sessionId, { text: text_, at: Date.now() }); // [dsh-patch:notify-source]
            return { ok: true };"""
    if old_fallback not in h:
        raise SystemExit("host-interaction.js 未找到 fallback 锚点，已中止。")
    h = h.replace(old_fallback, new_fallback, 1)
    open(host_path, "w", encoding="utf-8").write(h)
    print(f"patched host: {host_path}")

# ── 2) service.js：导入记录表 + 按来源动态选择摘要长度 ──
w = open(service_path, encoding="utf-8").read()
if "[dsh-patch:notify-source]" not in w:
    old_imp = "import { DshInteractionHost } from './host-interaction.js';"
    new_imp = "import { DshInteractionHost, chatInjectedPrompts } from './host-interaction.js';"
    if old_imp not in w:
        raise SystemExit("service.js 未找到 host-interaction import，已中止。")
    w = w.replace(old_imp, new_imp, 1)

    pattern = re.compile(
        r"        // Build the message\n"
        r"        const lines = \[\];\n"
        r"        if \(userPrompt\) \{\n"
        r"            lines\.push\(`💬 \$\{truncate\(tidy\(userPrompt\), \d+\)\}`\);\n"
        r"        \}\n"
        r"        if \(reply\) \{\n"
        r"            lines\.push\(`🤖 \$\{truncate\(tidy\(reply\), \d+\)\}`\);\n"
        r"        \}",
        re.S,
    )
    replacement = (
        "        // Build the message\n"
        "        const lines = [];\n"
        "        // [dsh-patch:notify-source] 按来源选择长度：微信注入 → 最多 2 条；Web → 全文分片\n"
        "        const injected = session?.id ? chatInjectedPrompts.get(session.id) : undefined;\n"
        "        const fromChat = !!(injected && userPrompt && userPrompt.trim() === String(injected.text ?? '').trim());\n"
        f"        const limits = fromChat ? {{ prompt: 200, reply: {chat_reply_max} }} : {{ prompt: 500, reply: 12000 }};\n"
        "        if (userPrompt) {\n"
        "            lines.push(`💬 ${truncate(tidy(userPrompt), limits.prompt)}`);\n"
        "        }\n"
        "        if (reply) {\n"
        "            lines.push(`🤖 ${truncate(tidy(reply), limits.reply)}`);\n"
        "        }"
    )
    if not pattern.search(w):
        raise SystemExit("service.js 未找到消息构建块，已中止（请确认插件版本）。")
    w = pattern.sub(replacement, w, count=1)

    old_return = "        return { message: lines.join('\\n'), details };"
    new_return = (
        "        details.promptSource = fromChat ? 'wechat' : 'web'; // [dsh-patch:notify-source]\n"
        "        if (fromChat && session?.id)\n"
        "            chatInjectedPrompts.delete(session.id);\n"
        "        return { message: lines.join('\\n'), details };"
    )
    if old_return not in w:
        raise SystemExit("service.js 未找到 return 锚点，已中止。")
    w = w.replace(old_return, new_return, 1)
    print(f"patched service: {service_path}")

# 无论是否首次打补丁，都把聊天来源上限校正到目标值
limits_pattern = re.compile(r"const limits = fromChat \? \{ prompt: \d+, reply: \d+ \} : \{ prompt: \d+, reply: \d+ \};")
normalized = limits_pattern.sub(
    f"const limits = fromChat ? {{ prompt: 200, reply: {chat_reply_max} }} : {{ prompt: 500, reply: 12000 }};",
    w,
)
if normalized != w:
    w = normalized
    print(f"normalized chat reply limit to {chat_reply_max}")
open(service_path, "w", encoding="utf-8").write(w)

# ── 3) wechat.js：按来源分片（聊天来源最多 CHAT_MAX_CHUNKS 条）──
x = open(wechat_path, encoding="utf-8").read()

# 3a) 常量 CHAT_MAX_CHUNKS
const_anchor = "const MAX_TEXT_LENGTH = 2000;"
const_line = f"const CHAT_MAX_CHUNKS = {chat_max_chunks}; // [dsh-patch:notify-source] 微信来源最多分几条"
if const_anchor not in x:
    raise SystemExit("wechat.js 未找到 MAX_TEXT_LENGTH 锚点，已中止。")
if re.search(r"const CHAT_MAX_CHUNKS = \d+; // \[dsh-patch:notify-source\]", x):
    x = re.sub(r"const CHAT_MAX_CHUNKS = \d+; // \[dsh-patch:notify-source\][^\n]*", const_line, x, count=1)
elif "CHAT_MAX_CHUNKS" not in x:
    x = x.replace(const_anchor, const_anchor + "\n" + const_line, 1)

# 3b) chunks 逻辑（兼容：未打补丁 / 旧单条版 / 新版本）
new_block = (
    "        // [dsh-patch:notify-source] 微信来源最多 CHAT_MAX_CHUNKS 条；Web 来源完整分片\n"
    "        const chatOrigin = event.details?.promptSource === 'wechat';\n"
    "        const chunks = chatOrigin\n"
    "            ? (() => {\n"
    "                const all = splitForWeChat(text, MAX_TEXT_LENGTH - 200);\n"
    "                if (all.length <= CHAT_MAX_CHUNKS)\n"
    "                    return all;\n"
    "                const kept = all.slice(0, CHAT_MAX_CHUNKS);\n"
    "                kept[kept.length - 1] = `${kept[kept.length - 1]}\\n…（已截断，完整内容请在 Mac 端查看）`;\n"
    "                return kept;\n"
    "            })()\n"
    "            : splitForWeChat(text, MAX_TEXT_LENGTH - 200);"
)
if "const chatOrigin = event.details?.promptSource === 'wechat';" in x:
    x = re.sub(
        r"        // \[dsh-patch:notify-source\][^\n]*\n"
        r"        const chatOrigin = event\.details\?\.promptSource === 'wechat';\n"
        r"        const chunks = chatOrigin\n[\s\S]*?:\s*splitForWeChat\(text, MAX_TEXT_LENGTH - 200\);",
        new_block,
        x,
        count=1,
    )
else:
    plain = "        const chunks = splitForWeChat(text, MAX_TEXT_LENGTH - 200);"
    if plain not in x:
        raise SystemExit("wechat.js 未找到 chunks 锚点（需先打 fulltext 补丁？），已中止。")
    x = x.replace(plain, new_block, 1)

open(wechat_path, "w", encoding="utf-8").write(x)
print(f"patched wechat: {wechat_path} (chat max chunks={chat_max_chunks})")
PY

echo "✔ 来源感知补丁完成：微信来源 → 最多 ${CHAT_MAX_CHUNKS} 条（问题 200 / 回复 ${CHAT_REPLY_MAX}，超出截断并提示）；Web → 全文（≤12000 分片）"
echo "  重启后生效：dsh-safe boot"
echo "  提示：插件升级后需重新运行（先 fulltext 再本脚本）。"
