# SwiftAgent 架构

## 模块边界

### SwiftAgentCore（库）
可共享、可复用的 agent 运行时。无 CLI/TUI 依赖。

**职责：**
- 领域类型（Conversation、Message、Tool、Permission、Config 等）
- Agent 循环引擎（query → stream → execute → loop）
- 工具系统（协议、注册表、43 个内置工具）
- LLM 适配器（Anthropic API 客户端、流式传输、重试）
- 配置管理（多源加载、合并）
- 权限引擎（基于模式的决策管道）
- Session 和记忆持久化
- MCP 协议集成
- 子 agent 和任务管理
- Hooks、插件、功能开关

### SwiftAgentCLI（可执行文件）
精简的 CLI 层。所有 UI/UX 均位于此处。

**职责：**
- ArgumentParser 命令结构
- 终端渲染（ANSI 转义序列、虚拟缓冲区、diff）
- 输入处理（raw mode、composer、history、slash 补全）
- 权限审批 UI
- 流式输出格式化和 Markdown 渲染

## 设计原则

1. **无上帝文件。** 当文件难以推理时就进行分解。
2. **显式类型。** 优先使用枚举和结构体，而非布尔值和位置字面量。
3. **Actor 隔离。** 对可变共享状态使用 Swift actor。
4. **Claude Code 对等。** 命名、行为和边界与 Claude Code 对齐。
5. **无需线上模型即可测试。** 单元测试使用 Mock LLM 响应。

## 关键架构决策

| 决策 | 选择 | 原因 |
|---|---|---|
| 终端渲染 | 自定义 3 层 ANSI 引擎 | 不存在 Swift 版的 Ink；构建定制方案 |
| 异步模型 | Swift Concurrency（async/await, actor, AsyncStream） | 自然映射到 CC 的 AsyncGenerator 模式 |
| 工具定义 | Protocol + struct conformance | Swift 原生的方式表达 CC 的 builder 模式 |
| 提示管理 | 外部 .md 文件配合模板变量 | 直接复用 claude-code-system-prompts |
| 配置格式 | JSON（settings.json） | 兼容现有 Claude Code 配置 |
| Agent 循环位置 | ChatCommand（内联），而非 QueryEngine | 匹配 CC 模式；CLI 掌管循环编排 |
| 流解析 | 手动 SSE 累积 + contentBlockStop parse | CC 模式；避免对部分工具输入进行过早解析 |
| 子 agent 执行 | REPL 将 `AgentTool` 接入 `SubAgentManager` | 前台子 agent 完整运行并在状态行显示进度；后台子 agent 返回 `TaskOutput` 任务 ID，进度和最终输出存储在 `TaskManager` 中 |
| ChatCommand 分解 | 扩展文件（`+Type`、`+SystemPrompt` 等） | 保持结构体定义不变，使用模块级可见性进行扩展访问。从 1,992 行缩减至 1,111 行（-44%） |
| LineEditor 分解 | 5 个独立模块（`TextBuffer`、`TerminalInput`、`EditorRenderer`、`PasteBurstDetector`、`ComposerState`） | 类纯函数子系统，无终端副作用。从 1,287 行缩减至 461 行（-64%） |
| macOS App 布局 | `HSplitView` 三栏（而非 `NavigationSplitView`）+ 原生 `.toolbar` | 3 个独立开关（sidebar / right / focus）无法通过 `NavigationSplitViewVisibility` 的 4-case 枚举来表达，且 `.navigationSplitViewColumnWidth(min: 0)` 会保留已折叠列的布局槽位。`HSplitView`（NSSplitView 包装器）具有固定顺序列、灵活宽度 — 将某列折叠至 0pt 后其余列自然扩展填满。 |
| macOS 专注模式 | `if !focusMode { ContentView() }` — 完全从树中移除，而非 `.frame(width: 0)` | `ContentView` 携带 `.layoutPriority(1)`，因此即使宽度为 0，它仍占据前导槽位并把 `SidebarView` 挤到中间。从树中移除后 `HSplitView` 重新布局 sidebar + right，sidebar 回到前导边缘填满释放的空间。 |
| 聊天渲染 | `NSTableView` 配合 cell 复用 + `NSStackView` blocks（非 SwiftUI `ScrollView`+`VStack`） | SwiftUI `ScrollView` 一次性构建所有视图 — 500 条消息的对话会 OOM。NSTableView 通过 `makeView(withIdentifier:owner:)` 回收行。每行（`ChatTableRowView`）使用 `NSStackView` 垂直堆叠 `ChatBlockView` 实例。每行高度通过 `measureHeight()` 计算并缓存结果。 |
| 消息模型 | 工具结果是 assistant 消息内的内联 blocks（非独立系统消息） | 匹配流式传输事件传递方式：工具结果紧接在其工具使用卡片之后弹出。`fromTurns` 将结果内联在匹配的 `toolUse` blocks 旁边，而非生成独立的系统消息。`fromCore` 同样处理 assistant 消息中的 `toolResult` blocks。这使得工具卡片 + 结果在视觉上保持相邻，避免孤立的结果远离其上下文。 |
| `fromTurns` UUID 策略 | 首个 assistant 获取 `lastAssistantID`（替换流式占位符），后续轮次获取唯一 `assistant.uuid` | 所有轮次共享同一 UUID 会在 JSONL 去重中冲突（`readMessages` 保留每个 UUID 的最后出现），导致较早轮次的工具使用 blocks 被静默丢弃。每轮唯一 UUID 保留所有 blocks。 |
| 折叠系统 | `FoldTarget.toolResult` 仅以 `toolUseID` 为键（无 `messageID`）；`FoldState` 在 Coordinator 中持久化 | 工具卡片及其结果 block 位于不同行/消息中（工具卡片在 assistant 消息中，结果可能在同一或相邻消息中）。仅以 `toolUseID` 为键确保点击卡片时无论哪个消息携带结果都能切换。`FoldState` 是 `AppKitChatBridge.Coordinator` 拥有的 `ObservableObject`，跨重载复用，因此折叠状态在切换线程时能保持。 |
| 折叠工具结果渲染 | 零高度 — header 和 content 均隐藏，`intrinsicContentSize.height = 0` | 之前折叠结果仅隐藏内容文本，留下可见的 "Result" header 并占用空间。完全零高度折叠将该 block 从布局中彻底移除，使其下方文本能干净上移。 |

## 设计约定

1. **每个工具一个文件** — 匹配 CC 的文件组织方式
2. **PascalCase LLM 工具名** — `"Bash"` 而非 `"bash"`，匹配 CC
3. **camelCase JSON schema 属性** — `"taskId"` 而非 `"task_id"`，匹配 CC
4. **保留 CC 原生 snake_case** — Edit/Write/Read 工具保留 `file_path`、`old_string`、`new_string`、`replace_all`（CC 自身约定）
5. **Tool 协议** 定义在 `Types/Tool.swift` 中，所有工具通过 struct 实现
6. **工具描述** 在 `description()` 方法中（LLM 可见）；`prompt()` 定义在协议上，但尚未接入 SystemPromptBuilder

## CC 工具实现对齐

每个工具必须匹配 CC 的底层机制，而非仅匹配 API 表面。
实现策略很重要：文件枚举 vs 二进制委托、循环结构 vs 输出切片等。

### GlobTool — `rg --files --glob`（非 FileManager.enumerator）

**CC**（`utils/glob.ts`）：委托给 ripgrep，通过 `rg --files --glob <pattern> --sort=modified --no-ignore --hidden <path>`。JavaScript 中无文件系统遍历 — ripgrep 在 Rust 中处理一切并在完成后立即退出。结果切片：`absolutePaths.slice(offset, offset + limit)`。

**之前**：`FileManager.default.enumerator(atPath:)` — 对搜索树中的每个文件进行深度递归枚举（O(所有文件)），然后截断至 100 条。`NSAllDescendantPathsEnumerator` 遍历 `Library`、`Caches`、`DerivedData` 等，导致在 home 目录中使用 `**/*.swift` 等宽泛模式时挂起数分钟。

**之后**（已对齐）：
- 主要：`rg --files --glob <pattern> --sort=modified --no-ignore --hidden`，配合 VCS 排除 `--glob !.git` 等。与 CC 相同的参数。
- 回退：Foundation enumerator，在 100 条结果时提前 `break`，并为 `Library`、`Caches`、`node_modules`、`.swiftpm` 等使用 `skipDirs`。
- 结果：任何目录均毫秒级完成，永不挂起。

### GrepTool — `rg` 配合完整参数集（已对齐）

使用 ripgrep 进行内容搜索：`--hidden`、`--max-columns`、`-i`、`-n`、`-U --multiline-dotall`、`--glob`、`--type`、`-C/-B/-A` 上下文行。rg 未安装时回退到 `NSRegularExpression`。匹配 CC 的 `GrepTool.ts` / `ripgrep.ts`。

### AgentTool / SubAgentManager — 对话隔离

子 agent 获得一个仅设置了 `systemPrompt` 的全新 `Conversation` — 不泄露父对话。`disallowedTools` 防止递归 agent 生成（Explore agent 不能调用 Agent）。工具通过 `effectiveTools(allToolNames:)` 过滤。

### QueryEngine — Turn.toolResults 已填充

CC 的 `QueryEngine.ts` 在每个 `Turn` 中捕获工具结果，以便完整的对话结构（user → assistant {tool_use} → user {tool_result}）在通过 `fromTurns` → `buildConversation` 往返过程中得以保留。之前 `QueryEngine.run()` 将 `toolResultMsg` 追加到 `messages` 但不追加到 `completedTurns[].toolResults`，导致 `fromTurns` 重建产生孤立的 `tool_use` blocks 而没有匹配的 `tool_result` blocks — API 在后续发送中拒绝此请求并返回 HTTP 400。已通过填充 `Turn.toolResults` 修复。

## 详细模块布局

```
Sources/SwiftAgentCore/
├── Types/                    # 22 个文件 — 协议、枚举、结构体
│   ├── Tool.swift            # 核心 Tool 协议
│   ├── Conversation.swift    # Message、Conversation 模型
│   ├── Config.swift          # 80+ 设置字段
│   ├── Permission.swift      # 权限类型和模式
│   ├── StreamEvent.swift     # SSE 流事件类型
│   ├── HookJSONTypes.swift   # Hook 事件 JSON 类型
│   ├── MessageFactory.swift  # 消息构造辅助
│   ├── Session.swift         # Session 管理类型
│   ├── Ids.swift             # 品牌化 ID（SessionId、AgentId 等）
│   └── ...                   # Agent, AttachmentTypes, ClassifierTypes,
│                             #   CompactionTypes, InputTypes, LogEntries,
│                             #   MCPServerConfig, SDKTypes, SandboxSettings,
│                             #   SettingSource, SlashCommand, SystemMessage,
│                             #   ThinkingConfig
│
├── Tools/                    # 43 个工具，每个文件一个
│   ├── BashTool.swift        # Shell 执行
│   ├── FileReadTool.swift    # 文件读取
│   ├── FileWriteTool.swift   # 文件写入
│   ├── FileEditTool.swift    # 精确字符串替换
│   ├── GlobTool.swift        # 文件名模式匹配
│   ├── GrepTool.swift        # ripgrep 内容搜索
│   ├── AgentTool.swift       # 子 agent 分发
│   ├── SkillTool.swift       # 技能调用
│   ├── Task*Tool.swift       # 任务管理（Create/Get/List/Output/Stop/Update）
│   ├── TodoWriteTool.swift   # 待办列表
│   ├── WebSearchTool.swift   # Web 搜索
│   ├── WebFetchTool.swift    # Web 抓取
│   ├── LSPTool.swift         # LSP 代码智能
│   └── ...                   # Cron*, MCP*, NotebookEdit, PowerShell 等
│
├── Agent/                    # Agent 循环引擎
│   ├── QueryEngine.swift     # 核心查询循环（streaming、batch、hooks、compaction）
│   ├── ToolExecutor.swift    # 工具执行（并发/流式）
│   ├── MessageNormalizer.swift # 消息规范化（9 passes）
│   ├── SystemPromptBuilder.swift # 系统提示构建
│   ├── Compactor.swift       # 上下文压缩
│   ├── SubAgentManager.swift # 子 agent 管理
│   ├── TaskManager.swift     # 后台任务生命周期（actor）
│   ├── StreamRenderer.swift  # 流式输出渲染
│   ├── ContextManager.swift  # 上下文管理
│   └── WorktreeManager.swift # Git worktree 隔离
│
├── LLM/                      # LLM 客户端层
│   ├── LLMClient.swift       # HTTP 客户端（认证、模型规范化、回退）
│   ├── LLMStreamParser.swift # SSE 流解析器
│   ├── ModelRegistry.swift   # 模型注册表
│   ├── RetryPolicy.swift     # 重试策略
│   └── TokenCounter.swift    # Token 计数
│
├── Safety/                   # 权限与安全
│   ├── PermissionEngine.swift # 10 步权限管道
│   ├── SafetyChecker.swift    # AST 感知安全检查
│   ├── PermissionStore.swift  # 权限持久化
│   └── PermissionClassifier.swift
│
├── MCP/                      # Model Context Protocol
│   ├── MCPClient.swift       # MCP 客户端（actor）
│   ├── MCPTransport.swift    # SSE/HTTP 传输
│   ├── MCPToolBridge.swift   # MCP 工具 → ToolDefinition 桥接
│   └── MCPResourceTypes.swift
│
├── Config/                   # 配置
│   ├── ConfigLoader.swift    # 5 层优先级合并
│   ├── ConfigSchema.swift    # Schema 定义与验证
│   └── APIKeyResolver.swift  # API key 解析链
│
├── State/                    # 应用状态
│   ├── AppState.swift        # 中央状态 actor
│   └── AppStateStore.swift   # Pub/sub 桥接
│
├── Features/                 # 功能开关
│   └── FeatureFlags.swift    # 运行时 + 编译时开关
│
├── Hooks/                    # Hook 系统
│   └── HookSystem.swift      # 所有 CC hook 事件类型，异步执行
│
├── Commands/                 # 命令系统
│   └── CommandRegistry.swift # Slash 命令注册 + 别名匹配
│
├── Plugins/                  # 插件系统
│   └── PluginManager.swift   # 目录扫描 + manifest 加载
│
├── Storage/                  # 持久化
│   ├── MemoryStore.swift     # 记忆存储（YAML frontmatter 解析）
│   └── SessionStore.swift    # Session JSON 持久化
│
├── Workspace/                # 工作区
│   └── ClaudeMdLoader.swift  # CLAUDE.md 层级加载 + @include
│
├── Utilities/                # 工具函数
│   └── ToolResultStorage.swift # 工具结果磁盘持久化
│
├── CoreTypes.swift           # 核心枚举（ExitReason 等）
└── ShellResolver.swift       # Shell 解析

Sources/SwiftAgentCLI/
├── EntryPoint.swift          # 程序入口点
├── ChatCommand.swift         # 编排器：run() + ArgumentParser 结构体
├── ChatCommand+Types.swift   # 共享类型（ExpandState、SessionState、CurrentToolTracker 等）
├── ChatCommand+SystemPrompt.swift  # 系统提示构建器（MCP、CLAUDE.md、延迟工具）
├── ChatCommand+ToolDisplay.swift   # 工具结果显示、Ctrl+O 展开/折叠
├── ChatCommand+SessionPicker.swift # 交互式会话选择器菜单
├── ChatCommand+UserPrompt.swift    # 交互式问题提示处理
├── TerminalRenderer.swift    # ANSI 渲染（banner、spinner、左边框、panel）
├── TerminalCapability.swift  # 终端能力检测（TTY、色彩、尺寸）
├── StatusLine.swift          # 底部常驻状态栏（token 用量、工作状态）
├── LineEditor.swift          # Raw-mode 编辑器的精简编排器
├── TextBuffer.swift          # 纯值类型文本/光标缓冲区，支持词边界
├── TerminalInput.swift       # 原始终端 I/O + 转义序列解析
├── EditorRenderer.swift      # 缓冲区→终端绘制，支持显示宽度
├── ComposerState.swift       # Popup 模式状态机（/ 和 @ 补全）
├── PasteBurstDetector.swift  # 粘贴突发检测 + 占位符替换
├── MarkdownRenderer.swift    # Markdown → ANSI（标题、代码块、表格）
├── InlinePopup.swift         # Popup UI 渲染（带滚动/高亮的菜单）
├── PopupDataSource.swift     # Popup 的命令 + 文件数据源
├── TerminalDisplayWidth.swift # CJK/emoji 感知的终端列宽辅助
├── ColorTheme.swift          # 色彩主题定义（default、monochrome）
├── DebugLogger.swift         # JSONL API 请求/响应日志
├── CollapseDetector.swift    # 工具结果折叠检测
├── ToolResultCache.swift     # 折叠结果缓存，供 /expand 使用
├── FileSearchIndex.swift     # 基于 git ls-files 的搜索索引，用于 @-mention
├── FuzzyMatcher.swift        # Popup 搜索的模糊匹配
├── TokenANSIRenderer.swift   # Token 级 ANSI 渲染
├── CodeTheme.swift           # 代码语法高亮主题
├── ChatToolExecutionScheduler.swift  # 并发工具执行
├── ChatToolInputAccumulator.swift    # 流式工具输入 JSON 累积器
└── ToolResultCache.swift     # 折叠/展开用工具结果缓存

Sources/SwiftAgentApp/            # macOS SwiftUI App（DeepSeek 驱动）
├── EntryPoint.swift              # @main App 入口、窗口、命令、错误覆盖层
├── Window/
│   └── MainContentView.swift     # HSplitView 三栏 + 原生 .toolbar（见下方 "macOS App 布局"）
├── Sidebar/
│   ├── SidebarView.swift         # 项目、线程、设置链接
│   ├── ProjectRowView.swift      # 项目可展开行
│   └── ThreadRowView.swift       # 线程可选择行
├── Content/
│   ├── ContentView.swift         # 中间栏：工具栏 + 消息 + 编辑器
│   ├── ComposerView.swift        # 消息输入（文本、发送、slash 命令）
│   ├── AppKitChatBridge.swift    # Coordinator：AppKit↔SwiftUI 桥接，FoldState 所有者
│   ├── ChatTableView.swift       # NSTableView 配合 cell 复用、高度缓存、流式传输
│   ├── ChatTableRowView.swift    # 行视图：NSStackView block 堆叠、折叠处理
│   ├── ChatBlockViews.swift      # Block 视图：text、thinking、toolUse、toolResult、system
│   ├── ChatFoldModel.swift       # FoldTarget 枚举 + FoldState ObservedObject + 自动折叠
│   └── ChatScrollContainer.swift # 滚动容器，配合粘性 + 浮动滚动按钮
├── RightTabs/
│   ├── RightTabsView.swift       # 多标签右侧工作区容器
│   ├── RightTabsStore.swift      # 标签状态管理
│   ├── TabBarView.swift          # 水平标签栏
│   ├── TabLabel.swift            # 单个标签标签
│   ├── TabContentView.swift      # 活动标签内容切换
│   ├── RightTab.swift            # 标签数据模型
│   ├── RightTabType.swift        # 标签类型枚举（review/terminal/browser/files/sideChat）
│   ├── AddTabMenu.swift          # + 按钮弹出菜单
│   ├── EmptyTabPlaceholder.swift # 空状态
│   └── panels/
│       └── ReviewPanelView.swift # Diff 审查面板
├── DeepSeek/
│   ├── DeepSeekClient.swift      # 流式 Chat Completions（SSE）
│   ├── DeepSeekConfig.swift      # API URL、模型、key 配置
│   ├── DeepSeekModel.swift       # 模型枚举（V3、R1、CoderV2）
│   └── KeychainStore.swift       # 安全 API key 存储
├── LLM/
│   └── AppLLMProvider.swift      # LLM provider 包装器
├── Storage/
│   ├── StorageManager.swift      # 数据库生命周期
│   ├── Database.swift            # SQLite 连接
│   ├── Migrations.swift          # Schema 迁移
│   ├── Models.swift              # 持久化数据模型
│   ├── ProjectRepository.swift   # Project CRUD
│   ├── ThreadRepository.swift    # Thread CRUD
│   └── MessageRepository.swift   # Message CRUD
├── ViewModels/
│   ├── AppViewModel.swift        # 根 app 状态（项目、线程、API key）
│   ├── ThreadViewModel.swift     # 线程状态 + 消息发送
│   ├── ProjectViewModel.swift    # 项目状态
│   └── ComposerViewModel.swift   # 编辑器输入状态
├── Skills/
│   ├── SkillsView.swift          # 技能库浏览器
│   ├── SkillCard.swift           # 单个技能卡片
│   ├── SkillCreatorSheet.swift   # 技能创建向导
│   └── SkillScope.swift          # 技能范围枚举（user/project/system）
├── MCP/
│   ├── MCPConfigView.swift       # MCP 服务器管理
│   ├── MCPConfigStore.swift      # MCP 配置持久化
│   ├── MCPServerCard.swift       # 服务器卡片（含状态）
│   └── AddMCPServerSheet.swift   # 添加服务器表单
├── Worktree/
│   ├── WorktreeManager.swift     # Git worktree 操作
│   └── WorktreePickerSheet.swift # Worktree 选择器 UI
├── Appshots/
│   ├── GlobalHotkey.swift        # Cmd+Cmd 监听器 + toast 状态
│   ├── AppshotCapture.swift      # 通过 Accessibility API 截屏
│   ├── AppshotToastView.swift    # 截屏成功/失败 toast
│   └── AXTextExtractor.swift     # AX 文本提取
├── Modals/
│   ├── PermissionModal.swift     # 沙箱权限弹窗
│   ├── PermissionPicker.swift    # 权限级别选择器
│   ├── NewProjectSheet.swift     # 新建项目
│   ├── ModelPicker.swift         # 模型选择 sheet
│   ├── SlashCommandPalette.swift # Slash 命令选择器
│   ├── RenameSheet.swift         # 重命名线程/项目
│   ├── RenameTarget.swift        # 重命名目标枚举
│   ├── AddMenu.swift             # 编辑器 + 菜单
│   └── PluginsSubmenu.swift      # 插件子菜单
├── URLHandling/
│   └── URLRouter.swift           # swiftagent:// URL 路由
├── Settings/                     # 独立设置窗口
│   ├── SettingsWindow.swift      # 带侧边栏 + 内容的窗口
│   ├── personal/
│   │   ├── GeneralSettings.swift
│   │   ├── AppearanceSettings.swift
│   │   ├── ConfigurationSettings.swift
│   │   ├── PersonalizationSettings.swift
│   │   └── KeyboardShortcutsSettings.swift
│   ├── integrations/
│   │   ├── AppshotsSettings.swift
│   │   ├── MCPServersSettings.swift
│   │   ├── BrowserSettings.swift
│   │   └── ComputerUseSettings.swift
│   ├── coding/
│   │   ├── HooksSettings.swift
│   │   ├── ConnectionsSettings.swift
│   │   ├── GitSettings.swift
│   │   ├── EnvironmentsSettings.swift
│   │   └── WorktreesSettings.swift
│   └── archived/
│       └── ArchivedChatsSettings.swift
├── Animations/
│   ├── AnimationTokens.swift     # 时长/缓动 token 定义
│   └── ViewExtensions.swift      # 过渡辅助
├── Errors/
│   ├── ErrorPresenter.swift      # 16 种错误状态，严重性分类
│   ├── ErrorBannerView.swift     # 顶部横幅（可重试错误）
│   ├── ErrorToastView.swift      # 底部 toast（警告）
│   └── ErrorModalView.swift      # 弹窗覆盖层（严重错误）
├── Accessibility/
│   └── A11yExtensions.swift      # a11y 标签、对比度、减少动画
├── Shortcuts/
│   └── ShortcutRegistry.swift    # 27+ 快捷键，单一事实来源
└── DesignSystem/
    ├── Color.swift               # 设计 token 色彩（深色模式）
    ├── Typography.swift          # 字体定义
    ├── Spacing.swift             # 间距刻度
    ├── Radius.swift              # 圆角半径 token
    └── StatusDot.swift           # 状态指示器组件

Tests/
├── SwiftAgentCoreTests/      # 核心库测试（16 个套件）
├── SwiftAgentCLITests/       # 终端渲染和输入回归测试
├── SwiftAgentAppTests/       # App 单元测试（8 个套件）
└── SwiftAgentAppUITests/     # XCUITest 套件（5 个套件）
```

## App 架构 — SwiftAgentApp

macOS App 采用 **MVVM** 配合 SwiftUI，底层由 SQLite 持久化支持：

- **AppViewModel** — 根 view model，拥有全部状态（项目、线程、API key、LLM provider、**布局开关**）
- **ThreadViewModel** — 每个线程的状态、消息列表、发送/流生命周期
- **ProjectViewModel** — 每个项目的状态（名称、路径、线程）
- **ComposerViewModel** — 输入缓冲区状态、slash 命令解析

数据从 Storage（SQLite）→ AppViewModel → 通过 `@Published` / `@EnvironmentObject` 流向 SwiftUI 视图。

设置窗口是**独立 NSWindow**（非应用内弹出层，符合 §17 #23），通过 `⌘,` 或侧边栏 ⚙ 链接使用 URL scheme `swiftagent-settings://` 打开。

### macOS App 布局 — HSplitView 三栏

主窗口是三栏工作区：**侧边栏（左） | 内容（中） | 右侧标签（右）**。每个栏可通过原生 macOS 工具栏独立开关。

```
┌─────────────────────────────────────────────────────┐
│ [▤]                                  [⤡] [▥]       │  ← macOS 原生 .toolbar
├──────────┬──────────────────────┬───────────────────┤
│ 侧边栏   │  内容（聊天）         │  右侧标签         │
│ (240-320)│  (480-inf)           │  (380-520)        │
└──────────┴──────────────────────┴───────────────────┘
```

**为什么是 `HSplitView` 而非 `NavigationSplitView`**

我们最初使用 `NavigationSplitView`，因为它是 macOS 的"现代导航"模式。它在两个方面打破了 3 独立开关模型：

1. `.navigationSplitViewColumnWidth(min: 0)` 将某列折叠至 0pt，但 `NavigationSplitView` 仍保留折叠列的布局槽位 — 相邻列不会扩展填满空隙。专注模式（折叠内容）会留下空白带且右侧栏不会扩展填补。
2. `NavigationSplitViewVisibility` 只有 4 个 case：`.automatic`、`.all`、`.doubleColumn`、`.detailOnly`。**没有任何值表示"侧边栏 + detail，隐藏内容"** — 这正是专注模式所需。通过 4-case 枚举映射 3 个独立开关是有损的。

`HSplitView`（AppKit 的 `NSSplitView` 的 SwiftUI 包装器）具有固定顺序列、灵活宽度。将某列折叠至 0pt 后其余列自然扩展填满释放的空间。无保留布局槽位，无枚举映射噩梦。

**为什么专注模式使用 `if !focusMode { ContentView() }`**

我们尝试了 `.frame(minWidth: 0, idealWidth: 0, maxWidth: 0)` 将 `ContentView` 折叠至 0 宽度。结果：`ContentView` 仍然占据前导布局槽位（因为其携带 `.layoutPriority(1)`），因此 `SidebarView` 被推到窗口中间，右侧栏不会扩展填满空隙。在专注模式下将 `ContentView` 从视图树中完全移除，让 `HSplitView` 重新布局 sidebar + right，使 sidebar 回到前导边缘，right 扩展填满释放的空间。

**布局状态**

`AppViewModel` 拥有三个独立的 `@Published` 标志：

| 标志 | 为 `false` 时的效果 |
|---|---|
| `sidebarVisible` | 侧边栏列的 `min/ideal/max` 宽度均为 0 → 列折叠，内容向左扩展 |
| `rightVisible` | 右侧列的 `min/ideal/max` 宽度均为 0 → 列折叠，内容向右扩展 |
| `focusMode` | `ContentView` 从树中移除 → 右侧栏扩展填满释放的空间；侧边栏保持在原位 |

这些标志**不在启动之间持久化** — 它们是临时的会话偏好。`MainContentView` 通过 `.animation(.easeInOut(duration: 0.18), value: <flag>)` 为宽度变化添加动画，以实现平滑过渡。

**工具栏**

`.toolbar` 附加在 `HSplitView` 上（适用于 `Window` scene 内的任何 SwiftUI 视图），并将三个栏开关渲染到原生 macOS 工具栏：

| 按钮 | 位置 | SF Symbol | 绑定对象 | 快捷键 |
|---|---|---|---|---|
| 侧边栏开关 | `.navigation`（系统侧边栏槽位） | `sidebar.left` | `sidebarVisible` | `⌘B` |
| 专注模式开关 | `.primaryAction`（尾部） | `arrow.up.left.and.arrow.down.right` / `arrow.down.right.and.arrow.up.left`（专注模式下交换） | `focusMode` | （仅工具栏） |
| 右栏开关 | `.primaryAction`（尾部） | `sidebar.squares.right` / `sidebar.right`（右侧隐藏时交换） | `rightVisible` | `⇧⌘B` |

`.navigation` 位置使侧边栏开关获得系统侧边栏折叠按钮样式。专注按钮在激活时获得 `.tint` 前景色，以便用户一眼看到专注状态。

`ShortcutRegistry.panels` 列出了键盘快捷键；实际绑定位于 `EntryPoint.swift` 的 `.commands` modifier（`CommandGroup(after: .toolbar)`）中。

## 参考资料

- [Claude Code 源码研究](~/CLI/Claude-Code-Source-Study/) — 25 章深度分析
- [Claude Code 系统提示](~/CLI/claude-code-system-prompts/) — 190+ 模块化提示
- [Claude Code 源码](~/CLI/claude-code/) — 完整 TypeScript 参考实现（~512K 行）
