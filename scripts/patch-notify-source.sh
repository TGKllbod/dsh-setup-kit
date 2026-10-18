#!/usr/bin/env bash
# patch-notify-source.sh — 按消息来源决定微信通知长度
#
# 目标行为：
#   · 用户消息来自微信（ClawBot 注入）→ 通知精简为单条（问题 200 / 回复 500 字）
#   · 用户消息来自 Mac/PC（Web GUI）→ 通知不截断（回复最多 12000 字，微信端按
#     1800 字分片发送）
#
# 原理（原地、幂等）：
#   1) host-interaction.js：记录插件注入的聊天 prompt（sessionId → {text, at}）；
#   2) service.js：生成通知时把"本轮最后一条用户消息"与记录比对：
#      文本一致 → 判为聊天来源（精简）；否则按 Web 来源（全文）。
#
# 依赖：先跑 scripts/patch-notify-fulltext.sh（提供分片发送）；本脚本可单独应用，
#       但若插件升级后重建 node_modules，需先重跑 fulltext 再跑本脚本。
#
# 用法：bash scripts/patch-notify-source.sh
# 环境变量：DSH_HOME（默认 ~/.dsh）· DSH_PROFILE（默认 web）
# 注意：插件升级/重装后需重新运行。
set -euo pipefail

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE="${DSH_PROFILE:-web}"
HOST="$DSH_HOME/profiles/$PROFILE/node_modules/dsh-notify-plugin/lib/host-interaction.js"
SERVICE="$DSH_HOME/profiles/$PROFILE/node_modules/dsh-notify-plugin/lib/service.js"

[ -f "$HOST" ] || { echo "找不到插件文件：${HOST}" >&2; exit 2; }
[ -f "$SERVICE" ] || { echo "找不到插件文件：${SERVICE}" >&2; exit 2; }

[ -f "$HOST.bak-notify-source" ] || cp -f "$HOST" "$HOST.bak-notify-source"
[ -f "$SERVICE.bak-notify-source" ] || cp -f "$SERVICE" "$SERVICE.bak-notify-source"

python3 - "$HOST" "$SERVICE" <<'PY'
import sys

host_path, service_path = sys.argv[1:3]

# ── 1) host-interaction.js：导出注入记录表 + prompt() 时写入 ──
h = open(host_path, encoding="utf-8").read()
if "[dsh-patch:notify-source]" in h:
    print("host-interaction.js 已标记来源，跳过")
else:
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
if "[dsh-patch:notify-source]" in w:
    print("service.js 已标记来源，跳过")
else:
    old_imp = "import { DshInteractionHost } from './host-interaction.js';"
    new_imp = "import { DshInteractionHost, chatInjectedPrompts } from './host-interaction.js';"
    if old_imp not in w:
        raise SystemExit("service.js 未找到 host-interaction import，已中止。")
    w = w.replace(old_imp, new_imp, 1)

    marker = "        // [dsh-patch:notify-source] 按来源选择长度：微信注入 → 精简单条；Web → 全文"
    import re
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
        "        // [dsh-patch:notify-source] 按来源选择长度：微信注入 → 精简单条；Web → 全文\n"
        "        const injected = session?.id ? chatInjectedPrompts.get(session.id) : undefined;\n"
        "        const fromChat = !!(injected && userPrompt && userPrompt.trim() === String(injected.text ?? '').trim());\n"
        "        const limits = fromChat ? { prompt: 200, reply: 500 } : { prompt: 500, reply: 12000 };\n"
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
    open(service_path, "w", encoding="utf-8").write(w)
    print(f"patched service: {service_path}")
PY

echo "✔ 来源感知补丁完成：微信来源 → 精简单条（200/500），Web 来源 → 全文（≤12000 字，分片发送）"
echo "  重启后生效：dsh-safe boot"
echo "  提示：插件升级后需重新运行（先 fulltext 再本脚本）。"
