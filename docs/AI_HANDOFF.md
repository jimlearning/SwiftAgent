# SwiftAgent — AI Handoff 文档

> **这是某个时间点的快照。** 有关最新文档，请参见下方文件。本文档在主要对齐里程碑后更新，而非每次提交。
>
> | 最新文档 | 涵盖内容 |
> |---|---|
> | [ARCHITECTURE.md](ARCHITECTURE.md) | 模块边界、设计决策、约定 |
> | [ROADMAP.md](ROADMAP.md) | 阶段进度、下一步优先级 |
> | [../CLAUDE.md](../CLAUDE.md) | AI 快速参考（构建、结构、约定） |
> | [../AGENTS.md](../AGENTS.md) | Agent 行为、原则、护栏 |

## 项目概述

**SwiftAgent** 是 [Claude Code](https://github.com/anthropics/claude-code) 的 Swift 语言 1:1 复刻版。目标是完整复刻 Claude Code 的源码架构、类型系统、工具生态和交互行为。

- **项目路径**: `/Users/jim/SwiftAgent/`
- **CC 源码参考**: `~/CLI/claude-code/`
- **当前对齐度**: ~99.0%
- **构建系统**: Swift Package Manager（0 warnings）
- **测试**: 258 个测试 / 61 个测试套件，全部通过

---

## 架构概览

```
Sources/
├── SwiftAgentCore/               # 核心库（所有业务逻辑）
│   ├── Types/                    # 类型系统（22 文件）— 协议、枚举、结构体
│   │   ├── Tool.swift            # Tool 协议定义（核心接口）
│   │   ├── Conversation.swift    # 对话/消息模型
│   │   ├── Config.swift          # 80+ 设置字段
│   │   ├── Permission.swift      # 权限类型
│   │   ├── StreamEvent.swift     # 流式事件
│   │   ├── HookJSONTypes.swift   # Hook JSON 类型
│   │   ├── MessageFactory.swift  # 消息工厂函数
│   │   ├── Session.swift         # 会话管理
│   │   ├── Ids.swift            # 品牌化 ID（SessionId, AgentId 等）
│   │   └── ...                   # Agent, AttachmentTypes, ClassifierTypes, 
│   │                             #   CompactionTypes, InputTypes, LogEntries,
│   │                             #   MCPServerConfig, SDKTypes, SandboxSettings,
│   │                             #   SettingSource, SlashCommand, SystemMessage,
│   │                             #   ThinkingConfig
│   │
│   ├── Tools/                    # 43 个工具（一文件一工具，匹配 CC 约定）
│   │   ├── BashTool.swift        # Shell 执行
│   │   ├── FileReadTool.swift    # 文件读取
│   │   ├── FileWriteTool.swift   # 文件写入
│   │   ├── FileEditTool.swift    # 文件编辑（精确字符串替换）
│   │   ├── GlobTool.swift        # 文件名模式匹配
│   │   ├── GrepTool.swift        # ripgrep 内容搜索
│   │   ├── AgentTool.swift       # 子代理调度
│   │   ├── SkillTool.swift       # 技能调用
│   │   ├── TaskCreateTool.swift  # 任务管理系列
│   │   ├── TaskGetTool.swift
│   │   ├── TaskListTool.swift
│   │   ├── TaskOutputTool.swift
│   │   ├── TaskStopTool.swift
│   │   ├── TaskUpdateTool.swift
│   │   ├── TodoWriteTool.swift   # 待办列表
│   │   ├── WebSearchTool.swift   # Web 搜索
│   │   ├── WebFetchTool.swift    # Web 抓取
│   │   ├── LSPTool.swift         # LSP 代码智能
│   │   ├── ConfigTool.swift      # 配置管理
│   │   ├── BriefTool.swift       # 用户消息（SendUserMessage）
│   │   ├── AskUserQuestionTool.swift
│   │   ├── EnterPlanModeTool.swift
│   │   ├── ExitPlanModeV2Tool.swift
│   │   ├── EnterWorktreeTool.swift
│   │   ├── ExitWorktreeTool.swift
│   │   ├── SendMessageTool.swift # 代理间消息
│   │   ├── SkillTool.swift
│   │   ├── ToolSearchTool.swift  # 延迟工具搜索
│   │   ├── NotebookEditTool.swift # Jupyter Notebook 编辑
│   │   ├── PowerShellTool.swift  # Windows PowerShell（平台条件）
│   │   ├── REPLMode.swift        # REPL 模式配置（非可调用工具）
│   │   ├── MCPTool.swift         # MCP 工具调用（stub）
│   │   ├── McpAuthTool.swift     # MCP OAuth 认证
│   │   ├── ListMcpResourcesTool.swift
│   │   ├── ReadMcpResourceTool.swift
│   │   ├── RemoteTriggerTool.swift # 远程触发（stub）
│   │   ├── TeamCreateTool.swift    # 多代理团队（stub）
│   │   ├── TeamDeleteTool.swift    # 团队删除（stub）
│   │   ├── CronCreateTool.swift    # 定时任务
│   │   ├── CronListTool.swift
│   │   ├── CronDeleteTool.swift
│   │   ├── SyntheticOutputTool.swift # 合成输出测试
│   │   ├── SleepTool.swift
│   │   ├── BuiltInAgents.swift      # 内置代理定义
│   │   ├── CronTypes.swift          # Cron 辅助类型
│   │   └── WorktreeTypes.swift      # Worktree 辅助类型
│   │
│   ├── Agent/                    # Agent 循环引擎
│   │   ├── QueryEngine.swift     # 核心查询循环（streaming, batch, hooks, compaction）
│   │   ├── ToolExecutor.swift    # 工具执行器（并发/流式）
│   │   ├── MessageNormalizer.swift # 消息规范化（9 passes）
│   │   ├── SystemPromptBuilder.swift # 系统提示构建
│   │   ├── Compactor.swift       # 上下文压缩
│   │   ├── SubAgentManager.swift # 子代理管理
│   │   ├── TaskManager.swift     # 后台任务管理
│   │   ├── StreamRenderer.swift  # 流式输出渲染
│   │   ├── ContextManager.swift  # 上下文管理
│   │   └── WorktreeManager.swift # Git worktree 管理
│   │
│   ├── LLM/                      # LLM 客户端
│   │   ├── LLMClient.swift       # HTTP 客户端（auth headers, model normalization, fallback）
│   │   ├── LLMStreamParser.swift # SSE 流解析器
│   │   ├── ModelRegistry.swift   # 模型注册表
│   │   ├── RetryPolicy.swift     # 重试策略
│   │   └── TokenCounter.swift    # Token 计数
│   │
│   ├── Safety/                   # 权限与安全
│   │   ├── PermissionEngine.swift # 10 步权限管道
│   │   ├── SafetyChecker.swift    # AST 感知安全检查
│   │   ├── PermissionStore.swift  # 权限持久化
│   │   └── PermissionClassifier.swift
│   │
│   ├── MCP/                      # MCP 集成
│   │   ├── MCPClient.swift       # MCP 客户端
│   │   ├── MCPTransport.swift    # SSE/HTTP 传输
│   │   ├── MCPToolBridge.swift   # 工具桥接
│   │   └── MCPResourceTypes.swift
│   │
│   ├── Config/                   # 配置加载
│   │   ├── ConfigLoader.swift    # 层级优先级加载
│   │   ├── ConfigSchema.swift    # Schema 定义
│   │   └── APIKeyResolver.swift  # API Key 解析
│   │
│   ├── State/                    # 应用状态
│   │   ├── AppState.swift
│   │   └── AppStateStore.swift
│   │
│   ├── Features/                 # 功能开关
│   │   └── FeatureFlags.swift
│   │
│   ├── Hooks/                    # Hook 系统
│   │   └── HookSystem.swift      # 所有 CC hook 事件类型
│   │
│   ├── Commands/                 # 命令系统
│   │   └── CommandRegistry.swift # Slash 命令注册 + 别名匹配
│   │
│   ├── Plugins/                  # 插件系统
│   │   └── PluginManager.swift   # 目录扫描 + manifest 加载
│   │
│   ├── Storage/                  # 持久化
│   │   ├── MemoryStore.swift     # 记忆存储（frontmatter 解析）
│   │   └── SessionStore.swift    # 会话存储
│   │
│   ├── Workspace/                # 工作区
│   │   └── ClaudeMdLoader.swift  # CLAUDE.md 层级加载 + @include
│   │
│   ├── Utilities/                # 工具函数
│   │   └── ToolResultStorage.swift # 工具结果磁盘持久化
│   │
│   ├── CoreTypes.swift           # 核心枚举和常量（ExitReason 等）
│   └── ShellResolver.swift       # Shell 解析
│
├── SwiftAgentCLI/                # CLI 入口
│   ├── EntryPoint.swift          # 程序入口
│   ├── ChatCommand.swift         # 主命令 + 全部 43 工具注册 + 内联代理循环
│   ├── TerminalRenderer.swift    # 终端渲染 (banner, spinner, left-border)
│   ├── TerminalCapability.swift  # 终端能力检测
│   ├── LineEditor.swift          # Raw-mode 行编辑器 (历史、bracketed paste、多行输入、ESC 取消)
│   ├── MarkdownRenderer.swift    # Markdown → ANSI 渲染 (标题、代码块、表格、引用)
│   ├── TerminalDisplayWidth.swift # CJK/emoji 终端显示宽度计算
│   ├── DebugLogger.swift         # JSONL 调试日志 (API 请求/响应)
│   ├── ColorTheme.swift          # 色彩主题
│   └── StreamRenderer.swift      # SSE 流事件渲染
│
└── Tests/
    ├── SwiftAgentCoreTests/
    └── SwiftAgentCLITests/       # 终端渲染和输入回归测试；总计 61 套件，258 测试
        ├── Phase1TypesTests.swift
        ├── Phase2LLMTests.swift
        ├── Phase3AgentTests.swift
        ├── Phase4ToolsTests.swift
        ├── Phase6SafetyTests.swift
        ├── Phase7ConfigTests.swift
        ├── Phase8CommandsTests.swift
        ├── Phase9StorageTests.swift
        ├── Phase10MCPTests.swift
        ├── Phase11SubAgentTests.swift
        ├── Phase12AdvancedTests.swift
        └── CoreTypesTests.swift
```

---

## 构建和测试

```bash
# 构建
swift build --disable-sandbox

# 运行全部测试
swift test --disable-sandbox --no-parallel

# 运行单个测试套件
swift test --disable-sandbox --no-parallel --filter Phase4ToolsTests
```

**注意**: 必须使用 `--disable-sandbox` 因为测试涉及文件系统操作。必须使用 `--no-parallel` 因为部分测试有共享状态。

---

## 当前对齐状态（~99.0%）

### 最近修复：后台 subagent 进度 UX

- `TaskManager` 现在存储结构化的进度信息（`TaskProgressEvent` / `TaskProgressSummary`），与传统累积的 `output` 文本并存。
- `SubAgentManager` 将流式 agent 事件映射为结构化阶段，如 `thinking`、`using_tool`、`writing_results` 和 `turn_complete`。
- `TaskOutputTool(block: true)` 在等待期间轮询任务快照并发出 `TaskOutputProgressData`，使 CLI spinner 能够显示紧凑的后台任务摘要，而非仅显示 `Running TaskOutput...`。
- 回归测试覆盖位于 `Phase11SubAgentTests` 和 `TerminalRenderingTests` 中。

### 已完成对齐（主要）

| 领域 | 状态 |
|------|------|
| **Tool 协议** | 所有方法签名匹配 CC（call, description, prompt, validateInput, checkPermissions 等） |
| **工具名称** | 全部 43 个工具的 LLM 名称匹配 CC（PascalCase，无 "Tool" 后缀） |
| **工具参数** | JSON schema 全部使用 camelCase，匹配 CC |
| **searchHint** | 33 个工具有 CC 匹配的搜索提示 |
| **shouldDefer** | 24 个工具设置为 true，匹配 CC |
| **isConcurrencySafe** | 全部 9 个不匹配已修正 |
| **aliases** | BriefTool 有 `["Brief"]` 别名 |
| **REPL 模式** | 现在是配置概念（非可调用工具），匹配 CC |
| **CLI 交互** | 粘贴检测、多行输入 (Option+Enter/Shift+Enter)、ESC 取消、Markdown 渲染、行编辑器历史、CJK 宽度对齐 |
| **类型系统** | 22 个类型文件涵盖全部 CC 领域类型 |
| **QueryEngine** | streaming, batch, hooks, compaction, content block accumulation |
| **MessageNormalizer** | 9 passes 匹配 CC（stripSignature, user-merge, assistant merge 等） |
| **LLMClient** | auth headers, model normalization, fallback, beta keys |
| **PermissionEngine** | 10 步管道, AST-aware, denial tracking |
| **Hook 系统** | 所有事件类型, 异步执行, 超时, JSON 解析, blocking/non-blocking |
| **MCP 传输** | SSE 和 HTTP 传输实现 |
| **ConfigLoader** | 层级优先级加载匹配 CC |
| **ClaudeMdLoader** | 层级加载 + @include 指令 |
| **PluginManager** | 目录扫描, manifest 优先级（.claude-plugin/ → plugin.json → manifest.json） |
| **MemoryStore** | frontmatter 解析, project/user memory |
| **Branded IDs** | SessionId, AgentId 等品牌化类型 |
| **Settings** | 80+ 字段匹配 CC |

### 剩余差距（~1.0%）

| 差距 | 影响 | 修复难度 |
|------|------|----------|
| **MCPTool/McpAuthTool 为 stub** | MCP 工具调用的完整实现需要 MCP 客户端基础设施 | 高 |
| **RemoteTriggerTool 为 stub** | 需要 claude.ai OAuth API 后端 | 高（需要后端） |
| **TeamCreateTool/TeamDeleteTool 为 stub** | 需要多代理 swarm 基础设施（tmux, team files） | 高 |
| **prompt() 方法内容** | SA 在 description() 中有文档内容，prompt() 有协议但未被调用 | 中 |
| **isEnabled() 覆盖** | 19 个工具需要功能开关检查（isTodoV2Enabled, isAgentSwarmsEnabled 等） | 中（需要基础设施） |
| **CLI 标志** | CC 有 ~70 个 CLI 标志，SA 有 ~7 个（--model, --permission, --api-key, --no-color, --no-markdown, --debug/-d, --help） | 中 |
| **TUI 功能** | 完整终端 UI | 高 |
| **CC 内部工具** | TungstenTool, SuggestBackgroundPRTool 等 ant-only 工具未复制 | 不需要 |

---

## 关键设计约定

1. **一文件一工具**: 每个工具实现一个 .swift 文件，匹配 CC 的文件组织方式
2. **PascalCase 工具名**: 所有工具的 LLM 名称使用 PascalCase（如 `"Bash"` 而非 `"bash"`），匹配 CC
3. **camelCase 参数**: 所有 JSON schema 属性使用 camelCase（如 `"taskId"` 而非 `"task_id"`），匹配 CC
4. **CC 原生 snake_case 保留**: Edit/Write/Read 工具的 `file_path`、`old_string`、`new_string`、`replace_all` 保持 snake_case（这是 CC 自己的约定）
5. **Tool 协议**: 核心协议定义在 `Types/Tool.swift`，所有工具通过 struct 实现 Tool 协议
6. **描述在 description()**: 工具文档内容在 `description()` 方法中（LLM 可见），`prompt()` 定义在协议上但尚未被系统提示构建器调用

---

## SwiftAgentApp — macOS App（第 1-5 阶段已完成，v0.5.0）

> **截至 2026-06-16**，SwiftAgentApp macOS target 交付了完全打磨的产品。

### 架构

macOS App 采用 **MVVM** 配合 SwiftUI，底层由 SQLite 持久化支持：

- **AppViewModel** — 根状态（项目、线程、API key、LLM provider、**布局开关**）
- **ThreadViewModel** — 每个线程的状态、消息发送/流生命周期
- **ProjectViewModel** — 每个项目的状态

数据流：Storage（SQLite）→ AppViewModel → 通过 `@Published` / `@EnvironmentObject` 流向 SwiftUI 视图。

### 三栏布局（HSplitView）

主窗口是三栏 `HSplitView`（侧边栏 | 内容 | 右侧标签），三个独立开关（`sidebarVisible`、`rightVisible`、`focusMode`）接入原生 macOS 工具栏，通过 `.toolbar { ToolbarItem(placement: .navigation | .primaryAction) }` 实现。详见 [ARCHITECTURE.md](ARCHITECTURE.md) 的 "macOS App 布局 — HSplitView 三栏" 部分了解设计原理（为什么不用 `NavigationSplitView`，为什么专注模式将 `ContentView` 从树中完全移除）。

### 关键模块

| 模块 | 描述 | 文件数 |
|--------|-------------|-------|
| **设置** | 独立窗口（4 类 × 13 标签页） | 18 文件 |
| **右侧标签** | 多标签工作区（Review/Terminal/Browser/Files/Side chat） | 10 文件 |
| **存储** | SQLite 持久化（Projects、Threads、Messages） | 6 文件 |
| **DeepSeek** | 流式 Chat Completions、Keychain API key | 4 文件 |
| **技能** | 技能库 + 创建向导 | 4 文件 |
| **MCP** | MCP 服务器配置 + 管理 | 4 文件 |
| **Appshots** | Cmd+Cmd 通过 Accessibility API 截屏 | 4 文件 |
| **错误** | 16 种错误状态，带 Banner/Toast/Modal 展示 | 4 文件 |
| **动画** | 时长 token、缓动、减少动画支持 | 1 文件 |
| **无障碍** | a11y 标签、高对比度、动态字体、VoiceOver | 1 文件 |
| **快捷键** | 27+ 快捷键注册表（单一事实来源） | 1 文件 |
| **设计系统** | Color、Typography、Spacing、Radius、StatusDot | 5 文件 |

### 设置分类

- **个人**（5 个标签页）：通用、外观、配置、个性化、键盘快捷键
- **集成**（4 个标签页）：Appshots、MCP 服务器、浏览器、Computer Use（占位）
- **编码**（5 个标签页）：Hooks、连接、Git、环境、Worktrees
- **归档**（1 个标签页）：已归档聊天（恢复 / 永久删除）

### 键盘快捷键（27+）

15 个快捷键通过 App Scene 中的 `.commands` modifier 绑定。完整表格（27+ 条目）显示在设置 → 键盘快捷键中。分类：线程管理（7）、导航（7）、右侧标签（10）、面板（3）、环境（1）、全局（5）。

### 错误状态（16 种）

规范中的所有 16 种已覆盖：沙箱拒绝、网络重连、429 速率限制、5xx 模型错误、Worktree 冲突、401 无效密钥、402 余额不足、Appshot 权限、Appshot 截取失败、MCP 断开连接、技能加载失败、Diff 合并失败、/goal 持久化失败、项目切换数据丢失、线程列表 >1000、网络代理。

### 无障碍

- 所有交互元素已标记
- 检测到"减少动画"并缩短动画时长
- 遵循高对比度模式
- 支持动态字体
- 语义色彩（无纯颜色-only 信号）

### 测试

- **258 个单元测试**，跨 61 个套件（Core、CLI、App）— 全部通过
- **5 个 XCUITest 套件**（LaunchAndSeeLayout、NewThreadSendsMessage、SwitchPanel、SettingsOpens、ThemeSwitch）

### 构建

```bash
swift build --disable-sandbox    # 0 errors, 0 warnings
swift test --disable-sandbox --no-parallel  # 258 通过, 0 失败
```

---

## 如果继续开发，建议的优先级
