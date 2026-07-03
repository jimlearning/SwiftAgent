# SwiftAgent Roadmap

## 阶段进度 — Core（已完成）

| 阶段 | 名称 | 状态 | 备注 |
|---|---|---|---|
| 0 | Project Scaffolding | ✅ 完成 | Package.swift, docs, CI scripts |
| 1 | Core Types & Domain Model | ✅ 完成 | 22 type files, full CC domain model |
| 2 | LLM Adapter & Streaming | ✅ 完成 | LLMClient, StreamParser, RetryPolicy, ModelRegistry, TokenCounter |
| 3 | Agent Loop | ✅ 完成 | QueryEngine, PromptBuilder, ContextManager, ToolExecutor, StreamRenderer |
| 4 | Tool System | ✅ 完成 | 43 tools (Read/Write/Edit/Bash/Glob/Grep + Agent/Skill/Task*/MCP/etc.) |
| 5 | CLI & Terminal UI | ✅ 完成 | ChatCommand, TerminalRenderer, LineEditor (paste, multi-line, ESC cancel), MarkdownRenderer |
| 6 | Permission & Safety | ✅ 完成 | 10-step pipeline, AST-aware SafetyChecker, PermissionStore |
| 7 | Configuration System | ✅ 完成 | 5-layer ConfigLoader, ConfigSchema, APIKeyResolver |
| 8 | Slash Commands | ✅ 完成 | CommandRegistry with built-ins |
| 9 | Session & Memory | ✅ 完成 | SessionStore (JSON), MemoryStore (CLAUDE.md with frontmatter) |
| 10 | MCP Integration | ✅ 完成 | MCPClient, SSE/HTTP transport, tool bridge |
| 11 | Sub-Agent & Tasks | ✅ 完成 | SubAgentManager, TaskManager (actor), WorktreeManager |
| 12+ | Advanced Features | ✅ 完成 | HookSystem, PluginManager, FeatureFlags |

## 阶段进度 — SwiftAgentApp（已完成）

| 阶段 | 名称 | 状态 | 备注 |
|---|---|---|---|
| 1 | Skeleton | ✅ 完成 | HSplitView 3-pane (Sidebar / Content / Right), DesignSystem, Sidebar, Content, Right panel |
| 2 | DeepSeek Integration | ✅ 完成 | DeepSeekClient, KeychainStore, Composer 4 controls, streaming chat |
| 3 | Multi-Thread + Persistence | ✅ 完成 | SQLite storage, Projects, Threads, Messages, slash commands |
| 4 | Advanced Features | ✅ 完成 | Skills, MCP, Worktree, Appshots, 4-tier permissions, right multi-tabs |
| 5 | Polish | ✅ 完成 | Settings (4 cat/13 tabs), 27+ shortcuts, animations, 16 errors, a11y, UI tests |

构建: 0 错误, 0 警告。测试: 258 通过 (Core, CLI, App)。

## 当前阻塞项

无。

## 后续优先级

### v1.1（计划中）

1. **Computer Use** — Agent 桌面交互（点击、输入、导航应用）
2. **6 Role Plugins** — 专业 agent 角色（Code Reviewer, Architect, DevOps 等）
3. **Face ID / Password Lock** — macOS 本地解锁，用于敏感操作
4. **完善存根功能** — Voice input (^M), Browser panel (WKWebView), Terminal panel (PTY)
5. **Enhanced Appshots** — 多窗口捕获、区域选择

### v1.2+（未来）

1. **Mobile Companion** — iOS 配套应用
2. **Remote SSH** — 第一方远程执行
3. **Cloud Environments** — 托管远程沙箱
4. **Sites Deployment** — 一键部署到托管

## 近期完成项

全部 12 个核心阶段 + 5 个应用阶段已完成。阶段 5（Polish）交付了：
- Settings 窗口，包含 4 个类别 / 13 个选项卡
- 完整键盘快捷键表（27+ 个快捷键）
- 动画系统，支持 reduce-motion
- 16 种错误状态（banner/toast/modal）
- 无障碍（VoiceOver labels, high contrast, dynamic type）
- XCUITest 套件，覆盖核心流程
- CHANGELOG.md，更新了 docs（CLAUDE.md, AGENTS.md, ARCHITECTURE.md, AI_HANDOFF.md, README.md）

### TUI 分解（2026 年 6 月）

- **ChatCommand** 拆分为 5 个扩展文件：`+Types`、`+SystemPrompt`、`+ToolDisplay`、`+SessionPicker`、`+UserPrompt`。主文件从 1,992 行缩减至 1,111 行（-44%）。
- **LineEditor** 分解为 5 个独立模块：`TextBuffer`（值类型缓冲区）、`TerminalInput`（原始 I/O + escape 解析）、`EditorRenderer`（终端绘制）、`PasteBurstDetector`（粘贴处理）、`ComposerState`（弹窗状态机）。主文件从 1,287 行缩减至 461 行（-64%）。
- CLI 目录从 10 个文件增长到 27 个文件，每个文件具有单一、明确的职责。
