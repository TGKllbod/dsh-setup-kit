# DSH 插件审计（2026-10-18 终版 · dsh 0.2.1-rc.2）

> 目的：回答"每个插件是干什么的、有没有必要、当前是否真的可用"。
> 证据：`~/.dsh/profiles/web/package.json`、`dsh-safe check` 隔离冒烟日志、npm registry 元数据、插件 README 源码。

## 一、当前启用（冒烟通过）

| 插件/层 | 功能 | 兼容/运行证据 | 必要性 | 建议 |
|---|---|---|---|---|
| `dsh-deepseek-balance@0.1.0` | 输入区常驻 DeepSeek 余额（15s 刷新）+ 本会话费用估算 | peers 宽松（cordis/credentials/webserver ≥rc.5），冒烟正常 | 高（成本感知） | 保留 |
| `@paicat1/dsh-screenshot@1.2.0` | 截图落盘（人工热键/相机按钮；agent 工具需 modlens） | peers/engines 无限制，冒烟正常 | 中 | 保留 |
| `dsh-notify-plugin@1.4.6` | **跨平台桌面通知**：完成/暂停/失败/提问/授权/计划审阅；macOS 用 `osascript` + `afplay`，Windows 用 PowerShell Toast，Linux 用 notify-send；另有 webhook/企微/微信/Telegram 渠道（默认关闭） | peers 仅 cordis ^4.0.1 + schemastery（本机 4.0.5 ✓），无 dsh 版本闸门；守护冒烟通过 | 高（离开窗口也能收到完成/授权提醒） | 保留；设置页可调声音/事件过滤，外部渠道默认不开 |
| `dsh-video-understand@0.5.2` | 视频 → ASR+场景+轨迹 → 摘要/问答 | ⚠️ 启动日志：`tool registration skipped: JsonSchemaError … upgrade_layer.type must be a single type string` → **工具未注册，实际不可用** | 视使用频率 | **建议停用**（`dsh-safe plugin remove dsh-video-understand`），等上游修 schema |
| `@deepseek-ai/dsh-experimental-plugin-market-bundle` | 官方实验插件市场（"发现"页 + 索引源） | 官方 bundle，冒烟正常 | 中 | 保留（已发布自建索引） |
| `@deepseek-ai/dsh-experimental-agent-team-profile` | 实验性 Agent Team | 官方 bundle，冒烟正常 | 视多 agent 使用 | 保留或按需关闭 |
| `@deepseek-ai/dsh-experimental-voice-input-bundle` | 实验性语音输入 | 官方 bundle，冒烟正常 | 视语音使用 | 保留或按需关闭 |
| `memory`（MCP Reference Memory） | 跨会话记忆（本地 JSONL） | 启动日志 `Knowledge Graph MCP Server running on stdio`；本会话可见 `mcp__memory__*` | 高 | 保留 |

## 二、已移除 / 不可用（不要重复踩坑）

| 插件 | 原因 | 恢复条件 |
|---|---|---|
| `picturereader` 3.3.3 | 依赖 0.2 已移除的 `settingsScope`；强启导致 `pending（waiting for service: settingsScope）` → GUI 卡死 | 上游发布支持 0.2.x 的版本 |
| `dsh-better` 0.5.5 | `engines.dsh` 写死 `0.1.2-rc.1`，被 0.2.1 兼容检查拒绝 | 上游发布支持 0.2.x 的版本 |
| `dsh-notify` 0.1.7（SailingBoat） | **仅 Windows**（PowerShell Toast + 托盘），macOS 无通知 | 仅 Windows 机器可用 |
| `dsh-notify-say` / `dsh-notify-windows` 等同类 | 仅 Windows（WinRT Toast / TTS） | 仅 Windows |
| mermaid 渲染/`dsh-image-serve`/`dsh-appearance-gallery` | 前端 DOM/路径语义不兼容或未验证 | 等上游支持 |

## 三、功能补齐（不依赖不兼容插件）

| 能力 | 方案 |
|---|---|
| 读图 / OCR | `dsh-ocr <图片>`（macOS Vision，长图自动分片，不依赖插件）；日常也可直接贴图给 4.1 Flash（原生图片输入） |
| 完成/授权通知 | `dsh-notify-plugin`（本机已装，重启后生效；设置 → 插件 → 通知 可调） |
| 截图 | `@paicat1/dsh-screenshot` 或系统 `screencapture`（见 screen-capture-guide skill） |
| 视频理解 | 暂用 ffmpeg 抽帧 + `dsh-ocr` / 模型原生图片输入；等插件修复 |
| 启动安全 | `dsh-safe boot/check/plugin add|remove`：快照 + 隔离冒烟 + 自动回滚（见 README「启动守护」） |

## 四、原则
- **必要性 ≠ 装上就好**：兼容性被拒的插件 = 该版本不可用；客户端插件激活失败会直接阻塞 GUI。
- 所有变更走 `dsh-safe`：快照 → 变更 → 隔离冒烟（含 dump-config 预检 + bundle 全量核对 + 真实启动）→ 失败自动回滚。
- 变更后重启一律用 `dsh-safe boot`，不再裸跑 `dsh web`。
