# DSH 插件审计（2026-10-18，dsh 0.2.1-rc.2）

> 目的：回答"每个插件是干什么的、有没有必要、当前是否真的可用"。
> 证据来源：`~/.dsh/profiles/web/package.json`、隔离启动冒烟日志（`dsh-safe check`）、npm registry 元数据。

## 一、当前启用中

| 插件/层 | 功能 | 兼容证据 | 必要性评估 | 建议 |
|---|---|---|---|---|
| `dsh-deepseek-balance@0.1.0` | 输入区常驻 DeepSeek 余额（15s）+ 本会话费用估算 | peers 为 cordis/credentials/webserver `>=0.1.0-rc.5`，启动日志无报错 | 高（实时成本感知） | **保留** |
| `@paicat1/dsh-screenshot@1.2.0` | 截图落盘（人工热键/相机按钮；agent 工具需 modlens） | peers/engines 均无限制，正常加载 | 中（读图/汇报场景有用） | **保留**；agent 自助截图需另装 modlens |
| `dsh-video-understand@0.5.2` | 视频 → ASR+场景+轨迹 → 摘要/问答 | ⚠️ 启动日志：`tool registration skipped: JsonSchemaError … upgrade_layer.type must be a single type string` → **工具注册失败** | 依使用频率；当前实际不可用 | **先停用**（等上游修复 schema），保留记录 |
| `@deepseek-ai/dsh-experimental-plugin-market-bundle` | 官方实验插件市场（"发现"页 + 索引源） | 官方 bundle，启动正常 | 中（统一管理/升级插件） | **保留**（已发布自建索引） |
| `@deepseek-ai/dsh-experimental-agent-team-profile` | 实验性 Agent Team | 官方 bundle，启动正常 | 视是否使用多 agent | 保留或按需关闭 |
| `@deepseek-ai/dsh-experimental-voice-input-bundle` | 实验性语音输入 | 官方 bundle，启动正常 | 视是否使用语音 | 保留或按需关闭 |
| `memory`（MCP Reference Memory） | 跨会话记忆（本地 JSONL） | 启动日志 `Knowledge Graph MCP Server running on stdio`；`mcp__memory__*` 工具在会话可见 | 高（长期偏好/上下文） | **保留** |

## 二、已禁用（不兼容 0.2.x，等上游）

| 插件 | 原因 | 恢复条件 |
|---|---|---|
| `picturereader`（3.3.3） | 依赖已被 0.2 移除的 `settingsScope` 客户端服务；强启导致 `pending（waiting for service: settingsScope）`，GUI 卡死 | 上游发布声明支持 0.2.x 的版本 |
| `dsh-better`（0.5.5） | `engines.dsh` 写死 `0.1.2-rc.1`，被兼容检查拒绝 | 上游发布支持 0.2.x 的版本 |

**通知功能替代**：社区已有 2026-10-17/18 新发布的 0.2.x 适配候选，其中 `dsh-notify@0.1.7`（SailingBoat-ovo/dsh-notify）已在 npm 发布、无 dsh 版本闸门，可经 `dsh-safe plugin add dsh-notify@0.1.7` 安全试用（失败会自动回滚）。

## 三、功能补齐方案（不依赖被测插件）

| 能力 | 方案 |
|---|---|
| 读图/OCR | `scripts/dsh-ocr`（macOS Vision 二进制 + 长图自动分片），不依赖插件；日常贴图也可用 4.1 Flash 原生图片输入 |
| 截图 | `@paicat1/dsh-screenshot` 保留；或用系统 `screencapture`（见 screen-capture-guide skill） |
| 通知 | 先用系统脚本/终端提示；待 `dsh-safe plugin add dsh-notify@0.1.7` 冒烟通过后再启用 |
| 视频理解 | 等 `dsh-video-understand` 修复 JSON Schema；期间可用 ffmpeg 抽帧 + `dsh-ocr`/模型原生图片输入 |

## 四、原则
- **功能必要性 ≠ 装上就好**：每个插件都增加启动失败面；能用系统能力/官方功能替代的，不装第三方。
- 所有变更走 `dsh-safe` 的"快照 → 变更 → 冒烟 → 失败回滚"流程。
- 客户端插件（有 `dsh.client`）风险高于纯 host 插件：启动时激活失败会直接阻塞 GUI。
