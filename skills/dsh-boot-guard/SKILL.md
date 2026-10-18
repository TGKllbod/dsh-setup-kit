---
name: dsh-boot-guard
description: 在 DSH（DeepSeek Harness）上变更插件/profile 或重启 GUI 前，使用隔离冒烟与自动回滚避免启动失败。当需要安装/移除 dsh 插件、修改 profile、或用户要重启 GUI，或出现 "Failed to load plugins / did not activate / pending waiting for service" 报错时使用。Triggers when changing dsh plugins/profile, before restarting the GUI, or when dsh web fails to load plugins.
---

# DSH 启动守护（Boot Guard）

## 背景（为什么必须有）
2026-10-18 事故：强行启用不兼容的 client 插件（picturereader）后，`dsh web` 启动报
`Failed to load plugins / web boot: 1 entry did not activate / picturereader: pending（waiting for service: settingsScope）`，GUI 整体卡死。

**教训**：`--dump-config` 通过 ≠ 能启动；兼容性被拒的插件 = 该版本不可用。

## 硬规则
1. **不绕过兼容闸门**：不 `allow-version --accept-risk` 强装；不手改 `dsh.profile.bundles`。
2. 任何插件/profile 变更前必须**快照** `package.json`、`cordis.patch.yml`、`pnpm-lock.yaml`。
3. 变更后必须跑**隔离冒烟**（临时 DSH_HOME + `--port 0`，不写正式 profile），出现
   `Failed to load plugins / did not activate / pending…waiting for service` 即失败。
4. 冒烟失败 → **自动回滚**，不要反复重启正式 GUI。
5. 重启 GUI 也建议走 `dsh-safe boot`（先冒烟再启动）。

## 工具
仓库 `scripts/dsh-safe.sh`：
```bash
dsh-safe check                    # 只做隔离冒烟
dsh-safe boot --no-open           # 冒烟通过后启动正式 GUI；失败自动回滚
dsh-safe plugin add <包>@<版本>    # 安全插件变更（快照→变更→冒烟→失败回滚）
dsh-safe plugin remove <包>
dsh-safe snapshot / rollback      # 手动快照/回滚
```
配套 `scripts/dsh-ocr`：不依赖插件、长图自动分片的本地 OCR（恢复读图能力的兜底）。
配套 `scripts/patch-notify-fulltext.sh`（500/4000 + 微信 1800 字分片）与 `scripts/patch-notify-source.sh`（微信来源→精简单条；Web→全文分片）；`scripts/patch-notify-length.sh` 为单条轻量版。**插件升级/重装后需重新运行**。

## 常见故障定位
- 日志出现 `pending（waiting for service: <服务名>）` → 该客户端插件依赖的服务在当前 dsh 版本不存在：移除该插件（deps+bundles）后重启。
- 日志出现 `registration skipped / JsonSchemaError` → 插件工具注册失败（功能降级但可启动）：记录到审计表，评估是否停用该插件。
- 启动后浏览器 401 + "reopen the URL printed by dsh web" → 正常鉴权，用启动日志里带 token 的 URL 打开。
