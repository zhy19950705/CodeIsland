<h1 align="center">
  <img src="logo.png" width="48" height="48" alt="SuperIsland Logo" valign="middle">&nbsp;
  SuperIsland
</h1>
<p align="center">
  <b>macOS 灵动岛（刘海）实时 AI 编码 Agent 状态面板</b><br>
  <a href="#一键安装">一键安装</a> •
  <a href="#功能特性">功能</a> •
  <a href="#支持的工具">支持的工具</a> •
  <a href="#从源码构建">构建</a><br>
  <a href="README.md">English</a> | 简体中文
</p>

---

<p align="center">
  <img src="docs/images/notch-panel.png" width="700" alt="SuperIsland Panel Preview">
</p>

## SuperIsland 是什么？

SuperIsland 常驻在 MacBook 刘海区域，实时展示 AI 编码 Agent 的工作状态。你不用频繁切回终端或 IDE，就能直接看到 Claude、Codex、Gemini、Cursor 等工具当前是否正在执行、等待授权、请求输入，还是已经完成。

它通过 Unix socket IPC 接入多种 AI 编码工具，把会话状态、工具调用、权限请求和 AI 回复集中显示在一个轻量的像素风面板里。

## 功能特性

- 刘海原生 UI，空闲时自动收起，工作时展开
- 支持 9 种 AI 编码工具：Claude Code、Codex、Gemini CLI、Cursor、Copilot、Qoder、Factory、CodeBuddy、OpenCode
- 实时展示会话状态、工具调用和权限请求
- 支持在面板中直接审批权限、回答问题
- 点击会话可跳回对应终端标签页或 IDE 窗口
- 支持像素风角色、音效、外接显示器和中英双语
- 自动安装和修复 hooks，减少手工配置成本

## 支持的工具

| | 工具 | 事件 | 跳转 | 状态 |
|:---:|------|------|------|------|
| <img src="docs/images/mascots/claude.gif" width="28"> | <img src="Sources/SuperIsland/Resources/cli-icons/claude.png" width="16"> Claude Code | 13 | 终端标签页 | 完整 |
| <img src="docs/images/mascots/codex.gif" width="28"> | <img src="Sources/SuperIsland/Resources/cli-icons/codex.png" width="16"> Codex | 3 | 终端 | 基础 |
| <img src="docs/images/mascots/gemini.gif" width="28"> | <img src="Sources/SuperIsland/Resources/cli-icons/gemini.png" width="16"> Gemini CLI | 6 | 终端 | 完整 |
| <img src="docs/images/mascots/cursor.gif" width="28"> | <img src="Sources/SuperIsland/Resources/cli-icons/cursor.png" width="16"> Cursor | 10 | IDE | 完整 |
| <img src="docs/images/mascots/copilot.gif" width="28"> | <img src="Sources/SuperIsland/Resources/cli-icons/copilot.png" width="16"> Copilot | 6 | 终端 | 完整 |
| <img src="docs/images/mascots/qoder.gif" width="28"> | <img src="Sources/SuperIsland/Resources/cli-icons/qoder.png" width="16"> Qoder | 10 | IDE | 完整 |
| <img src="docs/images/mascots/factory.gif" width="28"> | <img src="Sources/SuperIsland/Resources/cli-icons/factory.png" width="16"> Factory | 10 | IDE | 完整 |
| <img src="docs/images/mascots/codebuddy.gif" width="28"> | <img src="Sources/SuperIsland/Resources/cli-icons/codebuddy.png" width="16"> CodeBuddy | 10 | APP/终端 | 完整 |
| <img src="docs/images/mascots/opencode.gif" width="28"> | <img src="Sources/SuperIsland/Resources/cli-icons/opencode.png" width="16"> OpenCode | All | APP/终端 | 完整 |

## 一键安装

推荐直接运行：

```bash
curl -fsSL https://guandata-autotest-report.oss-cn-hangzhou.aliyuncs.com/cdn/superIsland/install.sh | bash
```

这条命令会自动：

- 从 OSS 读取最新 `version.json`
- 下载对应版本的 `SuperIsland.dmg`
- 挂载 DMG 并安装 `SuperIsland.app`
- 默认覆盖安装到 `/Applications/SuperIsland.app`

如果 `/Applications` 需要管理员权限，脚本会在安装阶段请求 `sudo`。

### 手动下载

也可以直接下载 DMG：

```bash
open https://guandata-autotest-report.oss-cn-hangzhou.aliyuncs.com/cdn/superIsland/SuperIsland.dmg
```

下载后将 `SuperIsland.app` 拖到「应用程序」目录即可。

### App 内更新

App 内“检查更新”会读取下面这份清单：

```text
https://guandata-autotest-report.oss-cn-hangzhou.aliyuncs.com/cdn/superIsland/version.json
```

清单里会提供当前版本的 `downloadUrl`、`releaseUrl` 和 `installerUrl`。

## 从源码构建

需要：

- macOS 14+
- Swift 5.9+

```bash
git clone https://github.com/wxtsky/SuperIsland.git
cd SuperIsland

# 开发模式
swift build && open .build/debug/SuperIsland.app

# 发布模式（universal binary）
./build.sh
open .build/release/SuperIsland.app
```

## 工作原理

```text
AI 工具
  → 触发 Hook 事件
    → superisland-bridge
      → Unix socket (/tmp/superisland-<uid>.sock)
        → SuperIsland 接收事件
          → 实时更新 UI
```

SuperIsland 会把轻量级 hooks 安装到各个 AI 工具的配置中。工具触发事件后，hook 会把 JSON 消息通过 Unix socket 发给桌面应用，面板收到后立即刷新状态。

对 OpenCode，则是通过 JS 插件直接连接 socket，不依赖额外桥接进程。

## 设置

当前设置面板主要包含：

- 通用：语言、开机启动、显示器选择
- 行为：自动隐藏、智能通知抑制、会话清理
- 外观：面板高度、字体大小、AI 回复行数
- 角色：预览像素风角色和动画
- 声音：8-bit 风格音效
- Hooks：查看安装状态、重装或卸载 hooks
- 关于：版本信息和链接

## 系统要求

- macOS 14.0（Sonoma）或更高版本
- 带刘海的 MacBook 体验最佳，但也支持外接显示器

## 首次启动提示

首次启动时，macOS 可能提示来自未认证开发者。这是未做 Developer ID 签名和公证时的正常现象。你可以在：

- 系统设置 → 隐私与安全性

里选择“仍要打开”。

## 致谢

本项目受 [claude-island](https://github.com/farouqaldori/claude-island) 启发，感谢原项目提供把 AI Agent 状态带进 macOS 刘海区域的思路。

## 许可证

MIT 许可证，详见 [LICENSE](LICENSE)。
