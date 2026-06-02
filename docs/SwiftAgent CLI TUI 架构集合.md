SwiftAgent CLI TUI 架构

  整体分层

  ChatCommand.swift (Agent Loop + 渲染调度)
  ├── TerminalRenderer.swift     — ANSI 输出、Panel/Border/Spinner
  ├── ColorTheme.swift           — ANSI 颜色 + 主题系统
  ├── TerminalCapability.swift   — TTY 能力检测 (色深、宽高)
  ├── TerminalDisplayWidth.swift — CJK/emoji 宽度计算
  ├── MarkdownRenderer.swift     — Markdown → ANSI (含代码高亮)
  ├── LineEditor.swift           — 原始模式行编辑器 (Raw Mode)
  ├── InlinePopup.swift          — 内联弹出菜单 (slash commands)
  ├── DebugLogger.swift          — JSONL 调试日志
  └── TreeSitterSyntaxHighlighter (外部依赖，代码块语法高亮)

  核心组件详解

  1. TerminalCapability (TerminalCapability.swift:4)

  - 终端能力检测层：isTTY（是否交互终端）、supportsColor（通过 COLORTERM/TERM 环境变量检测）、columns/rows（通过 ioctl(TIOCGWINSZ) 获取，fallback 到 COLUMNS/LINES 环境变量）
  - 提供 scrubANSICodes 方法：非 TTY 环境自动剥离 ANSI 转义码

  2. ColorTheme (ColorTheme.swift:2)

  - ANSIColor 枚举：16 色 + 256 色索引
  - ANSIStyle：bold/dim/italic/underline/reverse
  - ColorTheme 结构体：primary、secondary、accent、error、warning、muted 等语义色，预置 .default、.monochrome、.accessible 三套主题
  - ansi() 全局函数：组合颜色+样式生成 ANSI 转义序列

  3. TerminalRenderer (TerminalRenderer.swift:6)

  - write() — 基础彩色输出
  - renderBanner() — 欢迎横幅（Unicode 箱框字符）
  - renderStatusLine() — 状态栏（反向视频 + token 统计）
  - renderDelta() — 流式增量文本处理（\r\n → \n 清洗）
  - renderPanel() — Rich 风格 Panel（╭── title ──╮ 边框 + 自动换行）
  - renderLeftBorder() — 左侧竖线边框（用于 AI 回复流式输出）
  - spinnerFrame() / renderThinkingLine() — 点阵动画（⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏）
  - drainTTYInput() — 清空 TTY 输入缓冲（生成结束后丢弃误触按键）
  - 光标控制：saveCursor/restoreCursor/cursorUp/cursorDown/clearScreen

  4. MarkdownRenderer (MarkdownRenderer.swift:7)

  - Markdown → ANSI 转换：标题、列表、代码块、表格、链接、粗体/斜体
  - render() 主入口，flushTableBuffer() 表格渲染
  - 代码块通过 TreeSitterSyntaxHighlighter 做语法高亮

  5. LineEditor (LineEditor.swift:36)

  - 原始模式（raw mode）行编辑器，支持：
    - 光标移动（左右、Home/End、词间跳转）
    - 行编辑（插入、删除、退格）
    - 历史记录（上下翻页）
    - Ctrl+C 取消、Ctrl+D EOF
    - Shift+Enter 软换行
    - 多行编辑 + 粘贴检测（bracketed paste）
    - Ghost text（灰色提示文本）
  - rawModeReadLine() 主循环：按键 → 编辑缓冲区 → redrawLine() ANSI 刷新
  - InlinePopup 集成（slash 命令补全弹窗）

  6. InlinePopup (InlinePopup.swift:44)

  - 内联弹窗 UI（类似 Claude Code 的 slash 命令菜单）
  - Unicode 箱框边框（╭─ query ─╮），带帮助文字列
  - render() 输出到 LineEditor 的 writeToStdout 闭包
  - 支持键盘导航（上下选择，Enter 确认，Ctrl+C 取消）

  7. ChatCommand — Agent Loop (ChatCommand.swift:164)

  - run() 方法：初始化 → 欢迎 → 主循环
  - SpinnerPauseFlag：控制 spinner 动画启停
  - CurrentToolTracker：跟踪当前工具调用用于状态显示

  数据流（一次典型的用户交互）

  用户输入 (LineEditor.readLine)
    → ChatCommand.run: 构建 conversationHistory
    → LLMClient.stream: SSE 事件流
    → TerminalRenderer.renderLeftBorder: 流式渲染 AI 回复
    → TerminalRenderer.renderThinkingLine: 思考动画
    → ToolExecutor.execute: 工具调用
    → MarkdownRenderer.render: 最终输出格式化
    → TerminalRenderer.renderStatusLine: Token 统计
    → 循环回到 LineEditor

  关键设计决策

  ┌─────────────┬───────────────────────────────────────────────────────┐
  │    决策     │                         实现                          │
  ├─────────────┼───────────────────────────────────────────────────────┤
  │ ANSI 转义码 │ 手动拼接字符串（无第三方 TUI 框架依赖）               │
  ├─────────────┼───────────────────────────────────────────────────────┤
  │ TTY 检测    │ isatty() + ioctl + 环境变量 fallback                  │
  ├─────────────┼───────────────────────────────────────────────────────┤
  │ 管道安全    │ scrubANSICodes 保证非 TTY 输出纯文本                  │
  ├─────────────┼───────────────────────────────────────────────────────┤
  │ 流式输出    │ renderLeftBorder 逐行追加，不做原地更新               │
  ├─────────────┼───────────────────────────────────────────────────────┤
  │ 编辑器      │ 自定义 raw mode 实现，非 readline/libedit             │
  ├─────────────┼───────────────────────────────────────────────────────┤
  │ 颜色系统    │ 语义化主题（primary/secondary/error），支持 mono 模式 │
  └─────────────┴───────────────────────────────────────────────────────┘


------


  TUI 架构总览

  ┌─────────────────────────────────────────────────────────┐
  │                    ChatCommand.run()                     │
  │                    (主循环 + 编排)                        │
  ├─────────────────────────────────────────────────────────┤
  │  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐ │
  │  │  LineEditor   │  │TerminalRenderer│ │  InlinePopup  │ │
  │  │  (原始输入)    │  │  (输出渲染)    │  │  (@/ 补全)   │ │
  │  └──────┬───────┘  └──────┬───────┘  └──────┬────────┘ │
  │         │                 │                  │          │
  │  ┌──────┴─────────────────┴──────────────────┴────────┐ │
  │  │              TerminalCapability                     │ │
  │  │         (TTY 检测 / 颜色支持 / 终端尺寸)             │ │
  │  └────────────────────────────────────────────────────┘ │
  │  ┌────────────┐  ┌──────────┐  ┌────────────────────┐  │
  │  │ ColorTheme  │  │ CodeTheme │  │ ANSIColor/ANIStyle │  │
  │  └────────────┘  └──────────┘  └────────────────────┘  │
  │  ┌────────────┐  ┌──────────────┐  ┌────────────────┐  │
  │  │ StatusLine  │  │StreamRenderer│  │  DebugLogger   │  │
  │  │ (底部状态)   │  │ (流事件格式化) │  │  (JSONL 调试)  │  │
  │  └────────────┘  └──────────────┘  └────────────────┘  │
  └─────────────────────────────────────────────────────────┘

  ---
  核心组件（按文件）

  1. ChatCommand.swift — 主 REPL 循环 (2000+ 行)

  这是 CLI 的入口和编排中心。当前是一个巨石文件，包含：

  - Agent 循环 (run():201): 无限 while 循环，调用 editor.readLine() → 处理输入 → 调用 LLM → 流式渲染响应
  - 流事件分发: textDelta / thinkingDelta 由 switch 处理，将文本定向到 TerminalRenderer.renderLeftBorder() 或行内 spinner
  - 43 个工具注册 (registerBuiltinTools)
  - 斜杠命令处理 (/exit, /clear, /model, /resume 等)
  - 原始输入处理 (readRawByte, readEscapeSeq) — 输入/粘贴时 ESC 打断 LLM 生成

  数据流: conversationHistory: [Message] 随每轮对话累积。每个新的用户消息会附加 assistant 消息 + tool use + tool results。

  ---
  2. TerminalRenderer.swift — 输出渲染器

  一个纯函数式的 struct（Sendable），包含 16 个渲染方法：

  ┌─────────────────────────────────┬────────────────────────────────────────────────┐
  │              方法               │                      用途                      │
  ├─────────────────────────────────┼────────────────────────────────────────────────┤
  │ renderBanner()                  │ ┌── 标题 ──┐ 风格的欢迎横幅                    │
  ├─────────────────────────────────┼────────────────────────────────────────────────┤
  │ renderLeftBorder()              │ AI 响应渲染为 │  前缀行                        │
  ├─────────────────────────────────┼────────────────────────────────────────────────┤
  │ renderPanel()                   │ 全边框面板（标题 + 换行内容），最大宽度 80 列  │
  ├─────────────────────────────────┼────────────────────────────────────────────────┤
  │ renderThinkingLine()            │ ⠋ Thinking... 带 braille spinner 帧            │
  ├─────────────────────────────────┼────────────────────────────────────────────────┤
  │ renderStatusLine()              │ 反显底部状态行：[Working...] Tokens: ↓X ↑Y     │
  ├─────────────────────────────────┼────────────────────────────────────────────────┤
  │ renderDelta()                   │ 流式增量去除 ANSI                              │
  ├─────────────────────────────────┼────────────────────────────────────────────────┤
  │ renderPermissionPrompt()        │ 权限/批准提示模板                              │
  ├─────────────────────────────────┼────────────────────────────────────────────────┤
  │ clearScreen() / cursorUp/Down() │ ANSI 光标控制                                  │
  ├─────────────────────────────────┼────────────────────────────────────────────────┤
  │ saveCursor() / restoreCursor()  │ DEC 私有模式光标保存                           │
  ├─────────────────────────────────┼────────────────────────────────────────────────┤
  │ spinnerFrame()                  │ 返回带颜色的 braille spinner 字符 (⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏) │
  ├─────────────────────────────────┼────────────────────────────────────────────────┤
  │ drainTTYInput()                 │ 在 LLM 生成期间刷新残留键盘输入                │
  └─────────────────────────────────┴────────────────────────────────────────────────┘

  ---
  3. TerminalCapability.swift — 终端能力检测

  检测并封装：
  - isTTY: stdin 和 stdout 是否都是 TTY
  - supportsColor: 检查 TERM / COLORTERM 环境变量
  - columns / rows: 来自 ioctl(TIOCGWINSZ)，回退到 COLUMNS 环境变量，最后使用 80x24
  - scrubANSICodes(): 非 TTY 模式下去除 ANSI 转义码
  - color(): 在支持颜色的终端中包装 ANSI 颜色代码

  ---
  4. LineEditor.swift — 原始模式输入编辑器（39 个方法）

  一个基于类的原始模式行编辑器：

  - readLine(): 主循环 — 进入原始模式，读取字节，构建输入缓冲区
  - 原始模式管理: enterRawMode() / restoreTerminal() — 设置/恢复 termios 属性
  - 粘贴处理: handlePaste() 检测并规范化粘贴内容，使用占位符避免在粘贴输入时触发 ESC 中断
  - 历史导航: 上下箭头浏览 history: [String]
  - 行重绘: redrawLine() 重新渲染当前缓冲区
  - 弹出补全: @ 和 / 触发 InlinePopup — 当检测到触发字符时 openPopup()
  - 控制序列: readEscapeSequence() 解码多字节 CSI 序列（光标移动、删除、Home/End 等）

  检测能力:
  - 括号粘贴模式 (bracketed paste \e[200~ ... \e[201~)
  - Shift 修饰键检测 (\e[1;2A 等)
  - UTF-8 解码
  - Ctrl+O 翻转展开/折叠

  ---
  5. InlinePopup.swift — 弹出补全（@ 文件 + / 斜杠）

  - refresh(): 从数据源重新加载匹配项
  - render(): 在光标上方绘制补全列表，使用 ANSI 定位
  - moveUp() / moveDown(): 选择导航
  - 支持数据源架构：FileDataSource（@-提及）和 CommandDataSource（/-斜杠命令）

  ---
  6. ColorTheme.swift — ANSI 颜色主题

  ColorTheme.default   → 蓝色 primary, 青色 secondary, 绿色成功, 黄色警告, 红色错误
  ---
  6. ColorTheme.swift — ANSI 颜色主题
  
  ColorTheme.default   → 蓝色 primary, 青色 secondary, 绿色成功, 黄色警告, 红色错误
  ColorTheme.monochrome → 全白色/灰色（--no-color 模式）
  
  类型：ANSIColor 枚举（black, red, green, yellow, blue, magenta, cyan, white, brightBlack...）+ ANIStyle（bold, dim, underline, blink, reverse）。
  
  ---
  7. StatusLine.swift — 底部状态行

  在流式传输时在终端底部渲染反显状态行：
  - update(): 调用 renderer.renderStatusLine()
  - clear(): 移除状态行
  
  ---
  8. StreamRenderer.swift (位于 SwiftAgentCore) — 流事件格式化
  
  将 StreamEvent 枚举值转换为终端可显示的字符串：
  - textDelta → 原样文本
  - thinkingDelta → "" (由 ContentBlockAccumulator 内联)
  - contentBlockStart(.thinking) → \n[Thinking...]\n
  - contentBlockStart(.toolUse) → \n→ Calling tool: {name}...\n
  - inputJSONDelta → "."
  - messageDelta → [Tokens: ↓X ↑Y] [Stop: reason]
  
  ---
  9. DebugLogger.swift — JSONL 调试日志
  
  当提供 --debug 时，将 API 请求/响应/流事件写入 ~/.swift-agent/logs/debug-YYYYMMDD-HHmmss.jsonl。掩盖 API key。
  
  --- 
  关键数据流
      
  用户按键 → LineEditor.readLine() → 输入字符串
      ↓ 
  ChatCommand.run() 处理输入
      ↓
  LLMClient.sendMessageStream() → SSE 事件流
      ↓ (每个事件)
  StreamRenderer.render() 格式化事件
      ↓
  TerminalRenderer 方法 (renderLeftBorder / renderThinkingLine)
      ↓
  stdout (ANSI 转义码用于定位/颜色)
  
  已知问题

  1. ChatCommand.swift 是巨石文件（~1700 行）— 包含 agent 循环、斜杠命令、工具注册、ESC 监控、所有 UI 逻辑。根据 [CLAUDE.md] 可以拆分。
  2. 渲染器是纯函数式的，但流状态分散在 ChatCommand.run() 中的局部变量之间 — 没有专用的 RenderingContext 结构体。
  3. 当提供 --no-color 时，TerminalCapability 和 ColorTheme.monochrome 会去除 ANSI — 但 renderLeftBorder 仍然输出 │ 前缀字符，在 plaintext 模式下可能需要注意。

  ------

  TUI 架构：SwiftAgent CLI
│ ─────────────────────
│ 
│ 概览
│ 
│ SwiftAgent 的一切都围绕一个终端实现。它没有使用 TermKit / ncurses / SwiftTerm，而是通过原始 ANSI 转义序列 +  termios  原始模式构建了自己的内联 TUI。所有代码都位于  Sources/SwiftAgentCLI/ （11 个文件，约 3600 行）。结果是一个功能齐全的编码代理 REPL，其结构与 Claude Code 的 Nanobot（Python）REPL 相匹配。
│ 
│ 组件图
│ 
│ ┌──────────────────────────────────────────────────────────────────────────┐
│ │                         ChatCommand.swift  (主 REPL 循环)                │
│ │                        /           |            \                        │
│ │                       /            |             \                       │
│ │            TerminalRenderer   LineEditor       MarkdownRenderer          │
│ │           (ANSI 渲染)     (原始模式输入)    (md→ANSI)                    │
│ │                 |                |                  |                    │
│ │          TerminalCapability   InlinePopup    TreeSitterSyntaxHighlighter │
│ │          (TTY 检测)         (弹出补全)                                   │
│ │                                   |                                      │
│ │                            PopupDataSource                               │
│ │                           (命令/文件/会话)                               │
│ └──────────────────────────────────────────────────────────────────────────┘
│ 
│ 架构分层
│ 
│ 1. 主循环 —  ChatCommand.swift （第 164 行，约 1500 行）
│ 
│ 这是整个应用程序。它是一个  AsyncParsableCommand （ArgumentParser），包含 REPL、内联代理循环和所有斜杠命令的分发。职责：
│ 
│ •  while true  REPL，使用  editor.readLine(prompt:)  进行输入
│ • 内联代理循环（最多 25 次迭代/轮次），包含 LLM 流式传输、工具输入 JSON 累积、截断恢复、ESC 取消
│ • 旋转器管理——  Task  每 100ms 渲染一帧旋转器，在  \r\e[K （回车 + 清除行）上绘制
│ • 可折叠的工具结果： emitCollapsedResults()  分组连续的可折叠工具（读取/grep/glob/ls/cat 等），将完整输出存储在  ToolResultCache  中，并仅显示单行摘要。 Ctrl+O  或  /expand  内联恢复完整输出
│ • 斜杠命令分发：23 个命令（ /help 、 /model 、 /compact 、 /review 、 /resume  等），通过  CommandRegistry  路由
│ • 会话持久化：加载/保存到  ~/.swift-agent/sessions/ 
│ • 首次轮次的系统提醒注入：延迟工具、MCP 指令、CLAUDE.md 内容
│ 
│ 2. ANSI 渲染 —  TerminalRenderer.swift （231 行）
│ 
│ 纯 ANSI 代码输出器。无抽象——直接写入原始转义序列。关键 API：
│ 
│ │             方法              │                  用途                   │
│ ├───────────────────────────────┼─────────────────────────────────────────┤
│ │ `renderBanner(version:)`      │ 带有 Unicode 框绘制的欢迎横幅           │
│ │ `renderPanel(title:content:)` │ 类似 Rich 的面板，带彩色边框 + 自动换行 │
│ │ `renderLeftBorder(content:)`  │ AI 响应显示——仅左侧 "│" 边框            │
│ │ `renderStatusLine(_:)`        │ 反向视频状态栏，含令牌 + 会话           │
│ │ `spinnerFrame(index:)`        │ Unicode Braille 旋转器："⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"    │
│ │ `renderThinkingLine(frame:)`  │ 带旋转器的 "⠋ Thinking..." 行           │
│ │ `drainTTYInput()`             │ 在 LLM 生成期间刷新杂散按键             │
│ │ `cursorUp/Down/Save/Restore`  │ 低级光标控制                            │
│ 
│ 3. 原始模式行编辑器 —  LineEditor.swift （1288 行）
│ 
│ 这是最复杂的组件——一个完全自定义的行编辑器，使用  termios  原始模式 + bracketed paste + Kitty 键盘协议。无 readline/libedit 依赖。
│ 
│ 功能：
│ • 历史导航：↑/↓ 循环浏览 500 条历史记录。多行缓冲区让 ↑/↓ 首先在行之间移动，在边界处退回到历史。具有 bash 风格的缓冲区隐藏/恢复功能
│ • 多行支持：Shift+Enter（通过  CGEventSource.flagsState  的 HID 层检测）和 Alt+Enter 插入文字换行
│ • 光标移动：←/→、Ctrl+A/E、Alt+←/→（基于单词边界的字符边界）、Home/End
│ • 编辑命令：Backspace、Ctrl+W（删除单词）、Alt+Backspace（仅删除字符数字单词）、Ctrl+U（清除行）、Ctrl+K（删除到行尾）
│ • 粘贴处理：Bracketed paste（ESC[200~...ESC[201~）+ 非 bracketed 的回退（50ms 输入检测窗口）。多行粘贴渲染摘要占位符以保持行清晰
│ • 内联弹出集成：当游标在单词边界时， @  和  /  会打开模糊搜索弹出窗口。在弹出窗口打开时输入可细化搜索，↓/↑ 导航，Enter/Tab 提交选择，Esc 取消
│ • 转义序列解析器：处理 CSI（ ESC[ ）、SS3（ ESC O ）、Alt/Option 修饰符、Kitty 协议（ CSI <key>;<mods>u ）、xterm 修饰符键（ CSI 1;<mods> <letter> ）
│ • UTF-8 解码器：内联的多字节 UTF-8 解码，带有超时保护的继续字节
│ • ESC 拦截： interceptEscape()  — 在原始模式下独立监控 stdin，仅在检测到裸 ESC（50ms 超时，无跟随字节）时返回 true。用于 LLM 生成期间的取消
│ 
│ 4. 内联弹出 —  InlinePopup.swift （331 行）
│ 
│ 一个在输入行下方渲染的原始 ANSI 弹出菜单。组件：
│ 
│ •  InlinePopup  — 核心弹出引擎。管理搜索查询、项目列表、选择索引、滚动偏移。将 Unicode 框绘制渲染为一个调用  write  的块：
│   • 顶部边框： ╭ <query> ───────────╮ 
│   • 项目： │ ▸ 选择项  <帮助文本> │ （选中项使用反向视频 + 加粗黄色高亮）
│   • 底部边框： ╰────────────────────╯ 
│   • 滚动指示器： │ ↑ 3 more │  /  │ ↓ 5 more │ 
│ •  PopupConfig  — 尺寸：最大高度=12，最大宽度=66
│ •  PopupState  /  EditorMode  — 跟踪弹出状态与正常模式
│ 
│ 5. 弹出数据源 —  PopupDataSource.swift （501 行）
│ 
│  PopupDataSource  协议提供  search(query:) -> [PopupItem] 。四个实现：
│ 
│ │        数据源        │ 触发方式 │                                                 数据                                                 │
│ ├──────────────────────┼──────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ │ `CommandDataSource`  │ `/`      │ 23+ 个内置斜杠命令 + 技能。委托给 `SessionDataSource` 用于 `/resume`                                 │
│ │ `FileDataSource`     │ `@`      │ 通过 `git ls-files` 的 `FileSearchIndex`（搜索时零磁盘 I/O）。支持目录作用域、隐藏文件切换、VCS 排除 │
│ │ `SessionDataSource`  │ nested   │ 保存的会话（`~/.swift-agent/sessions/`），带格式化的日期/消息计数                                    │
│ │ `ArgumentDataSource` │ 子菜单   │ 简单选项列表（例如模型名称、权限模式）                                                               │
│ 
│  PopupItem  具有  argumentHint （提交后显示的幽灵文本）、 subOptions （打开第二个弹出窗口获取参数值）、 subDataSource （用于动态子菜单，例如  /resume  → 会话列表）和  submitOnSelect （跳过第二次 Enter 确认）。
│ 
│ 6. Markdown 到 ANSI —  MarkdownRenderer.swift 
│ 
│ 将 AI 响应中的 markdown 转换为 ANSI 样式的文本。处理：围栏代码块（通过 TreeSitter 语法高亮，Monokai 主题）、标题（粗体 + 颜色）、内联代码（反向视频）、表格（Unicode 框绘制）、粗体/斜体/删除线、无序/有序列表、引用块、水平线。自动检测代码块进行回溯修复。
│ 
│ 7. 支持基础设施
│ 
│ •  TerminalCapability （62 行）：检测 isTTY、颜色支持（ COLORTERM / TERM  环境变量）、通过  TIOCGWINSZ  ioctl 获取终端大小。在非 TTY/管道模式下剥离 ANSI 代码。
│ •  TerminalDisplayWidth （105 行）：Unicode 感知的终端列计算。正确处理 zero-width 字符（组合标记、变体选择器、零宽度连接器）、wide 字符（CJK、表情符号）、ASCII。用于弹出对齐和光标定位。
│ •  ColorTheme （115 行）：默认主题（蓝/青/绿/黄/红 + 加粗）和单色（ --no-color ）。支持 3/4 位、8 位和 true color（24 位 RGB）。用于  ansi()  便捷函数。
│ •  CollapseDetector  +  CollapsedSummaryFormatter  +  ToolResultCache ：检测可折叠工具（Read、Glob、Grep、类似搜索的 Bash 命令），将连续的可折叠工具分组，以概述形式发出单行摘要，缓存完整输出以供  /expand  或  Ctrl+O  检索。
│ •  DebugLogger （198 行）：将 API 交互写入  ~/.swift-agent/logs/debug-YYYYMMDD-HHmmss.jsonl ，使用 JSONL 格式。掩盖请求头中的 API 密钥。线程安全的写入队列。
│ •  CollapsedSummaryFormatter ：将折叠的工具结果组格式化为简洁的摘要行。
│ 
│ 数据流：一轮交互
│ 
│ ┌─────────────────────────────────────────────────────────────────────────────┐
│ │ 1. editor.readLine(prompt: "You: ")     ← LineEditor 原始模式               │
│ │    ↓ 用户输入 "fix the bug"                                                 │
│ │ 2. 添加到 conversationHistory                                               │
│ │ 3. 旋转器 Task 启动 (100ms 帧)                                              │
│ │ 4. client.send() → SSE 流                       ← LLMClient                 │
│ │    ↓ textDelta / thinkingDelta / inputJSONDelta  ← LLMStreamParser          │
│ │ 5. 手动累积工具输入 JSON                                                    │
│ │ 6. 在 contentBlockStop 解析 tool_use 块                                     │
│ │ 7. ChatToolExecutionScheduler.execute()      ← 带并发的工具执行器           │
│ │ 8. 对于 SendUserMessage：显示左侧边框文本         ← TerminalRenderer        │
│ │ 9. 对于可折叠工具：emitCollapsedResults()         ← CollapseDetector + 缓存 │
│ │ 10. 工具结果 → 带 toolResult 块的用户消息          ← 反馈给 LLM             │
│ │ 11. 重复直到模型返回纯文本或无工具调用的 end_turn                           │
│ │ 12. 旋转器 Task 取消                                                        │
│ │ 13. MarkdownRenderer.render(responseText)    ← 带语法的 ANSI                │
│ │ 14. 回到步骤 1                                                              │
│ │ 15. 在退出时：sessionStore.save(conversationHistory)                        │
│ └─────────────────────────────────────────────────────────────────────────────┘
│ 
│ 关键架构决策
│ 
│ • 无第三方 TUI 框架。一切都在 termios + poll() +  Darwin.write(STDOUT_FILENO)  之上构建。这是一个刻意的选择，以匹配 Claude Code 的方法。
│ •  writeToStdout  绕过 Foundation 的  print 。所有 ANSI 输出直接使用  Darwin.write ，避免不必要的缓冲和对  print  的 Unicode 处理。
│ • Bracketed paste 协议的本地实现。无需 ncurses；终端通过  ESC[2004h  进入 bracketed paste 模式。
│ • 仅原始模式键盘。转义序列通过超时保护的字节读取进行解析——没有 termios 标准模式或 readline。这使得历史、多行和弹出集成成为可能。
│ • 多行感知的光标定位。 TerminalDisplayWidth  处理 Unicode 宽度； LineEditor.redrawLine  计算视觉行数以正确重新定位游标，即使在多行输入和弹出叠加层中。
│ 
│ 当前差距（与 Claude Code 比较）
│ 
│ 1. 无终端能力协商：没有 terminfo、terminfo 或 CSI u/DA 查询。假设支持 256 色 + UTF-8。没有回退到较差的终端。
│ 2. 弹出窗口仅 @ 和 / ：CC 还在错误行（Grep/Read 结果）、命令别名、斜杠命令参数建议等旁边显示内联提示/诊断。SwiftAgent 目前仅触发单词边界上的  /  和  @ 。
│ 3. Markdown 渲染器不流式传输：它等待完整响应。CC 在块到达时流式渲染 markdown。
│ 4. 无想法/工具调用的并行流式传输：CC 在工具输入仍在流式传输时显示文本增量。SwiftAgent 在文本/想法的 spinner <-> delta 之间切换。
│ 5. 无与行编辑器分离的独立计划模式呈现器。
│ 6. 无线程安全的终端重绘： writeToStdout  跨并发 Task 共享，没有互斥锁。如果两个 Task 同时写入，可能会交错 ANSI 序列。

------

│ SwiftAgent CLI TUI 架构
│ ─────────────────────
│ 
│ 分层总览
│ 
│ ┌───────────────────────────────────────────────────────────────────────┐
│ │ SwiftAgentCLI (用户界面层)                                            │
│ │ ├── ChatCommand           ← REPL 主循环, 编排所有 TUI 组件            │
│ │ ├── TerminalRenderer      ← ANSI 渲染引擎 (banner/status/panel/delta) │
│ │ ├── LineEditor            ← 原始模式行编辑器 (历史/补全/多行)         │
│ │ │   └── InlinePopup       ← 内联弹出补全 (@文件 / /命令)              │
│ │ ├── MarkdownRenderer      ← Markdown → ANSI 转换                      │
│ │ ├── TerminalCapability    ← 终端能力检测 (TTY/颜色/尺寸)              │
│ │ ├── TerminalDisplayWidth  ← Unicode 字符宽度计算 (CJK/Emoji)          │
│ │ ├── ColorTheme / ANSIColor / ANIStyle  ← 颜色主题系统                 │
│ │ └── DebugLogger           ← JSONL 调试日志                            │
│ └───────────────────────────────────────────────────────────────────────┘
│ 
│ 核心组件职责
│ 
│ 1.  ChatCommand  ( Sources/SwiftAgentCLI/ChatCommand.swift:201 ) — 主循环编排器
│ 
│ • 初始化所有 TUI 组件:  TerminalRenderer ,  LineEditor ,  MarkdownRenderer ,  InlinePopup 
│ • REPL 循环: 读取输入 → 处理斜杠命令 → 发给 LLM → 流式渲染响应
│ • 维护  conversationHistory: [Message]  跨轮次累积
│ • 最大 25 次工具调用迭代, 自动完成检测
│ • 管理辅助状态:  ExpandState  (Ctrl+O 折叠/展开),  SharedModel  (运行时模型切换),  ToolResultCache 
│ 
│ 2.  TerminalRenderer  ( Sources/SwiftAgentCLI/TerminalRenderer.swift:6 ) — ANSI 渲染引擎
│ 
│ •  write()  — 带颜色/样式的终端打印, 非 TTY 时回退为纯文本
│ •  renderBanner()  — 欢迎横幅 (Unicode 边框 + 版本号)
│ •  renderStatusLine()  — 倒视频率状态行 (Working... / Tokens / 标题)
│ •  renderDelta()  — 流式增量渲染, 清理  \r\n 
│ •  renderPermissionPrompt()  — 权限提示
│ • 面板渲染:  renderPanel()  等 Nanobot 风格的 Rich Panel 等价物
│ • 光标控制:  cursorUp/Down ,  saveCursor/restoreCursor ,  clearScreen 
│ 
│ 3.  LineEditor  ( Sources/SwiftAgentCLI/LineEditor.swift ) — 原始模式行编辑器
│ 
│ •  rawModeReadLine()  — 核心原始模式输入循环, 逐字节处理
│ • 键盘支持: 方向键, Home/End, Ctrl+A/E, Alt+←/→, Ctrl+K/U/W, Delete/Backspace
│ • 多行编辑: 内嵌换行, 自动重绘
│ • 历史记录: 上下箭头浏览, 持久化
│ • Tab 补全: 集成  InlinePopup  数据源
│ • Ghost text (建议预填)
│ • 粘贴检测与去抖
│ •  TerminalDisplayWidth  用于计算含 CJK/Emoji 的 Unicode 字符宽度
│ 
│ 4.  InlinePopup  ( Sources/SwiftAgentCLI/InlinePopup.swift:44 ) — 内联弹出补全
│ 
│ • 两种触发模式:  /  (斜杠命令) 和  @  (文件引用)
│ • 数据源:  CommandDataSource  (内置命令+技能),  FileDataSource  (git ls-files 索引)
│ • 渲染: Unicode 边框 ( ╭╮╰╯ ), 高亮匹配, 帮助文本列, 滚动
│ • 键盘导航: 上下选择, Enter 确认, Escape 取消
│ 
│ 5.  MarkdownRenderer  ( Sources/SwiftAgentCLI/MarkdownRenderer.swift:7 ) — Markdown → ANSI
│ 
│ • 解析标题 ( # – ###### ), 粗体/斜体, 内联代码, 代码块, 链接, 列表, 引用块
│ • 语法高亮: 集成  TreeSitterSyntaxHighlighter  +  CodeTheme 
│ • 自动检测未标记的代码块 ( classifyBlock  /  codeKeywordDensity )
│ • 代码块渲染: 边框 + 语言标签 + 彩色语法
│ 
│ 6.  TerminalCapability  ( Sources/SwiftAgentCLI/TerminalCapability.swift:4 ) — 终端能力
│ 
│ •  isTTY  — 检查 stdout 是否为终端
│ •  detectColorSupport()  — 通过  COLORTERM  /  TERM  环境变量
│ •  detectSize()  — 通过  TIOCGWINSZ  ioctl 获取行列数
│ •  scrubANSICodes()  — 非 TTY 输出时剥离 ANSI 转义序列
│ 
│ 7.  ColorTheme  /  ANSIColor  /  ANIStyle  ( Sources/SwiftAgentCLI/ColorTheme.swift )
│ 
│ • 两个预设主题:  .default  (蓝色主色) 和  .monochrome  ( --no-color )
│ • 支持 16 色 ANSI + 24-bit true color
│ •  ansi()  便捷函数: 给文本包裹颜色+样式前缀和重置后缀
│ 
│ 流式渲染管道
│ 
│ ┌──────────────────────────────────────────────────────────┐
│ │ LLM SSE 事件流                                           │
│ │   → StreamRenderer.render(event:)   (Core 层, 事件→文本) │
│ │   → TerminalRenderer.renderDelta()  (CLI 层, ANSI 清理)  │
│ │   → print() / emitBlock()           (终端输出)           │
│ └──────────────────────────────────────────────────────────┘
│ 
│ •  textDelta  — 直接打印
│ •  thinkingDelta  — 暗色 (dimmed) 输出
│ •  inputJSONDelta  — 显示  .  进度点
│ •  toolUse  开始 —  → Calling tool: <name>... 
│ •  messageDelta  — Token 统计
│ 
│ 组件交互流程
│ 
│ ┌──────────────────────────────────────────────────────────────────────────┐
│ │ ChatCommand.run()                                                        │
│ │   ├─ TerminalRenderer.renderBanner()    → 横幅                           │
│ │   ├─ LineEditor.readLine()              → 用户输入 (含 InlinePopup 补全) │
│ │   ├─ 斜杠命令处理 (/clear, /model, ...)                                  │
│ │   ├─ LLMClient.stream()                 → SSE 流                         │
│ │   ├─ StreamRenderer + MarkdownRenderer  → ANSI 格式化                    │
│ │   ├─ TerminalRenderer.renderStatusLine() → 状态行                        │
│ │   └─ emitBlock()                        → 最终输出                       │
│ └──────────────────────────────────────────────────────────────────────────┘
│ 
│ 关键文件清单
│ 
│ │             文件             │ 行数  │               职责                │
│ ├──────────────────────────────┼───────┼───────────────────────────────────┤
│ │ `ChatCommand.swift`          │ ~1200 │ REPL 主循环 + 工具注册 + 斜杠命令 │
│ │ `TerminalRenderer.swift`     │ ~250  │ ANSI 渲染 + 面板 + 光标控制       │
│ │ `LineEditor.swift`           │ ~1100 │ 原始模式编辑器 + 历史             │
│ │ `InlinePopup.swift`          │ ~330  │ 内联弹出 UI                       │
│ │ `MarkdownRenderer.swift`     │ ~780  │ Markdown→ANSI                     │
│ │ `TerminalCapability.swift`   │ ~70   │ TTY/颜色/尺寸检测                 │
│ │ `TerminalDisplayWidth.swift` │ ~105  │ Unicode 宽度计算                  │
│ │ `ColorTheme.swift`           │ ~115  │ 颜色主题 + ANSI 转义码            │


------

│ SwiftAgent CLI TUI 架构
│ ─────────────────────
│ 
│ 分层结构
│ 
│ ┌──────────────────────────────────────────────────────────┐
│ │ ┌─────────────────────────────────────────────────────┐  │
│ │ │                   ChatCommand                       │  │
│ │ │  (AsyncParsableCommand — 入口 & 协调层)              │ │
│ │ │  Sources/SwiftAgentCLI/ChatCommand.swift            │  │
│ │ └──────┬──────────┬──────────┬───────────┬────────────┘  │
│ │        │          │          │           │               │
│ │        ▼          ▼          ▼           ▼               │
│ │ ┌──────────┐ ┌────────┐ ┌─────────┐ ┌──────────────┐     │
│ │ │ Terminal │ │ Line   │ │ Markdown│ │ TokenANSI    │     │
│ │ │ Renderer │ │ Editor │ │ Renderer│ │ Renderer     │     │
│ │ └────┬─────┘ └───┬────┘ └────┬────┘ └──────┬───────┘     │
│ │      │            │           │             │            │
│ │      ▼            ▼           ▼             ▼            │
│ │ ┌──────────┐ ┌─────────────────────────────┐             │
│ │ │ Terminal │ │         ColorTheme          │             │
│ │ │Capability│ │  (primary/secondary/success/ │            │
│ │ │          │ │   warning/error/dim/bold)   │             │
│ │ │ isTTY    │ └─────────────────────────────┘             │
│ │ │ columns  │                                             │
│ │ │ rows     │                                             │
│ │ │ color()  │                                             │
│ │ │ scrub()  │                                             │
│ │ └──────────┘                                             │
│ └──────────────────────────────────────────────────────────┘
│ 
│ 六大组件职责
│ 
│ │          组件          │             文件             │                                  职责                                   │
│ ├────────────────────────┼──────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
│ │ **ChatCommand**        │ `ChatCommand.swift:164`      │ 入口点，初始化所有渲染器、编辑器、LLM client、工具注册，运行 agent loop │
│ │ **TerminalRenderer**   │ `TerminalRenderer.swift:6`   │ ANSI 输出：banner、status line、delta 流、权限提示、面板、光标控制      │
│ │ **LineEditor**         │ `LineEditor.swift:36`        │ Raw mode 行编辑器：历史导航、补全 popup、多行粘贴、词边界移动           │
│ │ **MarkdownRenderer**   │ `MarkdownRenderer.swift:7`   │ 流式 Markdown→ANSI 渲染：表格缓冲、粗体/斜体/代码块                     │
│ │ **TerminalCapability** │ `TerminalCapability.swift:4` │ 终端能力探测：TTY 检测、`TIOCGWINSZ` 尺寸、颜色支持、ANSI scrub         │
│ │ **ColorTheme**         │ `ColorTheme.swift:2`         │ 颜色语义映射：`.default`（蓝/青/绿/黄/红）和 `.monochrome`              │
│ 
│ 初始化流程（`ChatCommand.run()`）
│ 
│ 1. 保存 termios 原始状态 — 防止 LineEditor 进入 raw mode 后丢失 cooked mode 终端配置
│ 2. 创建 TerminalCapability — 检测 TTY、颜色支持、终端尺寸
│ 3. 选择 ColorTheme —  --no-color  则用  .monochrome ，否则  .default 
│ 4. 创建 TerminalRenderer — 注入 capability + theme
│ 5. 创建 MarkdownRenderer — 注入 capability + theme + TreeSitterSyntaxHighlighter + CodeTheme
│ 6. 渲染 banner —  renderer.renderBanner(version:) ，输出 ANSI 框
│ 7. 创建 LineEditor — raw mode 输入循环
│ 8. 进入 agent loop — 流式处理、工具执行、状态行更新
│ 
│ 关键渲染方法
│ 
│ •  renderBanner  — 输出 Unicode 框  ┌───┐  风格的欢迎横幅
│ •  renderStatusLine  — 反向视频  \e[7m  状态栏：Working 状态 + token 计数 + 会话标题，填满终端宽度
│ •  renderDelta  — 流式增量渲染：清理  \r\n ，scrub ANSI
│ •  renderPermissionPrompt  — 工具权限确认提示
│ •  renderPanel  — Nanobot 风格 Rich Panel： ╭── title ──╮  边框 + 自动换行 + 颜色
│ 
│ LineEditor — 完整 Raw Mode 编辑器
│ 
│  rawModeReadLine （ :181 ）提供：
│ 
│ • 输入处理: Ctrl+C（取消/退出 popup）、Ctrl+D（EOF）、Ctrl+U（清除行）、Ctrl+W（删除词）
│ • Escape 序列: 上下左右箭头、Alt+左右（词跳转）、Home/End、Alt+Backspace（删除词）
│ • 历史导航:  navigateHistory(direction:)  支持上下箭头
│ • Popup 补全: 触发后  openPopup ，Tab 选中/Enter 提交，支持  submitOnSelect  自动提交
│ • 粘贴处理: 括号粘贴模式 + poll fallback，多行粘贴摘要压缩
│ • Shift+Enter: 通过 HID 键盘状态检测硬件修饰键，插入换行
│ • 重新绘制:  redrawLine  用  \e[J  清除 + 重绘，支持多行 buffer
│ • 回退:  fallbackReadLine  — 当不是 TTY 时降级为  readLine() 
│ 
│ 数据流
│ 
│ ┌────────────────────────────────────────────────────────────────────┐
│ │ LLM API → SSE 流                                                   │
│ │   ↓                                                                │
│ │ StreamRenderer.render(event:) → 转换为 StreamEvent → 文本/工具调用 │
│ │   ↓                                                                │
│ │ ChatCommand.run() → 逐 delta 调用 TerminalRenderer.renderDelta()   │
│ │   ↓                                                                │
│ │ MarkdownRenderer.render() → ANSI 化 markdown 块                    │
│ │   ↓                                                                │
│ │ TerminalRenderer.write() / renderStatusLine() → stdout             │
│ └────────────────────────────────────────────────────────────────────┘
│ 
│ TUI 设计原则
│ 
│ 1. TTY 感知 — 所有 ANSI 代码都经过  capability.isTTY  门控，pipe 模式下输出纯文本
│ 2. scrub 防护 —  scrubANSICodes  在非 TTY 时剥离控制序列
│ 3. 尺寸自适应 —  detectSize  通过  TIOCGWINSZ  ioctl +  $COLUMNS/$LINES  环境变量 fallback
│ 4. 双主题 — default（彩色）/ monochrome（ --no-color ），所有通过  ColorTheme  注入
│ 5. 渲染器无状态 —  TerminalRenderer  是  Sendable  值类型，只依赖注入的  TerminalCapability 

------

TUI 架构总览
│ ────────
│ 
│ SwiftAgent 的 TUI 由 14 个 CLI 文件 层叠构成，位于  Sources/SwiftAgentCLI/ ，其核心渲染组件位于  Sources/SwiftAgentCore/Agent/StreamRenderer.swift 。
│ 
│ 分层图示
│ 
│ ┌──────────────────────────────────────────────────────┐
│ │ ┌─────────────────────────────────────────────────┐  │
│ │ │  ChatCommand (Agent Loop / REPL)                │  │
│ │ │  - 流式处理，会话管理，斜杠命令，工具注册  │       │
│ │ └──────────┬──────────────┬───────────────────────┘  │
│ │            │              │                          │
│ │      ┌─────▼─────┐  ┌─────▼──────────────┐           │
│ │      │ Terminal   │  │ MarkdownRenderer   │          │
│ │      │ Renderer   │  │ · 标题 · 表格     │           │
│ │      │ · 横幅     │  │ · 代码块 · 引用   │           │
│ │      │ · 面板     │  │ · 内联格式        │           │
│ │      │ · 左边框   │  └────────┬──────────┘           │
│ │      │ · 增量     │           │                      │
│ │      └─────┬──────┘    ┌──────▼───────────┐          │
│ │            │           │ TokenANSIRenderer │         │
│ │      ┌─────▼──────┐    │ (tree-sitter →    │         │
│ │      │ Terminal   │    │  终端 ANSI)       │         │
│ │      │ Capability │    └──────────────────┘          │
│ │      │ · TTY 检测 │                                  │
│ │      │ · 尺寸     │                                  │
│ │      │ · 颜色     │                                  │
│ │      └─────┬──────┘                                  │
│ │            │                                         │
│ │      ┌─────▼──────┐    ┌──────────────────┐          │
│ │      │ ColorTheme │    │ CodeTheme        │          │
│ │      │ · ANSIColor │   │ · 捕获名称映射   │          │
│ │      │ · ANIStyle │    │   到 ANSI 颜色    │         │
│ │      │ · ansi()   │    └──────────────────┘          │
│ │      └────────────┘                                  │
│ │                                                      │
│ │ ┌─────────────────────────────────────────────────┐  │
│ │ │  LineEditor (原始模式终端输入)                   │ │
│ │ │  · 历史 · 粘贴 · 转义序列 · 词边界              │  │
│ │ │  ┌──────────────────┐  ┌──────────────────────┐ │  │
│ │ │  │ InlinePopup      │  │ PopupDataSource      │ │  │
│ │ │  │ · / 弹出层       │  │ · CommandDataSource   │ │ │
│ │ │  │ · @ 弹出层       │  │ · FileDataSource      │ │ │
│ │ │  │ · ANSI 渲染      │  │ · SessionDataSource   │ │ │
│ │ │  └──────────────────┘  └──────────────────────┘ │  │
│ │ └─────────────────────────────────────────────────┘  │
│ │                                                      │
│ │ ┌──────────────────┐  ┌──────────────────────────┐   │
│ │ │ StatusLine       │  │ DebugLogger              │   │
│ │ │ · 工作状态        │  │ · JSONL 请求/响应日志    │  │
│ │ │ · 令牌使用量      │  │ · 流事件日志             │  │
│ │ └──────────────────┘  └──────────────────────────┘   │
│ └──────────────────────────────────────────────────────┘
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 核心渲染管道
│ 
│  TerminalCapability  ( TerminalCapability.swift:4 )
│ 检测 TTY 状态、颜色支持（无/16/256/真彩色）、终端尺寸（列/行）。是管道中最低层级——是所有渲染器的输入。
│ 
│  ColorTheme  +  ANSI  辅助函数 ( ColorTheme.swift )
│ •  ANSIColor （19 个成员，含真彩色支持）生成前景/背景转义码
│ •  ANIStyle （粗体、灰显、斜体、下划线、闪烁）——每条枚举值持有一个转义码
│ •  ansi(_:color:style:)  包装字符串，格式为  \e[...m + text + \e[0m 
│ •  default （蓝色系）和  monochrome （白色系）两个预置主题
│ 
│  CodeTheme  ( CodeTheme.swift:5 )
│ 将 tree-sitter 捕获名称（ keyword 、 string 、 function  等）映射到  ANSIColor 。单个主题：monokai。
│ 
│  TerminalRenderer  ( TerminalRenderer.swift:6 ) — 4 个输出方法：
│ │                   方法                    │              用途              │          特性          │
│ ├───────────────────────────────────────────┼────────────────────────────────┼────────────────────────┤
│ │ `write(_:color:style:)`                   │ 单行打印                       │ 如果非 TTY，跳过 ANSI  │
│ │ `renderBanner(version:)`                  │ 欢迎横幅                       │ 盒装 `╭──...──╮` 布局  │
│ │ `renderStatusLine(_:)`                    │ 令牌使用量/工作状态            │ 应用感知快照           │
│ │ `renderDelta(_:current:)`                 │ 内联流式文本                   │ 清理 CRLF              │
│ │ `renderPanel(title:content:borderColor:)` │ 带顶部/底部/两侧边框的盒装面板 │ 智能换行，最大 80 列宽 │
│ │ `renderLeftBorder(content:color:)`        │ AI 响应用简单 `│` 左边框       │ 比完整面板更简洁       │
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ Markdown 渲染
│ 
│  MarkdownRenderer  ( MarkdownRenderer.swift:7 ) — 整体流程为  render(_: String) → ANSI 格式文本 ：
│ 
│ 1. 自动检测：通过启发式算法（关键词密度、缩进模式、行分类）检测无围栏标记的代码块
│ 2. 块级解析：标题、== 和 -- 风格标题、围栏代码块（含嵌套深度跟踪）、GFM 表格、块引用、无序/有序列表、水平分割线
│ 3. 内联格式化：粗体、斜体、行内代码、链接、灰显样式
│ 4. 代码块渲染：委托给 tree-sitter 高亮器 →  TokenANSIRenderer  → 使用  CodeTheme  进行 ANSI 着色
│ 
│  TokenANSIRenderer  ( TokenANSIRenderer.swift:5 ) — 输出管道的关键部分：
│ • 按行迭代 token，维护 ANSI 样式栈
│ • 每行以代码装订线前缀（ │  ）+ 样式组合 + 重置结尾
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 输入层
│ 
│  LineEditor  ( LineEditor.swift:36 ) — 39 个成员，实现完整原始模式 readline：
│ • 原始模式终端设置（ termios  +信号处理）、退出时恢复
│ • 使用硬连接超时的转义序列解析器（ readByteWithTimeout ）
│ • 括号粘贴检测与处理（ readBracketedPasteContent ）——超过 1000 字符时截断并摘要显示，防止卡顿
│ • 历史导航（ navigateHistory ），含词边界检测（ wordBoundaryBefore / After ）
│ • 基于渲染计数的光标定位，处理多字节/宽字符
│ •  / （斜杠命令）和  @ （文件提及）的内联弹出层集成
│ • 回退模式：非 TTY 环境下调用 Swift 原生  readLine() 
│ 
│  InlinePopup  ( InlinePopup.swift:44 ) — 在输入行上方渲染 ANSI 选择器：
│ • 可滚动的匹配列表（ moveUp / moveDown ）
│ • 根据弹出层类型（命令 vs 文件）显示不同的表头
│ • 使用自己的  ANSI  枚举管理弹出层 UI 的颜色
│ 
│  PopupDataSource  ( PopupDataSource.swift ) — 协议 + 三个实现：
│ •  CommandDataSource ：斜杠命令 + 技能，含参数提示和子选项
│ •  FileDataSource ：使用  FileSearchIndex  匹配路径（基于 git ls-files 构建一次，后续为内存查询）
│ •  SessionDataSource ：用于  /resume  的已保存会话
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 流式处理与代理循环
│ 
│  ChatCommand.run()  ( ChatCommand.swift:201 ) — 主要 REPL：
│ 1. 捕获原始 cook 模式 termios（用于  promptUserForQuestions ），初始化 LineEditor 的原始模式
│ 2. 初始化整个渲染栈： TerminalCapability  →  ColorTheme  →  TerminalRenderer  →  MarkdownRenderer 
│ 3. 启动带有工具注册的  SubAgentManager 、MCP 引导
│ 4. 事件循环：输入 → 系统提示构建 → LLM 流式处理 → 工具执行 → 响应渲染 → 重复
│ 5. 流式事件处理程序积累文本增量、思考增量、工具输入 JSON，组装最终的助手消息
│ 
│  StreamRenderer （核心层， StreamRenderer.swift:5 ）
│ 将原始  StreamEvent  枚举值映射为终端安全的字符串：
│ •  textDelta  → 内联文本
│ •  thinkingDelta  /  signatureDelta  → 空字符串（在其他地方积累）
│ •  contentBlockStart(.toolUse)  →  → Calling tool: X... 
│ •  inputJSONDelta  →  . （点指示器）
│ •  messageDelta  → 令牌使用量 + 停止原因
│ 
│  StatusLine  ( StatusLine.swift:5 ) — 底部状态行，显示：
│ •  [Working...]  旋转动画（处理中时）
│ • 令牌使用量、持续时间
│ 
│  DebugLogger  ( DebugLogger.swift:7 ) — 带  --debug  时启用：
│ • 将 JSONL 写入  ~/.swift-agent/logs/debug-*.jsonl 
│ • 记录请求体、响应状态、原始 SSE 事件、错误
│ • 在日志中屏蔽 API 密钥
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 辅助组件
│ 
│ │             文件             │                 用途                  │
│ ├──────────────────────────────┼───────────────────────────────────────┤
│ │ `TerminalDisplayWidth.swift` │ CJK 字符宽度处理                      │
│ │ `FuzzyMatcher.swift`         │ 弹出层补全的模糊匹配                  │
│ │ `FileSearchIndex.swift`      │ @-mention 的预建文件索引              │
│ │ `CollapseDetector.swift`     │ 检测何时折叠工具结果                  │
│ │ `ToolResultCache.swift`      │ 缓存折叠的工具结果，供 `/expand` 使用 │
│ │ `EntryPoint.swift`           │ ArgumentParser 入口点                 │
│ 
│ 关键设计决策
│ 
│ 1. 无 ncurses — 纯粹的 ANSI 转义序列 + 原始模式 termios。体积更小，无链接依赖。
│ 2. TerminalRenderer 与 MarkdownRenderer 分离 — 一个是基础设施层（颜色、边框、面板），另一个是内容层（markdown 语义）。它们协同工作，但不互相耦合。
│ 3. Core/CLI 边界 —  StreamRenderer  属于 Core 层（不含终端 I/O），而  TerminalRenderer  和  MarkdownRenderer  属于 CLI 层（直接输出到终端）。
│ 4. 内联弹出层 — 弹出层不占用全屏，而是在输入行上方渲染，输入完成后自动清除，使 UI 保持连贯且流畅。
│ 5. 括号粘贴处理 —  LineEditor  在解析大粘贴时使用超时机制，避免阻塞，超过阈值时摘要显示粘贴内容。

------

│ SwiftAgent CLI TUI 架构总览
│ ───────────────────────
│ 
│ 核心渲染管线
│ 
│ ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ │ LLM API (SSE流)                                                                                         │
│ │   │                                                                                                     │
│ │   ▼                                                                                                     │
│ │ ChatCommand.run()  ─── 内联 agent loop ─── 逐事件处理 (.textDelta / .thinkingDelta / .contentBlockStop) │
│ │   │                                                                                                     │
│ │   ├─ 实时流式输出 ──→ 终端直接输出 (print + fflush)，无行缓冲                                           │
│ │   │                                                                                                     │
│ │   ├─ 文本累积后 ──→ MarkdownRenderer.render()  ──→ ANSI 格式化 → print                                  │
│ │   │                  (语法高亮 + 表格 + 代码块 + 内联样式)                                              │
│ │   │                                                                                                     │
│ │   ├─ 无 markdown 时 ──→ TerminalRenderer.renderLeftBorder() ──→ 左竖线 + ANSI                           │
│ │   │                                                                                                     │
│ │   └─ 折叠工具结果 ──→ CollapseDetector → CollapsedSummaryFormatter → emitBlock                          │
│ └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
│ 
│ 四个关键渲染器
│ 
│ │          组件          │                  位置                  │                                              职责                                               │
│ ├────────────────────────┼────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────┤
│ │ **`StreamRenderer`**   │ `SwiftAgentCore/Agent/`                │ Core 层，将 `StreamEvent` 映射为纯文本 — 工具调用、thinking、token 统计。**不做 ANSI 终端控制** │
│ │ **`TerminalRenderer`** │ `SwiftAgentCLI/TerminalRenderer.swift` │ 48 个方法。Box drawing（`╭── ╮ ╰ ╯ │`）、面板、左竖线、spinner、思考行、状态行、清屏、光标控制  │
│ │ **`MarkdownRenderer`** │ `SwiftAgentCLI/MarkdownRenderer.swift` │ 770 行。Fenced 代码块解析、语言检测、TreeSitter 语法高亮、表格检测/渲染、粗体/斜体/内联代码     │
│ │ **`StatusLine`**       │ `SwiftAgentCLI/StatusLine.swift`       │ 底部状态行 — 反色显示进度/token/标题                                                            │
│ 
│ ChatCommand.run() 主循环 (`Sources/SwiftAgentCLI/ChatCommand.swift:201-895`)
│ 
│ ┌──────────────────────────────────────────────────────────────────────────────────────────┐
│ │ 1. 终端保存 (termios) → 创建 TerminalCapability → TerminalRenderer → MarkdownRenderer    │
│ │ 2. LineEditor 注册 popup data source (@ 文件 / 命令)                                     │
│ │ 3. REPL: editor.readLine(prompt: "You: ") → 处理 /slash 命令                             │
│ │ 4. 用户输入作为 Message(type: .user) append 到 conversationHistory                       │
│ │ 5. 内联 agent 循环 (while true):                                                         │
│ │    ├─ Spinner Task (独立) — 调用 renderer.spinnerFrame() + renderer.renderThinkingLine() │
│ │    ├─ LLM 流式迭代 (for try await event in stream):                                      │
│ │    │   ├─ .textDelta → turnText 累积                                                     │
│ │    │   ├─ .thinkingDelta → dim 模式流式输出 (showThinking 模式)                          │
│ │    │   ├─ .contentBlockStart(.toolUse) → toolInputAccumulator 开始                       │
│ │    │   ├─ .inputJSONDelta → toolInputAccumulator 追加                                    │
│ │    │   ├─ .contentBlockStop → 完成工具输入解析                                           │
│ │    │   └─ .messageDelta → 记录 token 用量                                                │
│ │    ├─ 工具输入解析完成 → toolBlocks (ChatToolInputAccumulator)                           │
│ │    ├─ 无 tool calls → 结束 → renderLeftBorder / MarkdownRenderer                         │
│ │    ├─ 有 tool calls → ChatToolExecutionScheduler (并行/串行) → emitCollapsedResults      │
│ │    └─ tool results 作为 user message append，继续循环                                    │
│ │ 6. 会话保存 → LineEditor.save()                                                          │
│ └──────────────────────────────────────────────────────────────────────────────────────────┘
│ 
│ LineEditor 细节 (`Sources/SwiftAgentCLI/LineEditor.swift`)
│ 
│ •  rawModeReadLine()  — 核心输入循环：进入 raw termios 模式 → 逐字节读取 → 处理箭头/转义序列
│ • Popups:  @  文件搜索 +  /  命令搜索，基于  FileSearchIndex  和  CommandDataSource 
│ • Bracketed paste:  readBracketedPasteContent()  检测粘贴数据， handlePaste()  处理多行内容并生成占位符
│ • Shift+Enter: 通过 HID 键盘状态检测物理 Shift 键状态，插入字面换行
│ • Ctrl+O: 折叠/展开切换，委托给  handleCtrlO()  操作  ToolResultCache 
│ 
│ 工具结果折叠系统
│ 
│ ┌───────────────────────────────────────────────────────────────────────┐
│ │ ChatToolExecutionScheduler (执行结果)                                 │
│ │   │                                                                   │
│ │   ▼                                                                   │
│ │ emitCollapsedResults()                                                │
│ │   ├─ CollapseDetector.collapse() → 按相似性分组 (多搜索/读取工具合并) │
│ │   ├─ CollapseDetector.makeGroup() → 生成折叠摘要行                    │
│ │   ├─ CollapsedSummaryFormatter → ANSI 彩色单行摘要 + 图标             │
│ │   └─ ToolResultCache.store() → 保存完整输出 (供 /expand 展开)         │
│ └───────────────────────────────────────────────────────────────────────┘
│ 
│ 终端能力检测
│ 
│  TerminalCapability  ( Sources/SwiftAgentCLI/TerminalCapability.swift ) — 单次检测 TTY 状态、颜色支持 ( --no-color )、终端尺寸 ( TIOCGWINSZ )， scrubANSICodes()  在非 TTY 环境剥离 ANSI。
│ 
│ 架构要点
│ 
│ • 无缓冲流式渲染 — 文本 delta 直接  print+fflush ，不经过  StreamRenderer / TerminalRenderer  缓冲层
│ • Spinner 与 thinking 互斥 — showThinking 模式下 spinner 暂停，thinking 以 dim 样式原地渲染
│ • Markdown 与纯文本分支 —  --no-markdown  标志决定用  markdown.render()  还是  renderer.renderLeftBorder() 
│ • CodeTheme + ColorTheme 双主题 —  CodeTheme  管理代码高亮颜色， ColorTheme  管理 UI chrome（面板/边框/spinner）

------

│ SwiftAgent CLI — TUI 架构
│ ───────────────────────
│ 
│ 架构总览
│ 
│ ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ │ ChatCommand.run()          ← 主循环 (inline agent loop)                                     │
│ │   ├── TerminalRenderer     ← ANSI 渲染输出                                                  │
│ │   │     ├── TerminalCapability  ← TTY/颜色/尺寸检测                                         │
│ │   │     ├── ColorTheme          ← 颜色主题 (default / monochrome)                           │
│ │   │     └── ANSI escapes        ← 光标控制、边框、spinner、面板                             │
│ │   ├── LineEditor            ← Raw-mode 行编辑器 (stdin 事件驱动)                            │
│ │   │     ├── History persistence ← ~/.swift-agent/history/cli_history                        │
│ │   │     ├── InlinePopup         ← @ / / 补全弹出层                                          │
│ │   │     │     └── PopupDataSource ← CommandDataSource / FileDataSource / ArgumentDataSource │
│ │   │     ├── Paste handling      ← 多行粘贴摘要 + bracketed paste                            │
│ │   │     └── Escape sequences    ← 箭头键、Alt+←→、kitty protocol、Shift+Enter               │
│ │   ├── MarkdownRenderer      ← Markdown → ANSI 转换 (代码块、表格、链接)                     │
│ │   │     └── TreeSitterSyntaxHighlighter ← 语法高亮                                          │
│ │   ├── StreamRenderer        ← SSE 事件 → 用户可见文本 (Core 层)                             │
│ │   ├── Spinner               ← 异步 Task, 工具运行时的帧动画                                 │
│ │   ├── CollapsedResult       ← 工具输出折叠/展开 (Ctrl+O / /expand)                          │
│ │   │     ├── CollapseDetector                                                                │
│ │   │     ├── CollapsedSummaryFormatter                                                       │
│ │   │     └── ToolResultCache                                                                 │
│ │   └── DebugLogger           ← JSONL 调试日志 (~/.swift-agent/logs/)                         │
│ └─────────────────────────────────────────────────────────────────────────────────────────────┘
│ 
│ 核心组件详解
│ 
│ 1. `ChatCommand` (内联 Agent 循环) — `ChatCommand.swift:164`
│ 
│ 主 REPL 循环是 Nanobot 风格的纯直连实现（非 WebSocket/HTTP server），完全内联在  run()  方法（~700 行）：
│ 
│ 1. Terminal 保存/恢复 — 在  LineEditor  put terminal to raw mode 前保存  termios 
│ 2. 组件初始化 —  TerminalRenderer  +  MarkdownRenderer  +  LLMClient  +  ToolRegistry  +  LineEditor 
│ 3. Bootstrap — MCP servers, 内置工具注册, skill 枚举, inline popup data sources
│ 4. REPL 循环 ( while true ):
│    •  renderer.drainTTYInput()  — 清空模型生成期间积压的按键
│    •  editor.readLine(prompt: "You: ")  — raw-mode 行编辑
│    • Slash commands ( /help ,  /exit ,  /clear ,  /model ,  /expand ,  /resume  等)
│    • ESC 拦截 —  interceptEscape()  用独立的 raw-mode term (50ms 超时) Watch bare ESC
│    • Stream 事件处理 —  textDelta  /  thinkingDelta  /  contentBlockStart  /  inputJSONDelta  /  messageDelta 
│    • 工具执行 —  ChatToolExecutionScheduler  并发调度 (concurrency-safe tools 并行, others 串行)
│    • Truncation recovery —  max_tokens  或 JSON 截断时自动 continue
│    • Tool result 折叠 —  emitCollapsedResults  分组渲染
│    • AI 响应渲染 —  MarkdownRenderer.render()  或  TerminalRenderer.renderLeftBorder() 
│ 
│ 2. `TerminalRenderer` — `TerminalRenderer.swift:6`
│ 
│ 纯 ANSI 输出渲染器，无外部依赖：
│ 
│ │             方法              │                       功能                        │
│ ├───────────────────────────────┼───────────────────────────────────────────────────┤
│ │ `write(_:color:style:)`       │ 带颜色的 `print`，非 TTY 时退化                   │
│ │ `renderBanner(version:)`      │ Unicode 框线欢迎 Banner                           │
│ │ `renderStatusLine(_:)`        │ 反向视频状态行 (tokens / session)                 │
│ │ `renderLeftBorder(content:)`  │ AI 回复左侧 `│ ` 前缀                             │
│ │ `renderPanel(title:content:)` │ Rich-style 完整边框面板 (word-wrap, ╭╮╰╯)         │
│ │ `renderThinkingLine(frame:)`  │ 带 spinner 的 "Thinking..." 行                    │
│ │ `spinnerFrame(index:)`        │ Braille spinner 帧 (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`)                 │
│ │ `drainTTYInput()`             │ 用 `tcflush(TCIFLUSH)` + poll fallback 清空 stdin │
│ 
│ 3. `LineEditor` — `LineEditor.swift:36`
│ 
│ 自实现的 raw-mode 行编辑器（无 GNU readline / libedit 依赖）：
│ 
│ • Raw mode:  termios  — 禁用 ICANON/ECHO/ISIG，启用 bracketed paste ( ?2004h )
│ • Escape sequences: CSI ( ESC [ A/B/C/D ), SS3 ( ESC O A/B/C/D ), kitty keyboard protocol ( CSI key;mods u ), xterm modified keys
│ • Kitty protocol 支持: Shift+Enter → 插入换行, Alt+Backspace → 删除词
│ • Shift 检测: 通过  CGEventSource.flagsState(.hidSystemState)  读 HID 键盘状态 区分 Shift+Enter vs Enter
│ • Inline popup:  @  或  /  触发时切换到 popup mode，渲染在输入区下方
│ • Paste 处理: Bracketed paste 提取内容，多行粘贴显示摘要  [Pasted text #N +M lines] 
│ • History:  ~/.swift-agent/history/cli_history ，null-byte 分隔支持多行条目，上限 500
│ • Ghost text: Command 参数提示以 dim 样式显示在光标后
│ • Multi-line:  \n  内容支持垂直光标移动（↑↓ 在行间导航，只在首行/末行时进入 history）
│ 
│ 4. `InlinePopup` — `InlinePopup.swift:44`
│ 
│ 类似 Claude Code 的 inline completion popup：
│ 
│ • 渲染: Unicode box-drawing ( ╭╮╰╯│ )，动态宽度计算，match 高亮（bold+yellow），选中反转视频， ▸  指示器，scroll arrow ( ↑ N more )
│ • 交互: 逐字符增量搜索，↑↓ 导航，Enter/Tab 确认，ESC 取消，空格提交+关闭
│ • Sub-menu: 命令确认后自动打开参数选择子菜单（如  /model  → 模型列表）
│ • 帮助文本: 右侧 dim 样式显示命令帮助
│ 
│ 5. `MarkdownRenderer` — `MarkdownRenderer.swift:7`
│ 
│ TermKit 风格 Markdown → ANSI 转换：
│ • 代码块自动检测 + 语法高亮 (TreeSitter)
│ • 链接替换、粗体/斜体/行内代码 ANSI 样式
│ • 代码块边框、缩进剥离
│ 
│ 6. `StreamRenderer` (Core 层) — `StreamRenderer.swift:5`
│ 
│ SSE 事件 → 用户可见文本的映射（属于  SwiftAgentCore ，非 CLI 层）：
│ •  textDelta  → 文本直传
│ •  contentBlockStart(.toolUse)  →  → Calling tool: name... 
│ •  messageDelta  →  [Tokens: ↓N ↑M] 
│ •  thinkingDelta  → 走  ContentBlockAccumulator  (不在 StreamRenderer 内渲染)
│ 
│ 7. **Spinner 系统**
│ 
│ 异步  Task  在 Agent 循环期间运行：
│ • 默认显示  ⠋ Thinking... 
│ • 工具运行时显示  ⠋ Running Tool → Bash: command 
│ •  showThinking  模式时暂停 spinner，让 thinking text 无闪烁内联渲染
│ •  SpinnerPauseFlag  在  AskUserQuestion  交互期间暂停
│ 
│ 8. **Tool Result 折叠**
│ 
│ 类似 CC 的 tool result 折叠系统：
│ •  CollapseDetector  判断可折叠性
│ •  CollapsedSummaryFormatter  单行/详细摘要
│ •  ToolResultCache  持久化完整输出
│ •  Ctrl+O  /  /expand last  /  /expand N  切换展开/折叠
│ 
│ 关键设计决策
│ 
│ 1. 无 TUI 框架依赖 — 全部基于 ANSI escape codes + termios syscalls，无 TermKit/Ncurses
│ 2. Core/CLI 分层 —  StreamRenderer  在 Core（事件→文本）， TerminalRenderer  在 CLI（ANSI 颜色/布局）
│ 3. Actor-free 并发 — 用 manual  Task  +  @unchecked Sendable  + 共享状态而非 Actor
│ 4. Kitty protocol 向前兼容 — 已实现 kitty keyboard protocol 解析 (CSI u)，尽管当前主要依赖传统 escape codes
│ 5. Paste safety — 多行粘贴不自动提交，显示摘要确认
│ 6. 可测试 —  TerminalCapability.init(isTTY:supportsColor:columns:rows:)  允许强制注入测试值

------

│ SwiftAgent CLI TUI 架构分析
│ ───────────────────────
│ 
│ 整体分层
│ 
│ ┌──────────────────────────────────────────────────────────────────────────┐
│ │ ┌─────────────────────────────────────────────────────┐                  │
│ │ │                  ChatCommand.swift                   │  ← REPL 主循环  │
│ │ │   agent loop · spinner · 流事件 · Ctrl+O 折叠        │                 │
│ │ ├─────────────────────────────────────────────────────┤                  │
│ │ │  TerminalRenderer  │  MarkdownRenderer  │  LineEditor │  ← 渲染 + 输入 │
│ │ │  ANSI/Unicode box  │  代码高亮/表格/    │  raw mode  │                 │
│ │ │  面板/状态栏/微调  │  粗体/斜体/链接    │  行编辑     │                │
│ │ ├─────────────────────────────────────────────────────┤                  │
│ │ │  ColorTheme  │  TerminalCapability  │  DisplayWidth  │  ← 基础设施     │
│ │ │  ANSIColor   │  TTY检测/尺寸/颜色    │  Unicode宽度  │                 │
│ │ │  ANIStyle    │                       │              │                  │
│ │ ├─────────────────────────────────────────────────────┤                  │
│ │ │  StreamRenderer (Core)  │  AppState (Actor)         │  ← 共享状态      │
│ │ │  协议级流事件 → 文本     │  处理状态/Token/压缩      │                 │
│ │ └─────────────────────────────────────────────────────┘                  │
│ └──────────────────────────────────────────────────────────────────────────┘
│ 
│ 关键组件详解
│ 
│ 1. `ChatCommand.swift` — REPL 主循环
│ 
│ • 输入循环:  while true  中调用  editor.readLine(prompt: "You: ")  获取用户输入
│ • Agent 循环: 内嵌  while true ，每轮发送 API 请求 → 流式处理事件 → 执行工具 → 重复，直到  stop_reason == "end_turn"  或 ESC 取消
│ • 流事件处理 ( ChatCommand.swift:635-706 ):
│   •  .textDelta  — 累积到  turnText ， print()  直接写入 stdout
│   •  .thinkingDelta  — 累积到  thinkingText ， --show-thinking  时以  \u{001B}[2m  (dim) 实时流式输出
│   •  .contentBlockStart(.toolUse)  — 开始解析工具调用 JSON
│   •  .inputJSONDelta  — 逐步累积工具输入参数到  ChatToolInputAccumulator 
│   •  .contentBlockStop  — 结束当前工具块
│   •  .messageDelta  — 更新 token 统计
│ • 工具执行调度:  ChatToolExecutionScheduler.execute()  支持并发/串行分区执行
│ • Ctrl+O 折叠:  ExpandState  +  ToolResultCache  — 展开/折叠工具输出块，通过 ANSI  ESC[nA  +  ESC[0J  清除重绘
│ 
│ 2. `TerminalRenderer.swift` — ANSI 渲染器
│ 
│ •  renderBanner()  (l.25): Unicode box-drawing 欢迎横幅  ┌───┐ 
│ •  renderStatusLine()  (l.38): ANSI 反色  ESC[7m  + 全宽，显示 token 统计
│ •  renderPanel()  (l.111): Nanobot 风格 Rich Panel，带  ╭── title ──╮  边框 + 自动换行
│ •  renderLeftBorder()  (l.184): 简洁左边框  │  ，用于 AI 回复
│ •  renderDelta()  (l.61): 流式文本清理 ( \r\n  →  \n )
│ •  renderPermissionPrompt()  (l.67): 工具权限确认提示
│ • 微调 (Spinner):
│   •  spinnerFrame(index:)  (l.198):  ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏  braille 旋转动画
│   •  renderThinkingLine()  (l.205):  \rESC[K  ⠋ Thinking... 
│ • 光标控制:  clearScreen()  (ESC[2J+ESC[H),  cursorUp/Down() ,  saveCursor/restoreCursor() 
│ •  drainTTYInput()  (l.213): 清除模型生成期间积累的输入缓冲
│ 
│ 3. `LineEditor.swift` — Raw 模式行编辑器
│ 
│ • 初始化 (l.36-89): 保存  termios 、加载历史文件、检测 TTY
│ • 架构:  readLine()  → 非 TTY 时走  fallbackReadLine ，TTY 时走  rawModeReadLine 
│ • rawModeReadLine (l.181-523):
│   •  enterRawMode()  — 设置  ICANON/ECHO  关闭、逐字节读取
│   • 处理每字节输入: 可打印字符 → 插入 buffer、Ctrl 组合键 → 编辑操作
│   • 支持: ←→ 移动、Backspace、Delete、Ctrl+A/E (行首/尾)、Ctrl+K/U (删除)、Ctrl+W (删除词)、Alt+←→ (词跳转)、Up/Down (历史导航)
│   • 粘贴爆发检测: 读取 2000+ 字节/10ms 突发 → 视为粘贴，用  [Pasted N chars]  摘要代替
│   • Bracketed Paste: 通过  ESC[?2004h/l  支持括号粘贴模式
│ • 重绘  redrawLine()  (l.992):
│   • 使用 ANSI 移动  ESC[lastCursorRow A  + 清屏  ESC[J 
│   • 多行 buffer 对齐: 首行显示 prompt (蓝色  ESC[1;34m )，续行用空格缩进
│   • 光标定位通过  renderedRows()  +  cursorPosition()  计算
│ • ESC 拦截  interceptEscape()  (l.129): 独立的 raw-mode poll 循环，区分裸 ESC (50ms 超时) 和转义序列
│ • Popup 支持: 内联建议/补全弹窗 ( openPopup ,  handlePopupChar ,  commitPopupSelection )
│ 
│ 4. `MarkdownRenderer.swift` — Markdown → ANSI
│ 
│ • 行分类:  LineKind  枚举 — heading/codeFence/horizontalRule/listItem/tableRow/blockquote/blank/text
│ • 渲染管道: 逐行处理：
│   1. 代码块检测 (fence 解析)
│   2. 表格检测 (至少 2 行 + 分隔符)
│   3. 标题渲染 (### → bold)
│   4. 内联渲染:  粗体  → bold,  斜体  → italic, 反引号 → inline code,  text  → 链接
│   5. 自动代码块检测 ( autoDetectCodeBlocks ) — 无显式 fence 时识别缩进/关键词密度
│ • 代码高亮: 通过  SyntaxHighlightingEngine  协议委托给 Tree-sitter
│ 
│ 5. 基础设施层
│ 
│ │          组件          │             文件             │                                     职责                                      │
│ ├────────────────────────┼──────────────────────────────┼───────────────────────────────────────────────────────────────────────────────┤
│ │ `TerminalCapability`   │ `TerminalCapability.swift`   │ `isTTY`, `supportsColor`, `columns/rows` (via `TIOCGWINSZ` ioctl), ANSI scrub │
│ │ `ColorTheme`           │ `ColorTheme.swift`           │ 语义颜色: primary/secondary/success/warning/error/dim + 样式: bold/dim/italic │
│ │ `ANSIColor`            │ `ColorTheme.swift`           │ 16 色 + true color (RGB) + foreground/background escape 生成                  │
│ │ `TerminalDisplayWidth` │ `TerminalDisplayWidth.swift` │ Unicode 宽度计算 (CJK 宽字符=2, 组合字符=0, Emoji, Tab=4)                     │
│ │ `DebugLogger`          │ `DebugLogger.swift`          │ JSONL 调试日志 (`~/.swift-agent/logs/`)                                       │
│ 
│ 6. 跨边界组件
│ 
│ •  SpinnerPauseFlag  (ChatCommand.swift:1676):  NSLock  保护的  @unchecked Sendable ，微调器暂停标志 — 在交互式提示期间阻止  \rESC[K  破坏用户输入
│ •  ExpandState  (ChatCommand.swift:11): Ctrl+O 折叠/展开的引用类型状态
│ •  CurrentToolTracker  (ChatCommand.swift:1696): 微调器和流处理器之间共享的当前工具名，同样线程安全
│ •  ChatToolInputAccumulator : 流式 JSON 累积 → 解析工具调用参数
│ 
│ 与 Claude Code 的对齐状态
│ 
│ │           特性           │ CC  │   SwiftAgent    │               差距               │
│ ├──────────────────────────┼─────┼─────────────────┼──────────────────────────────────┤
│ │ Raw mode 行编辑          │ ✓   │ ✓               │ 缺少 Vim 模式                    │
│ │ Unicode box-drawing 面板 │ ✓   │ ✓               │ 对齐                             │
│ │ Braille spinner          │ ✓   │ ✓               │ 对齐                             │
│ │ Thinking 流式输出 (dim)  │ ✓   │ ✓               │ 对齐                             │
│ │ Bracketed paste 检测     │ ✓   │ ✓               │ 对齐                             │
│ │ 工具结果折叠 (Ctrl+O)    │ ✓   │ ✓               │ 对齐                             │
│ │ Prompt 输入模式          │ ✓   │ enum 定义存在   │ 未连线                           │
│ │ Composer 分离            │ ✓   │ ✗               │ LineEditor 是单体                │
│ │ Inline ghost text        │ ✓   │ struct 定义存在 │ 未实现                           │
│ │ Slash command popup      │ ✓   │ 部分            │ popup 框架存在，slash 注册不完整 │
│ 
│ 数据流总结
│ 
│ ┌──────────────────────────────────────────────────────────────────────────────┐
│ │ 用户按键 → LineEditor.rawModeReadLine() → buffer                             │
│ │     ↓ (Enter)                                                                │
│ │ ChatCommand.run() → conversationHistory                                      │
│ │     ↓                                                                        │
│ │ QueryEngine.run() → LLMClient.send() → SSE stream                            │
│ │     ↓                                                                        │
│ │ ChatCommand for-loop: StreamEvent 分发                                       │
│ │     ├→ textDelta        → print() + TerminalRenderer.renderDelta()           │
│ │     ├→ thinkingDelta    → print(dim) / 累积                                  │
│ │     ├→ contentBlockStart → toolInputAccumulator.startTool()                  │
│ │     ├→ inputJSONDelta   → toolInputAccumulator.append()                      │
│ │     ├→ contentBlockStop  → 触发工具执行                                      │
│ │     └→ messageDelta     → sessionState.addTokens()                           │
│ │     ↓                                                                        │
│ │ ToolExecutor.execute() → TerminalRenderer.renderPanel() / renderLeftBorder() │
│ │     ↓ (MarkdownRenderer)                                                     │
│ │ emitBlock() → print() → stdout                                               │
│ └──────────────────────────────────────────────────────────────────────────────┘


------

│ SwiftAgent CLI TUI 架构总览
│ ───────────────────────
│ 
│ 基于 codegraph 探索结果，整个 TUI 分为 五层结构：
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 1. 入口层：`ChatCommand` (ChatCommand.swift:164)
│ 
│  ChatCommand.run()  (line 201) 是整个交互循环的入口。它初始化所有子系统后进入一个  while true  REPL：
│ 
│ ┌─────────────────────────────────────────────────────────────────────┐
│ │ 初始化 → LineEditor → 读取输入 → 处理 slash 命令 / 发送 LLM 请求 →  │
│ │   流式渲染响应 → print 输出 → 循环                                  │
│ └─────────────────────────────────────────────────────────────────────┘
│ 
│ 初始化顺序（第 201-393 行）：
│ 1. 保存终端 termios 状态（退出 raw mode 时恢复）
│ 2. 解析 API key → 构建  LLMClient 
│ 3. 创建  TerminalCapability  →  TerminalRenderer  →  MarkdownRenderer 
│ 4. 注册 43 个内置工具 + MCP 工具
│ 5. 构建 system prompt + MCP 指令注入
│ 6. 给  LineEditor  注入 popup 数据源（slash 命令补全 +  @  文件补全）
│ 
│ emitBlock (line 923) 是所有输出的出口——简单的  print  包装。
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 2. 终端渲染层：`TerminalRenderer` (TerminalRenderer.swift:6)
│ 
│ 无状态、Sendable 的结构体，组合  TerminalCapability  +  ColorTheme 。提供 16 个方法，分三类：
│ 
│ │      类别       │            方法            │               用途                │
│ ├─────────────────┼────────────────────────────┼───────────────────────────────────┤
│ │ **AI 内容渲染** │ `renderBanner`             │ 启动横幅（┌───┐ 箱型）            │
│ │                 │ `renderLeftBorder`         │ 左边界 `│ ` 前缀                  │
│ │                 │ `renderDelta`              │ 流式文本增量                      │
│ │                 │ `renderThinkingLine`       │ `⠋ Thinking...` 动画              │
│ │                 │ `renderPanel`              │ 完整面板（╭──╮ 带标题、自动换行） │
│ │                 │ `spinnerFrame`             │ braille spinner 单帧              │
│ │ **交互提示**    │ `renderPermissionPrompt`   │ "Allow Bash? [y]es/[n]o/[a]lways" │
│ │                 │ `renderStatusLine`         │ 反显状态栏（token 用量、标题）    │
│ │ **终端控制**    │ `clearScreen`              │ `\e[2J\e[H`                       │
│ │                 │ `cursorUp/Down`            │ 行列移动                          │
│ │                 │ `saveCursor/restoreCursor` │ 坐标保存/恢复                     │
│ │                 │ `drainTTYInput`            │ 排空 stdin 缓冲区                 │
│ 
│ 关键设计：
│ •  renderLeftBorder  是 AI 回复的主要渲染方式——比  renderPanel  轻量，只有  │   左边框，无上下边框
│ •  renderPanel  用于重要块（标题  ╭── title ────╮ ，内宽 80 字符，支持单词边界换行）
│ •  renderStatusLine  使用 ANSI reverse video  \e[7m  做反显
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 3. 终端能力检测层：`TerminalCapability` (TerminalCapability.swift:4)
│ 
│ 纯检测结构体，无副作用：
│ 
│ •  isTTY  — 是否交互终端
│ •  colorSupport  — 检测  COLORTERM  /  TERM  环境变量
│ •  columns  —  TIOCGWINSZ  ioctl 获取列宽
│ •  color(_:color:)  /  scrubANSICodes(_:)  — 条件性 ANSI 着色
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 4. Markdown 渲染层：`MarkdownRenderer` (MarkdownRenderer.swift:7)
│ 
│  render(_:)  (line 28) 是核心管线：
│ 
│ ┌────────────────────────────────────────────────────────┐
│ │ 原始 Markdown                                          │
│ │   → autoDetectCodeBlocks (自动检测无 fence 的代码块)   │
│ │   → 逐行解析：                                         │
│ │     ├── fenced code block → renderCodeBlock (语法高亮) │
│ │     ├── table → renderTable                            │
│ │     ├── heading → renderHeading                        │
│ │     ├── blockquote → renderBlockquote                  │
│ │     ├── list → renderListItem                          │
│ │     ├── divider → renderDivider                        │
│ │     └── inline → renderInline (bold/italic/link/code)  │
│ │   → 每行用 border("│ ") 加左边界                       │
│ │   → ANSI 字符串输出                                    │
│ └────────────────────────────────────────────────────────┘
│ 
│ 依赖  TreeSitterSyntaxHighlighter  +  CodeTheme.monokai  做代码块语法高亮。
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 5. 输入层：`LineEditor` (LineEditor.swift:36)
│ 
│  @unchecked Sendable  class，raw-mode 行编辑器。核心状态：
│ 
│ • 历史系统：持久化到文件，bash/zsh readline 行为（ stashedBuffer  机制——浏览历史时保存当前输入，按 ↓ 可恢复）
│ • Popup 系统： slashDataSource （命令补全）和  atDataSource （文件补全），通过  setPopupDataSources  注入
│ • Paste 处理：bracketed paste 检测、burst 合并、paste placeholder 替换
│ • Escape 序列解析： readEscapeSequence  /  readComplexCSI  处理方向键、Option+键等
│ 
│ redrawLine (line 992) 和 cursorPosition (line 1083) 管理终端光标定位——跟踪  drawnLines  和  lastCursorRow  以正确清除并重绘。
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 数据流全景
│ 
│ ┌─────────────────────────────────────────────────────────────────────────────────┐
│ │ 用户按键                                                                        │
│ │   → LineEditor.readLine()  (raw mode, 历史, popup)                              │
│ │   → ChatCommand.run()      (slash 命令 / LLM 请求)                              │
│ │   → LLMClient.stream()     (SSE 事件流)                                         │
│ │   → Stream?TextDelta       → TerminalRenderer.renderDelta  → emitBlock (左边界) │
│ │   → Stream?ToolUse         → ToolExecutor.execute          → ToolResultCache    │
│ │   → Stream?Thinking        → TerminalRenderer.renderThinkingLine (spinner)      │
│ │   → 完整响应               → MarkdownRenderer.render       → emitBlock (面板)   │
│ │   → print() 到终端                                                              │
│ └─────────────────────────────────────────────────────────────────────────────────┘
│ 
│ 关键架构决策
│ 
│ 1. Core/CLI 边界： StreamRenderer  在 Core 层（纯逻辑，格式化事件）， TerminalRenderer  在 CLI 层（ANSI、TTY 检测）
│ 2. TerminalRenderer 无状态：所有渲染方法都是纯函数，输入字符串输出字符串，方便测试
│ 3. MarkdownRenderer 在 CLI 层：因为它依赖终端宽度和颜色能力
│ 4. Status line 使用 reverse video：保持 TUI "帧"感，不干扰主内容区


------

│ 架构概览
│ ────
│ 
│ TUI 分为四个不同的层次，边界清晰：
│ 
│ ┌─────────────────────────────────────────────────────────────┐
│ │ ┌──────────────────────────────────────────────────────┐    │
│ │ │  ChatCommand (Agent 主循环)                           │   │
│ │ │  - 用户输入 → stream → 渲染 → 工具执行循环             │  │
│ │ │  - 持有 TerminalCapability, TerminalRenderer,         │   │
│ │ │    MarkdownRenderer, DebugLogger                     │    │
│ │ ├──────────────────────────────────────────────────────┤    │
│ │ │  LineEditor (原始模式输入)                              │ │
│ │ │  - 原始 termios 模式，每次按键                         │  │
│ │ │  - 内联补全弹窗 (InlinePopup)                          │  │
│ │ │  - Emacs 风格的编辑、历史、粘贴处理                     │ │
│ │ ├──────────────────────────────────────────────────────┤    │
│ │ │  渲染管线                                              │  │
│ │ │  - TerminalRenderer (ANSI 横幅、状态行)                │  │
│ │ │  - StreamRenderer (LLM SSE → 终端安全文本)             │  │
│ │ │  - MarkdownRenderer (代码块语法高亮)                   │  │
│ │ │  - CodeTheme + TreeSitterSyntaxHighlighter            │   │
│ │ ├──────────────────────────────────────────────────────┤    │
│ │ │  终端抽象层                                            │  │
│ │ │  - TerminalCapability (TTY 检测、大小、颜色)           │  │
│ │ │  - TerminalDisplayWidth (CJK/表情符号宽度)              │ │
│ │ │  - ANSIColor / ANIStyle / ColorTheme                  │   │
│ │ └──────────────────────────────────────────────────────┘    │
│ └─────────────────────────────────────────────────────────────┘
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 1. ChatCommand —— Agent 主循环 (`Sources/SwiftAgentCLI/ChatCommand.swift:201-933`)
│ ───────────────────────────────────────────────────────────────────────────────
│ 
│ 这是 TUI 的中心。运行时 \(201-230 行）：
│ 
│ 1. 在  LineEditor  将其置为原始模式之前，通过  tcgetattr  捕获原始终端  termios 。
│ 2. 解析  TerminalCapability()  用于检测 TTY/颜色/大小。
│ 3. 通过  ColorTheme （默认或黑白）选择主题。
│ 4. 实例化整个渲染管线： TerminalRenderer 、 TreeSitterSyntaxHighlighter 、 MarkdownRenderer 。
│ 
│ 主循环（~434 行）：
│ ┌─────────────────────────────────────────────────────────── swift ┐
│ │ guard let line = editor.readLine(prompt: "You: ") else { break } │
│ └──────────────────────────────────────────────────────────────────┘
│ 每次读取一行原始模式，然后将其输入  QueryEngine ，通过流事件（ textDelta 、 thinkingDelta 、 inputJSONDelta 、 contentBlockStop 、 messageDelta ）运行，并代表 LLM 执行工具。
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 2. LineEditor (`Sources/SwiftAgentCLI/LineEditor.swift:36`)
│ ───────────────────────────────────────────────────────────
│ 
│ 一个功能完备的原始模式行编辑器。架构：
│ 
│ │            组件            │ 位置（行） │                                   用途                                    │
│ ├────────────────────────────┼────────────┼───────────────────────────────────────────────────────────────────────────┤
│ │ `readLine(prompt:)`        │ 100        │ 入口 —— 如果 TTY，委托给原始模式；否则回退到 `Swift.readLine()`           │
│ │ `rawModeReadLine(prompt:)` │ 181        │ 核心原始模式循环 —— 进入原始模式，读取字节，分派到处理程序                │
│ │ `redrawLine`               │ 992        │ 清除前一个区域，绘制带 ANSI 样式的提示符，处理多行换行                    │
│ │ `renderedRows`             │ 1076       │ 根据提示宽度 + 终端列数计算显示行数                                       │
│ │ `cursorPosition`           │ 1083       │ 将缓冲区偏移量映射到（行，列）以进行光标放置                              │
│ │ `handlePaste`              │ 566        │ 检测并去抖动括号粘贴序列（`\e[200~` ... `\e[201~`）                       │
│ │ `wordBoundaryBefore`       │ 937        │ Alt+左键两阶段单词边界（非单词字符，然后单词字符）                        │
│ │ `wordBoundaryAfter`        │ 967        │ Alt+右键，对称反向                                                        │
│ │ `readEscapeSequence`       │ 667        │ 解析 ANSI escape/decimal/function 序列；处理方向键、Alt+字符、Ctrl+箭头键 │
│ │ `historyState`             │ —          │ 通过 `↑↓` 导航保存的提示符/缓冲区对，并可跨行搜索重复使用                 │
│ 
│ 粘贴处理（544-594 行）是最复杂的：将占位符  [Paste-{i}]  扩展回原始粘贴内容，规范化 CRLF，并在缓冲区超过阈值时生成  [Paste-{n}]  摘要。
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 3. InlinePopup (`Sources/SwiftAgentCLI/InlinePopup.swift:44`)
│ ─────────────────────────────────────────────────────────────
│ 
│ 在输入行上方渲染的类似 fzf 的补全弹出窗口。架构：
│ 
│ ┌─────────────────────────────────────────────────────────────────┐
│ │ ╭ query ───────────────────────────────╮  ← 顶部边框 + 搜索查询 │
│ │ │ display text              help text  │  ← 选定项 = 反色       │
│ │ │ dim item                              │  ← 未选定项 = 暗淡    │
│ │ ╰──────────────────────────────────────╯  ← 底部边框            │
│ └─────────────────────────────────────────────────────────────────┘
│ 
│ •  reloadDataSource  /  refresh  —— 更新项目列表
│ •  appendQuery  /  deleteQueryChar  —— 增量过滤
│ •  moveUp  /  moveDown  —— 在过滤后的列表中导航
│ •  updateScroll  (151 行) —— 保持选定项在可见窗口内
│ •  render(to:terminalWidth:inputStartCol:)  (187 行) —— 绘制带 ANSI 边框、标题、滚动指示器和 truncation 的弹出窗口
│ 
│ 弹出窗口始终在输入行上方渲染，光标在渲染后恢复到输入区域。
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 4. 渲染管线
│ ───────
│ 
│ StreamRenderer (`Sources/SwiftAgentCore/Agent/StreamRenderer.swift:5`)
│ 位于 Core 中（可复用）。将 LLM 流事件转换为终端安全输出：
│ •  textDelta  → 原始文本透传
│ •  thinkingDelta  →  ""  （静默累积）
│ •  contentBlockStart(.toolUse)  →  "→ Calling tool: <name>...\n" 
│ •  messageDelta  → 使用量/停止原因
│ •  inputJSONDelta  →  "."  （工具输入进度点）
│ • 工具函数： sanitize （CRLF→LF）、 wrap （截断至宽度）
│ 
│ TerminalRenderer (`Sources/SwiftAgentCLI/TerminalRenderer.swift:6`)
│ 面向用户的 CLI 渲染器：
│ •  write(_:color:style:)  —— 如果 TTY，则打印 ANSI 样式文本；否则打印纯文本
│ •  renderBanner(version:)  —— 带有 ANSI 颜色 + 粗体的盒装欢迎横幅
│ •  renderStatusLine(_: AppStateSnapshot)  —— 带有操作模式指示器的 "[Working...]" 状态
│ 
│ MarkdownRenderer (`Sources/SwiftAgentCLI/MarkdownRenderer.swift:7`)
│ 完整的 Markdown→ANSI 渲染器，包括：
│ • 标题、粗体、斜体、暗淡、列表、水平线、引用块
│ • 带有  TreeSitterSyntaxHighlighter  的围栏代码块 +  CodeTheme （默认：Monokai）
│ • 表格渲染与列宽计算
│ • 链接呈现
│ 
│ DebugLogger (`Sources/SwiftAgentCLI/DebugLogger.swift:7`)
│ 非 TUI，但对调试 TUI 行为至关重要。将 API 交互以 JSONL 格式写入  ~/.swift-agent/logs/ ：
│ • 请求体、响应状态、原始 SSE 事件
│ • 已屏蔽的 API 密钥（ maskSensitiveHeaders ）
│ • 使用统计、错误、信息日志
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 5. 终端抽象
│ ───────
│ 
│ TerminalCapability (`Sources/SwiftAgentCLI/TerminalCapability.swift:4`)
│ 通过  isatty 、 COLORTERM 、 FORCE_COLOR  和 terminfo 查询检测：
│ • TTY 状态
│ • 24 位 True Color 支持
│ • 终端尺寸（通过  TIOCGWINSZ  ioctl）
│ •  scrubANSICodes  —— 当输出到管道时，剥离 ANSI escape
│ 
│ TerminalDisplayWidth (`Sources/SwiftAgentCLI/TerminalDisplayWidth.swift:3`)
│ Unicode 感知的显示宽度计算：
│ • CJK 字符 = 2 个单元格
│ • 组合标记 = 0 个单元格
│ • 制表符 = 4 个单元格
│ • 表情符号 = 2 个单元格（ZWJ 检测）
│ • ANSI escape 剥离以进行可见宽度计算
│ • 缓冲区偏移量 →  (行, 列)  映射
│ 
│ ColorTheme / ANSIColor (`Sources/SwiftAgentCLI/ColorTheme.swift`)
│ •  ANSIColor  枚举：8 种标准颜色、8 种亮色、 trueColor(r,g,b) 
│ •  ANIStyle ：粗体、暗淡、斜体、下划线、闪烁、反色、删除线
│ •  ColorTheme ：语义槽（主要、次要、成功、警告、错误、暗淡、粗体样式）
│ • 两种预设： default （蓝色主题）和  monochrome 
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 数据流总结
│ ─────
│ 
│ ┌────────────────────────────────────────────────────────────────────┐
│ │ 用户按键                                                           │
│ │   → LineEditor.rawModeReadLine()          [原始模式，每次按键]     │
│ │   → redrawLine()                           [每次按键后重绘输入行]  │
│ │   → InlinePopup.render()                   [Tab 键弹出选择]        │
│ │   → readLine() → String                                            │
│ │   → ChatCommand.run()                      [String → QueryEngine]  │
│ │   → LLM 流事件                                                     │
│ │      → StreamRenderer.render()             [SSE → 终端文本]        │
│ │      → TerminalRenderer.renderStatusLine() [Working... 状态]       │
│ │      → MarkdownRenderer                    [带代码高亮的 Markdown] │
│ │   → ToolExecutor.execute()                 [Bash、Read、Write 等]  │
│ │   → 循环（最多 25 次迭代）                                         │
│ └────────────────────────────────────────────────────────────────────┘

------

│ SwiftAgent CLI TUI 架构
│ ─────────────────────
│ 
│ 分层架构
│ 
│ ┌──────────────────────────────────────────────────────────────────────┐
│ │ ┌─────────────────────────────────────────────────────────────┐      │
│ │ │  Sources/SwiftAgentCLI/  (20 个文件)                          │    │
│ │ │  CLI 入口、终端渲染、行编辑、弹窗、Markdown                      │ │
│ │ ├─────────────────────────────────────────────────────────────┤      │
│ │ │  Sources/SwiftAgentCore/Agent/                               │     │
│ │ │  QueryEngine、ToolExecutor、StreamRenderer、Compactor         │    │
│ │ ├─────────────────────────────────────────────────────────────┤      │
│ │ │  Sources/SwiftAgentCore/LLM/                                 │     │
│ │ │  LLMClient、LLMStreamParser、ContentBlockAccumulator、Retry   │    │
│ │ └─────────────────────────────────────────────────────────────┘      │
│ └──────────────────────────────────────────────────────────────────────┘
│ 
│ 核心组件
│ 
│ │            文件            │ 大小  │                             角色                              │
│ ├────────────────────────────┼───────┼───────────────────────────────────────────────────────────────┤
│ │ `ChatCommand.swift`        │ 86KB  │ **主循环** — REPL、斜杠命令、MCP 引导、工具注册、会话管理     │
│ │ `LineEditor.swift`         │ 56KB  │ **原始模式行编辑器** — 历史记录、粘贴检测、括号粘贴、弹窗集成 │
│ │ `MarkdownRenderer.swift`   │ 33KB  │ ANSI Markdown 渲染，支持 Tree-sitter 语法高亮                 │
│ │ `PopupDataSource.swift`    │ 20KB  │ 命令/文件/会话的弹窗数据源                                    │
│ │ `CollapseDetector.swift`   │ 14KB  │ 工具输出后的长内容折叠                                        │
│ │ `InlinePopup.swift`        │ 11KB  │ 内联补全 UI（`/` 和 `@` 触发器）                              │
│ │ `TerminalRenderer.swift`   │ 9KB   │ ANSI 终端：横幅、状态行、光标、颜色                           │
│ │ `DebugLogger.swift`        │ 7KB   │ API 交互的 JSONL 调试日志                                     │
│ │ `StatusLine.swift`         │ 1.3KB │ 底部状态行（工作状态、token 计数）                            │
│ │ `TerminalCapability.swift` │ 2.3KB │ TTY/颜色/尺寸检测                                             │
│ 
│ 数据流：一次用户交互
│ 
│ ┌───────────────────────────────────────────────────────────────────────┐
│ │ 用户输入                                                              │
│ │   │                                                                   │
│ │   ▼                                                                   │
│ │ LineEditor.readLine()           ← raw 模式, 历史, / 和 @ 的弹窗数据源 │
│ │   │                                                                   │
│ │   ▼                                                                   │
│ │ ChatCommand.run()               ← REPL 循环, 斜杠命令, 提示构建       │
│ │   │                                                                   │
│ │   ▼                                                                   │
│ │ QueryEngine.run()               ← 核心代理循环 (25次迭代/轮次)        │
│ │   │                                                                   │
│ │   ├── LLMClient.send()          ← Anthropic SSE 流                    │
│ │   │     └── LLMStreamParser     ← SSE → StreamEvent 枚举              │
│ │   │                                                                   │
│ │   ├── ContentBlockAccumulator   ← 按块索引跟踪 text/thinking/tool_use │
│ │   │                                                                   │
│ │   ├── StreamRenderer.render()   ← StreamEvent → 终端文本              │
│ │   │     └── TerminalRenderer    ← 颜色/样式/ANSI 处理                 │
│ │   │                                                                   │
│ │   ├── ToolExecutor.execute()    ← 验证 → 权限 → 调用 → 持久化         │
│ │   │     └── ToolRegistry        ← 包含 MCP 扩展的 43+ 工具            │
│ │   │                                                                   │
│ │   └── StatusLine.update()       ← 底部反向视频状态行                  │
│ └───────────────────────────────────────────────────────────────────────┘
│ 
│ ChatCommand.run() 内部的关键初始化顺序（来源：`ChatCommand.swift:201`）
│ 
│ 1. 终端捕获 — 在  LineEditor  将终端设为 raw 模式之前，先保存  termios 
│ 2. API 密钥解析 — 环境变量、钥匙串、 ~/.claude.json 、 --api-key 
│ 3. 渲染管线 —  TerminalCapability  →  TerminalRenderer  +  MarkdownRenderer  +  TreeSitterSyntaxHighlighter 
│ 4. 工具注册 —  ToolRegistry()  +  registerBuiltinTools()  + MCP 引导程序
│ 5. 行编辑器 — 为  /  和  @  弹窗配置  PopupDataSource  的  LineEditor() 
│ 6. REPL 循环 —  while true { editor.readLine() → 处理 → QueryEngine.run() } 
│ 
│ 流式处理：ContentBlockAccumulator 模式
│ 
│  QueryEngine.run() （来源： QueryEngine.swift:60 ）模拟了 Claude Code 的流式工具执行：
│ 
│ • 块开始：跟踪  tool_use  的  text / thinking / index 
│ • 增量：按内容块类型路由： textDelta  → 流式输出， thinkingDelta  → 静音/变暗
│ • JSON 增量：累积  inputJSONDelta ，在  contentBlockStop  时解析
│ • 块结束：工具在  content_block_stop  时立即开始执行，与模型流重叠 —— 无需等待  message_stop 
│ • 执行中的工具：使用  Task  并发实现的  PendingToolExecution  队列
│ 
│ Key Types
│ 
│ •  StreamEvent （来源： Types/StreamEvent.swift:1 ）— 11 种事件类型： textDelta 、 thinkingDelta 、 inputJSONDelta 、 contentBlockStart/Stop 、 messageDelta/Stop 、 ping 、 error 
│ •  ToolUseContext （来源： ToolExecutor.swift:14 ）— 承载工作目录、权限模式、MCP 客户端、plan 模式、中止信号、权限处理程序
│ •  TerminalCapability （来源： TerminalCapability.swift:4 ）—  isTTY 、 columns 、 rows 、颜色支持、ANSI 清理
│ •  InlinePopup （来源： InlinePopup.swift:44 ）— 使用  reloadDataSource 、 appendQuery / deleteQueryChar 、 moveUp/Down  和  render()  管理补全叠加层
│ 
│ Decomposition Opportunities（源自 CLAUDE.md）
│ 
│ ChatCommand.swift 有 86KB，是明显的"上帝文件"。可以分解为：
│ •  REPL  循环 + 斜杠命令分发
│ • MCP 引导 + 工具注册
│ • 会话管理（加载/保存/恢复）
│ • 工具结果折叠/展开
│ • Escape 序列 + Ctrl+O 处理

------

SwiftAgent CLI — TUI 架构总览

  分层结构（3 层）

  ┌──────────────────────────────────────────────────────────┐
  │  ChatCommand.swift  ← 主循环、状态管理、工具编排            │
  ├──────────────────────────────────────────────────────────┤
  │  TerminalRenderer / MarkdownRenderer / StreamRenderer     │
  │  ← 输出渲染层：ANSI 格式化、Markdown、流式文本              │
  ├──────────────────────────────────────────────────────────┤
  │  LineEditor / InlinePopup  ← 输入层：原始模式编辑、弹出菜单  │
  └──────────────────────────────────────────────────────────┘

  核心组件

  输入层 — LineEditor (Sources/SwiftAgentCLI/LineEditor.swift:36)
  - 原始终端模式 (termios raw mode)，逐字节读取
  - 多行输入缓冲区，支持光标移动、编辑、历史记录
  - Ctrl+O 弹出菜单模式 → 委托给 InlinePopup 渲染
  - 通过 writeToStdout 直接写 ANSI 控制序列（光标定位、清屏）
  - 通过 TerminalDisplayWidth 计算 Unicode/CJK/Emoji 宽度

  输出渲染层 — 三层管道：

  ┌──────────────────┬───────────────────────────────────────────────┬─────────────────────────────────────────────────────┐
  │ StreamRenderer   │ LLM 流事件 → 纯文本（Core 层）                │ Sources/SwiftAgentCore/Agent/StreamRenderer.swift:5 │
  ├──────────────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
  │ TerminalRenderer │ ANSI 颜色、Banner、状态栏、面板、权限提示     │ Sources/SwiftAgentCLI/TerminalRenderer.swift:6      │
  ├──────────────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
  │ MarkdownRenderer │ Markdown → ANSI（代码高亮、表格、标题、列表） │ Sources/SwiftAgentCLI/MarkdownRenderer.swift:28     │
  └──────────────────┴───────────────────────────────────────────────┴─────────────────────────────────────────────────────┘

  弹出菜单 — InlinePopup (Sources/SwiftAgentCLI/InlinePopup.swift)
  - Ctrl+O 触发的文件/命令模糊搜索
  - PopupConfig 控制尺寸（max 12 行 × 66 列）
  - 通过 PopupDataSource 协议解耦数据源
  - 在 LineEditor.redrawLine 中被调用，叠加在输入行上方

  辅助组件：

  ┌──────────────────────┬──────────────────────────────────────────────────────┐
  │         组件         │                         职责                         │
  ├──────────────────────┼──────────────────────────────────────────────────────┤
  │ ColorTheme           │ 语义颜色（primary/success/warning/error）+ ANSI 映射 │
  ├──────────────────────┼──────────────────────────────────────────────────────┤
  │ ANSIColor            │ enum：16 色 + 256 色 + trueColor(r,g,b)              │
  ├──────────────────────┼──────────────────────────────────────────────────────┤
  │ TerminalCapability   │ TTY 检测、颜色支持、终端尺寸 (ioctl TIOCGWINSZ)      │
  ├──────────────────────┼──────────────────────────────────────────────────────┤
  │ TerminalDisplayWidth │ Unicode 宽度计算（CJK=2、组合字符=0、Emoji=2）       │
  ├──────────────────────┼──────────────────────────────────────────────────────┤
  │ AppStateSnapshot     │ 状态栏数据：处理中/Token 用量/会话标题               │
  └──────────────────────┴──────────────────────────────────────────────────────┘

  数据流向

  LineEditor → rawModeReadLine → readByte loop
    ├─ 普通输入 → redrawLine (ANSI 序列直写 stdout)
    ├─ Ctrl+O → InlinePopup.render → writeToStdout
    └─ Enter → 返回 buffer 给 ChatCommand.run()

  ChatCommand.run() 的 agent loop:
    ├─ LLM 响应 → StreamRenderer.render(event) → emitBlock()
    ├─ MarkdownRenderer.render(text) → emitBlock()
    └─ TerminalRenderer.write() → Swift.print(ansi(...))

  关键架构决策

  1. LineEditor 直接写 stdout — 不走 TerminalRenderer，而是通过 writeToStdout closure 直接写入，因为需要精细的 ANSI 光标控制（\e[nA/\e[J/\e[nC）
  2. TerminalRenderer 是外观层 — 包装 Swift.print + ansi() 函数，提供便捷但非核心的渲染方法
  3. Core 层保持纯文本 — StreamRenderer 属于 Core，只做文本转换不做 ANSI；CLI 层的 TerminalRenderer 负责所有终端样式
  4. Ghost text / stash — LineEditor 支持 Ghost Text 和 Stash 缓存（复杂编辑状态的临时存储）

  ------

 SwiftAgent CLI TUI 架构

  整体是一个 原始终端模式下的自主 TUI 系统 — 无 TermKit/Ncurses 依赖，直接用 ANSI escape codes + 原生 termios I/O。

  ---
  分层架构

  ┌─────────────────────────────────────────────┐
  │  ChatCommand (Agent Loop)                   │  ← 生命周期管理 + 状态编排
  ├─────────────────────────────────────────────┤
  │  LineEditor           TerminalRenderer      │  ← 读写分离
  │  ├─ InlinePopup (/)   ├─ Banner             │
  │  ├─ PopupDataSource   ├─ Panel/LeftBorder   │
  │  ├─ FuzzyMatcher      ├─ Spinner            │
  │  └─ TokenANSIRenderer ├─ MarkdownRenderer   │
  │                       └─ StatusLine         │                                                                                                                                    
  ├─────────────────────────────────────────────┤
  │  TerminalCapability   ColorTheme/ANSICode   │  ← 基础能力层
  │  TerminalDisplayWidth ANSIStyle             │
  ├─────────────────────────────────────────────┤
  │  termios/fcntl/poll/ioctl (Darwin)          │  ← 系统调用层
  └─────────────────────────────────────────────┘

  各模块职责

  ┌────────────────────────────┬────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │            文件            │  行数  │                                                                                职责                                                                                │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ ChatCommand.swift          │ ~2000+ │ Agent REPL 循环：读入→流式渲染→工具执行→输出→写状态栏                                                                                                              │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ LineEditor.swift           │ 1287   │ 原始模式行编辑器。箭头历史导航、光标移动、多行支持、粘贴检测（bracketed paste）、UTF-8 多字节解码、词级跳转（Alt+←/→）、Shift+Enter 检测（HID API）                │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ TerminalRenderer.swift     │ 231    │ 一次性渲染工具：Banner、Panel（Rich 风格盒框）、LeftBorder（AI 响应左边框）、Spinner 帧、权限提示、水平线、清屏、TTY drain                                         │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ MarkdownRenderer.swift     │ 772    │ 将 Markdown 转为 ANSI 终端输出。代码块（含语法高亮 hooks）、表格（含对齐）、标题（H1-H6 不同样式）、引用块、列表、内联格式。含代码自动检测（3+ 行缩进/关键词密度） │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ InlinePopup.swift          │ 330    │ 内联弹出菜单：/ 触发命令补全，@ 触发文件补全。搜索过滤、↑↓导航、虚拟滚动、字符匹配高亮                                                                             │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ StatusLine.swift           │ 42     │ 底部状态栏：[Working...]、Token 用量、Session 标题。Save/Restore cursor 定位                                                                                       │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ TerminalCapability.swift   │ 62     │ TTY 检测、色彩支持检测（TERM/COLORTERM env）、尺寸检测（ioctl winsize）                                                                                            │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ ColorTheme.swift           │ 116    │ ANSI 色彩系统：16 色 + true color、前景/背景、style code。默认/单色两套主题                                                                                        │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ TokenANSIRenderer.swift    │ —      │ 语法高亮 token → ANSI 转译                                                                                                                                         │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ FuzzyMatcher.swift         │ —      │ 模糊搜索评分（精确→前缀→子串→顺序子序列）                                                                                                                          │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ TerminalDisplayWidth.swift │ —      │ Unicode 显示宽度计算（CJK 宽字符=2，组合字符=0，emoji=2），行内 cursor 定位                                                                                        │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ PopupDataSource.swift      │ —      │ Popup 数据源协议 + 默认实现（斜杠命令/文件搜索）                                                                                                                   │
  └────────────────────────────┴────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  渲染流水线

  用户输入 → LineEditor (raw mode, 逐字节读取) → ChatCommand (LLM 调用) → SSE 流 → TerminalRenderer.renderDelta (增量文本) → 累积 full text → MarkdownRenderer.render (Markdown→ANSI) →
  TerminalRenderer.renderLeftBorder (左边框) → 打印到 stdout

  其间 StatusLine 定期更新底部状态行（save cursor → 移到底部 → 写状态 → restore cursor）。

  流式输出机制

  - LLM 在后台线程发送 StreamEvent
  - 主线程 switch event type：textDelta → 直接写 stdout（无缓冲）；thinkingDelta → dim 样式渲染；contentBlockStop → 触发全文 Markdown 后处理
  - Spinner 在流式等待期间通过 \r + schedule 定时器渲染动画帧

  关键设计决策

  1. 完全无框架：不依赖 TermKit/Ncurses/SwiftTerm。所有 ANSI 控制序列直接生成，termios 手动管理 raw/cooked 模式切换
  2. Cursor 显式追踪：不用 \033[s/\033[u（各终端行为不一致），而是在每次绘制后计算目标行列并用 \033[nA/\033[nB/\033[nC 精确移动
  3. 多行输入状态机：drawnLines 和 lastCursorRow 追踪占用的终端行数，确保重绘时正确清除旧内容
  4. Paste 安全：bracketed paste（\033[200~...\033[201~）完整捕获；fallback poll 检测快速连续字节
  5. Popup 为行内：渲染在输入行下方，不覆盖主交互区，取消/确认后自动调整 buffer

------

│ TUI 架构分析
│ ────────
│ 
│ 总览
│ 
│ SwiftAgent 的 TUI 层由 5 个核心组件 构成，全部位于  Sources/SwiftAgentCLI/  下，采用纯 ANSI 转义序列实现，无任何第三方 TUI 框架依赖。
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 架构分层
│ 
│ ┌──────────────────────────────────────────────────────────────────────────┐
│ │ ┌──────────────────────────────────────────────────────┐                 │
│ │ │                  ChatCommand.run()                    │  ← REPL 主循环 │
│ │ │  调度: LineEditor → LLM Stream → ToolExecutor → 渲染  │                │
│ │ ├──────────────────────────────────────────────────────┤                 │
│ │ │  LineEditor          │  TerminalRenderer              │  ← I/O 层      │
│ │ │  (raw mode input)    │  (ANSI 输出/格式化)             │               │
│ │ │  + InlinePopup       │  + MarkdownRenderer            │                │
│ │ ├──────────────────────────────────────────────────────┤                 │
│ │ │  TerminalCapability  │  ColorTheme / ANSIColor        │  ← 基础设施    │
│ │ │  TerminalDisplayWidth│  DebugLogger                   │                │
│ │ ├──────────────────────────────────────────────────────┤                 │
│ │ │               StreamRenderer (Core)                   │  ← Core 边界   │
│ │ │   StreamEvent → 终端文本                               │               │
│ │ └──────────────────────────────────────────────────────┘                 │
│ └──────────────────────────────────────────────────────────────────────────┘
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 1. `TerminalRenderer` — ANSI 渲染引擎 (`TerminalRenderer.swift:6`)
│ 
│ 核心输出层，所有终端绘制都经过它：
│ 
│ │                 方法                  │                  功能                   │
│ ├───────────────────────────────────────┼─────────────────────────────────────────┤
│ │ `write(_:color:style:)`               │ 基础色彩文本输出，非 TTY 时剥离 ANSI    │
│ │ `renderBanner(version:)`              │ 欢迎横幅（Unicode 框线）                │
│ │ `renderStatusLine(_:)`                │ 状态栏（反向视频），显示 Working/Tokens │
│ │ `renderDelta(_:current:)`             │ 流式文本增量                            │
│ │ `renderPanel(title:content:)`         │ Rich-style 面板，自动换行+边框          │
│ │ `renderLeftBorder(content:)`          │ AI 响应左侧竖线装饰                     │
│ │ `renderThinkingLine(frame:)`          │ 思考中... 的 braille spinner            │
│ │ `renderPermissionPrompt(tool:input:)` │ 权限确认提示                            │
│ │ `drainTTYInput()`                     │ 生成期间清空键盘缓冲                    │
│ 
│ 渲染模式 ( TerminalRenderer.swift:109-192 )：
│ •  renderPanel  — 完整四边框 Rich Panel，支持标题、自动折行、色彩
│ •  renderLeftBorder  — 仅左侧竖线，用于 AI 响应流式输出（避免闪烁）
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 2. `LineEditor` — Raw Mode 行编辑器 (`LineEditor.swift:36`)
│ 
│ 仿 GNU readline 的终端行编辑器，1288 行，是项目中最复杂的单文件：
│ 
│ 核心能力：
│ • Raw mode 逐字节读取 ( LineEditor.swift:619-645 )：通过  termios  关闭 ICANON/ECHO，启用 bracket paste
│ • 光标移动：← → 逐字，Alt+← → 逐词（字母数字边界），Home/End
│ • 行编辑：Backspace、Ctrl+W（删词）、Ctrl+K（删至尾）、Ctrl+U（清行）
│ • 历史导航：↑ ↓ 浏览历史文件，带  stashedBuffer  恢复机制 ( LineEditor.swift:836-928 )
│ • 多行支持：Shift+Enter 插入换行（通过 HID 读取 Shift 修饰键状态  LineEditor.swift:613-615 ），多行内 ↑ ↓ 先移动行内光标再切历史
│ • 粘贴处理：bracket paste 协议 + 超时检测回退 ( LineEditor.swift:522-608 )，多行粘贴显示摘要而非直接提交
│ 
│ Popup 子系统 ( LineEditor.swift:53-68 ,  LineEditor.swift:1106-1254 )：
│ •  @  → 文件搜索（ FileDataSource  +  FileSearchIndex ）
│ •  /  → 命令补全（ CommandDataSource  +  SkillFileLoader ）
│ • 三级交互：触发 → 搜索过滤 → 选择/取消 → 子菜单（sub-options / sub-data-source）
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 3. `InlinePopup` — 内联弹出菜单 (`InlinePopup.swift:44`)
│ 
│ 管理弹出菜单的状态与渲染：
│ 
│ ┌─────────────────────────────────────────────────────────────────┐
│ │ ╭ query ──────────────────────────────╮                         │
│ │ │ ▸ /help           Show commands...  │  ← reverse video 选中行 │
│ │ │   /exit           Exit session      │                         │
│ │ │   /model          Change model      │                         │
│ │ │ ↓ 15 more                           │  ← 滚动指示器           │
│ │ ╰─────────────────────────────────────╯                         │
│ └─────────────────────────────────────────────────────────────────┘
│ 
│ 核心逻辑：
│ • 搜索：输入追加到 query，data source 实时过滤
│ • 导航：↑ ↓ 移动  selectedIndex ，带  scrollOffset  虚拟滚动 ( InlinePopup.swift:151-163 )
│ • 选中高亮：黄色加粗匹配位置，反转视频选中行
│ • 帮助列：右侧显示  item.help ，宽度自适应
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 4. `TerminalCapability` + `TerminalDisplayWidth` — 基础设施
│ 
│  TerminalCapability  ( TerminalCapability.swift:4 )：
│ • TTY 检测 ( isatty )
│ • 色彩支持检测 ( COLORTERM / TERM  环境变量)
│ • 终端尺寸 ( TIOCGWINSZ  ioctl)
│ •  color(_:color:style:)  — 有色彩支持时包装 ANSI，否则原样
│ •  scrubANSICodes(_:)  — 非 TTY 输出时去除 ANSI
│ 
│  TerminalDisplayWidth  ( TerminalDisplayWidth.swift:3 )：
│ • 正确处理 CJK 宽字符（双列）、组合字符（零宽）、Emoji
│ •  rows(forWidth:columns:)  — 计算换行后的行数
│ •  cursorPosition(forOffset:columns:)  — offset → (row, column) 映射
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 5. `StreamRenderer` (Core 层) — 流事件格式化 (`StreamRenderer.swift:5`)
│ 
│ 位于  SwiftAgentCore  而非 CLI，将  StreamEvent  映射为终端可显示的字符串：
│ 
│ │              事件              │             输出             │
│ ├────────────────────────────────┼──────────────────────────────┤
│ │ `.textDelta`                   │ 直接透传文本                 │
│ │ `.thinkingDelta`               │ 空（由 CLI 层处理 dim 渲染） │
│ │ `.contentBlockStart(.toolUse)` │ `→ Calling tool: Bash...`    │
│ │ `.inputJSONDelta`              │ `.` 点进度指示               │
│ │ `.messageDelta`                │ Token 统计                   │
│ │ `.error`                       │ `❌ Error: ...`               │
│ 
│ 边界设计： StreamRenderer  只管事件→字符串，具体的 ANSI dim、spinner、cursor 由 CLI 层的  ChatCommand.run()  内联处理。
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 6. REPL 主循环 (`ChatCommand.run()`, `ChatCommand.swift:201`)
│ 
│ ┌──────────────────────────────────────────────────────────────────────────┐
│ │ drainTTYInput()  →  readLine("You: ")  →  slash command 路由 或 LLM 循环 │
│ │                                               │                          │
│ │                    ┌──────────────────────────┘                          │
│ │                    ▼                                                     │
│ │          client.send() SSE 流                                            │
│ │               │                                                          │
│ │               ├─ textDelta    → 实时 print (无缓冲)                      │
│ │               ├─ thinkingDelta → dim 模式渲染 (showThinking 开关)        │
│ │               ├─ toolUse      → spinner “Working...”                     │
│ │               ├─ inputJSONDelta → 积累 JSON 片段                         │
│ │               ├─ contentBlockStop → ToolExecutor.execute()               │
│ │               └─ messageStop  → 检查 stop_reason，决定继续或结束         │
│ └──────────────────────────────────────────────────────────────────────────┘
│ 
│ 关键设计决策：
│ • Spinner 异步 ( ChatCommand.swift:569-597 )：独立 Task，每 100ms 更新 braille 帧，智能暂停
│ • ESC 中断 ( ChatCommand.swift:531-538 )：独立 Task 监听 raw mode 下的裸 ESC 键按下
│ • cooked-mode 切换 ( ChatCommand.swift:201-207 )：保存原始 termios 用于 interactive user prompts 时恢复
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 问题与改进建议
│ 
│ │ 优先级 │                   问题                    │                                             说明                                             │
│ ├────────┼───────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────┤
│ │ **P0** │ `LineEditor` 过长 (1288行)                │ 应拆分为 `LineEditor+Readline`, `LineEditor+Popup`, `LineEditor+Paste`, `LineEditor+History` │
│ │ **P0** │ `ChatCommand` 过长 (1799行)               │ `run()` 方法 ~1200 行，包含 stream 处理、tool execute、render — 应提取 `AgentLoopController` │
│ │ **P1** │ InlinePopup ANSI 硬编码                   │ 使用内联 `"\u{001B}[36m"` 而非 `ColorTheme`/`ANSIColor`，与 Theme 系统脱节                   │
│ │ **P1** │ TerminalRenderer 与 LineEditor 色彩不一致 │ LineEditor 内联了 ANSI 色彩，不经过 Theme                                                    │
│ │ **P2** │ `showThinking` 全局标志                   │ 思考文本渲染逻辑分散在 3 处 case 中，应集中为 `ThinkingRenderer`                             │
│ │ **P2** │ 无终端 resize 信号处理                    │ `LineEditor.terminalColumns` 每次重绘时实时查询，但 popup 宽度不会动态更新                   │

------

SwiftAgent CLI TUI 架构

  架构分层

  ┌─────────────────────────────────────────────────┐
  │                  ChatCommand.run                 │  ← 主循环入口
  │  编排所有 TUI 子系统，管理会话生命周期           │
  └────────┬──────────────┬──────────────┬──────────┘
           │              │              │
           ▼              ▼              ▼
  ┌─────────────┐ ┌──────────────┐ ┌──────────────────┐
  │ LineEditor  │ │TerminalRender│ │ Message Pipeline │
  │ 原始模式输入│ │   ANSI 渲染  │ │   流式消息渲染   │
  └──────┬──────┘ └──────┬───────┘ └────────┬─────────┘
         │               │                  │
         ▼               ▼                  ▼
  ┌─────────────┐ ┌──────────────┐ ┌──────────────────┐
  │ InlinePopup │ │ ColorTheme   │ │ StreamRenderer   │
  │ 内联补全弹窗│ │   ANSI 工具  │ │   事件→输出文本  │
  └─────────────┘ └──────┬───────┘ └────────┬─────────┘
                         │                  │
                         ▼                  ▼
                ┌──────────────┐ ┌──────────────────┐
                │TerminalCapab│ │ MarkdownRenderer │
                │ 终端能力检测 │ │  Markdown→ANSI   │
                └──────────────┘ └──────────────────┘

  核心组件

  1. ChatCommand.run (Sources/SwiftAgentCLI/ChatCommand.swift:201) — 主循环

  初始化链路：
  - 捕获终端 termios 状态（用于 AskUserQuestion 恢复 cooked 模式）
  - 创建 TerminalCapability → ColorTheme → TerminalRenderer
  - 创建 MarkdownRenderer（含 TreeSitterSyntaxHighlighter + CodeTheme）
  - 创建 LineEditor — 原始模式输入
  - 注册 43 个内置工具到 ToolRegistry
  - 主循环：editor.readLine(prompt: "You: ") → 构建 API 请求 → 流式消费 SSE 事件

  2. LineEditor (Sources/SwiftAgentCLI/LineEditor.swift:36) — 原始模式行编辑器

  - readLine → rawModeReadLine（TTY）或 fallbackReadLine（非 TTY）
  - 完整 readline 行为：光标移动、历史导航（↑↓）、Ctrl+A/E 跳转行首尾
  - 粘贴爆冲检测：bracketed paste 支持，大文本粘贴自动替换为占位摘要
  - Popup 系统：/ 触发 slash command 补全，@ 触发文件补全 → InlinePopup
  - redrawLine 使用 ANSI 转义序列做原地重绘

  3. TerminalRenderer (Sources/SwiftAgentCLI/TerminalRenderer.swift:6) — ANSI 渲染器

  - write(text:color:style:) — 带 ANSI 颜色/样式输出
  - renderBanner — 欢迎横幅（unicode 框线）
  - renderStatusLine — 状态行（Working... / token 计数）
  - renderPermissionPrompt — 权限询问渲染
  - horizontalRule / renderDelta — 分隔线和增量渲染
  - saveCursor / restoreCursor / cursorUp — 光标控制

  4. InlinePopup (Sources/SwiftAgentCLI/InlinePopup.swift:44) — 内联补全弹窗

  - 在光标上方渲染带边框的选项列表
  - 支持键盘导航（↑↓ 选择，Enter 确认，Ctrl+C 取消）
  - 自适应终端宽度，截断过长文本
  - 双列模式：display + help 文本

  5. StreamRenderer (Sources/SwiftAgentCore/Agent/StreamRenderer.swift:8) — 流式事件渲染

  将 StreamEvent 枚举映射为可显示文本：
  - textDelta → 直接输出文本
  - thinkingDelta → 空字符串（由 ContentBlockAccumulator 累积后单独渲染）
  - contentBlockStart(.toolUse) → "→ Calling tool: Bash..."
  - inputJSONDelta → "." （工具参数流式点）
  - messageDelta → token 使用统计
  - 辅助：sanitize、wrap、highlightCodeBlocks

  6. MarkdownRenderer (Sources/SwiftAgentCLI/MarkdownRenderer.swift:7) — Markdown→ANSI

  - render 主方法：Markdown 文本 → ANSI 格式化输出
  - 代码块语法高亮（通过 TreeSitterSyntaxHighlighter）
  - 链接替换、bold/italic/dim 样式方法

  7. TerminalCapability (Sources/SwiftAgentCLI/TerminalCapability.swift:4) — 终端能力检测

  - isTTY — 是否交互式终端
  - detectColorSupport — 颜色支持级别
  - detectSize — 终端行列数
  - scrubANSICodes — 非 TTY 时去除 ANSI 转义码

  关键数据流

  用户输入                    LLM 响应
     │                           │
     ▼                           ▼
  LineEditor               SSE 事件流
  rawModeReadLine          (textDelta, thinkingDelta,
     │                      contentBlockStart, ...)
     ▼                           │
  ChatCommand.run                ▼
  构建 Messages              StreamRenderer.render
     │                           │
     ▼                           ▼
  LLMClient.send            TerminalRenderer.write
     │                      MarkdownRenderer.render
     ▼                           │
  工具执行                      ▼
  ToolExecutor.execute      终端输出 (ANSI)
     │
     ▼
  工具结果 → 下一轮 Messages

  文件清单

  ┌──────────────────────────┬──────────┬─────────────────────────────────┐
  │           文件           │ 行数估算 │              职责               │
  ├──────────────────────────┼──────────┼─────────────────────────────────┤
  │ ChatCommand.swift        │ ~1700+   │ 主循环、工具注册、命令处理      │
  ├──────────────────────────┼──────────┼─────────────────────────────────┤
  │ LineEditor.swift         │ ~1300+   │ 原始模式编辑器、popup、粘贴处理 │
  ├──────────────────────────┼──────────┼─────────────────────────────────┤
  │ MarkdownRenderer.swift   │ ~800+    │ Markdown→ANSI 渲染              │
  ├──────────────────────────┼──────────┼─────────────────────────────────┤
  │ TerminalRenderer.swift   │ ~100+    │ ANSI 输出、横幅、状态行         │
  ├──────────────────────────┼──────────┼─────────────────────────────────┤
  │ InlinePopup.swift        │ ~330+    │ 内联补全弹窗                    │
  ├──────────────────────────┼──────────┼─────────────────────────────────┤
  │ TerminalCapability.swift │ ~60+     │ TTY/颜色/尺寸检测               │
  ├──────────────────────────┼──────────┼─────────────────────────────────┤
  │ ColorTheme.swift         │ ~115+    │ ANSI 颜色/样式定义              │
  ├──────────────────────────┼──────────┼─────────────────────────────────┤
  │ StreamRenderer.swift     │ ~95      │ 流事件→文本映射                 │
  └──────────────────────────┴──────────┴─────────────────────────────────┘


------


│ 
│ 架构概览
│ ────
│ 
│ TUI 分为 5 层，每层职责清晰：
│ 
│ ┌───────────────────────────────────────────────┐
│ │ ┌─────────────────────────────────────────┐   │
│ │ │  ChatCommand.run()  ← 主 REPL 循环       │  │
│ │ │  (Sources/SwiftAgentCLI/ChatCommand.swift)│ │
│ │ └────────────┬────────────────────────────┘   │
│ │              │                                │
│ │     ┌────────┴────────┐                       │
│ │     │  输入层          │  渲染层              │
│ │     ├─────────────────┤                       │
│ │     │ LineEditor       │  TerminalRenderer    │
│ │     │ (raw mode)       │  MarkdownRenderer    │
│ │     │ 快捷键/弹窗      │  ANSI/边框/状态栏    │
│ │     └────────┬────────┘                       │
│ │              │                                │
│ │     ┌────────┴────────┐                       │
│ │     │  Streaming 层    │                      │
│ │     │ LLMClient.send() │                      │
│ │     │ SSE → StreamEvent│                      │
│ │     └────────┬────────┘                       │
│ │              │                                │
│ │     ┌────────┴─────────────────────────┐      │
│ │     │  Agent Loop (内联，无引擎抽象)     │    │
│ │     │  最大25轮 / 自动结束检测 / ESC取消 │    │
│ │     │  工具执行 / 折叠 / 截断恢复         │   │
│ │     └──────────────────────────────────┘      │
│ └───────────────────────────────────────────────┘
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 1. 入口 — `ChatCommand.run()` (第201行)
│ ───────────────────────────────────
│ 
│  ChatCommand  是一个 ArgumentParser  AsyncParsableCommand ，整个会话在  run()  中运行，直到用户退出。
│ 
│ 初始化顺序：
│ 
│ │        步骤        │  行号   │                                               说明                                                │
│ ├────────────────────┼─────────┼───────────────────────────────────────────────────────────────────────────────────────────────────┤
│ │ 保存原始终端状态   │ 205-207 │ `tcgetattr` 保存，用于 AskUserQuestion 恢复 cooked mode                                           │
│ │ 解析 API key       │ 210-211 │ `APIKeyResolver` — 环境变量 / keychain / `.claude.json`                                           │
│ │ 初始化渲染管线     │ 228-238 │ `TerminalCapability` → `TerminalRenderer` → `MarkdownRenderer` (含 `TreeSitterSyntaxHighlighter`) │
│ │ 输出 Banner        │ 240-241 │ Unicode 框线 + ANSI 颜色                                                                          │
│ │ 初始化 LLM 客户端  │ 251     │ `LLMClient(apiKey:baseURL:model:debugLogger:)`                                                    │
│ │ 注册 43 个内置工具 │ 262     │ `registerBuiltinTools(into:taskManager:subAgentManager:)`                                         │
│ │ 创建 LineEditor    │ 264     │ raw mode 行编辑器                                                                                 │
│ │ 设置弹窗数据源     │ 384-387 │ `@`-文件补全 + `/`-命令补全                                                                       │
│ │ 构建系统提示       │ 320     │ 一次性构建，含 MCP 指令，利用 prompt caching                                                      │
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 2. 输入层 — `LineEditor` (`Sources/SwiftAgentCLI/LineEditor.swift`)
│ ────────────────────────────────────────────────────────────────
│ 
│ 基于 Darwin raw mode 的自定义行编辑器：
│ 
│ 核心方法：`readLine(prompt:)` → `rawModeReadLine(prompt:)`
│ 
│ ┌───────────────────────────────────────────────────────┐
│ │ readLine → 非TTY? → fallbackReadLine (Swift.readLine) │
│ │                 ↓ TTY                                 │
│ │            rawModeReadLine:                           │
│ │            1. 输出 "You: " (蓝色 ANSI)                │
│ │            2. enterRawMode() — 关闭回显/行缓冲        │
│ │            3. readByte() 循环 (逐个字节，非阻塞轮询)  │
│ │            4. defer: restoreTerminal() + 输出 \r\n    │
│ └───────────────────────────────────────────────────────┘
│ 
│ 按键处理 (第206-305行)
│ 
│ │      按键       │                     行为                      │
│ ├─────────────────┼───────────────────────────────────────────────┤
│ │ `Ctrl+C` (3)    │ 弹窗模式：取消弹窗；正常模式：返回 nil (退出) │
│ │ `Ctrl+D` (4)    │ 空行退出，否则忽略（类 bash）                 │
│ │ `Enter` (10,13) │ 提交行（检测 Shift+Enter 换行）               │
│ │ `Ctrl+O` (15)   │ 展开/折叠上一个工具结果                       │
│ │ `Ctrl+N/P/F/B`  │ 方向键 + emacs 风格移动                       │
│ │ `Tab`           │ 触发弹窗补全 (slash/at-补全)                  │
│ │ `ESC`           │ 取消当前 LLM 请求                             │
│ │ 可打印字符      │ 插入 buffer，更新光标，重绘行                 │
│ 
│ 弹窗系统 (`EditorMode`)
│ 
│ ┌───────────────────────────────────────────┐
│ │ enum EditorMode {                         │
│ │     case normal                           │
│ │     case popup(PopupState)  // 内联覆盖层 │
│ │ }                                         │
│ └───────────────────────────────────────────┘
│ 
│ •  /  触发命令补全 ( CommandDataSource  — 内置命令 + 技能列表)
│ •  @  触发文件补全 ( FileDataSource  — 基于  git ls-files  的  FileSearchIndex )
│ • 弹窗覆盖在当前行上方，选项可导航，选择后填入 buffer
│ 
│ 附加功能
│ 
│ • Ghost text：命令参数提示，以暗色显示在光标后
│ • Paste burst 检测：检测快速粘贴，避免逐字符渲染
│ • 历史记录：跨会话持久化，方向键浏览
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 3. 渲染层 — `TerminalRenderer` + `MarkdownRenderer`
│ ────────────────────────────────────────────────
│ 
│ `TerminalRenderer` (第6行)
│ 
│ 依赖  TerminalCapability （自动检测 TTY / 颜色 / 尺寸）和  ColorTheme 。
│ 
│ │                    方法                     │                        功能                        │
│ ├─────────────────────────────────────────────┼────────────────────────────────────────────────────┤
│ │ `write(_:color:style:)`                     │ 输出带 ANSI 样式的文本（非 TTY 时去色）            │
│ │ `renderBanner(version:)`                    │ Unicode 框线 + 版本号，`┌──┐` 风格                 │
│ │ `renderStatusLine(_:)`                      │ 反向视频状态栏：`[Working...] Tokens: ↓X ↑Y title` │
│ │ `renderDelta(_:current:)`                   │ 流式文本增量（清理 `\r\n`）                        │
│ │ `renderLeftBorder(content:)`                │ 左边框渲染（类似 CC 的 panel）                     │
│ │ `renderPermissionPrompt(tool:input:)`       │ 权限提示：`Allow Bash? [y]es / [n]o / [a]lways`    │
│ │ `horizontalRule()`                          │ 分隔线，宽度取 `min(80, terminal.columns)`         │
│ │ `clearScreen()` / `cursorUp` / `cursorDown` │ 终端控制序列                                       │
│ │ `renderSpinner(frame:)`                     │ 旋转动画帧                                         │
│ │ `renderThinkingLine(frame:)`                │ "Thinking..." 行                                   │
│ 
│ `MarkdownRenderer` (`Sources/SwiftAgentCLI/MarkdownRenderer.swift`)
│ 
│ 流式 Markdown → ANSI 渲染器：
│ 
│ ┌─────────────────────────────────────────────────────────────┐
│ │ render(markdown) → 处理流程:                                │
│ │   1. 自动检测代码块 (autoDetectCodeBlocks — 未经围栏的代码) │
│ │   2. 逐行解析:                                              │
│ │      - 围栏代码块 → 语法高亮 (TreeSitter) + 左边框          │
│ │      - 表格 → 对齐列 + ANSI 表头                            │
│ │      - 标题 → 粗体/下划线                                   │
│ │      - 内联: **粗体**, *斜体*, `代码`, [链接]               │
│ │      - 列表 → 项目符号                                      │
│ │   3. 左边框（Nanobot 风格 Rich Panel）                      │
│ └─────────────────────────────────────────────────────────────┘
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 4. Agent Loop（内联，ChatCommand 第655-898行）
│ ───────────────────────────────────────
│ 
│ 这是核心——完全内联在  ChatCommand.run()  中，没有单独的  AgentLoop  类。
│ 
│ 外部循环：每个用户输入一轮
│ 
│ ┌─────────────────────────────────────────────────────────────────────┐
│ │ while true:                          # 行 430: REPL 循环            │
│ │   line = editor.readLine("You: ")    # 行 434: 阻塞读输入           │
│ │   处理 /command                      # 行 452: 斜杠命令             │
│ │   注入系统提示（首轮）                # 行 542-570: MCP + CLAUDE.md │
│ │   启动 spinner Task                  # 行 612: 异步旋转动画         │
│ │   启动 escape-watcher Task           # 行 577: 后台监听 ESC         │
│ │   进入内层 agent loop                # 行 655                       │
│ └─────────────────────────────────────────────────────────────────────┘
│ 
│ 内层循环：LLM → 工具 → LLM，直到模型完成
│ 
│ ┌──────────────────────────────────────────────────────────────┐
│ │ while true:                          # 行 655: Agent loop    │
│ │   ├─ 检查 ESC 取消                    # 行 657               │
│ │   ├─ 发送请求 (LLMClient.send)       # 行 677: 流式 SSE      │
│ │   ├─ 处理 StreamEvent 循环            # 行 686-758:          │
│ │   │   ├─ textDelta        → 累积 turnText，重置 spinner      │
│ │   │   ├─ thinkingDelta    → 累积 thinkingText，dim 渲染      │
│ │   │   ├─ contentBlockStart(.toolUse) → 设置 currentTool name │
│ │   │   ├─ inputJSONDelta   → 累积到 toolInputAccumulator      │
│ │   │   ├─ messageDelta     → 更新 token 计数                  │
│ │   │   └─ contentBlockStop → 完成工具块                       │
│ │   │                                                          │
│ │   ├─ 截断恢复 (行 768-815):                                  │
│ │   │   如果 stopReason == "max_tokens":                       │
│ │   │     ├─ 执行已解析的工具                                  │
│ │   │     ├─ 注入 "[system] Continue from where you left off." │
│ │   │     └─ continue (下一轮)                                 │
│ │   │                                                          │
│ │   ├─ 无工具调用 → 模型完成，break (行 819-830)               │
│ │   │                                                          │
│ │   ├─ 执行工具 (行 844-864):                                  │
│ │   │   ├─ ChatToolExecutionScheduler.execute()                │
│ │   │   │   └─ 并行安全工具并发执行；非安全工具串行            │
│ │   │   └─ executeTool() 每个工具                              │
│ │   │                                                          │
│ │   ├─ 发送工具结果 (行 887-896):                              │
│ │   │   └─ conversationHistory.append(toolResult blocks)       │
│ │   │                                                          │
│ │   └─ 如果 SendUserMessage → break (行 897)                   │
│ └──────────────────────────────────────────────────────────────┘
│ 
│ 取消机制
│ 
│ ┌──────────────────────────────────────────────────────────────┐
│ │ isCancelled (AtomicBool)                                     │
│ │   ├─ escape-watcher Task: 后台 poll stdin，检测到 ESC 即设置 │
│ │   ├─ LLM 流循环: 每个 event 后检查                           │
│ │   └─ Agent 循环: 每次 LLM 调用前检查                         │
│ └──────────────────────────────────────────────────────────────┘
│ 
│ 如果取消：
│ • Spinner 和 escape-watcher 被取消
│ • 当前轮次的对话历史被回滚 ( removeSubrange )
│ • 显示 "(cancelled — press ↑ to recall previous input)"
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 5. Streaming 管道
│ ───────────────
│ 
│ ┌─────────────────────────────────────────────────────────────────────┐
│ │ LLMClient.send()                # SSE 流                            │
│ │   ↓                                                                 │
│ │ AsyncThrowingStream<StreamEvent>                                    │
│ │   ↓ (ChatCommand 内联 switch)                                       │
│ │   ├─ .textDelta        → 直接 print()（无缓冲，实时渲染）           │
│ │   ├─ .thinkingDelta    → dim ANSI 前缀 print()                      │
│ │   ├─ .contentBlockStart → 更新 spinner 状态                         │
│ │   ├─ .inputJSONDelta   → toolInputAccumulator (手动 JSON 累积+解析) │
│ │   └─ .messageDelta     → token 统计                                 │
│ └─────────────────────────────────────────────────────────────────────┘
│ 
│ Spinner 与文本渲染的协调：
│ •  textDelta  到达时：清除 spinner 行 ( \r\e[K )
│ •  thinkingDelta  到达时：如果  showThinking ，清除 spinner 并以 dim 模式渲染
│ •  currentTool.isThinking  标志跟踪思考状态
│ •  SpinnerPauseFlag  在交互式提示期间暂停 spinner
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 6. 关键设计决策
│ ─────────
│ 
│ │        决策         │                                               说明                                               │
│ ├─────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────┤
│ │ **无 God Agent 类** │ Agent 循环完全内联在 `ChatCommand.run()` 中——699 行方法                                          │
│ │ **手动 JSON 累积**  │ `ChatToolInputAccumulator` 从流式 `inputJSONDelta` 手动累积+解析工具输入（而非流式 JSON 解析器） │
│ │ **Darwin 原生 I/O** │ `LineEditor` 使用 `Darwin.read/write` + `termios`，无第三方 TUI 框架（如 ncurses）               │
│ │ **Actor 隔离**      │ `AppState` 是 actor；`AtomicBool` 用于取消标志                                                   │
│ │ **无 framebuffer**  │ 直接写入 stdout，spinner 用 `\r\e[K` 清除+重写                                                   │
│ │ **语法高亮**        │ Tree-sitter（原生 C 库绑定），支持 ~20 种语言                                                    │
│ │ **MCP 集成**        │ Bootstrap 时连接服务器，工具注入 `ToolRegistry`，指令注入系统提示                                │
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ 文件清单
│ ────
│ 
│ │             文件              │ 行数  │                     职责                     │
│ ├───────────────────────────────┼───────┼──────────────────────────────────────────────┤
│ │ `ChatCommand.swift`           │ ~1981 │ 主 REPL + Agent 循环 + 工具注册 + 斜杠命令   │
│ │ `TerminalRenderer.swift`      │ ~200+ │ ANSI 渲染：横幅、边框、状态栏、面板、spinner │
│ │ `MarkdownRenderer.swift`      │ ~400+ │ 流式 Markdown → ANSI + 语法高亮              │
│ │ `LineEditor.swift`            │ ~1260 │ Raw mode 编辑器 + 弹窗 + 历史 + 粘贴检测     │
│ │ `TerminalCapability.swift`    │ ~62   │ TTY/颜色/尺寸检测                            │
│ │ `StreamRenderer.swift` (Core) │ ~100  │ 流事件 → 人类可读文本                        │
│ 
│ 这是一个典型的 胖 CLI 入口点 架构——所有编排逻辑都在  ChatCommand  中，而非  SwiftAgentCore  中的可重用 Agent 运行时。这与 CLAUDE.md 中提到的重构方向相符： ChatCommand  是将来的分解目标。

------

│ SwiftAgent CLI TUI 架构分析
│ ───────────────────────
│ 
│ 整体结构 — 分层设计
│ 
│ ┌────────────────────────────────────────────────────────────────────────┐
│ │ ChatCommand (REPL 控制)                                                │
│ │ ├── 输入层                                                             │
│ │ │   ├── LineEditor         ← raw mode 终端, 历史记录, 内联弹窗         │
│ │ │   │   └── InlinePopup    ← @ 文件补全 / / 命令补全                   │
│ │ │   └── TTY drain          ← 模型生成期间排空键盘缓冲                  │
│ │ ├── 输出层                                                             │
│ │ │   ├── TerminalRenderer   ← ANSI 逃逸, 横幅, 面板, spinner, 光标控制  │
│ │ │   │   └── TerminalCapability  ← TTY/颜色/尺寸检测, ANSI 清洗         │
│ │ │   ├── MarkdownRenderer   ← Markdown → ANSI 后处理 (代码块高亮, 链接) │
│ │ │   │   ├── TokenANSIRenderer   ← 语法 token → ANSI 颜色               │
│ │ │   │   └── TreeSitterSyntaxHighlighter ← 代码解析 → token 列表        │
│ │ │   ├── ColorTheme         ← 颜色主题 (default / monochrome)           │
│ │ │   └── StreamRenderer     ← Core 层: StreamEvent → 纯文本 (无 ANSI)   │
│ │ └── 控制流                                                             │
│ │     ├── ANSI helpers: ansi(), color(), writeToStdout(), emitBlock()    │
│ │     ├── SpinnerPauseFlag / CurrentToolTracker / ExpandState            │
│ │     └── 系统调用: tcgetattr/tcsetattr, termios, ioctl TIOCGWINSZ       │
│ └────────────────────────────────────────────────────────────────────────┘
│ 
│ 核心渲染流程 (一次 turn)
│ 
│ ┌────────────────────────────────────────────────────────────┐
│ │ 用户输入 → LineEditor.readLine("You: ")                    │
│ │   ↓                                                        │
│ │ ChatCommand.run() → agent 循环                             │
│ │   ├── client.send() 返回 SSE 流                            │
│ │   ├── for try await event in stream:                       │
│ │   │   ├── .thinkingDelta → 低亮显示思考内容 (dim=2 mode)   │
│ │   │   ├── .textDelta     → 复位样式, 累积 turnText         │
│ │   │   ├── .inputJSONDelta → 累积 JSON 构造 tool 调用       │
│ │   │   └── .messageDelta  → 记录 token 统计                 │
│ │   ├── 工具执行 → emitCollapsedResults()                    │
│ │   └── 最终输出:                                            │
│ │       ├── noMarkdown → renderer.renderLeftBorder(content:) │
│ │       └── 默认 → markdown.render(trimmed) → ANSI 格式化    │
│ └────────────────────────────────────────────────────────────┘
│ 
│ 关键文件 & 职责
│ 
│ │            文件            │ 行数  │                                         职责                                          │
│ ├────────────────────────────┼───────┼───────────────────────────────────────────────────────────────────────────────────────┤
│ │ `ChatCommand.swift`        │ ~1981 │ REPL 主循环, agent 循环, 流处理, 工具执行, 输出发射                                   │
│ │ `TerminalRenderer.swift`   │ 232   │ ANSI 渲染: banner, status line, panel, left-border, spinner, cursor, TTY drain        │
│ │ `TerminalCapability.swift` │ ~70   │ TTY 检测, 颜色支持检测 (`COLORTERM`/`TERM`), 终端尺寸 (`ioctl TIOCGWINSZ`), ANSI 清洗 │
│ │ `ColorTheme.swift`         │ 116   │ `ColorTheme` / `ANSIColor` (16色 + trueColor) / `ANIStyle` / `ansi()` 原始函数        │
│ │ `LineEditor.swift`         │ 1288  │ Raw mode 行编辑器: 光标移动, 历史记录, bracket paste 检测, 内联弹窗                   │
│ │ `InlinePopup.swift`        │ ~200  │ `/` 命令 & `@` 文件内联补全弹窗, 滚动, 选中                                           │
│ │ `MarkdownRenderer.swift`   │ ~780  │ 后处理: heading, list, code block 检测, 链接替换, 缩进剔除                            │
│ │ `TokenANSIRenderer.swift`  │ ~100  │ 语法 token → ANSI 颜色映射                                                            │
│ │ `StreamRenderer.swift`     │ 80    │ Core 层纯文本渲染 (`StreamEvent` → 纯文本, 无 ANSI)                                   │
│ 
│ ANSI 渲染栈
│ 
│ ┌───────────────────────────────────────────────────────────────────────┐
│ │ ansi() 自由函数 (ColorTheme.swift:109)                                │
│ │   → ANSIColor.foreground()  → \e[XXm                                  │
│ │   → ANIStyle.code           → \e[1m, \e[2m, \e[3m...                  │
│ │   → 结尾 reset: \e[0m                                                 │
│ │                                                                       │
│ │ TerminalCapability.color()  → 包装 ansi() + TTY 守卫                  │
│ │ TerminalCapability.scrubANSICodes()  → 非 TTY 时剥离所有 ANSI         │
│ │                                                                       │
│ │ Cursor 控制:  \e[s/\e[u (save/restore), \e[NA/\e[NB (up/down)         │
│ │ 屏幕控制:     \e[2J\e[H (clear), \e[7m...\e[0m (reverse video status) │
│ └───────────────────────────────────────────────────────────────────────┘
│ 
│ Spinner 子系统
│ 
│ ┌───────────────────────────────────────────────────────────────────────┐
│ │ ChatCommand.run():612 — 独立 Task, 100ms tick                         │
│ │   ├── SpinnerPauseFlag.paused  → 用户交互提示时暂停                   │
│ │   ├── currentTool.isThinking   → 思考时暂停 (避免闪烁)                │
│ │   ├── currentTool.displayLine  → 工具名 + spinner ("  ⠋ Bash ls -la") │
│ │   └── 默认: "  ⠋ Thinking..." (\r\e[K + spinner frame)                │
│ │                                                                       │
│ │ Spinner 在工具执行期间持续运行, 覆盖多轮 LLM 调用.                    │
│ │ cancel 时输出 \r\e[K 清除当前行.                                      │
│ └───────────────────────────────────────────────────────────────────────┘
│ 
│ LineEditor 输入流
│ 
│ ┌───────────────────────────────────────────────────────────────────┐
│ │ rawModeReadLine() — 逐字节读取, 解析 ANSI escape 序列             │
│ │ ├── ANSI 方向键 → 历史导航 (↑/↓), 光标移动 (←/→)                  │
│ │ ├── Ctrl+A/E    → 行首/行尾                                       │
│ │ ├── Ctrl+K/U    → 删除至行尾/行首                                 │
│ │ ├── Ctrl+D      → EOF (空行时退出)                                │
│ │ ├── Ctrl+O      → toggle expand/collapse                          │
│ │ ├── Bracketed paste (\e[200~ ... \e[201~) → paste burst 检测      │
│ │ ├── Tab         → 文件补全                                        │
│ │ ├── @ 字符      → 文件路径弹窗 (InlinePopup + FileSearchIndex)    │
│ │ ├── / 字符      → 命令/技能弹窗 (InlinePopup + CommandDataSource) │
│ │ └── Ghost text  → 选完命令后显示参数提示 (dim 样式)               │
│ └───────────────────────────────────────────────────────────────────┘
│ 
│ 关键设计决策
│ 
│ 1. 写时渲染 — 文字不缓冲，直接  print()  +  fflush(stdout)  流式输出
│ 2. Spinner 与 Thinking 互斥 — thinking 模式下暂停 spinner，避免同行覆盖
│ 3. TTY drain — 每轮开始前排空键盘缓冲，防止用户打字泄漏到下一行输入
│ 4. 双路输出 —  emitBlock()  统一块输出 (自动规范化换行)， writeToStdout()  用于原始 ANSI
│ 5. Markdown 后处理 — 积累完响应文本后才调用  markdown.render() ，不在流式过程中做转换
│ 6. Tool 结果折叠 —  CollapseDetector  +  CollapsedSummaryFormatter  +  ToolResultCache  实现可展开/折叠的工具结果
│ 
│ 模块依赖方向
│ 
│ ┌─────────────────────────────────────────────────────────────────────────────┐
│ │ SwiftAgentCore (Types, Tools, Agent, LLM)                                   │
│ │   ↑ 被依赖                                                                  │
│ │ SwiftAgentCLI (ChatCommand, TerminalRenderer, LineEditor, MarkdownRenderer) │
│ │   ↑ 不违反 Core/CLI 边界                                                    │
│ │   → CLI 依赖 Core，但 Core 不知道 CLI 的存在                                │
│ └─────────────────────────────────────────────────────────────────────────────┘


------

│ 架构总览
│ ────
│ 
│ ┌────────────────────────────────────────────────────────────────────────────────┐
│ │ SwiftAgentCLI (表示层)                                                         │
│ │   ├── ChatCommand.run()        ← 主 REPL 循环                                  │
│ │   ├── TerminalRenderer         ← ANSI 输出工具                                 │
│ │   ├── MarkdownRenderer         ← Markdown → ANSI（代码块、表格、粗体）         │
│ │   ├── LineEditor               ← raw-mode 行编辑器（历史、粘贴、弹窗）         │
│ │   ├── InlinePopup              ← 自动补全/搜索内联弹窗                         │
│ │   ├── TerminalCapability       ← TTY 检测、颜色支持、终端尺寸                  │
│ │   ├── ColorTheme               ← ANSI 颜色主题（默认/单色）                    │
│ │   └── DebugLogger              ← JSONL 调试日志                                │
│ │                                                                                │
│ │ SwiftAgentCore（数据/协议）                                                    │
│ │   ├── LLMClient                ← HTTP SSE 流调用 Anthropic API                 │
│ │   ├── LLMStreamParser          ← 将 SSE 数据 JSON → StreamEvent 枚举           │
│ │   ├── StreamEvent (enum)       ← textDelta, thinkingDelta, inputJSONDelta, ... │
│ │   ├── StreamRenderer            ← 将 StreamEvent → 终端安全的字符串            │
│ │   └── ContentBlockAccumulator   ← 解析工具调用 JSON 输入                       │
│ └────────────────────────────────────────────────────────────────────────────────┘
│ 
│ 核心渲染管线
│ ──────
│ 
│ SSE 字节 → 字符串 → 终端：
│ 
│ ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ │ HTTP SSE 数据 ─→ LLMStreamParser.parse() ─→ StreamEvent ─→ 内联 switch 语句 ─→ print()                        │
│ │                    （JSON → 枚举）            事件枚举         （位于 ChatCommand         （直接写入 stdout） │
│ │                                                              .run 主循环内部）                                │
│ └───────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
│ 
│ 与 Claude Code 的  StreamRenderer （统一字符串输出）不同，SwiftAgent 直接在  ChatCommand  的事件开关中渲染每种事件类型：
│ 
│ •  textDelta  → 直接  print()  输出（终端同步输出）
│ •  thinkingDelta  → 在  showThinking  打开时以 ANSI 暗色模式渲染
│ •  inputJSONDelta  → 由  ChatToolInputAccumulator  累积
│ •  contentBlockStop  → 完成时解析 JSON 并执行工具
│ 
│ UI 的 Markdown 渲染是分开的，在响应完成后再应用：
│ 
│ ┌────────────────────────────────────────────────────────────────────── swift ┐
│ │ // ChatCommand.swift 第 917-919 行                                   │
│ │ let rendered = noMarkdown                                     │
│ │     ? renderer.renderLeftBorder(content: trimmed)   // 左边框竖线 │
│ │     : markdown.render(trimmed)                      // 完整的 ANSI markdown │
│ └─────────────────────────────────────────────────────────────────────────────┘
│ 
│ 主代理循环（ChatCommand.run）
│ ──────────────────────
│ 
│ ┌────────────────────────────────────────────────────────────────────┐
│ │ ┌─────────────────────────────────────────────────────────┐        │
│ │ │  1. LineEditor.readLine(prompt: "You: ")                 │       │
│ │ │     └─ raw-mode，带历史，支持多行，支持内联弹窗             │    │
│ │ │                                                          │       │
│ │ │  2. 解析：/slash 命令 vs 普通输入                          │     │
│ │ │     /exit, /clear, /expand, /resume, /model 等            │      │
│ │ │                                                          │       │
│ │ │  3. 追加用户消息到对话历史                                 │     │
│ │ │                                                          │       │
│ │ │  4. 转义键监视器（后台任务，轮询 stdin）                    │    │
│ │ │                                                          │       │
│ │ │  5. 旋转指示器（100ms 帧循环，支持暂停）                    │    │
│ │ │                                                          │       │
│ │ │  6. 内部代理循环（最多无限轮次）                            │    │
│ │ │     ┌──────────────────────────────────────┐              │      │
│ │ │     │ LLMClient.send() → AsyncThrowingStream │              │    │
│ │ │     │ for await event in stream:            │              │     │
│ │ │     │   textDelta → print()                 │              │     │
│ │ │     │   thinkingDelta → 暗色流式输出          │              │   │
│ │ │     │   inputJSONDelta → 累积 JSON          │              │     │
│ │ │     │   messageDelta → 解析 usage/stop      │              │     │
│ │ │     │                                       │              │     │
│ │ │     │ 流结束后：                              │              │   │
│ │ │     │   有工具调用？执行 → 发送结果 → 继续循环  │              │ │
│ │ │     │   没有工具调用？完成                     │              │  │
│ │ │     └──────────────────────────────────────┘              │      │
│ │ │                                                          │       │
│ │ │  7. 取消旋转指示器                                        │      │
│ │ │                                                          │       │
│ │ │  8. 渲染最终响应（左边框 / markdown）                      │     │
│ │ │                                                          │       │
│ │ │  9. 显示缓存指标 + 耗时                                   │      │
│ │ │                                                          │       │
│ │ │  10. 持久化会话（用于 /resume）                            │     │
│ │ └─────────────────────────────────────────────────────────┘        │
│ └────────────────────────────────────────────────────────────────────┘
│ 
│ 组件交互
│ ────
│ 
│ ┌─────────────────────────────────────────────────────────┐
│ │ LineEditor.rawModeReadLine()                            │
│ │   ├─ 处理按键（Ctrl+C，回车，退格，Alt+Left 等）        │
│ │   ├─ 内联弹窗（/slash—触发自动补全，内联显示）          │
│ │   │    └─ InlinePopup.render(to:terminalWidth:)         │
│ │   │         └─ TerminalRenderer.write() ← 通过闭包注入  │
│ │   ├─ 粘贴检测 + 摘要化（大型粘贴防抖）                  │
│ │   └─ 带 ANSI 清理+移动+重新绘制的重绘循环               │
│ │                                                         │
│ │ TerminalRenderer                                        │
│ │   ├─ renderBanner() — 欢迎信息框                        │
│ │   ├─ renderPanel() — 完整的 Unicode 面板（标题 + 边框） │
│ │   ├─ renderLeftBorder() — 带 ANSI 色彩的左侧竖线        │
│ │   ├─ renderThinkingLine() — 旋转指示器 + "Thinking..."  │
│ │   ├─ renderDelta() — 流式文本清理                       │
│ │   ├─ drainTTYInput() — 清除杂散按键（tcflush）          │
│ │   └─ 光标控制工具（上/下/保存/恢复）                    │
│ │                                                         │
│ │ MarkdownRenderer（约 760 行）                           │
│ │   ├─ 代码块检测（有/无显式围栏）                        │
│ │   ├─ 通过 tree-sitter 进行语法高亮                      │
│ │   ├─ 表格推理 + 格式化管道                              │
│ │   ├─ 内联格式（粗体、斜体、链接）                       │
│ │   └─ 宽度限制的自动换行                                 │
│ └─────────────────────────────────────────────────────────┘
│ 
│ 关键设计决策
│ ──────
│ 
│ 1. 事件开关是内联的，不在 StreamRenderer 中 — SwiftAgentCore 里有一个  StreamRenderer  结构体，但在 CLI 中并未使用。实际的流式渲染直接发生在  ChatCommand.run()  内部，实现了最大程度的控制。
│ 
│ 2. 旋转指示器与流式渲染同时运行 — 一个并发的  Task  每 100ms 渲染一次旋转指示器帧。流式渲染时， spinnerTask  处于活动状态，第一个  textDelta  在写入文本前清除旋转指示器行。
│ 
│ 3. 原始模式行编辑器 —  LineEditor  使终端进入原始模式（ tcsetattr ），自行处理所有按键。这支持多行缓冲、内联弹窗自动补全，以及为单次按键 / 序列提供不同行为的编辑器状态机。
│ 
│ 4. Markdown 后处理 — 与一些渲染器按块处理不同， MarkdownRenderer  接收的是纯文本，自己检测代码块（自动检测和显式围栏），并生成 ANSI 格式的 markdown 用于最终输出。
│ 
│ 5. TTY 刷新防护 —  drainTTYInput()  在每轮开始时使用  tcflush(STDIN_FILENO, TCIFLUSH)  清除模型生成期间用户意外键入的残留输入。
│ 
│ 6. 转义键取消 — 一个并发的  Task  轮询 stdin，等待单独的 ESC 按键（100ms 超时，从而能检测到不带后续序列的情况）。设置一个  AtomicBool ，供代理循环的每一轮检查。
│ 
│ 文件布局
│ ────
│ 
│ │            文件            │ 行数  │                  职责                   │
│ ├────────────────────────────┼───────┼─────────────────────────────────────────┤
│ │ `ChatCommand.swift`        │ ~1984 │ 主 REPL，代理循环，工具编排，slash 命令 │
│ │ `LineEditor.swift`         │ ~1280 │ 原始模式行编辑，弹窗，粘贴处理          │
│ │ `MarkdownRenderer.swift`   │ ~770  │ Markdown 转 ANSI，代码高亮，表格        │
│ │ `InlinePopup.swift`        │ ~330  │ 内联自动补全弹窗 UI                     │
│ │ `TerminalRenderer.swift`   │ 231   │ ANSI 工具，面板，边框，旋转指示器       │
│ │ `TerminalCapability.swift` │ ~70   │ TTY 检测，颜色支持，终端尺寸            │
│ │ `ColorTheme.swift`         │ ~120  │ ANSI 颜色主题 + 样式                    │
│ │ `DebugLogger.swift`        │ ~130  │ JSONL 调试日志                          │

------

│ SwiftAgent CLI — TUI Architecture
│ ─────────────────────────────────
│ 
│ Overview
│ 
│ The TUI layer lives entirely in  Sources/SwiftAgentCLI/  and has 5 files (plus supporting types). The architecture follows a clean Core ↔ CLI boundary — the Core's  StreamRenderer  converts streaming protocol events into terminal-safe strings, and the CLI layer adds ANSI rendering, markdown formatting, and interactive line editing.
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ Architecture Layers
│ 
│ ┌──────────────────────────────────────────────────────┐
│ │ ┌──────────────────────────────────────────────────┐ │
│ │ │  ChatCommand.run  (main loop, line 201)          │ │
│ │ │  • Agent loop: prompt → stream → render → loop   │ │
│ │ │  • 25 max iterations, tool execution, session    │ │
│ │ │  • Orchestrates all TUI components below         │ │
│ │ └─────┬──────────────┬───────────────┬─────────────┘ │
│ │       │              │               │               │
│ │       ▼              ▼               ▼               │
│ │ ┌──────────┐ ┌──────────────┐ ┌────────────────┐     │
│ │ │LineEditor│ │TerminalRend. │ │MarkdownRend.   │     │
│ │ │(input)   │ │(ANSI output) │ │(rich text)     │     │
│ │ └──────────┘ └──────┬───────┘ └────────────────┘     │
│ │                     │                                │
│ │                     ▼                                │
│ │            ┌────────────────┐                        │
│ │            │TerminalCapability│                      │
│ │            │(TTY/color/size) │                       │
│ │            └────────────────┘                        │
│ └──────────────────────────────────────────────────────┘
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ Component Breakdown
│ 
│ 1. `ChatCommand` (`ChatCommand.swift:164`) — Main Loop
│ • 28 methods,  run()  is 750 lines
│ • Sets up all dependencies at startup:  TerminalCapability ,  TerminalRenderer ,  MarkdownRenderer ,  LineEditor ,  LLMClient ,  ToolRegistry 
│ • Main loop: reads input via  LineEditor.readLine  → streams LLM events → renders via  MarkdownRenderer.render  → formats tool calls with  TerminalRenderer.renderPanel  → executes tools
│ • Handles: banner, status lines, tool result display, session save/load,  /command  dispatch
│ 
│ 2. `TerminalRenderer` (`TerminalRenderer.swift:6`) — ANSI Output
│ • 16 methods for terminal drawing:
│   •  renderBanner()  — welcome box with version
│   •  renderPanel()  — full bordered panel (top/left/right/bottom using Unicode box-drawing chars:  ╭─╮│╰╯ )
│   •  renderLeftBorder()  — simple  │   left border (used for AI responses)
│   •  renderDelta()  — incremental text output during streaming
│   •  spinnerFrame()  — Braille dots spinner ( ⠋⠙⠹⠸... )
│   • Cursor control:  saveCursor() ,  restoreCursor() ,  cursorUp() ,  cursorDown() ,  clearScreen() 
│   •  renderStatusLine()  — token usage + "Working..." state
│ 
│ 3. `LineEditor` (`LineEditor.swift:36`) — Raw-mode Input
│ • 39 methods, ~1300 lines
│ •  readLine(prompt:)  →  rawModeReadLine()  (TTY) or  fallbackReadLine()  (non-TTY)
│ • Raw mode with  termios  manipulation:  enterRawMode() ,  restoreTerminal() 
│ • Handles: cursor movement, history navigation, escape sequences, bracketed paste, UTF-8 decoding, popup completion
│ • Paste burst detection:  handlePaste() ,  replaceBufferWithPasteSummary() ,  expandPastePlaceholders() 
│ 
│ 4. `MarkdownRenderer` (`MarkdownRenderer.swift:7`) — Rich Text
│ • 18 methods for markdown-to-ANSI conversion
│ • Auto-detects code blocks (indentation or fenced), syntax highlighting via  TreeSitterSyntaxHighlighter 
│ • Styles: bold, italic, dim, inline code, link rendering
│ • Code classification:  classifyLine() ,  classifyBlock() ,  looksLikeCodeLine()  via keyword density heuristics
│ 
│ 5. `TerminalCapability` (`TerminalCapability.swift:4`) — Environment Detection
│ • Detects TTY, color support ( detectColorSupport() ), terminal dimensions ( detectSize() )
│ •  color()  — guards ANSI output with  supportsColor 
│ •  scrubANSICodes()  — strips ANSI escapes for pipe/non-TTY output (critical for  --print /CI mode)
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ Key TUI Flows
│ 
│ Input flow:  ChatCommand.run  →  LineEditor.readLine  →  rawModeReadLine  (raw termios loop) → returns string
│ 
│ Output flow (streaming):  LLMClient.stream  →  StreamRenderer.render  (Core) → text accumulates →  MarkdownRenderer.render  (post-process) →  TerminalRenderer.renderLeftBorder  →  emitBlock  (print to stdout)
│ 
│ Tool display: tool results →  TerminalRenderer.renderPanel  (bordered) → collapse detection for long output
│ 
│ ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
│ 
│ Design Decisions & Gaps
│ 
│ │          Aspect          │                  Current State                   │                                     Notes                                     │
│ ├──────────────────────────┼──────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────┤
│ │ **CLAUDE.md mentions**   │ Composer separation not done                     │ God-file risk in `ChatCommand` (750+ line `run()`)                            │
│ │ **Spinner**              │ Simple `spinnerFrame()` + `renderThinkingLine()` │ No status-line recovery from partial renders                                  │
│ │ **Streaming robustness** │ `renderDelta` appends raw                        │ Flicker risk noted in CLAUDE.md directions                                    │
│ │ **Paste handling**       │ Bracketed paste + burst detection                │ Good — CC parity                                                              │
│ │ **Non-TTY mode**         │ `scrubANSICodes` on all output                   │ CC parity for CI/script-friendly output                                       │
│ │ **Popup/slash**          │ `LineEditor` has popup infrastructure            │ Slash commands are string switches in `handleCommand`, not typed metadata yet │
│ 
│ The CLAUDE.md explicitly flags  ChatCommand ,  TerminalRenderer , and  LineEditor  as targets for decomposition — particularly the 750-line  run()  method and the rendering pipeline that needs better flicker avoidance and status-line recovery.

------



