# SwiftAgent macApp — 生产级架构

> **目标：** 达到 Codex macOS App 的对等水平，成为 macOS 平台生产级的智能编程 IDE。
> **当前状态：** v0.5.0（演示级别）——本文档描述的是 **v1.0+ 的目标架构**。
> **相关文档：** [ARCHITECTURE.md](ARCHITECTURE.md)（模块边界）、[TUI_ARCHITECTURE.md](TUI_ARCHITECTURE.md)（CLI 渲染引擎）、[ROADMAP.md](ROADMAP.md)（各阶段进度）。

---

## 1. 架构理念

### 1.1. 设计原则

| 原则 | 理由 |
|-------|-----------|
| **AppKit 外壳，SwiftUI 内容** | 在 `NSSplitView`/`NSTabView` 容器内使用 SwiftUI 实现声明式 UI。AppKit 用于窗口管理、菜单栏、自定义文本系统、PTY。边界是 `NSViewRepresentable` / `NSViewControllerRepresentable`，专为 SwiftUI 无法表达的视图而设。 |
| **Actor 隔离的状态，@MainActor 视图** | 所有可变共享状态存在于 Swift actor 或 `@MainActor` ObservableObject 中。没有 `DispatchQueue` 面条代码。所有 ViewModel 上的 `@MainActor` 约束是有意为之——UI 状态变更必须同步到主运行循环。后台工作使用 `Task.detached` 并在完成后切回 actor。 |
| **Core/App 边界不可侵犯** | `SwiftAgentCore` 没有任何 AppKit/SwiftUI 导入。App 层将 Core 类型适配为 ViewModel。这一边界使得：(a) CLI 共享相同的 agent 运行时，(b) 无头/CI 模式复用引擎，(c) 无需 UI 依赖即可测试。 |
| **每个领域概念一个 ViewModel** | 不是一个 View 一个 ViewModel。`ThreadViewModel` 拥有单个线程的完整 agent 循环生命周期。`ComposerViewModel` 拥有输入缓冲区。View 通过 `@Published` 从这些 ViewModel 读取数据——View 是 ViewModel 状态的函数。 |
| **流式传输是第一公民** | LLM 的每个字节都是一个事件。UI 对文本增量、思考增量、工具使用开始/完成以及轮次边界做出反应。不做缓冲到完成才显示。流式管道必须能在后台运行、网络断开和长达 10 分钟的工具执行中存活。 |
| **权限不是对话框——而是一种模式** | 用户设置一个权限姿态（询问 / 批准 / 完全 / 自定义），该姿态管理整个会话。单个工具拒绝以内联横幅形式呈现，而非模态中断。这符合开发者实际使用这些工具的方式：设置一次，很少调整。 |

### 1.2. 什么使架构达到"生产级"

| 关注点 | 演示级别 | 生产级别 |
|---------|-----------|-----------------|
| **状态** | 单个 ViewModel 上的 `@Published`，重启后丢失 | Actor 树，持久化并恢复，能在强制退出后存活 |
| **错误处理** | 失败时 `print()` | 类型化错误分类，带退避重试，用户可见的带操作按钮的横幅 |
| **流式传输** | 即发即忘的 Task，网络慢时 UI 冻结 | 可取消、可恢复、感知背压、有进度指示 |
| **窗口管理** | 单窗口，无状态恢复 | 多窗口、`NSWindowRestoration`、每窗口会话隔离 |
| **持久化** | SQLite 手动 INSERT/UPDATE | WAL 模式、迁移系统、FTS5 搜索、预写日志保障崩溃安全 |
| **无障碍** | 部分视图上有 `.accessibilityLabel()` | 完整 VoiceOver 导航树、动态字体、减弱动态效果、高对比度、纯键盘操作 |
| **性能** | 将所有消息加载到 Array 中 | 虚拟滚动、惰性 block 解码、增量 diff 更新、内存压力处理 |
| **测试** | 少量 XCUITest 录制 | 每个 ViewModel 的单元测试、流式传输的集成测试、UI 快照测试、关键路径的 XCUITest |

---

## 2. 模块地图

```
Sources/SwiftAgentApp/
├── EntryPoint.swift                 # @main App，Scene 声明，.commands
├── AppDelegate.swift                # NSApplicationDelegate，生命周期，URL 处理
│
├── Shell/                           # 窗口和工作区外壳
│   ├── MainWindowController.swift   # NSWindowController — 多窗口，状态恢复
│   ├── MainWindow.swift             # NSWindow 子类 — 标题栏，标签页，尺寸
│   ├── WorkspaceSplitView.swift     # NSSplitView 包装器 — 三栏布局
│   ├── WindowRestoration.swift      # NSWindowRestoration 协议实现
│   └── WindowTabManager.swift       # 每窗口标签页状态 (NSWindowTabGroup)
│
├── Panes/                           # 三个主面板
│   ├── Sidebar/
│   │   ├── SidebarViewController.swift      # 承载 SwiftUI 侧边栏的 NSViewController
│   │   ├── ProjectOutlineView.swift         # 基于 NSOutlineView 的项目树
│   │   ├── ThreadListView.swift             # 带搜索/过滤的 SwiftUI 线程列表
│   │   ├── SidebarSearchController.swift    # Quick Open 风格的模糊搜索
│   │   └── SidebarState.swift               # 展开、选中、过滤状态
│   ├── Content/
│   │   ├── ContentViewController.swift      # 消息列表 + 编辑器的宿主
│   │   ├── MessageListView.swift            # 虚拟滚动消息列表
│   │   ├── MessageBubbleView.swift          # 单条消息渲染
│   │   ├── ThinkingBlockView.swift          # 可展开的推理显示
│   │   ├── ToolCallCardView.swift           # 工具执行卡片（折叠/展开）
│   │   ├── DiffPreviewView.swift            # 内联 unified diff 带语法高亮
│   │   ├── Composer/
│   │   │   ├── ComposerViewController.swift # 基于 NSTextView 的富文本编辑器
│   │   │   ├── ComposerTextView.swift       # NSTextView 子类 — 语法感知
│   │   │   ├── MentionCompletion.swift      # @-mention 自动补全窗口
│   │   │   ├── SlashCommandCompletion.swift # /-command 自动补全
│   │   │   ├── ImagePasteHandler.swift      # 剪贴板图片 → 附件
│   │   │   ├── FileDropHandler.swift        # 拖放文件插入
│   │   │   └── ComposerControlsView.swift   # SwiftUI 控制行（模型、权限、发送）
│   │   └── ContextChipsView.swift           # 活动上下文标签（文件、技能、MCP）
│   └── Right/
│       ├── RightTabsViewController.swift    # NSTabViewController — 标签页管理
│       ├── panels/
│       │   ├── Review/
│       │   │   ├── ReviewPanelView.swift    # 带文件列表和内联预览的 Diff 审查
│       │   │   ├── DiffFileList.swift       # 审查中的变更文件侧边栏
│       │   │   ├── DiffContentView.swift    # 并排或 unified diff 视图
│       │   │   └── DiffViewModel.swift      # Git diff 计算和缓存
│       │   ├── Terminal/
│       │   │   ├── TerminalPanelView.swift  # SwiftUI 包装器
│       │   │   ├── PTYTerminalController.swift # PTY fork + I/O 通过 DispatchIO
│       │   │   ├── TerminalEmulator.swift   # VT100/xterm 状态机
│       │   │   └── TerminalGridView.swift   # Metal 加速的网格渲染器
│       │   ├── Browser/
│       │   │   ├── BrowserPanelView.swift   # WKWebView 包装器
│       │   │   ├── BrowserToolbar.swift     # URL 栏、导航按钮、devtools 开关
│       │   │   └── BrowserViewModel.swift   # URL 状态、历史、devtools 桥接
│       │   ├── Files/
│       │   │   ├── FilesPanelView.swift     # 带 git 状态覆盖的文件浏览器
│       │   │   ├── FileOutlineView.swift    # NSOutlineView — 惰性目录展开
│       │   │   ├── FileContextMenu.swift    # 右键菜单：打开、在 Finder 中显示、git log、diff
│       │   │   └── FilePreviewView.swift    # QuickLook 风格的文件预览
│       │   └── SideChat/
│       │       ├── SideChatPanelView.swift  # 右侧面板中的独立聊天
│       │       └── SideChatViewModel.swift  # 限定作用域的对话状态
│       └── RightTabsStore.swift             # 标签页状态、顺序、持久化
│
├── Agent/                           # Agent 运行时桥接
│   ├── AgentSessionManager.swift    # 子系统引导：run()、cancel()
│   ├── AppAgentProvider.swift       # LLM provider 工厂 + 模型解析
│   ├── AgentMessageAdapter.swift    # Core Message ↔ App AgentMessage 转换
│   ├── StreamingEventBus.swift      # 从 agent 循环发出的 UI 事件的 AsyncSequence
│   ├── PermissionUIBridge.swift     # 将 PermissionEngine 请求映射为 SwiftUI 弹窗
│   ├── AgentMessages.swift          # UI 层消息模型（blocks、流式状态）
│   └── AgentDebugger.swift          # 应用内调试面板 + JSONL 日志
│
├── LLM/                             # 多 provider 的 LLM 层
│   ├── LLMProvider.swift            # 协议：stream()、models()、capabilities()
│   ├── AnthropicProvider.swift      # Anthropic Messages API（Claude 模型）
│   ├── OpenAIChatProvider.swift     # OpenAI Chat Completions（GPT、o-series）
│   ├── DeepSeekProvider.swift       # DeepSeek Chat Completions（V3、R1）
│   ├── LocalModelProvider.swift     # llama.cpp / MLX 服务器桥接
│   ├── ProviderRegistry.swift       # 发现、验证、选择 provider
│   ├── ModelResolver.swift          # 模型名称 → provider + 能力
│   ├── StreamPipeline.swift         # SSE → StreamEvent 管道，带重试
│   └── TokenCounter.swift           # 每模型 token 计数（tiktoken + 回退方案）
│
├── Tools/                           # 工具可视化和交互
│   ├── ToolExecutionTracker.swift   # 每工具状态：pending → running → done/error
│   ├── ToolResultRenderer.swift     # 工具输出显示的内容类型分发
│   ├── ToolDiffGenerator.swift      # 为 Edit/Write 工具计算 unified diff
│   ├── ToolApprovalSheet.swift      # 单个工具批准的 SwiftUI sheet
│   └── ToolOutputTruncation.swift   # 大量输出的智能截断
│
├── Storage/                         # 持久化层
│   ├── StorageManager.swift         # 数据库生命周期、迁移、vacuum
│   ├── Database.swift               # SQLite 连接池（WAL 模式，串行化）
│   ├── Migrations.swift             # 版本化 schema 迁移（仅向前）
│   ├── Models.swift                 # PersistedModel、PersistedThread 等
│   ├── ProjectRepository.swift      # CRUD + FTS 搜索
│   ├── ThreadRepository.swift       # CRUD + 批量操作
│   ├── MessageRepository.swift      # Block 级存储，FTS5 索引
│   ├── ConversationExporter.swift   # 导出为 JSON/Markdown/PDF
│   ├── BackupManager.swift          # 自动 SQLite 备份 + 完整性检查
│   └── SpotlightIndexer.swift       # CSSearchableIndex 集成
│
├── Sync/                            # 多设备同步
│   ├── SyncEngine.swift             # iCloud + 自定义同步编排
│   ├── CloudKitStore.swift          # 基于 CKContainer 的对话同步
│   ├── ConflictResolver.swift       # 最后写入胜出 + 合并策略
│   └── SyncStatusMonitor.swift      # 网络可用性、同步进度
│
├── Editor/                          # 代码编辑器集成
│   ├── EditorBridge.swift           # 外部编辑器集成协议
│   ├── XcodeEditorSource.swift      # Xcode 编辑器集成（通过 Accessibility）
│   ├── VSCodeEditorSource.swift     # VS Code 集成（通过扩展）
│   ├── BuiltInEditorView.swift      # 基础内置代码编辑器 (NSTextView)
│   └── EditingSessionTracker.swift  # 跟踪活跃编辑器、光标、选区
│
├── Workspace/                       # 项目工作区
│   ├── WorkspaceManager.swift       # 多根工作区、.swiftagent/ 配置
│   ├── FileWatcher.swift            # 基于 FSEvents 的文件变更检测
│   ├── GitService.swift             # Git 操作（status、diff、log、blame）
│   ├── LSPClient.swift              # Language Server Protocol 客户端
│   └── ProjectIndexer.swift         # 后台代码索引，供 @-mention 使用
│
├── Settings/                        # 设置（4 个类别 × 13+ 标签页）
│   ├── SettingsWindowController.swift
│   ├── SettingsState.swift          # 发布式设置、持久化、验证
│   ├── personal/                    # 通用、外观、配置、个性化、快捷键
│   ├── integrations/                # Appshots、MCP、浏览器、Computer Use
│   ├── coding/                      # Hooks、连接、Git、环境、Worktrees
│   └── archived/                    # 已归档对话
│
├── Shortcuts/                       # 键盘快捷键系统
│   ├── ShortcutRegistry.swift       # 唯一来源（Command + KeyBinding）
│   ├── ShortcutRecorderView.swift   # 自定义快捷键录制控件
│   └── CommandPalette.swift         # ⌘⇧P 风格命令面板
│
├── Permissions/                     # 权限 UI
│   ├── PermissionBannerView.swift   # 被拒绝操作的内联横幅
│   ├── PermissionModePicker.swift   # 编辑器中的快速模式切换器
│   ├── PermissionRulesEditor.swift  # 自定义规则编辑器（设置中）
│   └── PermissionAuditLog.swift     # 什么被允许/拒绝 + 时间
│
├── Accessibility/
│   ├── A11yExtensions.swift         # 每个交互元素的标签、提示、值
│   ├── VoiceOverNavigator.swift     # 对话导航的自定义转子操作
│   ├── DynamicTypeObserver.swift    # 响应内容大小类别变化
│   └── KeyboardNavigator.swift      # 完整键盘操作（无需鼠标）
│
├── Errors/
│   ├── ErrorPresenter.swift         # 集中式错误状态机
│   ├── ErrorBannerView.swift        # 顶部锚定的可重试错误横幅
│   ├── ErrorToastView.swift         # 底部锚定的临时警告
│   ├── ErrorModalView.swift         # 不可恢复错误的模态框
│   └── ErrorTaxonomy.swift          # AppError 枚举 — 每个错误路径都已枚举
│
├── Appshots/
│   ├── GlobalHotkeyManager.swift    # Cmd+Cmd 监听器 + CGEvent tap
│   ├── AppshotCapture.swift         # 屏幕捕获 + AX 文本提取
│   ├── AppshotAnnotator.swift       # 在捕获上叠加绘图工具
│   ├── AppshotHistoryView.swift     # 最近捕获的画廊
│   └── AppshotToastView.swift       # 捕获确认叠加层
│
├── Notifications/
│   ├── NotificationManager.swift    # UNUserNotificationCenter 委托
│   ├── NotificationScheduler.swift  # 线程完成、权限请求
│   └── NotificationPreferences.swift # 细粒度通知设置
│
├── DesignSystem/
│   ├── Color.swift                  # 语义颜色令牌（原生深色模式）
│   ├── Typography.swift             # 支持动态字体的字体定义
│   ├── Spacing.swift                # 4pt 网格间距比例
│   ├── Radius.swift                 # 圆角半径令牌
│   ├── StatusDot.swift              # 动画状态指示器
│   ├── Icons.swift                  # SF Symbol 目录（哪个符号对应哪个概念）
│   └── AnimationTokens.swift        # 持续时间 + 缓动预设
│
└── Utilities/
    ├── Debouncer.swift              # 搜索/过滤的输入防抖
    ├── Throttler.swift              # 文件监视事件的速率限制器
    ├── ClipboardManager.swift       # 剪贴板监控 + 图片提取
    ├── LoggingInfrastructure.swift  # OSLog 集成，带日志级别 + 分类
    └── TelemetryOptIn.swift         # 匿名使用统计（严格主动选择加入）
```

---

## 3. 数据流架构

### 3.1. 状态层级

```
                    ┌─────────────────────────────┐
                    │     AppViewModel             │
                    │  (根 @MainActor 状态)        │
                    │                               │
                    │  • API key 状态               │
                    │  • Agent 会话引导             │
                    │  • 布局开关                   │
                    │  • Projects[] + globalThreads[]│
                    │  • pendingAttachments          │
                    └──────────┬──────────────────────┘
                               │
            ┌──────────────────┼──────────────────────┐
            ▼                  ▼                       ▼
   ┌────────────────┐  ┌──────────────┐  ┌────────────────────┐
   │ ProjectViewModel│  │ThreadViewModel│  │ SettingsViewModel  │
   │ (每个项目)       │  │ (每个线程)    │  │ (共享，1 个窗口)   │
   │                 │  │               │  │                    │
   │ • name, path    │  │ • messages[]  │  │ • 80+ 设置项       │
   │ • threads[]     │  │ • state       │  │ • keychain I/O     │
   │ • isExpanded    │  │ • model       │  │ • 持久化           │
   └─────────────────┘  │ • agent 循环  │  └────────────────────┘
                         │ • 流式传输   │
                         │ • queue count │
                         └──────┬────────┘
                                │
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼
          ┌──────────────┐ ┌─────────┐ ┌──────────────┐
          │ComposerVM    │ │MessageVM│ │ToolTracker   │
          │ (每个线程)    │ │(每条消息)│ │ (每次运行)    │
          └──────────────┘ └─────────┘ └──────────────┘
```

### 3.2. Agent 循环数据流

```
用户输入 "fix the login bug" → 回车
  │
  ▼
ComposerView.sendAction()
  ├─ ComposerViewModel.text → thread.send(userText:)
  │
  ▼
ThreadViewModel.startAgentRun()
  ├─ 追加 AgentMessage.user(text) 到 messages[]
  ├─ 追加 AgentMessage.assistantStreaming() 占位符
  ├─ state = .executing
  ├─ 从 messages[] 构建 Conversation
  │   └─ AgentMessageAdapter.toCoreMessages()
  │
  ▼
AgentSessionManager.run()
  ├─ 从 Project 解析工作目录
  ├─ 从当前设置解析模型 + 工具
  ├─ 构建系统提示（CLAUDE.md、MEMORY.md、MCP 上下文）
  ├─ 调用 QueryEngine.run()
  │   │
  │   ▼  (每轮 — 重复直到 end_turn 或用户取消)
  │   ┌─────────────────────────────────────────────┐
  │   │ LLMClient.send(messages) → SSE 流           │
  │   │   ├─ textDelta          → 流式事件          │
  │   │   ├─ thinkingDelta      → 流式事件          │
  │   │   ├─ toolUse start/stop → 工具执行          │
  │   │   └─ usage metadata     → token 计数器      │
  │   │                                              │
  │   │ ToolExecutor.execute()                       │
  │   │   ├─ 权限检查 → 可能挂起                     │
  │   │   ├─ 运行工具 (Bash/Read/Edit/...)           │
  │   │   └─ ToolResult → 对话历史                   │
  │   └─────────────────────────────────────────────┘
  │
  ▼
StreamingEventBus (AsyncSequence)
  ├─ ThreadViewModel.handleStreamEvent()
  │   ├─ .textDelta → 更新 message.blocks[i].text
  │   ├─ .thinkingDelta → 更新 message.blocks[i].thinking
  │   ├─ .toolStarted → 创建 ToolUseBlock(status: .executing)
  │   ├─ .toolCompleted → 更新 ToolUseBlock(status: .completed/.error)
  │   └─ .turnComplete → 持久化中间状态
  │
  ▼
Agent 循环结束 (end_turn、错误或取消)
  ├─ ThreadViewModel.handleRunResult()
  │   ├─ 从已完成的轮次重建 messages
  │   ├─ 将所有消息持久化到 SQLite
  │   ├─ state = .done / .failed(msg)
  │   └─ onStreamComplete?() → 刷新 diff 摘要
  │
  ▼
UI 响应式更新
  ├─ MessageListView 重新渲染（新消息）
  ├─ ReviewPanelView 刷新 (DiffService.refresh)
  ├─ SidebarView 更新线程标题 + 时间
  └─ ComposerView 自动聚焦等待下一次输入
```

### 3.3. 流式传输管道（生产级要求）

```
来自网络的 SSE 字节
  │
  ▼
LLMStreamParser (Core)
  ├─ 累积不完整的行
  ├─ 解析 SSE 事件："data: {...}"
  ├─ 解码 JSON → StreamEvent 枚举
  │   (textDelta | thinkingDelta | contentBlockStart | contentBlockStop |
  │    inputJSONDelta | toolUse | toolResult | error | messageDelta)
  │
  ▼
StreamPipeline (App — 增加弹性)
  ├─ RetryPolicy：429/5xx 时指数退避
  ├─ ConnectionMonitor：NWPathMonitor 检查网络可达性
  ├─ ResumeToken：保存最后消息 ID 以便断线后恢复
  └─ Backpressure：以 UI 友好的速率产生事件（最大 60fps）
  │
  ▼
StreamingEventBus (App — 扇出)
  ├─ ThreadViewModel 上的 Published 属性（主 actor）
  ├─ ToolExecutionTracker（针对特定工具的更新）
  ├─ DebugLogger（JSONL 转储供开发者使用）
  └─ NotificationManager（完成时）
```

---

## 4. 关键用户体验路径

### 4.1. 编辑器（最主要的交互界面）

编辑器是最常接触的 UI 元素。它必须感觉原生、响应迅速且功能强大。

**富文本编辑（基于 NSTextView）：**
- 当前 SwiftUI `TextEditor` 不够用：没有语法高亮、没有内联补全、没有 @-mention 标签、没有图片粘贴。
- 替换为包装在 `NSViewRepresentable` 中的 `NSTextView`。
- `ComposerTextView` 子类增加：(a) 通过 TextKit 2 实现的语法高亮代码块，(b) 通过 `NSTextAttachment` 实现的内联 @-mention 标签渲染，(c) `/` 命令的幽灵文本，(d) 自适应高度（最小 1 行，最大 8 行并支持滚动）。

**@-Mention 系统：**
- **文件**：由 `@` 触发 → 对工作区文件进行模糊搜索 → 插入为 mention 标签（发送时解析为完整路径）。
- **技能**：`@skill-name` → 搜索已安装的技能 → 插入技能调用。
- **MCP 工具**：`@mcp/server/tool` → 插入 MCP 工具调用。
- **线程**：`@thread-name` → 链接到另一个线程（用于上下文共享）。
- Mention 标签以内联圆角标签形式渲染，可通过退格键删除。

**斜杠命令系统：**
- `/` 在编辑器上方打开浮动的命令面板。
- 命令包括：`/help`、`/clear`、`/compact`、`/model`、`/permission`、`/plan`、`/goal`、`/skills`、`/mcp`、`/status`、`/export`、`/settings`、`/debug`、`/retry`、`/fork`、`/summarize`。
- 每个命令都有描述、参数提示和键盘快捷键。
- 参数自动补全（例如 `/model` → 显示可用模型并标明当前选中）。

**图片与文件粘贴：**
- `NSPasteboard` 监控图片类型（PNG、JPEG、HEIC）。
- 粘贴图片 → 自动上传到模型（如果支持多模态）或保存为临时文件并附加为 `[Image: filename.png]`。
- 从 Finder 拖放文件 → 插入为文件 mention 标签。

**发送行为：**
- Enter：立即发送。
- Shift+Enter：插入换行符。
- Agent 执行期间发送：将消息排入队列（显示徽章计数）。
- 执行期间出现停止按钮（■）→ 调用 `thread.cancel()`。

**编辑器状态机：**
```
  idle ──┬── typing → dirty ── Enter → sending → idle
         │                      └─ Shift+Enter → dirty（追加 \n）
         │
         ├── / → slashCommand（面板打开）
         │      └─ select → 插入命令文本 → dirty
         │      └─ dismiss → dirty（保留已输入文本）
         │
         ├── @ → mentionCompletion（弹出框打开）
         │      └─ select → 插入 mention 标签 → dirty
         │      └─ dismiss → dirty
         │
         └── executing（agent 运行中）
                ├─ Enter → queueMessage → 递增 queueCount
                └─ 点击 ■ → cancel → idle
```

### 4.2. 流式消息显示

**每条消息的状态机：**
```
pending（占位符）
  → streaming（部分内容到达中）
    → complete（assistant 完成）
    → error（流失败）
    → cancelled（用户中断）
```

**消息中的 Block 类型：**
| Block | 显示方式 |
|-------|---------|
| `text(String)` | Markdown 渲染的正文文本 |
| `thinking(String)` | 默认折叠："思考了 12 秒 ▸"。点击展开为 dim/斜体文本。 |
| `toolUse(ToolUseBlock)` | 工具调用卡片：spinner → 对勾 + 摘要。点击展开完整输入/输出。 |
| `toolResult(ToolResultBlock)` | 内联结果或带行数的折叠预览。 |
| `diff(DiffBlock)` | 带语法高亮的 unified diff，+N -M 行计数。 |
| `error(ErrorBlock)` | 红色边框的错误卡片，带重试/关闭操作。 |

**流式传输性能要求：**
- 文本增量必须以 60fps 渲染——使用 `NSTextView.textStorage?.append()` 进行批量更新。
- 思考增量以 dim 样式渲染，可节流至 15fps（它们是次要内容）。
- 工具调用卡片在 `toolStarted` 时立即出现，在 `toolCompleted` 时动画化状态变化。
- Markdown 重新解析：流式传输期间以 200ms 防抖，完成时完整重新渲染。
- 虚拟滚动：仅渲染视口 ±2 屏幕范围内的消息。`MessageListView` 使用 `LazyVStack` 并基于显式 ID 的 diffing。

### 4.3. 消息列表（虚拟滚动）

**问题：** 一个 500 轮的对话加上工具输出可能包含 200,000+ 行文本。在 `ScrollView` → `VStack` 中渲染所有消息会导致 OOM。

**解决方案：**
- `MessageListView` 通过 `ScrollViewReader` + 手动可见性跟踪使用 `UICollectionView` 风格的视图回收。
- 每条消息的渲染高度根据 block 数量 + 文本长度估算，然后在首次布局时进行测量。
- `MessageBubbleView` 惰性解码 blocks：仅解码当前视口中可见的 block 类型。
- 超过 100 行的工具输出默认折叠，带"显示完整输出（N 行）"展开器。
- 消息存储保留原始文本 + 元数据；Markdown → AttributedString 转换按消息 ID 缓存。

### 4.4. 右侧面板标签页

右侧面板是一个多标签工作区。标签页通过键盘快捷键或 + 菜单创建。

| 标签页 | 快捷键 | 实现方式 | 关键 UX 关注点 |
|-----|----------|---------------|----------------|
| **Review** | `⌃⇧G` | SwiftUI + 通过 `GitService` 执行 `git diff` | 必须在 agent 编辑文件时实时更新。使用 `FileWatcher` + 防抖的 `git diff --stat` 刷新。 |
| **Terminal** | `⌃`` ` | 自定义 PTY + VT100 模拟器 + Metal 网格渲染器 | 完整终端模拟——不是嵌入 `Terminal.app`。必须支持颜色、光标定位、交互式 TUI。 |
| **Browser** | `⌘T` | `WKWebView` 带 devtools 桥接 | 本地文档浏览。URL 栏、前进/后退、devtools 开关。 |
| **Files** | `⌘P` | `NSOutlineView` 带惰性加载 + `FileWatcher` 实时更新 | Git 状态覆盖（修改/新增/删除图标）。右键上下文菜单用于 git 操作。 |
| **Side Chat** | `⌥⌘S` | 独立的 `ThreadViewModel`，限定在当前文件/选区 | 不污染主线程的并行对话。适用于"解释这个文件"类问题。 |

**标签页生命周期：**
- 标签页按窗口持久化，重启时恢复。
- 每个窗口最多 10 个标签页；打开第 11 个时提示关闭最近最少使用的标签页。
- 标签页状态（滚动位置、终端 cwd、浏览器 URL）按标签页持久化到 `UserDefaults` 中。

### 4.5. Diff 审查面板（关键路径）

这是技术难度最高的面板——它必须实时显示文件变更并提供正确的 diff 计算。

**架构：**
```
Agent 完成一轮
  │
  ▼
ThreadViewModel.onStreamComplete()
  ├─ AppViewModel.refreshDiffSummary()
  │   └─ DiffService.refresh(for: appViewModel)
  │       ├─ 运行 `git diff --stat` → 文件列表 +N -M
  │       ├─ 对每个变更文件运行 `git diff --unified=3 <file>`
  │       ├─ 解析 unified diff → 结构化的 DiffHunk[]
  │       ├─ 在内存中缓存结果（下一轮时失效）
  │       └─ 将 DiffSummary 发布到 @Published lastReviewEntries
  │
  ▼
ReviewPanelView（绑定到 lastReviewEntries）
  ├─ 左侧边栏：文件列表，带变更计数 + 状态图标
  ├─ 右侧内容：选中文件的 diff
  │   ├─ Diff 头 (--- a/ +++ b/)
  │   ├─ Hunk 头 (@@ -L,S +L,S @@)
  │   ├─ 新增行（绿色背景）
  │   ├─ 删除行（红色背景）
  │   └─ 上下文行（未变更）
  └─ 底部栏："全部接受" / "全部还原" / "暂存选中"
```

**Diff 计算策略：**
- 主要：`git diff`（快速、准确、处理重命名）。
- 回退方案（无 git 仓库）：对前后文件内容使用 Myers diff 算法。
- 缓存失效：`FileWatcher` 检测到外部写入 → 使该文件的缓存失效。
- 大文件（>10K 行）：分块流式输出 diff，显示前 500 个 hunks 并附"显示 N 个变更中的 500 个"警告。

---

## 5. 多窗口架构

### 5.1. 窗口模型

每个窗口是一个独立的工作区，拥有自己的状态：
- 自己的 `AppViewModel` 实例（或限定作用域的子集）
- 自己的项目选择
- 自己的线程选择
- 自己的右侧面板标签页状态

窗口通过以下方式创建：
- `⌘N` → 空状态的新窗口（用户选择项目/线程）
- `File > New Window` → 同上
- `Window > Duplicate` → 克隆当前窗口状态
- `Dock menu > New Window` → 新的空窗口
- 重启时状态恢复 → 从上次会话重新打开所有窗口

### 5.2. NSWindowRestoration

```swift
// 每个窗口编码其状态以备恢复：
struct WindowRestorationState: Codable {
    let windowFrame: CGRect
    let selectedProjectID: String?
    let selectedThreadID: String?
    let sidebarVisible: Bool
    let sidebarWidth: CGFloat
    let rightVisible: Bool
    let rightWidth: CGFloat
    let rightTabs: [RestoredTabState]
}

// 重启时：
// 1. 调用 NSApplication.restoreWindow(withIdentifier:state:)
// 2. 解码 WindowRestorationState
// 3. 创建 MainWindowController
// 4. 恢复布局 + 选择 + 标签页
// 5. 如果项目/线程不再存在，显示空状态
```

### 5.3. 窗口标签组（macOS 15+）

原生 `NSWindowTabGroup` 支持：
- 在有标签页的窗口中按 `⌘T` → 在同一窗口中新建标签页
- 每个标签页有独立的线程选择，但共享窗口的项目
- 标签页标题 = 线程标题
- 拖出标签页 → 变为独立窗口

---

## 6. 持久化层

### 6.1. SQLite Schema（目标）

```sql
-- 项目
CREATE TABLE projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    path TEXT NOT NULL UNIQUE,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    metadata TEXT  -- JSON blob：自定义设置、排除路径
);

-- 线程
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
    title TEXT NOT NULL DEFAULT 'Untitled',
    state TEXT NOT NULL DEFAULT 'idle',
    mode TEXT NOT NULL DEFAULT 'code',
    sandbox_mode TEXT NOT NULL DEFAULT 'workspace-write',
    execution_env TEXT NOT NULL DEFAULT 'local',
    model TEXT NOT NULL,
    system_prompt_hash TEXT,     -- 检测提示词变更
    token_usage_in INTEGER DEFAULT 0,
    token_usage_out INTEGER DEFAULT 0,
    turn_count INTEGER DEFAULT 0,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    archived_at REAL             -- NULL = 活跃
);
CREATE INDEX idx_threads_project ON threads(project_id);
CREATE INDEX idx_threads_updated ON threads(updated_at DESC);
CREATE INDEX idx_threads_archived ON threads(archived_at);

-- 消息（block 级存储）
CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    role TEXT NOT NULL,           -- 'user'、'assistant'、'system'
    turn_index INTEGER,           -- 第几轮 agent turn（用户消息为 NULL）
    blocks_json TEXT NOT NULL,    -- ContentBlock 的 JSON 数组
    token_usage_in INTEGER,
    token_usage_out INTEGER,
    created_at REAL NOT NULL
);
CREATE INDEX idx_messages_thread ON messages(thread_id, created_at);
CREATE INDEX idx_messages_role ON messages(thread_id, role);

-- FTS5 全文搜索所有消息
CREATE VIRTUAL TABLE messages_fts USING fts5(
    thread_id, content, tokenize='porter unicode61'
);

-- 附件（图片、文件）
CREATE TABLE attachments (
    id TEXT PRIMARY KEY,
    message_id TEXT REFERENCES messages(id) ON DELETE CASCADE,
    filename TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    size_bytes INTEGER NOT NULL,
    storage_path TEXT NOT NULL,   -- 相对于 app 容器
    thumbnail_path TEXT,          -- 图片缩略图
    created_at REAL NOT NULL
);

-- 设置（键值对，带类型）
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value_json TEXT NOT NULL,
    updated_at REAL NOT NULL
);

-- 权限（用户决策）
CREATE TABLE permissions (
    id TEXT PRIMARY KEY,
    rule_type TEXT NOT NULL,      -- 'tool'、'path'、'domain'、'command'
    pattern TEXT NOT NULL,        -- 工具名、文件 glob、域名模式
    decision TEXT NOT NULL,       -- 'allow'、'deny'、'ask'
    scope TEXT NOT NULL DEFAULT 'session',  -- 'session'、'project'、'global'
    created_at REAL NOT NULL
);

-- 同步元数据
CREATE TABLE sync_metadata (
    entity_type TEXT NOT NULL,    -- 'thread'、'message'、'setting'
    entity_id TEXT NOT NULL,
    cloudkit_record_id TEXT,
    last_modified REAL NOT NULL,
    last_synced REAL,
    sync_status TEXT NOT NULL DEFAULT 'pending',
    PRIMARY KEY (entity_type, entity_id)
);
```

### 6.2. 迁移策略

- 仅向前，版本化迁移。
- `Migrations.swift` 包含一个有序的 `Migration` 结构体数组。
- 每个迁移：`version: Int, up: (Database) throws -> Void`。
- 迁移在事务中运行。失败 → 回滚，记录错误，提醒用户。
- 迁移前自动备份：将数据库文件复制到 `~/Library/Application Support/SwiftAgent/Backups/`。

### 6.3. 性能

- WAL 模式（默认）：写入期间可并发读取。
- `PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;`
- `PRAGMA cache_size=-8000;`（8MB 页面缓存）。
- 消息 blocks 以每条消息一个 JSON blob 存储（而非每 block 一行），以最小化行数。
- FTS5 内容通过 messages 表上的触发器同步。
- App 进入后台时定期执行 `PRAGMA optimize;`。
- 当空闲页面超过 50MB 时自动执行 VACUUM。

---

## 7. 权限与安全架构

### 7.1. 权限模式

| 模式 | 行为 |
|------|----------|
| **Ask for Approval（请求批准）** | 每次工具调用都暂停并显示权限对话框。用户可选择始终允许 / 允许一次 / 拒绝。 |
| **Approve for Me（为我批准）** | 工具自动运行，但执行后显示摘要横幅。拒绝操作以内联形式显示。 |
| **Full Access（完全访问）** | 无中断。所有工具运行。审查面板显示发生了什么。 |
| **Custom（自定义）** | 按工具、按路径、按域名的规则。在 Settings → Permissions 中配置。 |

### 7.2. 权限管道（从 Core 桥接）

```
ToolExecutor.execute(tool, input)
  │
  ▼
PermissionEngine.evaluate(tool, input, mode)
  ├─ checkDenyList(tool) → 立即阻止
  ├─ checkAllowList(tool) → 立即允许
  ├─ checkCustomRules(tool, input) → 匹配用户规则
  ├─ checkASTSafety(input) → 检测危险模式
  │   ├─ rm -rf / → 阻止
  │   ├─ curl | bash → 警告
  │   └─ git push --force origin main → 警告
  ├─ evaluateMode：
  │   ├─ .fullAccess → 允许
  │   ├─ .approveForMe → 允许并显示横幅
  │   ├─ .askForApproval → 提示用户
  │   └─ .custom → 应用匹配的规则
  │
  ▼
PermissionUIBridge.prompt(tool, message)
  │
  ▼ (如果 mode == .askForApproval)
PermissionUIBridge.pendingPermission published
  → SwiftUI 弹窗或内联横幅
  → 用户点击 Allow / Deny / Always Allow
  → continuation.resume(returning: .allow / .deny)
```

### 7.3. 权限 UI

- **不是模态对话框。** 模态权限对话框会打断打字快、使用键盘的开发者的流程。
- **内联横幅** 显示在编辑器下方："Bash 想要运行 `npm install`。[Allow] [Deny] [Always allow npm]"。
- **键盘可操作：** Tab 选择按钮，Space/Enter 激活。ESC = 拒绝。
- **审计跟踪：** 所有权限决策记录到 `~/.swiftagent/permissions.log`，可在 Settings → Permissions → Audit Log 中查看。

---

## 8. LLM Provider 架构

### 8.1. 多 Provider 抽象

```swift
protocol LLMProvider {
    var providerID: String { get }           // "anthropic"、"openai"、"deepseek"
    var displayName: String { get }          // "Anthropic"、"OpenAI"、"DeepSeek"
    var availableModels: [ModelInfo] { get } // 动态模型列表
    var capabilities: ProviderCapabilities { get }

    func stream(
        messages: [Message],
        model: String,
        tools: [ToolDefinition],
        systemPrompt: String,
        temperature: Double?
    ) -> AsyncThrowingStream<StreamEvent, Error>

    func countTokens(_ text: String, model: String) -> Int
}

struct ProviderCapabilities {
    let supportsThinking: Bool         // 扩展推理
    let supportsVision: Bool           // 图片输入
    let supportsTools: Bool            // 原生工具使用
    let supportsCaching: Bool          // 提示词缓存
    let supportsStreaming: Bool        // SSE
    let maxContextWindow: Int          // token 限制
    let maxOutputTokens: Int
}
```

### 8.2. Provider 注册表

- Provider 在启动时通过 `ProviderRegistry` 注册。
- 内置 provider：Anthropic (Claude)、OpenAI (GPT、o-series)、DeepSeek (V3、R1)。
- 本地 provider：llama.cpp server、MLX server、Ollama —— 通过 localhost 端口扫描或手动 URL 输入发现。
- API key 按 provider 存储在 Keychain 中。
- 对话中途切换模型：允许，但如果上下文窗口差异显著则发出警告。

### 8.3. API Key 管理

- 存储在 macOS Keychain 中，`kSecAttrService = "com.swiftagent.api"`。
- `kSecAttrAccount` = provider ID。
- `kSecAttrLabel` = 用户可见名称。
- 首次使用时提示 Keychain 访问（macOS 授权）。
- Key 可以从环境变量、`~/.claude.json` 或手动输入导入。

---

## 9. 工具执行与可视化

### 9.1. 工具执行跟踪

```swift
@MainActor
final class ToolExecutionTracker: ObservableObject {
    struct RunningTool: Identifiable {
        let id: String          // toolUseID
        let name: String        // "Bash"、"Read"、"Edit"
        let summary: String     // "npm install react" 或 "src/App.tsx:42-45"
        let startTime: Date
        var status: ToolStatus  // .running、.completed、.error(String)
        let isCollapsible: Bool // Read/Glob/Grep 为 true
    }

    @Published var runningTools: [RunningTool] = []
    @Published var collapsedGroups: [CollapsedToolGroup] = []

    // 状态栏的计算属性：
    // 1 个工具："Running Bash → npm install"
    // 2-3 个："3 tools running | Bash; Read; Grep"
    // 4+ 个："5 tools running | Bash; Read +3 more"
    var statusLine: String { ... }
}
```

### 9.2. 工具结果渲染

工具输出按内容类型分发：

| 输出类型 | 检测方式 | 显示方式 |
|-------------|-----------|---------|
| 短文本（<200 行） | 行数 | 带语法高亮的内联代码块 |
| 长文本（>200 行） | 行数 | 折叠预览："Output: 1,247 lines (3.2MB) ▸ Show" |
| Diff 输出 | 以 `diff --git` 或 `--- a/` `+++ b/` 开头 | 带语法高亮的 unified diff 视图 |
| 文件树 | 行匹配 `├──` 或 `│   ` 模式 | 格式化的树形视图 |
| JSON | 可成功解析为 JSON | 可折叠的 JSON 树（类似浏览器 devtools） |
| 错误 | 非零退出码或 stderr 内容 | 红色边框的错误卡片，带 stderr |
| 图片 | 具有图片魔法字节的二进制数据 | 内联图片预览（如果使用多模态模型） |
| 空输出 | 零长度输出 | 灰色 "(no output)" 文本 |

### 9.3. 工具批准 UI

对于需要批准的模式，批准 sheet 不是阻塞性 `NSAlert`：

```
┌──────────────────────────────────────────────────────────────┐
│  ⚡ Bash wants to execute a command                           │
│                                                              │
│  $ npm install react react-dom                               │
│                                                              │
│  Working directory: /Users/jim/my-project                    │
│  Estimated duration: < 30s                                   │
│                                                              │
│  [Always allow npm]   [Allow once]   [Deny]   [View diff]   │
└──────────────────────────────────────────────────────────────┘
```

- 以 SwiftUI sheet 或编辑器下方的内联横幅呈现。
- 键盘：Tab 导航，Space/Enter 确认。
- ESC 或 ⌘. = 拒绝。
- "Always allow" 创建持久权限规则。

---

## 10. Terminal 面板（生产级 PTY）

右侧面板的 Terminal 标签页必须是真正的终端模拟器，而不是通过 `NSWorkspace` 嵌入的 `Terminal.app`。嵌入第二个 Terminal.app 存在安全边界问题，视觉上不协调，且无法共享状态。

### 10.1. PTY 架构

```
RightTabsViewController
  └─ TerminalPanelView (SwiftUI)
       └─ PTYTerminalController (AppKit 控制器)
            ├─ fork() + exec() 子进程（用户的 shell）
            ├─ PTY 主 FD → DispatchIO channel（读取）
            ├─ DispatchIO channel（写入） → PTY 主 FD
            │
            ▼
       TerminalEmulator (VT100/xterm 状态机)
            ├─ 解析转义序列：CSI、OSC、DCS、APC
            ├─ 维护光标位置、滚动区域、字符属性
            ├─ 支持：256 色、true color、鼠标 (SGR)、bracketed paste
            │   kitty keyboard protocol、同步输出
            │
            ▼
       TerminalGridView (Metal 加速的网格渲染器)
            ├─ 2D 字符网格（行 × 列）
            ├─ Metal shader 用于字形渲染（GPU 加速）
            ├─ 单元格属性：前景色、背景色、加粗、斜体、下划线
            ├─ 损伤跟踪：仅重绘变更的单元格
            └─ 通过 CADisplayLink 实现光标闪烁
```

### 10.2. 设计决策

- **自定义模拟器，而非 libvterm。** libvterm 是 C 语言，在 Swift 中有内存管理难题。用 Swift 写一个 VT100 解析器大约 1500 行，并且可以完全控制性能和集成。
- **Metal 渲染，而非 NSTextView。** NSTextView 无法处理终端吞吐量（`find .` 时可达 100K+ 更新/秒）。Metal 网格渲染器可以以 60fps 显示数百万个单元格。
- **损伤跟踪。** 仅将变更的单元格传输到 GPU。未变更区域复用前一帧的纹理。
- **同步输出 (DECSET 2026)。** 批量终端更新以消除快速输出期间的视觉撕裂。
- **Shell 集成。** 通过 `PROMPT_COMMAND`/`precmd` 注入 shell hooks 以跟踪工作目录和命令开始/结束。使能功能：从聊天中"在终端中重新运行"、agent 与终端之间的工作目录同步。

### 10.3. 回退方案

如果 Metal 不可用（VM、旧硬件）：回退到基于 `NSTextView` 的渲染器，并节流更新。

---

## 11. 文件监视与 Git 集成

### 11.1. 文件监视

- 使用 `FSEvents` API（非轮询）。
- 每个项目根目录一个 `FSEventStream`。
- 200ms 防抖：批量收集多个文件系统事件，然后一次触发。
- 跟踪的事件类型：Created、Modified、Removed、Renamed。
- 变更时：使相关缓存失效（diff 缓存、文件树节点、语法高亮）。

### 11.2. Git Service

```swift
protocol GitServiceProtocol {
    func status() async throws -> GitStatus          // git status --porcelain
    func diff(file: String) async throws -> String   // git diff --unified=3
    func diffStat() async throws -> [DiffStatEntry]  // git diff --stat
    func log(file: String, limit: Int) async throws -> [GitCommit]
    func blame(file: String, line: Int) async throws -> GitBlame
    func branches() async throws -> [GitBranch]
    func currentBranch() async throws -> String
}

// 实现包装 /usr/bin/git，通过 Process() 调用
// 所有 git 操作 5 秒超时
// 结果缓存 TTL：status = 2s、diff = 直到下次编辑、log = 30s
```

- `GitService` 在后台 actor 上运行（非 `@MainActor`）。
- 结果通过 `ProjectViewModel` 上的 `@Published` 发布。
- `FileWatcher` → git status 缓存失效 → UI 刷新。

---

## 12. 搜索架构

### 12.1. 全文搜索 (FTS5)

```
搜索查询："fix login bug"
  │
  ▼
在 messages_fts 上执行 FTS5 搜索
  ├─ 匹配包含 "fix"、"login"、"bug" 的消息
  ├─ 按线程排序，然后按时间顺序
  ├─ 返回：[(threadId, threadTitle, messageId, snippet, rank)]
  │
  ▼
SearchResultsView
  ├─ 按线程分组
  ├─ 显示带高亮匹配的片段
  ├─ 点击结果 → 导航到该线程中的该消息
  └─ 线程内 ⌘F → 过滤到线程内搜索模式
```

### 12.2. Quick Open (⌘⇧O)

命令面板风格的模糊搜索：
- 工作区中的文件（通过 `git ls-files` + 模糊匹配）
- 线程（按标题）
- 设置页面
- 斜杠命令
- 最近的 agent 操作

### 12.3. Spotlight 集成

`CSSearchableIndex` 索引：
- 线程标题和摘要
- 关键决策/结果（从 `/goal` 完成中提取）
- 文件编辑（线程 + 文件 + 时间戳）

用户可以从 macOS Spotlight 搜索："login fix" → 打开 SwiftAgent 到该线程。

---

## 13. 无障碍（生产级）

### 13.1. VoiceOver

每个交互元素必须具有：
- `.accessibilityLabel(_:)` — 此元素是什么
- `.accessibilityHint(_:)` — 激活时发生什么
- `.accessibilityValue(_:)` — 当前状态（用于开关、选择器）
- `.accessibilityAction(named:)` — 超出点击的自定义操作

**对话专用的 VoiceOver 支持：**
- 自定义转子操作："下一条消息"、"上一条消息"、"下一个工具调用"、"复制代码块"
- 消息角色播报："用户消息：How do I..." / "助手消息：Here's how..."
- 思考块："思考了 12 秒 — 已展开" / "思考了 12 秒 — 已折叠，双击展开"
- 工具调用："Bash 工具运行中：npm install。双击查看详情"
- 流式传输：开始播报"响应流式传输中"一次，然后在文本增量期间保持静默（避免冗长）。结束时播报"响应完成"。

### 13.2. 动态字体

- 所有字体使用 `.font(.body)` / `.font(.headline)` 等，不使用固定点数。
- 布局适应无障碍文本大小（最高到 `XXXLarge`）。
- 侧边栏最小宽度随文本大小按比例增加。
- 编辑器高度随文本大小缩放。

### 13.3. 减弱动态效果

- `.animation(..., value:)` 受 `@Environment(\.accessibilityReduceMotion)` 保护。
- 当减弱动态效果开启时：无布局动画，即时过渡。
- Spinner 使用静态 "..." 而非动画盲文字符。

### 13.4. 纯键盘操作

- 完整键盘导航：Tab/Shift+Tab、方向键、Space/Enter 激活。
- ⌘F 搜索，⌘⇧F 全局搜索。
- ⌘⇧O Quick Open。
- 所有工具栏按钮可通过键盘快捷键访问。
- 编辑器：始终可聚焦，Enter 发送，Shift+Enter 换行。
- 权限提示：Tab 导航按钮，Space/Enter 选择。

---

## 14. 错误处理策略

### 14.1. 错误分类

```swift
enum AppError: Error, Identifiable {
    // 网络（可重试）
    case networkTimeout
    case networkDisconnected
    case networkProxy(String)

    // API（部分可重试）
    case rateLimited429(retryAfter: Int?)
    case serverError5xx(status: Int)
    case invalidAPIKey401
    case lowBalance402
    case modelOverloaded

    // 权限
    case sandboxDenied(tool: String, path: String)
    case permissionRequired(tool: String)

    // 数据
    case databaseCorrupted
    case migrationFailed(version: Int, reason: String)
    case threadNotFound(id: String)
    case projectNotFound(id: String)

    // 外部
    case worktreeConflict(branch: String)
    case diffMergeFailed(file: String)
    case mcpDisconnected(server: String)
    case skillLoadFailed(name: String, reason: String)

    // 系统
    case appshotPermissionDenied
    case appshotCaptureFailed(reason: String)
    case keychainAccessDenied
    case diskSpaceLow(availableBytes: Int64)
}
```

### 14.2. 错误呈现策略

| 严重性 | UI | 示例 |
|----------|----|---------|
| **可重试** | 顶部横幅带操作按钮。若未交互，8 秒后自动消失。 | "网络超时 — [重试]" / "速率限制 — 12 秒后重试" |
| **警告** | 底部 toast。5 秒后自动消失。 | "MCP 服务器 'filesystem' 已断开 — 正在重连" |
| **致命** | 模态叠加层，带解释 + 操作。无操作无法关闭。 | "数据库损坏 — [从备份恢复] [退出]" |
| **内联** | 相关组件内的红色文本。 | 工具调用卡片上的权限拒绝内联提示 |

### 14.3. 恢复策略

- **网络错误：** 指数退避重试（1s、2s、4s、8s、16s，然后放弃）。
- **速率限制 (429)：** 遵循 `Retry-After` 头。显示倒计时器。
- **流断开：** 保存最后收到的消息 ID。提供"恢复"按钮，重新连接并从最后检查点继续。
- **数据库损坏：** 启动时自动完整性检查。如果损坏：提供从最近自动备份恢复的选项。
- **工具执行失败：** 在工具卡片上显示错误，继续 agent 循环。Agent 可以决定重试或采取替代方法。

---

## 15. 通知

### 15.1. 用户可见的通知

| 事件 | 通知 |
|-------|-------------|
| Agent 轮次完成 | "Agent finished — 3 files changed"，带查看 diff 的操作 |
| 需要权限（App 在后台时） | "Bash wants to run a command — tap to review" |
| 长时间运行的工具完成 | "npm install finished (took 2m 15s)" |
| 接近速率限制 | "API usage at 80% of limit" |

### 15.2. 通知偏好设置

Settings → Notifications 允许用户切换：
- 完成时通知（开/关）
- 需要权限时通知（开/关）
- 运行超过 N 秒时通知（滑块：30s / 1m / 5m / 从不）
- 安静模式：抑制所有通知 N 分钟 / 直到明天
- 每个项目的通知覆盖

---

## 16. 性能预算

| 指标 | 目标 | 测量方式 |
|--------|--------|-------------|
| App 启动（冷启动） | < 1.5s 至可交互 | `NSApplicationDidFinishLaunching` → UI 第一帧 |
| App 启动（热启动，从 Dock） | < 0.5s | 同上 |
| 窗口打开 | < 200ms | `window.makeKeyAndOrderFront()` → 第一帧 |
| 线程切换 | < 100ms | 点击线程 → 消息可见 |
| 消息发送 → 首个 token | < 500ms（不含 LLM 延迟） | Enter → textDelta |
| 文本增量 → UI 更新 | < 16ms (60fps) | textDelta 事件 → 渲染字符 |
| 工具开始 → 卡片出现 | < 50ms | toolStarted 事件 → ToolCallCard 出现 |
| 消息列表滚动（500 条消息） | 持续 60fps | 快速滚动期间的 FPS |
| 内存：空闲 | < 150MB | `NSProcessInfo.physicalMemory` 差值 |
| 内存：200 轮对话 | < 400MB | 同上，加载完整对话后 |
| SQLite 查询（线程列表） | < 5ms | 查询周围的 `CFAbsoluteTime` |
| FTS5 搜索（100K 条消息） | < 50ms | 同上 |

---

## 17. 测试策略

### 17.1. 测试金字塔

```
            ┌──────┐
            │ UITest│  5% — 关键路径的 XCUITest（发送消息、打开设置、
            │       │       切换线程、创建项目、diff 审查）
            ├──────┤
            │Integra│ 15% — 流式管道、持久化往返、
            │ tion  │       权限流程、多窗口状态
            ├──────┤
            │ View  │ 30% — ViewModel 状态转换、消息渲染、
            │ Model │       工具跟踪、错误处理、搜索
            ├──────┤
            │  Unit │ 50% — 单个类型、适配器、解析器、格式化器、
            │       │       diff 计算、VT100 解析器、FTS 分词器
            └──────┘
```

### 17.2. 关键测试套件（目标）

| 套件 | 测试内容 | 数量 |
|-------|---------------|-------|
| `MessageAdapterTests` | Core Message ↔ App AgentMessage 往返 | 20+ |
| `StreamingEventBusTests` | 事件传递顺序、背压、取消 | 15+ |
| `ThreadViewModelTests` | 状态机：idle→executing→done、error、cancel、队列 | 25+ |
| `ComposerViewModelTests` | 文本操作、mention 解析、斜杠检测 | 20+ |
| `PermissionUIBridgeTests` | 模式解析、自定义规则、审计跟踪 | 15+ |
| `DiffServiceTests` | Git diff 解析、Myers 回退、缓存 | 20+ |
| `VT100ParserTests` | 转义序列解析、光标定位、滚动区域 | 30+ |
| `TerminalEmulatorTests` | 完整终端状态机 (DEC STD 070 序列) | 40+ |
| `StorageTests` | CRUD、迁移、FTS 搜索、备份/恢复 | 30+ |
| `SyncEngineTests` | 冲突解决、CloudKit 记录映射 | 20+ |
| `AccessibilityTests` | 标签存在、转子操作、动态字体布局 | 15+ |
| `PersistenceRoundTripTests` | 写入对话 → 重启 → 读回 → 匹配 | 10+ |
| `MultiWindowTests` | 两个窗口、独立状态、无交叉干扰 | 10+ |
| `XCUITestCriticalPaths` | 发送消息、查看响应、打开审查、切换线程 | 15+ |

---

## 18. 实施分阶段计划

### 阶段 1：基础升级（骨架）

**目标：** 将演示级组件替换为生产级基础。App 仍应端到端工作，但每个子系统现在建立在正确的架构上。

| # | 任务 | 原因 |
|---|------|-----|
| 1.1 | 多 provider LLM 层（`LLMProvider` 协议 + Anthropic/OpenAI/DeepSeek provider） | 解耦仅依赖 DeepSeek 的状态；启用 Claude 和 GPT |
| 1.2 | `AgentSessionManager` 重构，增加适当的错误传播和取消机制 | 当前引导脆弱；错误仅用 `print()` |
| 1.3 | 消息持久化，使用 FTS5 + WAL 模式优化 | 当前存储可用但无搜索，崩溃时可能损坏 |
| 1.4 | `Migration` 系统（版本化、仅向前、事务性） | Schema 会演进；需要安全的迁移路径 |
| 1.5 | `AppError` 分类 + `ErrorPresenter` 状态机升级 | 已有 16 种错误但覆盖不完整 |
| 1.6 | 合适的基于 `NSTextView` 的 `ComposerTextView`，替换 SwiftUI `TextEditor` | 解锁 @-mention、图片粘贴、语法高亮 |

### 阶段 2：核心 UX（用户最常接触的部分）

**目标：** 主要交互循环（编辑器 → 消息列表 → 工具卡片 → diff 审查）达到生产质量。

| # | 任务 | 原因 |
|---|------|-----|
| 2.1 | @-Mention 系统（文件、技能、MCP 工具、线程） | 高级用户功能；区别于基本聊天 |
| 2.2 | 斜杠命令面板，带参数补全 | 可发现性；匹配 Codex/CC 的预期 |
| 2.3 | 虚拟滚动 `MessageListView` | 对话会增长很大；当前 ScrollView 无法扩展 |
| 2.4 | 思考块展开/折叠，带 dim 渲染 | 推理模型 (R1、o-series) 输出长思考链 |
| 2.5 | 工具调用卡片：进度动画、展开/折叠、diff 预览 | 当前卡片是静态的；需要实时进度 |
| 2.6 | `DiffService`，带 git-diff 集成和缓存 | 审查面板是编程 agent 的头号差异化功能 |
| 2.7 | `ReviewPanelView`，带文件列表 + unified diff + 接受/还原 | 同上 |

### 阶段 3：右侧面板生产化

**目标：** 右侧面板标签页成为真正的工具，而非占位符。

| # | 任务 | 原因 |
|---|------|-----|
| 3.1 | PTY 终端，带 VT100 模拟器 + Metal 网格渲染器 | 终端对开发工作流至关重要；嵌入 Terminal.app 是错误的 |
| 3.2 | `FileWatcher` (FSEvents) + 带 git 状态的实时文件树 | 当前 FilesPanelView 是静态的；需要实时更新 |
| 3.3 | 文件右键菜单（在编辑器中打开、在 Finder 中显示、git log、diff） | 开发者期望的右键操作 |
| 3.4 | `BrowserPanelView`，带 WKWebView + URL 栏 + devtools | 本地文档、API 参考、已部署应用预览 |
| 3.5 | `SideChatPanelView`，带限定作用域的对话（当前文件上下文） | "解释这个文件"而不污染主线程 |

### 阶段 4：多窗口与持久化

**目标：** 专业应用行为——窗口、恢复、搜索和同步。

| # | 任务 | 原因 |
|---|------|-----|
| 4.1 | `MainWindowController`，带 NSWindowRestoration | 重启后状态丢失是不专业的 |
| 4.2 | 多窗口支持（独立工作区） | 高级用户同时处理多个项目 |
| 4.3 | FTS5 全文搜索，带结果 UI | "我在哪里讨论过 login bug？" |
| 4.4 | Quick Open 面板 (⌘⇧O)，带模糊文件/线程/设置搜索 | 快速导航；匹配 VS Code/Xcode 的预期 |
| 4.5 | Spotlight 索引 (`CSSearchableIndex`) | macOS 原生体验；对话可从系统 Spotlight 中找到 |
| 4.6 | 对话导出 (JSON、Markdown、PDF) | 分享、合规、备份 |

### 阶段 5：打磨与加固

**目标：** 无障碍、性能、可靠性和视觉精细化。

| # | 任务 | 原因 |
|---|------|-----|
| 5.1 | 完整 VoiceOver 支持，带自定义转子 | 无障碍认证所必需 |
| 5.2 | 动态字体 + 减弱动态效果 + 高对比度 | 无障碍认证所必需 |
| 5.3 | 纯键盘操作审计（每个操作都可到达） | 高级用户；无障碍 |
| 5.4 | 性能分析：Instruments (Allocations、Time Profiler、Metal) | 达到性能预算目标 |
| 5.5 | 内存压力处理 (`NSNotification.Name.DidReceiveMemoryWarning`) | 长时间运行的 agent 会话可能消耗大量内存 |
| 5.6 | 崩溃恢复：恢复未发送的编辑器文本、重新打开上一个线程 | 防止数据丢失 |
| 5.7 | 动画审计：时间、缓动、减弱动态效果兼容性 | 视觉打磨 |
| 5.8 | 所有 16 种 `AppError` 情况的错误恢复 | 当前错误处理不完整 |

### 阶段 6：高级功能

| # | 任务 | 原因 |
|---|------|-----|
| 6.1 | iCloud 同步对话和设置 | 多设备用户 |
| 6.2 | 自定义快捷键录制器（可编辑的键绑定） | 高级用户定制 |
| 6.3 | Computer Use（agent 通过 Accessibility API 控制 macOS 应用） | 相比基于 Web 的 agent 的独特 macOS 优势 |
| 6.4 | 语音输入（麦克风 → Whisper → 编辑器文本） | 替代输入方式 |
| 6.5 | LSP 集成（代码智能：跳转到定义、引用、诊断） | agent 上下文中的真正 IDE 功能 |
| 6.6 | 插件/扩展 API，供第三方工具和 provider 扩展 | 生态发展 |

---

## 19. 风险登记

| 风险 | 严重性 | 缓解措施 |
|------|----------|-----------|
| **SwiftUI 在复杂文本编辑方面不成熟** | 高 | 编辑器使用 `NSTextView` 通过 `NSViewRepresentable`。SwiftUI 仅用于外围装饰。 |
| **终端模拟器复杂度** | 高 | 先实现 VT100 子集（覆盖 80% 实际使用场景）。若 Metal 不可用，回退至基于 `NSTextView` 的渲染器。 |
| **LLM provider API 不稳定** | 中 | `LLMProvider` 协议隔离 provider 特定代码。每个 provider 一个文件。版本固定的 API 端点。 |
| **强制退出时 SQLite 损坏** | 中 | WAL 模式 + 自动完整性检查 + 备份 + 恢复流程。 |
| **长对话期间内存增长** | 中 | Core 中的压缩已处理此问题。App 层增加：惰性 block 解码、虚拟滚动、内存压力响应。 |
| **通过工具链绕过权限** | 高 | Core 中的 AST 感知安全检查器。App 层增加：审计日志、可疑模式检测、危险工具的速率限制。 |
| **流式传输断开无恢复机制** | 中 | `StreamPipeline` 中的 `ResumeToken`。通过 `NWPathMonitor` 进行连接监控。指数退避自动重试。 |
| **多窗口状态损坏** | 低 | 每窗口 Actor 隔离状态。每个窗口有独立的 `AppViewModel` 或限定作用域的状态切片。 |
| **无障碍功能退化** | 中 | 无障碍审计作为 CI 门禁。`A11yExtensions` 提供可 lint 的 API 表面。使用 accessibility inspector 的 XCUITest。 |

---

## 20. 关键设计决策（持续更新）

| # | 决策 | 理由 | 重新评估时机 |
|---|----------|-----------|-------------|
| 1 | AppKit 外壳加 SwiftUI 内容，而非纯 SwiftUI | SwiftUI 无法表达：自定义文本系统（编辑器）、PTY 终端、Metal 渲染、`NSOutlineView` 惰性加载、窗口标签组、`NSWindowRestoration` | SwiftUI 7+ 获得这些能力 |
| 2 | 所有 ViewModel 上使用 `@MainActor` | UI 状态变更必须同步。后台工作使用 detached task 加 actor-hop。比临时队列管理更简单。 | 性能分析显示主线程争用 |
| 3 | 自定义 VT100 模拟器，而非 libvterm | libvterm 是 C 语言，在 Swift 中存在内存管理摩擦。VT100 解析器是约 1500 行可理解的状态机代码。 | libvterm 获得官方 Swift 绑定 |
| 4 | SQLite + FTS5，而非 Core Data | Core Data 在大文本 blob 下性能下降。SQLite 对 WAL、FTS 和迁移提供直接控制。 | Core Data 获得一流 FTS 支持 |
| 5 | Metal 终端渲染，而非 NSTextView | NSTextView 无法处理终端吞吐量（100K+ 字符/秒）。Metal 网格渲染器在此用例中快 10-100 倍。 | NSTextView 获得 GPU 加速 |
| 6 | 每窗口一个 `AppViewModel`，而非全局单例 | 多窗口需要独立状态。每个窗口有自己的项目/线程选择。 | 只需要单窗口用例 |
| 7 | `LLMProvider` 协议 + 每 provider 实现 | 将模型访问与 UI 解耦。启用本地模型、自定义端点。 | 所有 provider 趋同于 OpenAI 兼容 API |
| 8 | 仅向前 SQLite 迁移 | 回滚很少被测试，且经常失败。仅向前 + 迁移前备份更安全。 | 需要支持升级失败后的降级 |
| 9 | 权限作为模式，而非每操作对话框 | 模态对话框打断开发者流程。基于模式的权限 + 内联批准尊重用户已建立的信任姿态。 | 用户研究显示偏好每操作对话框 |
| 10 | Block 级消息存储（每条消息一个 JSON blob） | 每 block 一行会爆炸行数（每条消息可有 20+ 个 blocks）。JSON blob 保持存储紧凑。FTS5 提取可搜索文本。 | 需要跨消息查询单个 blocks |

---

## 21. 附录：当前状态差距分析

| 当前 (v0.5.0) | 目标 (v1.0) | 阶段 |
|-------------------|---------------|-------|
| 仅 DeepSeek LLM | 多 provider（Anthropic、OpenAI、DeepSeek、本地） | 1 |
| SwiftUI `TextEditor` 编辑器 | `NSTextView`，带 @-mention、斜杠命令、图片粘贴 | 1 |
| 简单 `ScrollView` + `VStack` 消息 | 虚拟滚动消息列表，带惰性 block 解码 | 2 |
| 静态工具调用卡片 | 动画进度、展开/折叠、diff 预览 | 2 |
| 占位符右侧面板标签页 | 真实终端 (PTY)、实时文件浏览器、真实 diff 审查 | 3 |
| 无窗口恢复 | `NSWindowRestoration` + 多窗口支持 | 4 |
| 演示级错误处理 | 类型化错误分类，所有情况带重试/恢复 | 1 |
| 基础 SQLite | WAL 模式、FTS5、迁移、备份/恢复 | 1 |
| 最小化无障碍标签 | 完整 VoiceOver、动态字体、减弱动态效果、纯键盘操作 | 5 |
| 无搜索 | FTS5 全文搜索 + Quick Open + Spotlight | 4 |
| 单窗口 | 多窗口 + 独立工作区 | 4 |
| 无通知 | 完成、权限、长时间运行的用户通知 | 5 |
| 258 个测试（主要是 Core/CLI） | 400+ 测试，含 App 特定套件 | 全部 |
