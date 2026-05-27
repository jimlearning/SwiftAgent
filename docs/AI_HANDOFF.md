# SwiftAgent — AI Handoff 文档

> **This is a point-in-time snapshot.** For living documentation, see the files below. This document is updated after major alignment milestones, not per-commit.
>
> | Living doc | Covers |
> |---|---|
> | [ARCHITECTURE.md](ARCHITECTURE.md) | Module boundaries, design decisions, conventions |
> | [ROADMAP.md](ROADMAP.md) | Phase progress, next priorities |
> | [../CLAUDE.md](../CLAUDE.md) | AI quick-reference (build, structure, conventions) |
> | [../AGENTS.md](../AGENTS.md) | Agent behavior, principles, guardrails |

## 项目概述

**SwiftAgent** 是 [Claude Code](https://github.com/anthropics/claude-code) 的 Swift 语言 1:1 复刻版。目标是完整复刻 Claude Code 的源码架构、类型系统、工具生态和交互行为。

- **项目路径**: `/Users/jim/SwiftAgent/`
- **CC 源码参考**: `/Users/jim/SwiftAgent/claude-code/`
- **当前对齐度**: ~99.0%
- **构建系统**: Swift Package Manager (0 warnings)
- **测试**: 171 个测试 / 47 个测试套件，全部通过

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
    └── SwiftAgentCLITests/       # 终端渲染和输入回归测试；总计 47 套件，171 测试
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

- `TaskManager` now stores structured progress (`TaskProgressEvent` / `TaskProgressSummary`) alongside the legacy accumulated `output` text.
- `SubAgentManager` maps streaming agent events into structured phases such as `thinking`, `using_tool`, `writing_results`, and `turn_complete`.
- `TaskOutputTool(block: true)` polls task snapshots while waiting and emits `TaskOutputProgressData`, allowing the CLI spinner to show compact background-task summaries instead of only `Running TaskOutput...`.
- Regression coverage lives in `Phase11SubAgentTests` and `TerminalRenderingTests`.

### ✅ 已完成对齐（主要）

| 领域 | 状态 |
|------|------|
| **Tool 协议** | ✅ 所有方法签名匹配 CC（call, description, prompt, validateInput, checkPermissions 等） |
| **工具名称** | ✅ 全部 43 个工具的 LLM 名称匹配 CC（PascalCase，无 "Tool" 后缀） |
| **工具参数** | ✅ JSON schema 全部使用 camelCase，匹配 CC |
| **searchHint** | ✅ 33 个工具有 CC 匹配的搜索提示 |
| **shouldDefer** | ✅ 24 个工具设置为 true，匹配 CC |
| **isConcurrencySafe** | ✅ 全部 9 个不匹配已修正 |
| **aliases** | ✅ BriefTool 有 `["Brief"]` 别名 |
| **REPL 模式** | ✅ 现在是配置概念（非可调用工具），匹配 CC |
| **CLI 交互** | ✅ 粘贴检测、多行输入 (Option+Enter/Shift+Enter)、ESC 取消、Markdown 渲染、行编辑器历史、CJK 宽度对齐 |
| **类型系统** | ✅ 22 个类型文件涵盖全部 CC 领域类型 |
| **QueryEngine** | ✅ streaming, batch, hooks, compaction, content block accumulation |
| **MessageNormalizer** | ✅ 9 passes 匹配 CC（stripSignature, user-merge, assistant merge 等） |
| **LLMClient** | ✅ auth headers, model normalization, fallback, beta keys |
| **PermissionEngine** | ✅ 10 步管道, AST-aware, denial tracking |
| **Hook 系统** | ✅ 所有事件类型, 异步执行, 超时, JSON 解析, blocking/non-blocking |
| **MCP 传输** | ✅ SSE 和 HTTP 传输实现 |
| **ConfigLoader** | ✅ 层级优先级加载匹配 CC |
| **ClaudeMdLoader** | ✅ 层级加载 + @include 指令 |
| **PluginManager** | ✅ 目录扫描, manifest 优先级（.claude-plugin/ → plugin.json → manifest.json） |
| **MemoryStore** | ✅ frontmatter 解析, project/user memory |
| **Branded IDs** | ✅ SessionId, AgentId 等品牌化类型 |
| **Settings** | ✅ 80+ 字段匹配 CC |

### ⚠️ 剩余差距（~1.0%）

| 差距 | 影响 | 修复难度 |
|------|------|----------|
| **MCPTool/McpAuthTool 为 stub** | MCP 工具调用的完整实现需要 MCP 客户端基础设施 | 高 |
| **RemoteTriggerTool 为 stub** | 需要 claude.ai OAuth API 后端 | 高（需要后端） |
| **TeamCreateTool/TeamDeleteTool 为 stub** | 需要多代理 swarm 基础设施（tmux, team files） | 高 |
| **prompt() 方法内容** | SA 在 description() 中有文档内容，prompt() 有协议但未被调用 | 中 |
| **isEnabled() 覆盖** | 19 个工具需要功能开关检查（isTodoV2Enabled, isAgentSwarmsEnabled 等） | 中（需要基础设施） |
| **CLI 标志** | CC 有 ~70 个 CLI 标志，SA 有 ~7 个（--model, --permission, --api-key, --no-color, --no-markdown, --debug/-d, --help） | 中 |
| **TUI 功能** | 完整终端 UI（tmux, iTerm2 集成）未实现 | 高 |
| **CLI 交互** | ✅ 粘贴检测、多行输入 (Option+Enter/Shift+Enter)、ESC 取消、Markdown 渲染、行编辑器历史、CJK 宽度对齐 | 已完成 |
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

## 如果继续开发，建议的优先级
