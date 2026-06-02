# SwiftAgent TUI 架构

## 概述

SwiftAgent 的 TUI 是一个零外部依赖、纯 Swift 实现的终端 UI，直接基于 ANSI 转义序列和 raw-mode 终端 I/O 构建。它采用 Nanobot REPL 模式（Claude Code 亦用此模式）：持久化的 read-eval-print 循环，配合流式 LLM 响应、内联工具执行、spinner 状态指示、Markdown 渲染和弹出式补全。

不使用任何外部 TUI 框架（ncurses、SwiftTerm、TermKit）。唯一的间接系统依赖是 Apple 的 `swift-argument-parser`，仅用于 CLI 入口点接线。

所有代码位于 `Sources/SwiftAgentCLI/`（约 22 个文件，~4000 行）。设计目标：Claude Code 行为层面的 1:1 对齐，但以 Swift 原生惯用方式实现，不盲从 TypeScript 模式。

---

## 架构分层

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          ChatCommand.swift                               │
│                       主 REPL 循环 + 内联 Agent 循环                     │
│           初始化 · 斜杠命令 · 流式处理 · 工具执行 · 会话管理            │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────────────┐  │
│  │   LineEditor     │  │ TerminalRenderer  │  │   MarkdownRenderer    │  │
│  │   raw-mode 输入  │  │   ANSI 输出渲染   │  │   Markdown → ANSI     │  │
│  │                  │  │                   │  │   含语法高亮          │  │
│  │ ┌──────────────┐ │  │ · renderBanner   │  │ · 代码块检测          │  │
│  │ │ InlinePopup  │ │  │ · renderPanel    │  │ · 表格渲染            │  │
│  │ │ @ / / 补全   │ │  │ · renderLeftBorder│ │ · 标题 + 内联格式    │  │
│  │ │ PopupDataSrc │ │  │ · spinnerFrame   │  │ · TreeSitter 集成     │  │
│  │ └──────────────┘ │  │ · cursor 控制    │  └───────────────────────┘  │
│  └──────────────────┘  └───────┬──────────┘                             │
│                                │                                         │
│  ┌─────────────────────────────┴──────────────────────────────────────┐  │
│  │                      基础设施层                                     │  │
│  │  TerminalCapability  │  ColorTheme / ANSIColor  │  TerminalDisplay  │  │
│  │  TTY · 颜色 · 尺寸   │  语义色 + 16/256/真彩色  │  Width (CJK/Emoji)│  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                      编排辅助                                        │ │
│  │  CurrentToolTracker  │  ChatToolInputAccum.  │  ChatToolExecScheduler│ │
│  │  CollapseDetector    │  CollapsedSummaryFmt  │  ToolResultCache      │ │
│  │  StatusLine          │  DebugLogger          │                      │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘

Core/CLI 边界：
  SwiftAgentCore (Types, Tools, Agent, LLM)  ← 纯逻辑，可复用
  SwiftAgentCLI (ChatCommand, TerminalRenderer, LineEditor, …) ← 终端 I/O
  CLI 依赖 Core，Core 不知 CLI 存在
```

### 文件清单

| 文件 | 行数 | 职责 |
|------|------|------|
| `ChatCommand.swift` | ~1799 | 主 REPL 循环 + 内联 Agent 循环 + 43 工具注册 + 斜杠命令分发 + Spinner/Escape 管理 |
| `LineEditor.swift` | ~1288 | Raw-mode 行编辑器：历史 · 粘贴 · 转义序列 · 词边界 · Popup 集成 · Ghost text |
| `MarkdownRenderer.swift` | ~780 | Markdown → ANSI：代码高亮 · 表格 · 标题 · 内联格式 · 左边界 · 自动代码块检测 |
| `InlinePopup.swift` | ~330 | 内联补全弹出菜单：`/` 命令 + `@` 文件搜索 · 滚动 · 选中高亮 · 子菜单 |
| `TerminalRenderer.swift` | ~232 | ANSI 基元：Banner · Panel · LeftBorder · Spinner · 光标控制 · TTY drain |
| `PopupDataSource.swift` | ~500 | 四个数据源：CommandDataSource · FileDataSource · SessionDataSource · ArgumentDataSource |
| `CollapseDetector.swift` | ~350 | 工具结果可折叠判定 + 分组合并 + 摘要生成 |
| `TerminalCapability.swift` | ~62 | TTY 检测、色彩支持（TERM/COLORTERM）、终端尺寸（ioctl TIOCGWINSZ）、ANSI scrub |
| `ColorTheme.swift` | ~116 | ANSI 颜色体系：16 色 + true color + ANIStyle + default/monochrome 双主题 |
| `TerminalDisplayWidth.swift` | ~105 | Unicode 感知列宽 (CJK=2, 组合字符=0, Emoji=2) + cursor 定位 |
| `DebugLogger.swift` | ~198 | JSONL 调试日志 (API 请求/响应/SE 事件)，API key 掩盖 |
| `SyntaxHighlighter.swift` | ~400 | 双引擎 tokenizer：正则 (13 语言) + Tree-sitter |
| `TokenANSIRenderer.swift` | ~100 | 语法 token → ANSI 颜色映射 |
| `CodeTheme.swift` | ~80 | 代码高亮颜色预设 (Monokai, GitHub) |
| `ToolResultCache.swift` | ~80 | 折叠工具结果缓存，供 `/expand` / `Ctrl+O` 展开 |
| `CollapsedSummaryFormatter.swift` | ~150 | 折叠工具结果组 → 单行 ANSI 摘要 |
| `FuzzyMatcher.swift` | ~100 | 四层评分：精确 → 前缀 → 子串 → 有序子序列 |
| `FileSearchIndex.swift` | ~200 | 基于 git ls-files 的文件搜索索引 (内存操作) |
| `StreamRenderer.swift` (Core) | ~100 | StreamEvent → 纯文本 (无 ANSI)，属于 Core 层 |

---

## 1. 入口点与 REPL 循环

### 初始化流程 (`ChatCommand.run()`, L201-393)

```
1. 保存终端 termios 状态 — 用于 AskUserQuestion 时恢复 cooked mode
2. 解析 API key — 环境变量 / keychain / ~/.claude.json / --api-key
3. 创建 TerminalCapability — 检测 TTY、色彩、尺寸
4. 选择 ColorTheme — --no-color 则 .monochrome，否则 .default
5. 创建 TerminalRenderer — 注入 capability + theme
6. 创建 MarkdownRenderer — 注入 capability + theme + TreeSitterSyntaxHighlighter + CodeTheme
7. 渲染 Banner — renderer.renderBanner(version:) 输出 Unicode 框线
8. 创建 LLMClient + ToolRegistry + 注册 43 个内置工具
9. MCP Bootstrap — 连接服务器，注册 MCP 工具，收集服务器指令
10. 构建系统固化 System Prompt — 一次性构建，含 MCP 指令，利用 prompt caching
11. 创建 LineEditor — 注入 / 命令和 @ 文件 popup 数据源
12. 进入 REPL 循环
```

### REPL 循环 (`while true`, L430)

1. `renderer.drainTTYInput()` — 清空生成期间堆积的键盘缓冲
2. `editor.readLine(prompt: "You: ")` — raw mode 下阻塞等待输入
3. 输入以 `/` 开头 → 分发到 slash command 处理器（23+ 命令）
4. 否则，将用户消息追加到 `conversationHistory`，进入**内联 agent 循环**

### 内联 Agent 循环 (L655-898)

无人工迭代上限，模型通过 `stop_reason == "end_turn"` 自主决定何时停止：

1. 检查 ESC 取消标志 (`AtomicBool isCancelled`)
2. 启动 spinner Task（100ms 间隔，独立并发 Task）
3. 启动 ESC 监听 Task（raw mode 下 poll() + read() 监听裸 ESC）
4. 通过 `LLMClient.send()` 流式获取 LLM 响应
5. 分发 stream 事件：text/thinking delta、content block start/stop、message metadata
6. 流结束后：
   - 存在 `tool_use` block → 执行工具，结果追加到对话历史，循环继续
   - 无工具调用 → 模型结束，退出到 REPL
   - `stop_reason == "max_tokens"` → 截断恢复：执行已解析的工具调用，注入 `"[system] Continue from where you left off."` 继续提示
7. Spinner Task 取消，ESC watcher 取消
8. 渲染最终响应：MarkdownRenderer 或 renderLeftBorder

### Spinner 子系统 (L612-640)

- 独立 `Task`，每 100ms 一帧
- **无工具运行时**：`⠋ Thinking...`
- **工具活跃时**：`⠋ <工具名> → <命令摘要>`（通过 `CurrentToolTracker.displayLine`）
- **智能暂停**：
  - `SpinnerPauseFlag` — AskUserQuestion 交互期间暂停，防止 `\r\e[K` 清除用户输入
  - `currentTool.isThinking` — 思考文本到达时暂停，切换为 dim 模式文本渲染
- **取消时**：输出 `\r\e[K` 清除当前行

### ESC 中断机制 (L574-605)

- 后台 Task 运行 `editor.interceptEscape()`，独立 raw-mode poll 循环
- 区分裸 ESC (50ms 超时无后续字节) 和转义序列
- 在每次 LLM round 前和每个 stream 事件处理后检查 `AtomicBool isCancelled`
- 用户提问交互前先 cancel watcher、等 150ms 让 poll() 退出、恢复 cooked mode；完成后重启
- 取消时：spinner 和 watcher 被取消，当前轮次的对话历史回滚，显示 `"(cancelled — press ↑ to recall previous input)"`

### Cooked-mode 切换 (L201-207)

- 启动前保存原始 `termios`
- Interactive user prompts (AskUserQuestion) 时恢复 cooked mode，避免 raw mode 窃取 stdin 字节
- 用户回答完毕后恢复 raw mode

---

## 2. 终端基元层

### `TerminalCapability.swift`

启动时检测终端能力：

| 属性 | 来源 |
|------|------|
| `isTTY` | `isatty(STDIN_FILENO) && isatty(STDOUT_FILENO)` |
| `supportsColor` | `COLORTERM` 环境变量 / `TERM` 含 "color" 或 "256" / xterm |
| `columns` / `rows` | `TIOCGWINSZ` ioctl → `COLUMNS`/`LINES` 环境变量 → 默认 80×24 |

提供包装方法：
- `color(_:color:style:)` — 色彩支持时包装 ANSI，否则原样返回。这是终端降级为纯文本的唯一控制点。
- `scrubANSICodes(_:)` — 非 TTY 输出时正则去除所有 ANSI 转义序列。

提供测试用构造函数 `init(isTTY:supportsColor:columns:rows:)` 允许注入伪造值。

### `ColorTheme.swift`

语义色彩映射，与具体终端颜色解耦：

```
ColorTheme.default
├── primary: .blue        # 横幅、标题
├── secondary: .cyan      # 边框、装饰
├── success: .green       # 成功提示
├── warning: .yellow      # 警告
├── error: .red           # 错误
├── dim: .brightBlack     # 次要文本
└── bold: .bold           # 强调样式
```

`ColorTheme.monochrome` 将所有颜色映射为 white/brightBlack，通过 `--no-color` 标志激活。

`ANSIColor` 枚举：8 标准色（30-37）+ 8 高亮色（90-97）+ `trueColor(r:g:b:)`（24-bit True Color）。

`ANIStyle` 枚举：reset(0)、bold(1)、dim(2)、italic(3)、underline(4)、blink(5)。

顶层 `ansi()` 函数：用 color/style 前缀 + `\033[0m` 重置包装文本。

### `TerminalDisplayWidth.swift`

Unicode 感知的列宽测量。对正确的光标定位至关重要：

- **零宽字符**：控制字符、组合标记 (U+0300-036F)、变体选择器 (U+FE00-FE0F)、零宽连接符 (U+200D)
- **全宽字符**：CJK 汉字、Hangul、Emoji → 宽 2
- **Tab** → 宽 4
- **ANSI 转义剥离** 用于可见宽度计算
- `cursorPosition(forOffset:columns:)` → (row, col) 映射
- `rows(forWidth:columns:)` → 给定内容宽度和终端列数，计算占用行数

---

## 3. 输入系统

### `LineEditor.swift` — Raw-Mode 行编辑器

最复杂的单文件（1288 行）。在 raw terminal mode 下实现完整的行编辑器。

**Raw Mode 设置** (`enterRawMode()`, L619-645):
- 通过 `termios` + `tcsetattr` 禁用：ICANON（行缓冲）、ECHO（回显）、ISIG（信号生成）、IXON（流控）、ICRNL（`\r`→`\n` 转换）、OPOST（输出处理）
- 启用 bracket paste 模式 (`\033[?2004h`)

**键盘绑定**：

| 按键 | 行为 |
|------|------|
| Left/Right | 字符级光标移动 |
| Up/Down | 多行内行间移动；在首/尾行边界切到历史导航 |
| Alt+Left/Alt+Right | 按字母数字边界跳词 (wordBoundaryBefore/After) |
| Home/End | 行首 / 行尾 |
| Ctrl+A / Ctrl+E | 行首 / 行尾 (Emacs 风格) |
| Ctrl+U | 清空整行 |
| Ctrl+K | 删除至行尾 |
| Ctrl+W | 删除前一个词（空格边界） |
| Alt+Backspace | Bash 风格 backward-kill-word（字母数字边界） |
| Alt+Enter | 插入字面换行符 |
| Shift+Enter | 插入字面换行符（通过 `CGEventSource.flagsState(.hidSystemState)` 的 HID Shift 检测） |
| Tab | Popup 模式确认选中 / 正常模式插入 4 空格 |
| Ctrl+C | 取消 Popup；无 Popup 时返回 nil (EOF) |
| Ctrl+D | 空行时 EOF |
| Ctrl+O | `/expand last` 触发标记 |
| Escape | Popup 内取消 / 中断 LLM 生成 |

**Escape 序列解析器** (L667-799):
- 超时消歧：收到 `\033` 后等约 50ms 判断是裸 ESC 还是 CSI/SS3 序列开头
- 支持标准 CSI 方向键、Home/End（H/F 变体）
- 支持 SS3（tmux 风格 `ESC O ...`）方向键
- Kitty keyboard protocol (`CSI <key>;<mods> u`) 支持 Shift+Enter、Alt+Backspace
- xterm modified keys (`CSI <key>;<mods> <letter>`) 支持 Alt+方向键
- Bracketed paste：读取 `\033[200~ ... \033[201~` 分隔的内容
- Alt/Option+字符：ESC + b (word left)、ESC + f (word right)、ESC + DEL (delete word)

**Paste 处理** (L520-608):
- Burst 检测：50ms 内连续到达的字符视为同一粘贴操作
- 单行粘贴：直接插入
- 多行粘贴：显示 `[Pasted text #N +M lines]` 占位符，提交时展开为原始内容
- Bracketed paste 优先，非 bracket 终端用 poll() fallback
- 保留原始换行以便后续编辑

**历史系统** (L836-928):
- Null byte (`\0`) 分隔的文件格式，支持多行条目
- 旧版 `\n` 分隔格式自动检测并迁移
- StashedBuffer 机制：用户输入文本后按 ↑，文本被暂存；按 ↓ 超过最新条目时恢复到暂存内容（bash/zsh readline 行为）
- 500 条目上限
- 持久化到 `~/.swift-agent/history/cli_history`

**重绘策略** (`redrawLine()`, L992-1074):
1. 光标移到输入区域起始行 (`\033[lastCursorRowA`)
2. 从光标处清至屏尾 (`\r\033[J`)
3. 渲染 prompt（蓝色 `\033[1;34m`）+ 第一行输入
4. 渲染续行（padding 对齐 prompt 宽度）
5. 若 active 则渲染 popup（在输入区域下方）
6. 若存在 ghost text，在光标后以 dim 样式渲染
7. 将光标精确定位到插入位置

**关键设计**：使用 cursor-up 显式移动而非 save/restore（`\033[s`/`\033[u` 在不同终端模拟器中表现不一致）。代价是 LineEditor 必须自行追踪 `drawnLines` 和 `lastCursorRow`——跟踪前一次重绘占用的终端行数，确保下一次重绘前正确清除旧内容。

**Ghost Text** (L1029-1042):
- 从 popup 选中命令后，参数提示以 dim (`\033[90m`) 样式显示在光标后
- 例：选择 `/model` 后显示 `[model-name]` 的 ghost text
- 用户输入时自动清除

### `InlinePopup.swift` — 内联补全弹出菜单

在输入行下方渲染，用于 `/`（命令）和 `@`（文件）补全。

**渲染效果**：
```
╭ /mod ─────────────────────────────────╮
│ ↑ 3 more                              │  ← 向上滚动指示
│ ▸ /model          Change model        │  ← 选中行 (reverse video + ▸)
│   /doctor         Diagnose install    │
│   /memory         Edit session memory │
│ ↓ 15 more                             │  ← 向下滚动指示
╰───────────────────────────────────────╯
```

**状态管理**：
```
InlinePopup
├── dataSource: PopupDataSource   # 搜索后端
├── config: PopupConfig           # 视觉参数 (maxHeight=12, maxWidth=66)
├── items: [PopupItem]            # 当前匹配项
├── selectedIndex: Int            # 当前选中 (0-based)
├── scrollOffset: Int             # 虚拟滚动偏移
└── query: String                 # 搜索字符串
```

**核心逻辑**：
- **搜索**：输入追加到 query，`dataSource.search(query:)` 实时过滤，selectedIndex 重置为 0
- **导航**：↑ ↓ 移动 `selectedIndex`，`updateScroll()` 维护虚拟滚动窗口（确保选中项在可见区域内）
- **选中高亮**：黄色加粗标记匹配位置，反转视频标记选中行，`▸ ` 指示器
- **帮助列**：右侧 `item.help` 列显示命令/文件描述，宽度自适应（最多 popup 宽度的 1/3）
- **截断**：`fit(_:to:)` 正确处理 CJK 宽字符并追加 `…`
- **无匹配行为**：输入无匹配项时自动 dismiss popup 但保留 buffer 文本（`dismissPopupKeepBuffer()`）

**嵌套 Sub-menu 支持** — 选中项具有：
- `subOptions`（如 `/model` → `["default", "deepseek-v4-flash", ...]`）：自动打开 `ArgumentDataSource` 二级 popup
- `subDataSource`（如 `/resume` → `SessionDataSource`）：打开动态子菜单，列出已保存会话
- `isSubMenu` 标志：子菜单取消时仅关闭 popup，不删除已提交的命令文本
- `submitOnSelect`：选中即自动提交（如 /resume 选会话后直接加载，无需第二次 Enter）

**已知问题**：ANSI 硬编码（`"\u{001B}[36m"`）而非使用 `ColorTheme`/`ANSIColor`，与 Theme 系统脱节。

### `PopupDataSource.swift` — 补全数据源

`PopupDataSource` 协议：`search(query:) -> [PopupItem]`。四个实现：

| 数据源 | 触发 | 数据 | 特点 |
|--------|------|------|------|
| `CommandDataSource` | `/` | 28+ 内置命令 + skills | 模糊匹配命令名和别名；argumentHints 提供幽灵参数提示；subOptions 驱动子菜单；/resume 委托给 SessionDataSource |
| `FileDataSource` | `@` | 工作目录文件树 | 基于 git ls-files 的 FileSearchIndex（一次构建，内存查询）；支持目录作用域搜索；隐藏文件仅在 query 以 `.` 开头时显示；VCS 目录排除；目录条目以 `/` 结尾 |
| `SessionDataSource` | 嵌套 | 已保存会话 | 从 SessionStore 加载最近 20 个会话；显示 ID、日期、消息数；submitOnSelect |
| `ArgumentDataSource` | 子菜单 | 静态选项列表 | 简单字符串匹配；用于模型名、权限模式等参数值选择 |

**`PopupItem`** 结构：
- `display` — 列表显示的文本
- `insertText` — 选中后插入 buffer 的文本（含触发字符）
- `argumentHint` — 提交后显示的幽灵占位文本
- `subOptions` — 参数值子菜单的选项数组
- `subDataSource` — 动态子菜单的数据源
- `submitOnSelect` — 选中后是否自动提交整行
- `score` + `matchPositions` — 模糊搜索评分和匹配位置（用于高亮）

### `FuzzyMatcher.swift`

四级评分：
1. **1.0** — 精确匹配（大小写不敏感）
2. **0.9** — 前缀匹配
3. **0.7** — 子串匹配（任意位置）
4. **~0.5 × coverage** — 有序子序列匹配（所有 query 字符按序出现，按覆盖率缩放）
5. **0.0** — 无匹配

返回匹配位置用于弹窗中的字符高亮。

---

## 4. 输出渲染

### `TerminalRenderer.swift` — ANSI 输出基元

全部公开 API：

| 方法 | 功能 |
|------|------|
| `write(_:color:style:)` | 基础色彩文本输出，非 TTY 时跳过 ANSI |
| `renderBanner(version:)` | 欢迎横幅（Unicode 框线 `┌───┐`），宽度固定在 41 列 |
| `renderStatusLine(_:)` | 全宽反向视频状态栏，显示 Working / Tokens / Session |
| `renderDelta(_:current:)` | 流式文本增量，清理 `\r\n` 并 scrub ANSI |
| `renderPanel(title:content:borderColor:)` | Rich-style 面板，自适应终端宽度（最大 80 列），自动折行（智能断词），`╭── title ──╮` 标题 |
| `renderLeftBorder(content:color:)` | 仅左侧竖线 `│ ` 装饰，Nanobot 风格，用于 AI 响应流式输出 |
| `renderThinkingLine(frame:)` | Braille spinner `⠋` + "Thinking..." |
| `renderPermissionPrompt(tool:input:)` | 权限确认 `[y]es / [n]o / [a]lways` |
| `spinnerFrame(index:)` | 单帧 braille spinner（⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏） |
| `horizontalRule()` | 水平分隔线 |
| `clearScreen()` / `cursorUp(_:)` / `cursorDown(_:)` | 屏幕/光标控制 |
| `saveCursor()` / `restoreCursor()` | 光标位置保存/恢复 |
| `drainTTYInput()` | `tcflush(TCIFLUSH)` 清空键盘缓冲；回退到 `poll()` + 非阻塞 `read()` |

**渲染模式分离**：
- `renderPanel` — 四完整边框面板，用于静态内容（帮助页、diff 输出）
- `renderLeftBorder` — 仅左侧竖线，用于 AI 响应的流式输出，避免全边框重绘闪烁

### `MarkdownRenderer.swift` — Markdown → ANSI

块级状态机：

| 块类型 | 渲染方式 |
|--------|----------|
| H1 | 上划线 + `═══` 下划线 |
| H2 | 文本 + `───` 下划线 |
| H3 | 加粗 + 着色 |
| H4+ | 纯加粗 |
| 代码围栏 | 带 `┌── lang ──┐` 头的框线，语法高亮（fence 深度跟踪支持嵌套） |
| 表格 | 解析列，居中加粗表头，`├───┼───┤` 分隔符 |
| 引用块 | `▎` 前缀，dim 样式 |
| 水平分隔线 | 全宽 `───` |
| 列表项 | `•` 前缀，主题色 |

内联处理：
- `` `code` `` → 加下划线 dim
- `**bold**` → ANSI bold
- `*italic*` → ANSI italic
- `[text](url)` → 加下划线，主题色

自动代码块检测 (`autoDetectCodeBlocks`)：通过关键词密度和缩进模式识别无围栏标记的代码块。

代码块通过语法高亮引擎进行着色：`RegexSyntaxHighlighter`（13 语言）或 `TreeSitterSyntaxHighlighter` → `TokenANSIRenderer` → `CodeTheme`。

### `StreamRenderer.swift` (Core 层)

位于 `SwiftAgentCore` 而非 CLI 层。将 `StreamEvent` 映射为终端可显示的字符串。**不涉及 ANSI escape 或 cursor 操作**——这些由 CLI 层的 `ChatCommand.run()` 直接处理。

| StreamEvent | 输出 |
|-------------|------|
| `.textDelta(text)` | 直接透传 |
| `.thinkingDelta` | `""`（CLI 层单独处理 dim 渲染） |
| `.contentBlockStart(.thinking)` | `"\n[Thinking...]\n"` |
| `.contentBlockStart(.redactedThinking)` | `"\n[Thinking redacted]\n"` |
| `.contentBlockStart(.toolUse(name))` | `"\n→ Calling tool: {name}...\n"` |
| `.contentBlockStart(.serverToolUse(name))` | `"\n→ Server tool: {name}...\n"` |
| `.inputJSONDelta` | `"."` 点进度指示 |
| `.messageDelta(usage:)` | `"\n[Tokens: ↓n ↑m]"` |
| `.error(msg)` | `"\n❌ Error: {msg}\n"` |

**边界设计**：`StreamRenderer` 只负责语义格式化（事件 → 人类可读行）。视觉渲染（dim、spinner、cursor 移动）由 CLI 层内联处理。这确保 Core 层可复用到非终端场景（Web UI、IDE 插件等）。

### `StatusLine.swift`

渲染底部反向视频状态栏：
1. 从 `AppStateStore` 获取快照
2. 将光标移到底部行 (`\033[NB`)
3. 写入全宽反向视频行（`\033[7m ... \033[0m`）
4. 恢复光标位置

---

## 5. 语法高亮

### `SyntaxHighlighter.swift` — RegexSyntaxHighlighter

零依赖、基于正则的语法高亮器。单遍扫描、上下文感知：

1. **第一遍**：块注释、行注释、字符串、数字
2. **词令牌**：对照语言关键字字典检查
3. **上下文感知分类**：前一个令牌设置上下文：
   - `.declaration` → 下一个词是 `function.declaration`
   - `.typeAnnotation` → 下一个词是 `type`
4. **启发式**：PascalCase → `type`，后跟 `(` → `function.call`

支持 13 种语言：Swift、Python、JavaScript、TypeScript、Bash、JSON、Go、Rust、C、C++、Ruby、SQL、YAML、Markdown。

另含 `TreeSitterSyntaxHighlighter`，通过 tree-sitter 提供更高精度的语法高亮。

### `TokenANSIRenderer.swift`

线性遍历源文本，在令牌边界插入 ANSI 着色段。使用 `CodeTheme` 将捕获名（如 `keyword`、`string`、`function`）映射为颜色。

### `CodeTheme.swift`

Monokai 和 GitHub 两套预设。将 tree-sitter 风格的捕获名映射到 `ANSIColor` 值，支持模式匹配（如 `keyword*` 匹配 `keyword`、`keyword.function` 等）。

### `LanguageRegistry.swift`

语言语法定义注册表。包含每种语言的关键字集、注释风格、字符串定界符。

---

## 6. 工具执行显示

### `CurrentToolTracker`

线程安全（`NSLock` 保护）的活跃工具执行追踪器。支持 spinner 显示：

- `start(id:name:displayCmd:)` — 注册运行中的工具，带可选的命令摘要
- `update(id:status:)` — 更新进度消息（由 AgentTool、TaskOutput 使用）
- `finish(id:)` — 移除已完成的工具
- `displayLine` — 状态行计算属性：
  - 1 个工具：`Running <name> → <command>` 或自定义状态
  - 2-3 个工具：`<N> tools running | <name> running; <name> running`
  - 4+ 个工具：`<N> tools running | ...; ... +M more`
- `isThinking` — 用于暂停 spinner 显示 thinking 文本

注意：`SendUserMessage` 类工具名称从 spinner 中被抑制——它们是透明的消息传递机制，不是用户可见的工具。

### `ChatToolInputAccumulator`

从流式 `inputJSONDelta` 事件增量构建工具输入 JSON：
1. `startTool(name:id:)` — 开始为新 tool call 累积 JSON
2. `appendInputJSONDelta(_:)` — 追加 JSON 片段
3. `stopCurrentBlock()` — 解析累积的 JSON 为 `[String: JSONValue]`
4. `finish(stopReason:)` — 处理 `max_tokens` 截断

错误处理：
- 无效 JSON → `ChatToolInputError.invalidJSON`
- 被 token 限制截断 → `ChatToolInputError.truncatedByMaxTokens`

### `ChatToolExecutionScheduler`

乐观并行工具执行：
- 并发安全工具放在 `TaskGroup` 中并行执行
- 非安全工具按顺序依次执行
- 在对话历史中保持原始调用顺序

### 工具结果折叠系统

类似 Claude Code 的 `collapseReadSearch`：

```
ChatToolExecutionScheduler (执行结果)
  │
  ▼
emitCollapsedResults()
  ├── CollapseDetector.isCollapsible() → 判定工具类型（Read、Glob、Grep、搜索类 Bash 命令）
  ├── 分组：连续可折叠工具合并为一个 CollapsedGroup
  ├── CollapsedSummaryFormatter → ANSI 彩色单行摘要 + 内容预览（前 3 行、200 字宽）
  └── ToolResultCache.store() → 保存完整输出
```

展开/折叠控制：
- `Ctrl+O` → 纯切换：若已展开则折叠，否则展开最后一个 group
- `/expand last` 或 `/expand N` → 展开指定索引的 group
- 展开通过 ANSI `\033[nA\033[0J`（上移 + 清至屏尾）实现内联替换
- `ExpandState` 跟踪当前展开的 group 索引和行数，供折叠时精确清除

---

## 7. ANSI 转义序列参考

### 样式

| 代码 | 效果 | 使用位置 |
|------|------|----------|
| `\033[0m` | 重置 | 每个样式段后缀 |
| `\033[1m` | 加粗 | 标题、强调文本 |
| `\033[2m` | 变暗 | 思考文本、引用块、代码背景 |
| `\033[3m` | 斜体 | 强调 |
| `\033[4m` | 下划线 | 链接、行内代码 |
| `\033[7m` | 反转视频 | 状态栏、popup 选中行 |

### 颜色

| 代码 | 效果 |
|------|------|
| `\033[30m`–`\033[37m` | 标准前景色（黑–白） |
| `\033[90m`–`\033[97m` | 高亮前景色 |
| `\033[38;2;R;G;Bm` | TrueColor 前景色 |
| `\033[40m`–`\033[47m` | 标准背景色（前景色 +10） |

### 光标与屏幕

| 代码 | 效果 |
|------|------|
| `\033[N A` | 光标上移 N 行 |
| `\033[N B` | 光标下移 N 行 |
| `\033[N C` | 光标前移 N 列 |
| `\r` | 回车（至列 0） |
| `\033[K` | 清至行尾 |
| `\033[J` | 清至屏尾 |
| `\033[2J\033[H` | 清屏 + 光标归位 |

### Bracketed Paste

| 代码 | 效果 |
|------|------|
| `\033[?2004h` | 启用 bracketed paste |
| `\033[?2004l` | 禁用 bracketed paste |
| `\033[200~` | Paste 开始标记 |
| `\033[201~` | Paste 结束标记 |

---

## 8. 数据流

### 时序图：完整一轮对话

```
┌──────────┐     ┌───────────┐     ┌──────────┐     ┌────────────┐     ┌───────────┐
│LineEditor│     │ChatCommand│     │LLMClient │     │ ToolExecutor│    │Terminal   │
│(raw tty) │     │(编排器)    │     │  (HTTP)  │     │(core logic)│    │ Renderer  │
└────┬─────┘     └─────┬─────┘     └────┬─────┘     └─────┬──────┘     └─────┬─────┘
     │                 │                │                  │                  │
     │ readLine()      │                │                  │                  │
     │────────────────>│                │                  │                  │
     │                 │                │                  │                  │
     │  "You: help"    │                │                  │                  │
     │<────────────────│                │                  │                  │
     │                 │                │                  │                  │
     │                 │ send(messages) │                  │                  │
     │                 │───────────────>│                  │                  │
     │                 │                │  HTTP POST       │                  │
     │                 │                │ ─── SSE stream ─ │                  │
     │                 │                │                  │                  │
     │                 │  StreamEvent[] │                  │                  │
     │                 │<───────────────│                  │                  │
     │                 │                │                  │                  │
     │                 │ ── for each event ──              │                  │
     │                 │                │                  │                  │
     │                 │ .thinkingDelta │                  │                  │
     │                 │────────────────┼──────────────────┼── dim 文本 ────>│
     │                 │                │                  │                  │
     │                 │ .textDelta     │                  │                  │
     │                 │────────────────┼──────────────────┼── 纯文本 ───────>│
     │                 │                │                  │                  │
     │                 │ .contentBlockStart(toolUse)       │                  │
     │                 │────────────────┼───── ChatToolInputAccumulator ──>│
     │                 │       .startTool()                │                  │
     │                 │                │                  │                  │
     │                 │ .inputJSONDelta│                  │                  │
     │                 │────────────────┼─ .appendJSON() ─>│                  │
     │                 │                │                  │                  │
     │                 │ .contentBlockStop                 │                  │
     │                 │────────────────┼─ .stopBlock() ──>│                  │
     │                 │                │                  │                  │
     │  (stream 结束)   │                │                  │                  │
     │                 │                │                  │                  │
     │                 │ executable(name, input, ctx)      │                  │
     │                 │────────────────┼─────────────────>│                  │
     │                 │                │                  │                  │
     │                 │ currentTool    │                  │                  │
     │                 │ .start(id,name)│    spinner: ─────┼── "运行 X...">│
     │                 │                │                  │                  │
     │                 │                │                  │ toolResult()     │
     │                 │                │                  │──── "输出" ────>│
     │                 │                │                  │                  │
     │                 │ currentTool    │                  │                  │
     │                 │ .finish(id)    │    spinner: ─────┼── 清除 ────────>│
     │                 │                │                  │                  │
     │                 │ toolResultSummary(name, in, out)  │                  │
     │                 │────────────────┼──────────────────┼── "Bash → ...">│
     │                 │                │                  │                  │
     │                 │ (工具结果追加到历史, 循环回 send)     │                  │
     │                 │───────────────>│                  │                  │
     │                 │                │                  │                  │
     │  (或: 无工具调用 → 跳出到 REPL)    │                  │                  │
     │                 │                │                  │                  │
     │                 │ responseText   │                  │                  │
     │                 │────────────────┼──────────────────┼── markdown ────>│
     │                 │                │                  │    渲染         │
     │<────────────────│                │                  │                  │
     │  绘制 prompt    │                │                  │                  │
```

### Stream 事件处理管线

```
                        ┌──────────────────────────────────────┐
                        │        AsyncThrowingStream            │
                        │         <StreamEvent>                 │
                        └──────────┬───────────────────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    ▼              ▼              ▼
              ┌───────────┐ ┌───────────┐ ┌──────────────┐
              │thinking   │ │  text     │ │  tool_use    │
              │  delta    │ │  delta    │ │  + inputJSON │
              └─────┬─────┘ └─────┬─────┘ └──────┬───────┘
                    │              │              │
                    ▼              ▼              ▼
           ┌─────────────┐ ┌───────────┐ ┌─────────────────┐
           │ dim-mode    │ │ 累积到    │ │ ChatToolInput   │
           │ 文本输出    │ │ turnText  │ │ Accumulator     │
           └──────┬──────┘ └─────┬─────┘ │ .appendJSON()   │
                  │              │       └────────┬────────┘
                  ▼              ▼                ▼
           ┌─────────────┐ ┌───────────┐ ┌─────────────────┐
           │thinkingText │ │           │ │ 解析出的工具    │
           │ 存入历史    │ │           │ │ 调用 +          │
           └─────────────┘ │           │ │ [String:JSON]   │
                           │           │ └────────┬────────┘
                           │           │          │
                           ▼           ▼          ▼
                    ┌──────────────────────────────────────┐
                    │         Assistant Message            │
                    │  [thinking] + [text] + [tool_use*]   │
                    └──────────────┬───────────────────────┘
                                   │
                    ┌──────────────▼───────────────────────┐
                    │        存在 tool_use block?           │
                    └──────┬──────────────────┬────────────┘
                           │ YES              │ NO
                           ▼                  ▼
              ┌─────────────────────┐  ┌──────────────┐
              │ChatToolExecution    │  │  stopReason  │
              │Scheduler            │  │  == max_     │
              │(并行/串行)           │  │  tokens?     │
              └──────────┬──────────┘  └──┬────────┬──┘
                         │                │ YES    │ NO
                         ▼                ▼        ▼
              ┌──────────────────┐ ┌────────┐ ┌─────────┐
              │  ToolExecutor    │ │继续循环│ │跳出到   │
              │  .execute()      │ │        │ │  REPL   │
              └────────┬─────────┘ └────────┘ └─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │  ToolResult      │
              │  → history       │
              │  → 循环继续      │
              └──────────────────┘
```

### 重绘管线（输入侧）

```
┌─────────┐    ┌────────────┐    ┌──────────────┐    ┌──────────────┐
│readByte │    │EscapeParser│    │ handleChar   │    │  redrawLine  │
│(stdin)  │───>│(CSI/SS3/   │───>│(插入/删除/   │───>│(ANSI 光标    │
│         │    │ kitty/paste)│   │  导航/popup)  │    │  定位)       │
└─────────┘    └────────────┘    └──────────────┘    └──────┬───────┘
                                                            │
                              ┌─────────────────────────────┘
                              ▼
              ┌─────────────────────────────┐
              │  1. \033[lastCursorRowA     │ 移至输入起始行
              │  2. \r\033[J                │ 清至屏尾
              │  3. prompt + buffer[0]      │ 绘制第一行
              │  4. pad + buffer[1..]       │ 绘制续行
              │  5. ghost text (dim)        │ 若有 ghost 则绘制
              │  6. popup.render()          │ 若有 popup 则绘制
              │  7. cursor 定位到插入点     │ 定位光标
              └─────────────────────────────┘
```

### Spinner / 状态循环

```
┌──────────────────────┐
│  Spinner Task        │  每 100ms
│  (后台 Task)         │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐     ┌──────────────────┐
│ CurrentToolTracker   │────>│ displayLine      │
│ (NSLock 保护)        │     │ 计算属性          │
│                      │     └────────┬─────────┘
│ .isThinking          │              │
│ .active tools        │     ┌────────▼─────────┐
└──────────────────────┘     │ 1 个工具:          │
                             │   "Running X..."  │
                             │ 2-3 个工具:        │
                             │   "X; Y running"  │
                             │ 0 个工具:          │
                             │   "⠋ Thinking..." │
                             └────────┬─────────┘
                                      │
                                      ▼
                             ┌──────────────────┐
                             │ \r\033[K <帧>   │
                             │ <状态文本>       │
                             │ fflush(stdout)   │
                             └──────────────────┘
```

---

## 9. 设计决策与原理

| 决策 | 说明 |
|------|------|
| **零依赖 ANSI 而非 ncurses/TermKit** | 可移植性（无 C 库链接）、精确控制（部分更新、光标定位、流式输出）、CC 对齐（Claude Code 本身使用直接 ANSI） |
| **cursor-up 显式移动而非 save/restore** | `\033[s`/`\033[u` 在不同终端模拟器中表现不一致，尤其在滚动区域中。显式 `\033[N A` 是确定性的。代价：LineEditor 自行追踪 `drawnLines` 和 `lastCursorRow` |
| **独立 spinner Task** | 以 100ms 间隔独立于 async stream 运行，保持动画流畅。智能暂停：用户交互提示时、thinking 文本渲染时 |
| **Bracket paste 检测** | 无此则粘贴的多行文本会被解释为多次 `readLine()` 返回。Bracket paste 协议 (`\033[200~...\033[201~`) 使编辑器将整个粘贴作为单次操作捕获 |
| **Null-byte 历史分隔符** | 换行分隔的历史无法存储多行条目（粘贴的代码块会变成 N 个独立条目）。Null byte 不出现在用户输入中，是安全的分隔符 |
| **ESC 超时消歧** | 裸 `\033` (ESC 键) 和以 `\033[` 开头的 CSI 序列都以 `\033` 开始。~50ms 超时决定：有后续字节 → 序列，无 → 裸 ESC |
| **Panel vs LeftBorder 分离** | `renderPanel` 渲染完整四边框（静态内容），`renderLeftBorder` 仅左侧竖线（AI 响应流式输出），避免全边框重绘闪烁 |
| **Core/CLI 边界严格** | `StreamRenderer` 在 Core 层（纯文本转换），`TerminalRenderer` 在 CLI 层（ANSI 颜色/布局）。Core 可在非终端场景中复用 |
| **手动 JSON 累积** | `ChatToolInputAccumulator` 从增量流式片段手动累积和解析工具输入 JSON，而非使用流式 JSON 解析器 |
| **Actor-free 并发** | 使用 manual `Task` + `@unchecked Sendable` + `NSLock` 保护共享状态，而非 Swift Actor |
| **Kitty protocol 前向兼容** | 已实现 kitty keyboard protocol 解析 (`CSI key;mods u`)，尽管当前主要依赖传统 escape codes |
| **写时渲染无缓冲** | 文本 delta 直接 `print()` + `fflush(stdout)`，不经过渲染缓冲层。Markdown 后处理在完整响应文本积累后执行 |
| **双路输出** | `emitBlock()` 统一块输出（自动规范化换行），`writeToStdout()` 直接 `Darwin.write()` 输出原始 ANSI 控制序列 |

---

## 10. 模块分类

### 输入层

| 文件 | 角色 |
|------|------|
| `LineEditor.swift` | Raw-mode 行编辑器、历史、popup 集成 (1288 行) |
| `InlinePopup.swift` | 内联补全菜单渲染与状态管理 |
| `PopupDataSource.swift` | `/` 命令和 `@` 文件补全数据源 |
| `FuzzyMatcher.swift` | 模糊字符串匹配引擎 |

### 输出层

| 文件 | 角色 |
|------|------|
| `TerminalRenderer.swift` | ANSI 输出基元、spinner、panel、banner |
| `TerminalCapability.swift` | TTY 与色彩能力检测 |
| `TerminalDisplayWidth.swift` | Unicode 感知列宽测量 |
| `ColorTheme.swift` | 语义色彩调色板、ANSI 颜色码 |
| `StatusLine.swift` | 底部状态栏 |
| `MarkdownRenderer.swift` | Markdown → ANSI（含语法高亮） |

### 语法高亮

| 文件 | 角色 |
|------|------|
| `SyntaxHighlighter.swift` | 正则+tree-sitter 双引擎 tokenizer |
| `TokenANSIRenderer.swift` | Token → ANSI 颜色映射 |
| `CodeTheme.swift` | 捕获名 → 颜色预设 |
| `LanguageRegistry.swift` | 语言语法定义 |

### 编排

| 文件 | 角色 |
|------|------|
| `ChatCommand.swift` | REPL 循环、agent 循环、工具分发 (1799 行) |
| `ChatToolInputAccumulator.swift` | 流式 JSON 组装 |
| `ChatToolExecutionScheduler.swift` | 并行/串行工具调度 |
| `CurrentToolTracker`（内嵌类） | 线程安全工具状态供 spinner 使用 |
| `CollapseDetector.swift` | 工具输出折叠检测 |
| `CollapsedSummaryFormatter.swift` | 折叠组 → 单行 ANSI 摘要 |
| `ToolResultCache.swift` | 折叠工具结果缓存与展开 |

### 基础设施

| 文件 | 角色 |
|------|------|
| `DebugLogger.swift` | JSONL 调试日志 |
| `EntryPoint.swift` | ArgumentParser 接线 |
| `FileSearchIndex.swift` | 文件索引供 @ 搜索 |

---

## 11. 扩展点

### 添加新的 slash 命令
1. 在 `ChatCommand.run()` 中的 `commandEntries` 数组添加条目
2. 在 `handleCommand()` 方法中添加处理器

### 添加新的 popup 数据源
1. 实现 `PopupDataSource` 协议
2. 调用 `editor.setPopupDataSources()` 或扩展 `LineEditor` 支持新的触发字符

### 添加新的语法语言
1. 向 `LanguageRegistry.languages` 添加 `LanguageGrammar`
2. 添加关键字集、注释风格、字符串定界符
3. 无需更改正则——扫描器是语言无关的

### 添加新的代码主题
1. 向 `CodeTheme` 添加静态预设（如 `.dracula`）
2. 将捕获名映射到 `ANSIColor` 值

### 添加新的工具显示模式
1. 在 `ChatCommand` 的执行闭包中检查 `call.name`
2. 自定义 `CurrentToolTracker` 显示或完全跳过（如 `SendUserMessage` 的处理）

---

## 12. 已知问题与改进清单

### P0 — 紧急

| 问题 | 说明 |
|------|------|
| `ChatCommand` 过长 (1799 行) | `run()` 方法约 1200 行，含 stream 处理、tool 执行、UI 更新——应提取 `AgentLoopController` |
| `LineEditor` 过长 (1288 行) | 拆分为 `LineEditor+History`、`LineEditor+Paste`、`LineEditor+Popup`、`LineEditor+Readline` |

### P1 — 重要

| 问题 | 说明 |
|------|------|
| InlinePopup ANSI 硬编码 | 使用内联 `"\u{001B}[36m"` 而非 `ColorTheme`/`ANSIColor`，与 Theme 系统脱节 |
| LineEditor prompt 色彩硬编码 | `"\u{001B}[1;34m"` 应通过 `TerminalRenderer` 或 `ColorTheme` |
| StreamRenderer 的 `highlightCodeBlocks` 未使用 | 语法高亮集成待完善 |
| 无终端 resize 信号处理 | `LineEditor.terminalColumns` 每次重绘时实时查询，但 popup 宽度和已渲染内容不会动态更新 |
| `showThinking` 逻辑分散 | 思考文本渲染逻辑分布在 3 处 switch case 中，应集中为 `ThinkingRenderer` |

### P2 — 改善

| 问题 | 说明 |
|------|------|
| Unicode 宽度覆盖不全 | `TerminalDisplayWidth` 使用硬编码范围检测 CJK/emoji，不覆盖所有 Unicode 版本 |
| 无线程安全的终端重绘 | `writeToStdout` 跨并发 Task 共享，没有互斥锁。若两个 Task 同时写入，可能交错 ANSI 序列 |
| 无 Vim 模式 | LineEditor 仅支持 Emacs 风格键位 |
| Markdown 渲染器不流式传输 | 等待完整响应后再调用 `markdown.render()`，CC 可实现逐块流式渲染 |
| Popup 仅 / 和 @ | CC 还在错误行旁边显示内联诊断、命令别名建议等。SwiftAgent 仅触发单词边界上的 `/` 和 `@` |
| 无终端能力协商 | 没有 terminfo 或 CSI u/DA 查询。假设支持 256 色 + UTF-8，无回退机制 |

### 通用挑战

1. **终端模拟器差异**：并非所有终端都支持 TrueColor、italic 或 bracket paste。`TerminalCapability` 降级路径可优雅处理缺失功能，但边界情况仍然存在。
2. **ESC 消歧可靠性**：基于超时的消歧（~50ms）在本地终端上有效，但在高延迟连接（SSH、tmux）下可能失效。
3. **流式输出与缓冲**：Swift 的 `print()` 默认使用行缓冲；thinking delta 后需手动调用 `fflush(stdout)` 实现行中更新。
4. **线程安全**：`CurrentToolTracker` 和 `SessionState` 在 spinner Task 和主 agent 循环之间使用 `NSLock` 保护。`AppState` 使用 Actor 隔离。

---

## 13. 三方对比：Claude Code vs Codex CLI vs SwiftAgent

### 架构哲学

| | Claude Code | Codex CLI | SwiftAgent |
|---|---|---|---|
| **语言** | TypeScript (Node.js) | Rust (native binary) | Swift (native) |
| **TUI 方法** | 保留模式 React (Ink fork) | 保留模式 (ratatui widgets) | 即时模式直接 ANSI |
| **框架** | 定制 Ink fork (~90 文件) | 定制 ratatui 0.29 fork + crossterm 0.28 fork | 无 (从零构建) |
| **布局引擎** | Yoga Flexbox (WASM) | ratatui Constraint-based Rect | 无 (手动定位) |
| **渲染管线** | Reconciler → DOM → Screen → Diff → ANSI | Widgets → `Buffer` → `diff_buffers()` → `DrawCommand` → ANSI | String → `print()` |
| **更新策略** | 单元格级 diff + 损伤区域 | 单元格级 diff（prev/next `Buffer` 对比），`ClearToEnd` 优化 | 每帧全量重绘 |

### 渲染

| | Claude Code | Codex CLI | SwiftAgent |
|---|---|---|---|
| **渲染模型** | 双缓冲 Screen（2D 字符网格） | 双缓冲 `ratatui::Buffer`（2D 字符网格） | 单遍字符串输出 |
| **帧率** | ~60fps 节流 | 事件驱动，动画 32ms 帧调度 | 事件驱动（无帧概念） |
| **Diff 算法** | LogUpdate: prev/next screen diff, 8 项优化规则, DECSTBM 硬件滚动 | 自定义 `diff_buffers()`: 逐单元格对比，输出 `Put` + `ClearToEnd` | 无 |
| **Markdown** | React 组件 (`Box`/`Text`) | pulldown-cmark 0.10 → 自定义 `markdown_render.rs` → ratatui `Line`/`Span` | 自定义 ANSI 字符串渲染器 |
| **代码块** | React + Shikiji (tree-sitter) | syntect 5 + two-face 0.5 (~250 种语言, ~32 个主题) | 自定义正则 + TreeSitter + ANSI 框线 |
| **语法主题** | Shikiji 主题系统 | two-face 主题系统（syntect 兼容，32 个主题） | `CodeTheme`（monokai, github） |
| **流式输出** | React 状态更新 → diff → ANSI 补丁 | `StreamCore` 双区域 (stable + tail)，`MarkdownStreamCollector`，提交动画队列，表格暂缓 | `print()` + `fflush()` 逐 delta |

### 输入处理

| | Claude Code | Codex CLI | SwiftAgent |
|---|---|---|---|
| **Raw mode** | Node.js stdin raw mode | crossterm 事件流（定制 fork） | POSIX `termios` + `tcsetattr` |
| **键盘解析器** | 自定义: kitty protocol, SGR mouse, xterm modifyOtherKeys, 终端响应, bracketed paste | crossterm 事件流 + 自定义 `keymap.rs` (95K 行) | 自定义: CSI, SS3, kitty protocol, xterm modified, bracketed paste |
| **Mouse 支持** | SGR mouse, X10 mouse | SGR mouse (via crossterm) | 无 |
| **ESC 消歧** | 不需要 (Ink 事件系统) | crossterm 事件流处理 | 超时方案 (~50ms poll) |
| **Paste 检测** | Bracketed paste + 自定义 burst 逻辑 | Bracketed paste (via crossterm) | Bracketed paste + 50ms burst timer |

### 组件模型

| | Claude Code | Codex CLI | SwiftAgent |
|---|---|---|---|
| **组件系统** | React 函数组件 | ratatui `WidgetRef` trait + 自定义 `Renderable` trait，函数式组合 | 过程式函数 |
| **状态管理** | React hooks + Zustand stores | ratatui 有状态 widget + tokio channels + `AppEventSender` | 手动 + `CurrentToolTracker` (NSLock) |
| **Popup/dialog** | React 组件（fuzzy picker, select, dialog） | 自定义 ratatui widgets（resume_picker, pager_overlay, theme_picker） | `InlinePopup`（ANSI 框线） |
| **状态栏** | React `StatusLine` 组件 | 自定义 ratatui `StatusIndicatorWidget` + shimmer 动画 + 经过时间计时器 | `StatusLine`（ANSI reverse video） |
| **Spinner** | React `Spinner` 组件 | `StatusIndicatorWidget`: shimmer_text 动画、`Instant` 计时器、32ms 帧调度、`ReducedMotionIndicator` | 后台 Swift Task + ANSI 覆盖 |
| **Composer/Input** | React `Composer` 组件层级 | 自定义 ratatui widget + keymap 系统 (95K `keymap.rs` + 65K `keymap_setup.rs`)、`mention_codec`、`slash_command` | `LineEditor`（raw-mode 过程式） |

### 代码规模与依赖

| | Claude Code | Codex CLI | SwiftAgent |
|---|---|---|---|
| **TUI 代码库** | ~90 文件 (ink/) + ~150 组件 + ~80 hooks | ~297 个 `.rs` 文件在 `tui/src/`，110+ 顶层模块 | ~22 文件 (SwiftAgentCLI/) |
| **外部依赖** | react, react-reconciler, yoga (WASM), @shikiji, lodash, log-update | ratatui (定制 fork), crossterm (定制 fork), pulldown-cmark, syntect, two-face, tokio, + 60+ 内部 codex-* crates | 无（仅 `swift-argument-parser`） |
| **TUI 代码行数** | ~30,000+（估算） | ~187,000 行 Rust（`tui/src/`） | ~4,000 |
| **平台** | 跨平台 (Node.js) | 跨平台 (Rust + tokio) | macOS 15+ only |

### 优势与权衡

| 方面 | Claude Code | Codex CLI | SwiftAgent |
|------|-------------|-----------|------------|
| **视觉丰富度** | 高 — Flexbox 布局、平滑动画、鼠标交互、复杂对话框 | 高 — ratatui widget 系统、syntect 语法高亮、shimmer 动画、pager overlay、鼠标支持、主题选择器 | 中等 — ANSI 框线、spinner、popup、markdown。无 flex 布局、无鼠标 |
| **更新效率** | 优秀 — 单元格级 diff 仅写入变化字符。硬件滚动处理内容移动 | 优秀 — 自定义 `diff_buffers()` 逐单元格 diff + `ClearToEnd` 优化、`SynchronizedUpdate` 无闪烁、`scroll_region_up` | 基本 — 通过 `\r\033[K` 和光标定位实现整行覆盖 |
| **代码复杂度** | 非常高 — 自定义 React reconciler、Yoga WASM、双缓冲 screen、diff 优化器 | 非常高 — 定制终端后端 fork、自定义 diff 引擎、95K keymap 系统、双区域流式、297 个 Rust 源文件 | 低 — 直接 ANSI 字符串、无框架、无 diff 引擎 |
| **启动时间** | 慢 — WASM 实例化、React 树构建 | 快 — 原生 Rust 二进制、无 VM/JIT 开销 | 即时 — 无框架初始化 |
| **依赖风险** | 高 — fork 需维护、Yoga WASM 兼容性问题、React 版本锁定 | 中等 — 定制 ratatui/crossterm fork 需跟踪上游、60+ 内部 crate 依赖图 | 最小 — 仅 `swift-argument-parser` |
| **可调试性** | 复杂 — 需要 React devtools、reconciler 追踪 | 中等 — Rust 调试工具、ratatui buffer 检查、`--debug` 标志 | 简单 — `print()` 天然可调试、`--debug` 标志用于 API 日志 |
| **可扩展性** | 基于组件 — 组合 React 组件添加功能 | 基于 Widget — 实现 `WidgetRef`/`Renderable` trait，组合到布局中；清晰模块划分 | 基于函数 — 在过程式代码中添加渲染；扩展点文档清晰 |
| **SSH/tmux 兼容性** | 好 — ANSI 输出标准；鼠标需 SGR 支持 | 好 — ANSI 输出 via crossterm；鼠标需 SGR 支持 | 好 — 纯 ANSI、无鼠标、无高级协议 |

---
