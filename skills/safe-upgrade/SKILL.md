---
name: safe-upgrade
description: 安全升级 DeepSeek Harness（dsh）主体的标准流程。当用户要求升级/更新 dsh 核心版本（不是装插件），或升级过程中出现 npm 卡死/EPERM/符号链接报错时使用。Triggers when upgrading the dsh runtime package (e.g. to 0.2.1-rc.2), when npm install appears stuck, or when dsh web fails with "exists and is not a symlink or dsh-managed module proxy".
---

# dsh 安全升级流程（Safe Upgrade）

## 核心原则
1. **升级前必须备份** `~/.dsh/sessions`（V3 会话格式迁移后，新会话旧版本无法读取）。
2. **只升级 runtime 的 `@deepseek-ai/dsh`**；`~/.dsh/profiles/node_modules/@deepseek-ai/*` 是**指向 runtime 的符号链接**，禁止在 profiles 根目录 `npm install @deepseek-ai/dsh`（会把链接覆盖成真实目录，导致启动报 `exists and is not a symlink or dsh-managed module proxy`）。
3. **慢网络是"卡死"主因**：使用镜像 `--registry=https://registry.npmmirror.com` + `--prefer-offline --fetch-retries=3 --fetch-timeout=120000 --maxsockets=8`。官方 registry 单包可能耗时 76–94 秒。
4. **写 runtime 目录需要绕过沙箱限制**（DSH 会话内执行需 danger-full-access；用户终端执行则无此问题）。
5. 安装脚本**分两步**：先装依赖，再 `npm install-scripts approve <pkg>` + `npm rebuild`，避免编译阻塞整个安装。

## 执行清单
1. 检查无残留进程：`pgrep -fl "npm install"`，有则先结束。
2. 备份：`tar -czf ~/.dsh-backups/dsh-sessions-$(date +%s).tar.gz -C ~/.dsh sessions`，并保存 `runtime/package.json`、`profiles/web/package.json`、`cordis.patch.yml`。
3. 改 `runtime/package.json` 中 `"@deepseek-ai/dsh": "<目标版本>"`（用 node 改 JSON，勿手抖覆盖）。
4. 在 runtime 目录执行镜像安装（后台任务运行，定期查看输出；不要前台长时间阻塞）。
5. `npm install-scripts approve @deepseek-ai/dsh-subprocess-local koffi node-pty @google/genai protobufjs` + `npm rebuild`。
6. 预检：`dsh --profile web --dump-config`，exit 0 且无真实 error 即通过。
7. 让用户重启 GUI；验证 `dsh --version`、模型下拉（如 `deepseek-flash` = V4.1-Flash）、插件是否正常。
8. 如需回滚：把版本改回原值重装 + 解压会话备份。

## 插件兼容性：绝不可"强上"（2026-10-18 事故复盘）

**事故**：在 dsh `0.2.1-rc.2` 上，用 `allow-version --accept-risk` 绕过兼容检查强装 `picturereader@3.3.3` / `dsh-better@0.5.5`，并手工把它们写进 `profile.bundles`。重启后 `dsh web` 报：

```
Failed to load plugins
web boot: 1 entry did not activate
picturereader: pending（waiting for service: settingsScope）
```

GUI 整体卡死不可用，只能靠人工删除插件字段与目录恢复。

**原因**：0.2.x 移除了客户端插件依赖的 `settingsScope` 服务；被兼容检查拒绝的插件就是"不能用于该版本"。`--accept-risk` 只是跳过人机确认，不是修复不兼容；`--dump-config` 只能验证配置组合，**不能发现客户端 entry 激活失败**（该错误只在启动时出现）。

**红线（必须遵守）**：
1. 被当前 dsh 判为不兼容的插件 → **保持禁用，等上游发版支持**；不得使用 `allow-version --accept-risk` 强装，尤其 client 插件。
2. **禁止手改 `dsh.profile.bundles`** 来"启用"插件；只用官方插件管理器/`dsh plugin`，且装后检查返回的兼容性警告。
3. 任何 profile 插件变更后，**先做真实启动冒烟测试**（临时 profile / 备用端口启动一次并访问 `/`，确认无 `Failed to load plugins`），再让用户重启正式 GUI。仅 `--dump-config` 通过 ≠ 可启动。
4. 一次只改一项；改动前备份 `package.json`、`cordis.patch.yml`、`pnpm-lock.yaml`。
5. 保证用户终端可用的 **pnpm**（如 `~/.local/bin/pnpm`）；否则用户手动 `dsh plugin add/remove` 会 `spawn pnpm ENOENT`，只能手删文件、局面更乱。
6. 出现 `pending（waiting for service: ...）` 类启动失败时：先移除对应插件的 deps + bundles（及 node_modules 目录），再启动；不要尝试"再重启一次"。

## 本仓库脚本
`scripts/safe-upgrade.sh <版本>` 已封装上述步骤，可直接运行。Windows 等价命令见 README「平台差异」表格最后一行。
