# Phase 5: CLI & 终端 UI

## Requirements
- 实现交互式 Chat 命令 (readline-based)
- ANSI 转义序列渲染
- 终端原始模式 (raw mode) 输入处理
- 流式输出渲染器集成

## Technical Notes
- 对应 Claude Code 的 `cli.tsx` + Ink 渲染框架
- Swift 无直接对应 Ink，使用内置 ANSI 转义序列
- 终端能力检测 (isTTY, color support, columns)

## Files to Create

| 文件 | 说明 |
|---|---|
| SwiftAgentCLI/ChatCommand.swift | 交互式对话命令 |
| SwiftAgentCLI/TerminalRenderer.swift | ANSI 渲染工具 |
| SwiftAgentCLI/TerminalCapability.swift | 终端能力检测 |
| SwiftAgentCLI/StatusLine.swift | 底部状态栏 |
| SwiftAgentCLI/ColorTheme.swift | 颜色主题定义 |

## Acceptance Criteria
- [ ] `swift-agent chat` 启动交互式对话
- [ ] ANSI 颜色输出正常工作
- [ ] 状态栏显示 token 使用量
- [ ] Ctrl+C 处理退出
- [ ] 非 TTY 模式输出纯文本
- [ ] `swift build` + `swift test` 通过

**Output when complete:** `<promise>DONE</promise>`
