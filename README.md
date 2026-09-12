# DSH Setup Kit

> 把一台机器上验证过的 **DeepSeek Harness (dsh)** 插件组合与自研 **skills** 快速复制到另一台电脑（macOS / Windows / Linux）。
> 本仓库**只收录清单、安装脚本、skills 与适配说明**，不包含任何第三方插件源码。

**实测基准**：dsh `0.1.2-rc.1` · Node `≥22` · pnpm `9.x`（Windows 侧要点见 [平台差异](#平台差异与适配要点)）

---

## 包含内容

| 插件 | 版本 | 用途 | macOS | Windows |
|---|---|---|---|---|
| `picturereader` | 3.3.1 | **读图**：像素网格扫描 / OCR（多引擎）/ 裁剪 / 调色板 / 修图，让纯文本模型"看得见"图片 | ✅ OCR 引擎 `macos`（需编译，见下） | ✅ OCR 引擎 `windows`（系统内置，免装） |
| `dsh-video-understand` | 0.5.2 | **视频理解**：B站/本地视频 → ASR+场景+轨迹信息层 → 摘要/问答（默认 L0 全本地） | ✅ | ✅（需 ffmpeg + Python） |
| `@paicat1/dsh-screenshot` | 1.2.0 | **轻量截图**：人工热键/相机按钮 + 截图落盘（agent 工具需额外装 modlens，见可选增强） | ✅ | ✅（原生 PrintWindow，更贴合） |
| `dsh-deepseek-balance` | 0.1.0 | **余额实时显示**：输入区旁常驻余额（15s 刷新）+ 本会话费用（官价/峰谷） | ✅ | ✅ |
| `dsh-better` | 0.5.5 | **系统通知**：任务完成 / 提问或选项 / 出错三类通知（浏览器 Notification API → 系统通知中心） | ✅ | ✅（Windows Toast） |

自研 skills（复制到用户级技能目录即全局生效）：

| Skill | 作用 |
|---|---|
| `upload-consent-guard` | **外发护栏**：任何"上传到外部非本人账户/空间"前必须先说明、警示并征得同意 |
| `screen-capture-guide` | **截屏指引**：优先用已注册截图工具，其次系统截图（macOS `screencapture` / Windows PowerShell / Linux），禁止用浏览器自动化截屏；截完本地解读 |

---

## 快速开始

### 0. 前置检查

```bash
dsh --version      # 需 ≥ 0.1.2-rc.1（更低版本部分插件不生效）
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
dsh plugin --profile web add picturereader@3.3.1 -w
dsh plugin --profile web add dsh-video-understand@0.5.2 -w
dsh plugin --profile web add @paicat1/dsh-screenshot@1.2.0 -w
dsh plugin --profile web add dsh-deepseek-balance@0.1.0 -w
dsh plugin --profile web add dsh-better@0.5.5 -w
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

## 平台差异与适配要点

| 事项 | macOS | Windows |
|---|---|---|
| 用户级 skills 目录 | `~/.dsh/skills/` | `%USERPROFILE%\.dsh\skills\` |
| 截图（人工） | 系统 `screencapture` | 插件原生通道（PrintWindow）/ PowerShell 截屏脚本 |
| OCR 引擎 | 需编译一次：`node node_modules/picturereader/scripts/setup-macos.mjs`（需 Xcode 命令行工具） | 用内置 `windows` 引擎，**无需安装** |
| 通知 | 浏览器通知 → 通知中心；需在 设置→dsh-better 开启 + 浏览器授权 | 同机制 → Windows Toast；另请在 系统设置→通知 允许浏览器通知 |
| 余额 | host 侧 `curl` 请求官方接口；key 从 `~/.dsh/.credentials.yaml` 或环境变量 `DEEPSEEK_API_KEY` | 同左；Windows 10+ 自带 `curl.exe` |
| 视频理解 | 需 `ffmpeg`（`brew install ffmpeg`）+ Python（首次调用自动建 venv） | `winget install Gyan.FFmpeg` + 安装 Python 并加入 PATH（`winget install Python.Python.3.13`） |

### 可选增强

- **视频摘要/问答阶段**需要文本 LLM：启动 GUI 前设置
  `LLM_API_URL`（如 `https://api.deepseek.com/v1/chat/completions`）、`LLM_MODEL`（如 `deepseek-chat`）、`LLM_API_KEY`（不设则自动读 credentials 里的 `DEEPSEEK_API_KEY`）。
- **视觉语义理解（"这是教室/有几个人"这类）** 需要真正的 VLM：设置 `GLM_API_KEY`（免费 GLM-4V-Flash，[注册](https://open.bigmodel.cn)）或 `SEE_API_KEY` 后重启，`vision_analyze` 即可给出语义描述；否则只能用像素+OCR 证据。
- **Agent 自助截图**：`@paicat1/dsh-screenshot` 的 `modlens_screenshot` 工具**仅在检测到 modlens CLI 时注册**；需要它可另装 `@liustack/modlens`（注意其视觉路由需你自行配置可用 provider）。默认情况下人工热键/相机按钮仍可用。
- **通知授权**：设置 → dsh-better → 打开三类通知 → 点"授权桌面通知"；浏览器站点权限需允许（页面需保持打开，这是 Notification API 的固有边界）。

---

## 已验证与本版不兼容清单（避免踩坑）

以下项在 **dsh 0.1.2-rc.1** 下**不可用**，本套件刻意不收录；若想用需升级到 **≥ 0.1.5-alpha.1**：

| 项 | 现象/原因 |
|---|---|
| mermaid 渲染类插件（`dsh-mermaid-render` 等） | rc.1 前端**无 `data-conversation-scroll` DOM、无 mermaid 支持** → 装了也只显示代码块 |
| `dsh-image-serve`（本地图片内嵌） | 实现只认 Windows 盘符/UNC 路径，macOS 绝对路径被拒；rc.1 亦无本地图片路由 |
| `dsh-appearance-gallery`（皮肤库） | 升级后设置面板消失（跨版本 UI 插槽变动） |
| 「回答里直接出流程图/图片」 | 属 0.1.5 的能力（POSIX 本地图片路径渲染 + 新版 Web DOM） |

替代用法：流程图输出 `mermaid` 代码块后用 [mermaid.live](https://mermaid.live) 查看；图片先落到工作区给路径，再由用户拖入对话作为附件。

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

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-09 | 首次整理：基于 dsh 0.1.2-rc.1，收录 5 个插件 + 2 个 skills，macOS 实测、Windows 适配说明 |
