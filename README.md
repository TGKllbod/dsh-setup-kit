# DSH Setup Kit

> 把一台机器上验证过的 **DeepSeek Harness (dsh)** 插件组合与自研 **skills** 快速复制到另一台电脑（macOS / Windows / Linux）。
> 本仓库**只收录清单、安装脚本、skills 与适配说明**，不包含任何第三方插件源码。

**实测基准**：dsh `0.2.1-rc.2`（2026-10-18 实测通过）· Node `≥22` · pnpm `9.x`（Windows 侧要点见 [平台差异](#平台差异与适配要点)）
> 模型说明：0.2.1 起 DeepSeek 官方把 **DeepSeek-V4.1-Flash** 的模型 id 定为 `deepseek-flash`（旧 id `deepseek-v4-flash` 已由升级自动迁移），Pro 仍为 `deepseek-v4-pro`。

---

## 包含内容

| 插件 | 版本 | 用途 | macOS | Windows |
|---|---|---|---|---|
| `picturereader`（0.2.x 不兼容，见备注） | 3.3.3 | **读图**：像素扫描/OCR/裁剪/调色板/修图；0.2.x 下不可用，读图改用 `dsh-ocr` + 4.1 原生图片输入 | ❌ | ❌ |
| `dsh-notify-plugin` | 1.4.6 | **跨平台桌面通知**：完成/暂停/失败/提问/授权/计划审阅；macOS `osascript`+`afplay`，Windows Toast，Linux `notify-send`（webhook/企微/微信/Telegram 默认关闭） | ✅ | ✅ |
| `dsh-video-understand` | 0.5.2 | **视频理解**（⚠️ 0.2.1 下工具注册失败、当前不可用，等上游修复） | ⚠️ | ⚠️ |
| `@paicat1/dsh-screenshot` | 1.2.0 | **轻量截图**：人工热键/相机按钮 + 截图落盘（agent 工具需额外装 modlens，见可选增强） | ✅ | ✅（原生 PrintWindow，更贴合） |
| `dsh-deepseek-balance` | 0.1.0 | **余额实时显示**：输入区旁常驻余额（15s 刷新）+ 本会话费用（官价/峰谷） | ✅ | ✅ |

> 兼容性备注：`picturereader` 3.3.3 与 `dsh-better` 0.5.5 **不兼容 0.2.x**（分别为 settingsScope 已移除、engines 写死 0.1.2），本仓库不推荐在 0.2.1 安装；读图改用 `dsh-ocr` + 4.1 原生图片输入，通知改用 `dsh-notify-plugin`（跨平台）。

自研 skills（复制到用户级技能目录即全局生效）：

| Skill | 作用 |
|---|---|
| `upload-consent-guard` | **外发护栏**：任何"上传到外部非本人账户/空间"前必须先说明、警示并征得同意 |
| `screen-capture-guide` | **截屏指引**：优先用已注册截图工具，其次系统截图（macOS `screencapture` / Windows PowerShell / Linux），禁止用浏览器自动化截屏；截完本地解读 |
| `safe-upgrade` | **安全升级 dsh**：备份 → 镜像安装 → 分步脚本 → 预检 → 验证/回滚的固定流程（见 [升级 DSH](#升级-dsh安全流程)） |

---

## 快速开始

### 0. 前置检查

```bash
dsh --version      # 本套件在 0.2.1-rc.2 实测通过；语义上需 ≥0.1.2-rc.1
node --version     # 需 ≥ 22
pnpm --version     # dsh plugin 通过 pnpm 安装插件；缺失则：npm i -g pnpm
```

### macOS / Linux

```bash
git clone <本仓库地址> dsh-setup-kit && cd dsh-setup-kit
bash install-unix.sh            # 默认 profile: web；可传参：bash install-unix.sh myprofile
```

### Windows（PowerShell）

```powershell
git clone <本仓库地址> dsh-setup-kit; cd dsh-setup-kit
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
# 可选指定 profile： -Profile web
```

### 手动逐条（等价于脚本）

```bash
# picturereader 3.3.3 与 0.2.x 不兼容（settingsScope 已移除），暂不安装
dsh plugin --profile web add dsh-video-understand@0.5.2 -w
dsh plugin --profile web add @paicat1/dsh-screenshot@1.2.0 -w
dsh plugin --profile web add dsh-deepseek-balance@0.1.0 -w
dsh plugin --profile web add dsh-notify-plugin@1.4.6 -w
```

skills：

```bash
# macOS / Linux
mkdir -p ~/.dsh/skills && cp -R skills/* ~/.dsh/skills/
```
```powershell
# Windows
New-Item -ItemType Directory -Force "$env:USERPROFILE\.dsh\skills" | Out-Null
Copy-Item -Recurse -Force .\skills\* "$env:USERPROFILE\.dsh\skills\"
```

装完**重启 dsh**（重启 GUI 服务），然后按需完成下面"可选增强"。

---

## 启动守护（防重启失败，强烈推荐）

> 目标：**任何插件/profile 变更后，先验证能启动，再重启 GUI**；失败自动回滚，不把坏状态带给正式 GUI。

```bash
# 一次性安装到 PATH
install -m 755 scripts/dsh-safe.sh ~/.local/bin/dsh-safe
install -m 755 scripts/dsh-ocr   ~/.local/bin/dsh-ocr
```

| 命令 | 作用 |
|---|---|
| `dsh-safe check` | 隔离冒烟：临时 DSH_HOME + 随机端口启动一次，**读取当前 profile 但不写它** |
| `dsh-safe boot` | 冒烟通过后才 `exec dsh --profile web`；失败自动从快照回滚 |
| `dsh-safe plugin add <包>@<版本>` | 快照 → `dsh plugin` 变更 → 冒烟 → 失败自动回滚 |
| `dsh-safe snapshot` / `dsh-safe rollback` | 手动快照 / 恢复 profile 清单 |

判定依据：启动日志出现 `Failed to load plugins`、`entry did not activate`、`pending … waiting for service` → 失败；
出现 `registration skipped / JsonSchemaError` → 功能降级警告（可启动）。

配套 `dsh-ocr <图片>`：不依赖插件的本地 OCR（macOS Vision，长图自动分片），用于读图/读超长截图。
插件功能与必要性审计见 [`docs/plugin-audit.md`](./docs/plugin-audit.md)。

### 通知内容长度（本地补丁，按需组合）

`dsh-notify-plugin` 硬编码「用户问题 200 字 + 助手回复 500 字」，微信单条上限 2000 字。提供三个幂等补丁：

```bash
bash scripts/patch-notify-fulltext.sh   # 全文基础：问题 500 / 回复 4000，微信超 1800 字自动分片
bash scripts/patch-notify-source.sh     # 来源感知：微信来源→精简单条(200/500)；Web(Mac/PC)→全文(≤12000 字)
bash scripts/patch-notify-length.sh     # 轻量单条：问题 300 / 回复 1500（不推荐与上面混用）
```

- **来源判定**：插件记录自己注入的微信 prompt，通知生成时与"本轮最后一条用户消息"比对；一致 → 判为微信来源；
- 分片补丁：长回复按行边界切成多条 ≤1800 字消息，片间 400ms（防限流），按顺序到达；
- **重启后生效**（`dsh-safe boot`）；**插件升级/重装后需重新运行**；若三者都要，顺序：先 `fulltext` 再 `source`；
- 超过上限的回复仍会截断（Web 来源上限 12000 字）；系统通知/webhook 也会收到更长的正文。

---

## 升级 DSH（安全流程）

> 升级 dsh 主体不是 `dsh plugin` 能做的：要改 `deepseek-harness-runtime/package.json` 的 `@deepseek-ai/dsh` 版本并 npm 安装。
> 本仓库提供 `scripts/safe-upgrade.sh` 固化了这次踩坑经验（macOS/Linux；Windows 见文末说明）。

```bash
# 1) 先备份（脚本内部也会备份到 ~/.dsh-backups）
bash scripts/safe-upgrade.sh 0.2.1-rc.2
```

脚本步骤：**备份会话 → 改版本 → 镜像安装（秒级）→ 批准安装脚本并 rebuild → 启动预检 → 打印重启提示**。

### 升级前必读

1. **会话格式**：0.1.5 起升级为 **V3**——打开旧会话时生成新版日志（**原文件保留**），但**升级后的会话不支持旧版本读取**。因此升级前必须备份 `~/.dsh/sessions`，回滚只能靠备份。
2. **慢网络是"卡死"主因**：官方 registry 单包可达 76–94 秒；务必用镜像
   `--registry=https://registry.npmmirror.com` 并配合 `--prefer-offline --fetch-retries=3 --fetch-timeout=120000 --maxsockets=8`（脚本已内置）。
3. **不要在 `~/.dsh/profiles` 根目录 `npm install @deepseek-ai/dsh`**：会把受管符号链接覆盖成真实目录，导致 `dsh web` 报 "exists and is not a symlink or dsh-managed module proxy"（本仓库早期版本踩过这个坑）。只升级 runtime，profiles 下的 `@deepseek-ai/*` 是**指向 runtime 的符号链接**，会自动跟随。
4. **写系统目录要放宽沙箱/权限**；安装脚本用 `npm install-scripts approve <pkg>` + `npm rebuild` 分两步执行。

### 验证与回滚

```bash
dsh --version                                   # 应为目标版本
dsh --profile web --dump-config | tail          # 组合配置预检（无 error 即通过）
# 回滚：把 runtime/package.json 版本改回旧值重装，并恢复备份：
tar -xzf ~/.dsh-backups/dsh-sessions-<ts>.tar.gz -C "$HOME"
```

---

## 踩坑复盘：一次把 dsh 搞到"卡死"的教训（2026-10-18）

**现象**：在 0.2.1-rc.2 上强行启用被兼容检查拒绝的 `picturereader` 后重启，`dsh web` 启动失败：

```
Failed to load plugins
web boot: 1 entry did not activate
picturereader: pending（waiting for service: settingsScope）
```

GUI 整体不可操作，最后靠人工移除插件依赖/目录才恢复。

**根因**：0.2.x 移除了第三方客户端插件依赖的 `settingsScope`；被兼容检查拒绝 = 该版本不可用。`allow-version --accept-risk` 只是跳过确认，**并不修复不兼容**；`--dump-config` 只验证配置可组合，**发现不了客户端 entry 激活失败**。

**以后必须遵守**：
1. 兼容性被拒的插件 → 禁用等上游更新；不 `allow-version --accept-risk` 强装（尤其 client 插件）。
2. 不手改 `dsh.profile.bundles`；只用官方插件管理器/`dsh plugin`，并确认无兼容性警告。
3. 插件变更后先做**真实启动冒烟**（临时 profile/备用端口启动并访问 `/`，确认无 `Failed to load plugins`），再让用户重启正式 GUI。
4. 一次只改一项；改前备份 `package.json`、`cordis.patch.yml`、`pnpm-lock.yaml`。
5. 用户终端要有可用的 `pnpm`（如 `~/.local/bin/pnpm`），否则手动 `dsh plugin add/remove` 会 `spawn pnpm ENOENT`（本次已发生）。
6. 看到 `pending（waiting for service: …）`：移除该插件 deps+bundles 后重启，别反复重启碰运气。

### 正确的故障恢复顺序（别做危险操作）

1. **回退清单**：`dsh-safe rollback`，或手工从 `profiles/web/package.json` 与 `cordis.patch.yml` 移除该插件的 deps/bundles 条目。
   - ❌ 不要 `rm -rf ~/.dsh/profiles/web`（会丢全部插件/设置，豆包曾建议过）
   - ❌ 不要 `npm uninstall -g @deepseek-ai/dsh` 全局重装（本机是 runtime 目录安装）
   - ❌ 0.2.x 没有 `plugins.json`、没有 `dsh profile reset web`（这些是错误/过时说法；配置在 `profiles/web/package.json` + `cordis.patch.yml`）
2. **插件命令需要 pnpm**：本机已装 `~/.local/bin/pnpm`；没有 pnpm 时 `dsh plugin remove` 会 `spawn pnpm ENOENT`，看起来像"卸载没生效"。
3. 改完先 `dsh-safe check` 冒烟，通过后再启动/重启 GUI。
4. 启动后浏览器 401 + "reopen the URL printed by dsh web" 是正常鉴权，从启动日志抄带 token 的 URL。
5. 读图兜底：`dsh-ocr <图片>`（不依赖插件；长图自动分片）。

---

## 平台差异与适配要点

| 事项 | macOS | Windows |
|---|---|---|
| 用户级 skills 目录 | `~/.dsh/skills/` | `%USERPROFILE%\.dsh\skills\` |
| 截图（人工） | 系统 `screencapture` | 插件原生通道（PrintWindow）/ PowerShell 截屏脚本 |
| OCR 引擎 | 需编译一次：`node node_modules/picturereader/scripts/setup-macos.mjs`（需 Xcode 命令行工具） | 用内置 `windows` 引擎，**无需安装** |
| 通知 | `dsh-notify-plugin`：macOS `osascript` 系统通知 + `afplay` 提示音 | 同插件：Windows PowerShell Toast |
| 余额 | host 侧 `curl` 请求官方接口；key 从 `~/.dsh/.credentials.yaml` 或环境变量 `DEEPSEEK_API_KEY` | 同左；Windows 10+ 自带 `curl.exe` |
| 视频理解 | 需 `ffmpeg`（`brew install ffmpeg`）+ Python（首次调用自动建 venv） | `winget install Gyan.FFmpeg` + 安装 Python 并加入 PATH（`winget install Python.Python.3.13`） |
| dsh 升级 | `bash scripts/safe-upgrade.sh <ver>` | 手工等价：备份 → 改 `runtime/package.json` → `npm install --registry=https://registry.npmmirror.com --prefer-offline` → `npm install-scripts approve …` → `npm rebuild` → 预检 |

### 可选增强

- **视频摘要/问答阶段**需要文本 LLM：启动 GUI 前设置
  `LLM_API_URL`（如 `https://api.deepseek.com/v1/chat/completions`）、`LLM_MODEL`（如 `deepseek-chat`）、`LLM_API_KEY`（不设则自动读 credentials 里的 `DEEPSEEK_API_KEY`）。
- **视觉语义理解（"这是教室/有几个人"这类）** 需要真正的 VLM：设置 `GLM_API_KEY`（免费 GLM-4V-Flash，[注册](https://open.bigmodel.cn)）或 `SEE_API_KEY` 后重启，`vision_analyze` 即可给出语义描述；否则只能用像素+OCR 证据。
- **Agent 自助截图**：`@paicat1/dsh-screenshot` 的 `modlens_screenshot` 工具**仅在检测到 modlens CLI 时注册**；需要它可另装 `@liustack/modlens`（注意其视觉路由需你自行配置可用 provider）。默认情况下人工热键/相机按钮仍可用。
- **通知**：`dsh-notify-plugin` 默认启用系统通知（macOS `osascript` + `afplay`，Windows Toast，Linux notify-send）；在 设置 → 插件 → 通知 可调事件/声音；webhook/企微/微信/Telegram 渠道默认关闭。

---

## 已验证与本版不兼容清单（避免踩坑）

以 **dsh 0.2.1-rc.2** 为准：

| 项 | 现象/原因 |
|---|---|
| mermaid 渲染类插件（`dsh-mermaid-render` 等） | 0.2.1 前端产物中仍未检出 mermaid 或 `data-conversation-scroll` 支持 → 渲染插件大概率仍是纯代码块；使用前请先确认插件作者声明支持 0.2.x |
| `dsh-image-serve`（本地图片内嵌） | 实现只认 Windows 盘符/UNC 路径，**macOS 不适用**；macOS 本地图请用附件方式 |
| `dsh-appearance-gallery`（皮肤库） | 跨版本 UI 插槽变动会导致面板消失，未在 0.2.1 验证 |
| 「回答里直接出流程图/图片」 | 官方 0.1.5 起声明支持 POSIX 本地图片路径渲染，本仓库未在 0.2.1 上逐项实测；流程图建议输出 mermaid 代码块用 [mermaid.live](https://mermaid.live) 查看 |

---

## 卸载与回滚

```bash
dsh plugin --profile web remove <包名> -w      # 例：dsh plugin --profile web remove dsh-better -w
rm -rf ~/.dsh/skills/<skill名>                  # 删除某个 skill
```

---

## 安全与隐私

- 本套件安装的均为**第三方社区插件**；DeepSeek Harness 官方声明整体**尚未经过安全审计**，请按需审阅后再装。
- 所有密钥仅保存在本机（`~/.dsh/.credentials.yaml` / 环境变量），不要提交到任何仓库。
- 仓库内置 `upload-consent-guard`：任何"上传到外部非本人账户/空间"的动作都会先询问后再执行。

---

## 许可

本仓库自身内容（清单/脚本/skills）采用 **MIT** 许可，见 [LICENSE](./LICENSE)；
其中安装的第三方插件由各自作者按其各自许可分发，本仓库不包含其源码。

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-09 | 首次整理：基于 dsh 0.1.2-rc.1，收录 5 个插件 + 2 个 skills，macOS 实测、Windows 适配说明 |
| 2026-10-18 | 更新至 dsh 0.2.1-rc.2（实测通过）；新增 `safe-upgrade` 脚本与 skill、升级/回滚章节、V3 会话迁移与镜像加速说明；注明 4.1 模型 id `deepseek-flash` |
| 2026-10-18 | 补充「踩坑复盘」：禁止 allow-version 强装不兼容插件、禁止手改 bundles、必须做启动冒烟测试（`pending waiting for service: settingsScope` 事故） |
| 2026-10-18 | 新增 `scripts/dsh-safe.sh` 启动守护（隔离冒烟 + 失败自动回滚）与 `scripts/dsh-ocr` OCR 兜底、`dsh-boot-guard` skill、`docs/plugin-audit.md`；补充故障恢复正确流程与危险操作警告 |
| 2026-10-18 | 通知方案定为跨平台 `dsh-notify-plugin@1.4.6`（macOS osascript+afplay / Windows Toast / Linux notify-send）；移除 Windows-only 的 dsh-notify；审计标明 dsh-video-understand 在 0.2.1 下工具注册失败；守护新增 dump-config 预检与 bundle 全量核对 |
| 2026-10-18 | 新增 `scripts/patch-notify-length.sh`：通知摘要 200/500 → 300/1500 字（微信单条 2000 上限内）；审计补充 Web 卡片不消失、微信仅文本/语音入站等已知限制 |
| 2026-10-18 | 新增 `scripts/patch-notify-fulltext.sh`：通知摘要 500/4000 字 + 微信长消息按 1800 字分片发送（片间 400ms），解决微信通知显示不全 |
| 2026-10-18 | 新增 `scripts/patch-notify-source.sh`：来源感知——微信来源的轮次通知精简单条（200/500），Mac/PC（Web）来源不截断（≤12000 字，分片发送） |
