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

## 本仓库脚本
`scripts/safe-upgrade.sh <版本>` 已封装上述步骤，可直接运行。Windows 等价命令见 README「平台差异」表格最后一行。
