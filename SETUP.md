# OpenCode 全局配置安装复现文档

目的：在新环境（新机器 / WSL / Linux）重建本目录的插件与工具配置。所有步骤均在本机实测过（2026-08-28）。

## 1. 运行时依赖

| 工具 | 版本参考 | 安装 | 用途 |
|------|---------|------|------|
| Node.js | v22.22.2（nvm） | nvm | npm 全局包 |
| bun | 1.4.0 | `curl -fsSL https://bun.sh/install \| bash`（装完 `source ~/.bashrc`） | opencode 运行插件依赖安装（`bun install`）+ ocx CLI 的运行时 |
| ocx | 2.0.15 | `npm i -g ocx` | OCX 生态插件安装器（依赖 bun 在 PATH） |

## 2. opencode.jsonc 核心配置

`plugin` 数组当前内容（opencode.jsonc 与本文档同步维护）：

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["superpowers@git+https://github.com/obra/superpowers.git"],
  "lsp": true,
  "instructions": ["~/.config/opencode/memory-mechanism.md"],
  "permission": { "*": "allow", "git push": "deny" }
}
```

superpowers 无需手动装——opencode 启动时用 bun 自动拉取。

## 3. 插件清单

### 3.1 opencode-notify（系统通知）

- 仓库：https://github.com/kdcokenny/opencode-notify （MIT，288★）
- 作用：AI 完成任务 / 出错 / 请求权限 / 提问时发系统原生通知
- WSL2 路径：node-notifier 检测到 WSL 自动走 `WindowsToaster` 分支（node-notifier/index.js），用 vendor 自带 `snoretoast-x64.exe` 经 WSL interop 弹 **Windows 原生 Toast**——不依赖 notify-send，WSLg 无 D-Bus 通知服务是正常现象
- 跨平台：macOS 走 alerter（需 `brew install vjeantet/tap/alerter`）、Windows 走 SnoreToast、Linux 原生走 notify-send（需 `sudo apt install libnotify-bin`）

安装（OCX 方式，装到全局 `~/.config/opencode/plugins/`）：

```bash
npm i -g ocx            # 若未装
ocx init --global       # 生成 ocx.jsonc + profiles/default（幂等）
ocx add kdco/notify --from https://registry.kdco.dev --global
npm install --prefix ~/.config/opencode   # ocx 有时删了 node_modules 不重装，手动补
```

落位文件（自动加载，无需 opencode.jsonc 条目）：
- `plugins/notify.ts` + `plugins/notify/`（backend/cmux/status/title）
- `plugins/kdco-primitives/`（10 个依赖文件）
- 依赖：`node-notifier`、`detect-terminal`（package.json devDependencies）

**WSL 已知坑**：npm/bun 装出的 `snoretoast-*.exe` 无执行权限（644），插件静默失败。修复已在 package.json 加 postinstall：

```json
"scripts": {
  "postinstall": "chmod +x node_modules/node-notifier/vendor/snoreToast/*.exe 2>/dev/null || true"
}
```

验证：

```bash
chmod +x ~/.config/opencode/node_modules/node-notifier/vendor/snoreToast/*.exe
~/.config/opencode/node_modules/node-notifier/vendor/snoreToast/snoretoast-x64.exe -t "测试" -m "验证"
# 退出码 3=TimedOut 表示 Toast 已弹出（成功）；右下角应可见
```

可选配置 `~/.config/opencode/kdco-notify.json`（默认开箱即用）：quietHours 免打扰、notifyChildSessions、per-event 提示音。

### 3.2 tokscale（token 用量统计，纯本地）

- 仓库：https://github.com/junhoyeo/tokscale （MIT，5188★）
- 作用：读 `~/.local/share/opencode/opencode.db`，统计 LLM 调用次数、今日/本周/历史 token、按模型/客户端分布、成本估算；交互式 TUI
- 数据来源：只读本地 SQLite，不进 opencode 上下文

```bash
npm i -g tokscale
tokscale                        # 交互式 TUI（8 视图 + 贡献图）
tokscale --client opencode --today --light   # 今日表格
tokscale --client opencode --week --light    # 本周表格
tokscale models --today --json  # 模型分布，JSON 含 messageCount（调用次数）
```

隐私约定（重要，勿破坏）：
- **只用本地模式**：不运行 `tokscale login` / `tokscale submit` / `tokscale autosubmit enable`
- 保持 `~/.config/tokscale/settings.json` 中 `autosubmit.enabled: false`
- 唯一出网行为：拉 LiteLLM 价格表（只下载不上传）
- 曾评估 opencode-quota（919★）：token 报表部分本地，但 quota 功能必须带 API key 连厂商 API，未采用
- 曾装 opencode-wakatime 后卸载：心跳上报文件路径到 wakatime.com 云端，隐私不合适

## 4. 卸载对照

```bash
# opencode-notify
ocx remove kdco/notify --global   # 若 ocx 支持；否则手动删 plugins/notify* plugins/kdco-primitives
# tokscale
npm uninstall -g tokscale && rm -rf ~/.config/tokscale
```

## 5. 新环境快速核对清单

1. 装 nvm + Node 22、bun、npm 全局包（ocx、tokscale）
2. 确认 `~/.config/opencode/opencode.jsonc` plugin 数组含 superpowers
3. `ocx init --global && ocx add kdco/notify --from https://registry.kdco.dev --global`
4. `npm install --prefix ~/.config/opencode`（补 node-notifier / detect-terminal / @opencode-ai/plugin）
5. 确认 package.json 有 postinstall chmod 钩子（WSL .exe 权限坑）
6. WSL 通知验证：跑上面的 snoretoast 直调命令，Windows 右下角见 Toast 即通
7. 重启 opencode 生效