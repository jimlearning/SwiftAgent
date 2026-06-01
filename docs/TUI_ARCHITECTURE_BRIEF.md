# SwiftAgent TUI 架构（简）

## 总览

纯 Swift + ANSI 转义序列的终端 UI，零外部 TUI 框架依赖。采用 Nanobot REPL 模式。

## 分层

```
ChatCommand.run()         ← REPL 主循环 + 内联 agent 循环
  ├── LineEditor          ← raw-mode 输入（1288 行，项目最复杂单文件）
  │     └── InlinePopup   ← / 命令补全 + @ 文件补全
  ├── TerminalRenderer    ← ANSI 输出（panel/banner/spinner/状态栏）
  ├── MarkdownRenderer    ← Markdown → ANSI + 语法高亮
  └── StreamRenderer      ← Core 层：StreamEvent → 终端字符串
```

基础设施：`TerminalCapability`（TTY/色彩检测）、`ColorTheme`（语义调色板）、`TerminalDisplayWidth`（CJK/Emoji 宽度计算）。

## 核心组件

### LineEditor — Raw Mode 行编辑器

通过 `termios` raw mode 逐字节读取 stdin：

- **键盘绑定**：←→ 光标、↑↓ 历史/行间移动、Alt+←→ 跳词、Ctrl+A/E 首尾、Ctrl+W 删词、Ctrl+K 删至尾、Ctrl+U 清行、Alt+Enter/Shift+Enter 插入换行
- **历史**：`\0` 分隔多行条目，stashedBuffer 机制（bash 风格），500 条上限
- **Escape 解析**：CSI、SS3、Kitty protocol、xterm modified keys、bracket paste
- **Paste 处理**：50ms burst 检测，多行粘贴显示占位符
- **重绘**：cursor-up 定位 + `\r\033[J` 清除 + 重绘 buffer → popup → 恢复光标

### InlinePopup — 内联补全

```
╭ /mod ──────────────╮
│ ▸ /model  Change.. │  ← reverse video 选中
│   /doctor Diagnose │
╰────────────────────╯
```

- `/` → `CommandDataSource`（28+ 内置命令 + skills）
- `@` → `FileDataSource` + `FileSearchIndex`
- 四级模糊匹配（精确 1.0 / 前缀 0.9 / 子串 0.7 / 子序列 ~0.5）
- 支持 sub-menu 链式展开（`/model` → 参数值列表）

### TerminalRenderer — ANSI 输出

| 方法 | 用途 |
|------|------|
| `renderBanner` | 欢迎横幅 |
| `renderLeftBorder` | AI 响应 `│ ` 竖线 |
| `renderPanel` | 静态内容完整框线 |
| `renderThinkingLine` | Braille spinner `⠋` |
| `renderStatusLine` | 反向视频状态栏 |
| `drainTTYInput` | 清空键盘缓冲 |

### REPL 循环关键机制

- **Spinner**：独立 Task 100ms 间隔，智能暂停（用户提问/思考文本时）
- **ESC 中断**：后台 Task `poll()` + `read()` 监听裸 ESC，设置 AtomicBool
- **Cooked-mode 切换**：启动前保存 termios，用户交互时恢复，完成后切回 raw

## 数据流

```
readLine → 命令路由(/)? → LLM stream → 事件分发
  ├─ textDelta     → print() 实时输出
  ├─ thinkingDelta → dim 模式渲染
  ├─ toolUse       → ChatToolInputAccumulator 累积 JSON
  └─ messageStop   → ToolExecutor 执行 → 结果追加 → 循环 or 跳出
```

## 关键设计决策

| 决策 | 理由 |
|------|------|
| 零依赖 ANSI 而非 ncurses | 可移植性、精确控制、CC 对齐 |
| cursor-up 而非 save/restore | 跨终端确定性 |
| 独立 spinner Task | 流式 burst 时仍保持动画流畅 |
| `\0` 分隔历史 | 支持多行条目 |
| ESC 超时消歧 (~5ms) | 区分裸 ESC 与方向键序列 |

## 模块清单

**输入**：`LineEditor`、`InlinePopup`、`PopupDataSource`、`FuzzyMatcher`
**输出**：`TerminalRenderer`、`MarkdownRenderer`、`StatusLine`、`StreamRenderer`(Core)
**基础设施**：`TerminalCapability`、`TerminalDisplayWidth`、`ColorTheme`、`DebugLogger`
**编排**：`ChatCommand`、`ChatToolInputAccumulator`、`ChatToolExecutionScheduler`、`CurrentToolTracker`、`CollapseDetector`、`ToolResultCache`
**语法高亮**：`SyntaxHighlighter`、`TokenANSIRenderer`、`CodeTheme`、`LanguageRegistry`

## 主要改进点

- **P0**：`ChatCommand`(1799行) 和 `LineEditor`(1288行) 过长，需拆分
- **P1**：InlinePopup/LineEditor 中 ANSI 硬编码，未通过 ColorTheme
- **P2**：无 SIGWINCH 响应；`showThinking` 逻辑分散
