#!/usr/bin/env bash
# patch-notify-fulltext.sh — 让微信通知尽量发送完整回复（长度 + 分片）
#
# 背景：dsh-notify-plugin 把通知正文硬编码为「用户问题 200 + 助手回复 500」，
# 且微信适配器把整条消息截断到 2000 字（iLink 单条文本上限）。
#
# 本补丁做两件事（原地、幂等）：
#   1) service.js：用户问题 → 500 字、助手回复 → 4000 字；
#   2) wechat.js：formatText 不再整体截断；send() 按 ≤1800 字分片、片间 400ms
#      依次发送（保持顺序，失败会走原有错误处理）。
#
# 用法：bash scripts/patch-notify-fulltext.sh
# 环境变量：DSH_HOME（默认 ~/.dsh）· DSH_PROFILE（默认 web）·
#           DSH_NOTIFY_PROMPT_MAX（默认 500）· DSH_NOTIFY_REPLY_MAX（默认 4000）
# 注意：插件升级/重装后 node_modules 会被替换 → 重新运行本脚本。
set -euo pipefail

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE="${DSH_PROFILE:-web}"
PROMPT_MAX="${DSH_NOTIFY_PROMPT_MAX:-500}"
REPLY_MAX="${DSH_NOTIFY_REPLY_MAX:-4000}"
SERVICE="$DSH_HOME/profiles/$PROFILE/node_modules/dsh-notify-plugin/lib/service.js"
WECHAT="$DSH_HOME/profiles/$PROFILE/node_modules/dsh-notify-plugin/lib/adapters/wechat.js"

[ -f "$SERVICE" ] || { echo "找不到插件文件：${SERVICE}" >&2; exit 2; }
[ -f "$WECHAT" ] || { echo "找不到插件文件：${WECHAT}" >&2; exit 2; }

[ -f "$SERVICE.bak-notify-fulltext" ] || cp -f "$SERVICE" "$SERVICE.bak-notify-fulltext"
[ -f "$WECHAT.bak-notify-fulltext" ] || cp -f "$WECHAT" "$WECHAT.bak-notify-fulltext"

python3 - "$SERVICE" "$WECHAT" "$PROMPT_MAX" "$REPLY_MAX" <<'PY'
import re
import sys

service_path, wechat_path, prompt_max, reply_max = sys.argv[1:5]

# ── 1) service.js：放宽摘要长度（兼容之前打过的 200/500 或 300/1500 补丁）──
src = open(service_path, encoding="utf-8").read()
src2 = re.sub(r"truncate\(tidy\(userPrompt\), \d+\)", f"truncate(tidy(userPrompt), {prompt_max})", src)
src2 = re.sub(r"truncate\(tidy\(reply\), \d+\)", f"truncate(tidy(reply), {reply_max})", src2)
if src2 == src and "truncate(tidy(reply), 500)" not in src:
    raise SystemExit("service.js 未找到可替换的截断调用（插件版本可能变化），已中止。")
if src2 != src:
    open(service_path, "w", encoding="utf-8").write(src2)
    print(f"patched length: {service_path} (prompt={prompt_max}, reply={reply_max})")

# ── 2) wechat.js：formatText 取消整体截断 + send() 分片发送 ──
w = open(wechat_path, encoding="utf-8").read()
if "[dsh-patch:wechat-chunk]" in w:
    print("wechat.js 已分片补丁，跳过")
else:
    old_fmt = "        return truncateAtLine(text, MAX_TEXT_LENGTH);"
    new_fmt = "        return text; // [dsh-patch:wechat-chunk] chunking handled in send()"
    if old_fmt not in w:
        raise SystemExit("wechat.js formatText 未找到预期截断行，已中止。")
    w = w.replace(old_fmt, new_fmt, 1)

    old_send = """        const text = this.formatText(event);
        const failures = [];"""
    new_send = """        const text = this.formatText(event);
        // [dsh-patch:wechat-chunk] iLink 单条文本上限 2000；长通知分片发送
        const chunks = splitForWeChat(text, MAX_TEXT_LENGTH - 200);
        const failures = [];"""
    if old_send not in w:
        raise SystemExit("wechat.js send() 未找到预期开头，已中止。")
    w = w.replace(old_send, new_send, 1)

    old_loop = """            try {
                await this.sendMessage(userId, text, contextToken);
                this.ctx.logger.info('[notify] WeChat notification sent to %s', userId);
            }"""
    new_loop = """            try {
                for (let i = 0; i < chunks.length; i += 1) {
                    if (i > 0)
                        await sleep(400, this.controller?.signal);
                    await this.sendMessage(userId, chunks[i], contextToken);
                }
                this.ctx.logger.info('[notify] WeChat notification sent to %s (%d chunk(s))', userId, chunks.length);
            }"""
    if old_loop not in w:
        raise SystemExit("wechat.js send() 未找到预期发送循环，已中止。")
    w = w.replace(old_loop, new_loop, 1)

    anchor = "function truncateAtLine(text, max) {"
    helper = """/**
 * [dsh-patch:wechat-chunk] Split long text into iLink-safe chunks at line
 * boundaries so a long notification arrives as several ordered messages.
 */
function splitForWeChat(text, max) {
    const chunks = [];
    let rest = text;
    while (rest.length > max) {
        let cut = rest.lastIndexOf('\\n', max);
        if (cut < Math.floor(max * 0.5))
            cut = max;
        chunks.push(rest.slice(0, cut).trimEnd());
        rest = rest.slice(cut).replace(/^\\n+/, '');
    }
    if (rest.trim())
        chunks.push(rest.trim());
    return chunks.length > 0 ? chunks : [text];
}

"""
    if anchor not in w:
        raise SystemExit("wechat.js 未找到 truncateAtLine 锚点，已中止。")
    w = w.replace(anchor, helper + anchor, 1)
    open(wechat_path, "w", encoding="utf-8").write(w)
    print(f"patched chunking: {wechat_path}")
PY

echo "✔ 全文分段补丁完成（问题 ${PROMPT_MAX} / 回复 ${REPLY_MAX} 字，超出按 1800 字分片发送）"
echo "  重启后生效：dsh-safe boot"
echo "  提示：插件升级后需重新运行本脚本。"
