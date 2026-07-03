# SwiftAgent 文档

## 索引

| 文档 | 适用对象 | 阅读时机... |
|-----|-----|--------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | 模块边界、设计决策、详细布局 | 需要了解模块如何组合或代码应该放在何处时 |
| [ROADMAP.md](ROADMAP.md) | 阶段进度、后续优先级、阻塞项 | 需要了解已完成事项和下一步工作内容时 |
| [AI_HANDOFF.md](AI_HANDOFF.md) | 完整的 CC 对齐快照 | 作为新 AI/开发者上手，或需要完整差距分析时 |
| [PROMPT_CACHE_HIT_RATE.md](PROMPT_CACHE_HIT_RATE.md) | 提示缓存请求形状对齐、测量结果和陷阱 | 正在修改 LLM 请求格式或调查缓存命中率时 |
| [../specs/](../specs/) | 可执行功能规格 | 正在实现特定功能并需要验收标准时 |

## 快速开始

```bash
swift build --disable-sandbox     # 0 错误, 0 警告
swift test --disable-sandbox --no-parallel   # 171 tests, 47 suites
swift run --disable-sandbox swift-agent chat
```

## 当前 CLI 运行时说明

- 后台 sub-agent 通过 `TaskManager` 进行跟踪，配合结构化进度快照。`TaskOutput(block: true)` 在等待期间发送实时进度，因此聊天 spinner 可以汇总正在运行的后台任务，而非仅显示 `Running TaskOutput...`。
- 终端渲染测试覆盖了 CJK 宽度、markdown 表格、粘贴占位符、并行工具调度以及紧凑的后台任务进度状态。

## 项目概览

SwiftAgent 是 Swift 原生的 Claude Code 重新实现。两个模块：

- **SwiftAgentCore** — Agent 运行时：types, tools, LLM adapter, agent loop, safety, config, MCP, hooks, plugins
- **SwiftAgentCLI** — 终端：ArgumentParser commands, chat loop, ANSI rendering, line editor, markdown renderer

CC 源码参考：`~/CLI/claude-code/`
