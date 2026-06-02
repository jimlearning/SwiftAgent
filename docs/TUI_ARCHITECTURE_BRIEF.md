# SwiftAgent TUI 架构（简）

## 总览

纯 Swift + ANSI 转义序列的终端 UI，零外部 TUI 框架依赖（无 ncurses/TermKit）。采用 Nanobot REPL 模式，所有代码位于 `Sources/SwiftAgentCLI/`（~22 文件，~4000 行）。

## 分层架构

```
ChatCommand.run()              ← REPL 主循环 + 内联 agent 循环（1799 行）
  ├── LineEditor               ← raw-mode 输入（1288 行）
  │     └── InlinePopup        ← / 命令补全 + @ 文件补全 + 子菜单
  ├── TerminalRenderer         ← ANSI 输出基元（panel/banner/spinner/光标）
  ├── MarkdownRenderer         ← Markdown → ANSI + 语法高亮
  ├── StatusLine               ← 底部反向视频状态栏
  ├── CurrentToolTracker       ← 线程安全工具状态（NSLock）
  ├── ChatToolInputAccumulator ← 流式 JSON 累积 + 解析
  ├── ChatToolExecutionScheduler ← 并行/串行工具调度（TaskGroup）
  ├── CollapseDetector         ← 工具结果可折叠判定 + 分组合并
  ├── ToolResultCache          ← 折叠结果缓存（供 Ctrl+O / /expand 展开）
  └── StreamRenderer (Core)    ← Core 层：StreamEvent → 纯文本（无 ANSI）
```

基础设施：`TerminalCapability`（TTY/色彩/尺寸检测）、`ColorTheme` / `ANSIColor` / `ANIStyle`（语义调色板 + 16/256/真彩色）、`TerminalDisplayWidth`（CJK/Emoji 宽度计算）。

## 初始化流程

```
1. 保存 termios 原始状态     → 供 Cooked-mode 恢复
2. 解析 API Key              → 环境变量 / keychain / ~/.claude.json
3. 创建 TerminalCapability   → 检测 TTY、色彩、尺寸
4. 选择 ColorTheme           → --no-color ? monochrome : default
5. 创建 TerminalRenderer     → 注入 capability + theme
6. 创建 MarkdownRenderer     → 注入 capability + theme + TreeSitter 高亮
7. 渲染 Banner               → Unicode 框线欢迎横幅
8. 注册 43 个内置工具        → + MCP Bootstrap 工具
9. 构建 SystemPrompt         → 一次性构建，利用 prompt caching
10. 创建 LineEditor          → 注入 / 命令和 @ 文件 popup 数据源
11. 进入 REPL 循环
```

## 核心组件

### LineEditor — Raw Mode 行编辑器

通过 `termios` raw mode（ICANON/ECHO/ISIG 全关）逐字节读取：

- **编辑**：←→ 光标、↑↓ 历史/行间移动、Alt+←→ 按字母数字边界跳词、Ctrl+A/E 首尾、Home/End、Ctrl+W 删词（空格边界）、Alt+Backspace 删词（字母数字边界）、Ctrl+K 删至尾、Ctrl+U 清行
- **换行**：Alt+Enter / Shift+Enter 插入 `\n`（Shift 通过 `CGEventSource.flagsState(.hidSystemState)` 的 HID API 检测）
- **历史**：`\0` 分隔多行条目，500 条上限，stashedBuffer 机制（bash/zsh 风格：浏览历史后按 ↓ 恢复原输入），持久化到 `~/.swift-agent/history/cli_history`
- **Escape 解析**：CSI（`ESC[`）、SS3（`ESC O`）、Kitty protocol（`CSI key;mods u`）、xterm modified keys、bracketed paste（`ESC[200~...ESC[201~`）
- **Paste**：50ms burst 检测，单行直接插入，多行显示 `[Pasted text #N +M lines]` 占位符
- **Ghost text**：命令参数提示以 dim (`\033[90m`) 样式显示在光标后，用户输入时自动清除
- **重绘**：`lastCursorRow` 跟踪 → `\033[N A` → `\r\033[J` 清至屏尾 → 重绘 prompt + buffer → ghost text → popup → 精确定位光标。用显式 cursor-up 而非 save/restore（跨终端确定性）

### InlinePopup — 内联补全

```
╭ /mod ─────────────────────────────────╮
│ ↑ 3 more                              │  ← 滚动指示
│ ▸ /model          Change model        │  ← 选中行（reverse video + ▸）
│   /doctor         Diagnose install    │
│ ↓ 15 more                             │  ← 滚动指示
╰───────────────────────────────────────╯
```

- `/` → `CommandDataSource`（28+ 内置命令 + skills）+ 模糊匹配（精确 1.0 / 前缀 0.9 / 子串 0.7 / 有序子序列 ~0.5）
- `@` → `FileDataSource` + `FileSearchIndex`（基于 git ls-files 的内存索引，搜索时零磁盘 I/O）
- `argumentHint` → 选中后显示幽灵参数提示；`subOptions` → 自动打开二级参数值菜单（如 `/model` → 模型列表）；`subDataSource` → 动态子菜单（如 `/resume` → 会话列表）；`submitOnSelect` → 选中即提交
- 选中高亮：匹配位置黄色加粗 + 选中行反转视频 + `▸ ` 指示器

### TerminalRenderer — ANSI 输出

| 方法                  | 用途                          |
|-----------------------|-------------------------------|
| `renderBanner`        | 欢迎横幅（`┌───┐`）           |
| `renderPanel`         | 静态内容完整框线（`╭──╮`）    |
| `renderLeftBorder`    | AI 响应 `│ ` 竖线（流式避免闪烁）|
| `renderThinkingLine`  | `⠋ Thinking...`              |
| `renderStatusLine`    | 反向视频状态栏（全宽）        |
| `spinnerFrame`        | Braille 单帧（⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏） |
| `renderPermissionPrompt` | `[y]es / [n]o / [a]lways` |
| `drainTTYInput`       | `tcflush(TCIFLUSH)` 清空键盘缓冲 |

### REPL 关键机制

- **Spinner**：独立 `Task` 100ms 帧，智能暂停——`SpinnerPauseFlag`（AskUserQuestion 交互时）+ `currentTool.isThinking`（思考文本渲染时）。1 工具显示 `Running X`，多工具显示 `N tools running | X; Y`
- **ESC 中断**：后台 Task `poll()` + `read()` 监听裸 ESC（50ms 超时消歧），设置 `AtomicBool`。LLM 每轮前和每个事件后检查
- **Cooked-mode 切换**：启动前保存 `termios`，用户提问时 cancel watcher → 等 150ms 退出 → 恢复 cooked → 完成后重启 watcher + raw
- **工具结果折叠**：`CollapseDetector` 判定可折叠性（Read/Glob/Grep/搜索 Bash）→ `CollapsedSummaryFormatter` 单行摘要 → `ToolResultCache` 缓存完整输出 → `Ctrl+O` / `/expand N` 切换展开/折叠，通过 `\033[nA\033[0J` 内联替换
- **截断恢复**：`stop_reason == "max_tokens"` 时执行已解析的 tool calls → 注入 `"[system] Continue..."` → 继续循环

## 数据流

```
LineEditor.readLine("You: ") → /slash? → 命令分发 or LLM 请求
  → LLMClient.send() SSE 流 → 事件分发:
      ├─ textDelta      → print()+fflush 实时输出（无缓冲），累积到 turnText
      ├─ thinkingDelta  → dim 模式渲染（showThinking），累积到 thinkingText
      ├─ contentBlockStart(.toolUse) → toolInputAccumulator.startTool()
      ├─ inputJSONDelta → 累积 JSON 片段到 accumulator
      └─ contentBlockStop → 解析 tool call → ToolExecutor.execute()
  → 无 tool calls → end_turn → MarkdownRenderer.render() → emitBlock()
  → 有 tool calls → emitCollapsedResults() → 结果追加到历史 → 继续循环
```

## 关键设计决策

| 决策                           | 理由                                              |
|--------------------------------|---------------------------------------------------|
| 零依赖 ANSI 而非 ncurses/TermKit | 可移植性、精确流式控制、CC 对齐                   |
| cursor-up 显式定位而非 save/restore | `\033[s`/`\033[u` 跨终端不一致                     |
| 独立 spinner Task              | 流式 burst 时仍保持动画流畅；智能暂停              |
| `\0` 分隔历史                  | 支持多行条目（粘贴的代码块不会拆成 N 个独立条目） |
| ESC 超时消歧 (~50ms)           | 区分裸 ESC 键与方向键序列 (`\033[`)                |
| Panel vs LeftBorder 分离       | panel 用静态内容，left border 用流式输出（避免闪烁）|
| Core/CLI 边界                  | StreamRenderer (Core) 纯文本，TerminalRenderer (CLI) ANSI |
| Bracket paste 协议             | 完整捕获整个粘贴，避免多行被拆成多次 readLine      |
| Kitty protocol 前向兼容        | 已实现 CSI u 解析，支持 Shift+Enter/Alt+Backspace  |
| Markdown 后处理                | 积累完整响应后一次性渲染，代码块自动检测           |
| 双路输出                       | `emitBlock()` 块输出 + `writeToStdout()` 原始 ANSI |

## 模块清单

| 层         | 文件                                                                                              |
|------------|---------------------------------------------------------------------------------------------------|
| **输入**   | `LineEditor`(1288行)、`InlinePopup`(330行)、`PopupDataSource`(500行)、`FuzzyMatcher`、`FileSearchIndex` |
| **输出**   | `TerminalRenderer`(232行)、`MarkdownRenderer`(780行)、`StatusLine`、`StreamRenderer`(Core,100行)    |
| **语法高亮** | `SyntaxHighlighter`(400行)、`TokenANSIRenderer`(100行)、`CodeTheme`、`LanguageRegistry`              |
| **编排**   | `ChatCommand`(1799行)、`ChatToolInputAccumulator`、`ChatToolExecutionScheduler`、`CurrentToolTracker`、`CollapseDetector`、`CollapsedSummaryFormatter`、`ToolResultCache` |
| **基础设施** | `TerminalCapability`(62行)、`TerminalDisplayWidth`(105行)、`ColorTheme`(116行)、`DebugLogger`(198行)  |

## 改进清单

| 优先级 | 问题                                                      |
|--------|-----------------------------------------------------------|
| **P0** | `ChatCommand`(1799行) 含全部 agent loop/工具/渲染，需拆分 |
|        | `LineEditor`(1288行) 应拆为 Readline/Paste/Popup/History  |
| **P1** | InlinePopup/LineEditor 中 ANSI 硬编码，未通过 ColorTheme   |
|        | `StreamRenderer.highlightCodeBlocks` 未使用，高亮集成待完善 |
|        | 无终端 resize 信号处理（popup 宽度不动态更新）            |
|        | `showThinking` 逻辑分散在 3 处 switch case                |
| **P2** | Unicode 宽度覆盖硬编码，不覆盖所有 Unicode 版本           |
|        | `writeToStdout` 跨并发 Task 无线程安全保护                |
|        | Popup 仅 `/` 和 `@`，CC 还有内联诊断/别名建议等           |
|        | Markdown 渲染器不流式传输，等待完整响应                   |
|        | 无 Vim 模式；无终端能力协商（缺 terminfo/DA 查询）        |
