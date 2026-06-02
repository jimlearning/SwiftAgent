# SwiftAgent TUI — ANSI 绘制与更新策略

## 概述

SwiftAgent 不使用全屏 framebuffer、不实现 diff 引擎。所有终端更新通过直接的 ANSI 转义序列完成，不同场景使用不同的更新策略。三种终端交互模式共存：

| 模式 | 机制 | 使用场景 |
|------|------|----------|
| **原地覆盖** | `\r\033[K` 单行覆盖 | Spinner 帧更新 |
| **区域清除+重绘** | `\033[N A` + `\033[J` 清除 + 重写 | 输入行、Popup、折叠/展开 |
| **纯追加** | `print()` + `fflush()` 无任何 ANSI 控制 | 流式 LLM 输出、AI 响应、工具结果 |

不存在"全屏重绘"——最大清除范围是从输入区起始行到屏尾 (`\033[J`)，上方积累的对话历史完全不动。

---

## 1. 核心 ANSI 原语

### 1.1 光标控制

| 序列 | 效果 | 使用位置 |
|------|------|----------|
| `\033[N A` | 光标上移 N 行 | `LineEditor.redrawLine` — 移到输入区顶部 |
| `\033[N B` | 光标下移 N 行 | `LineEditor.redrawLine` — 移到 popup 渲染起始行 |
| `\033[N C` | 光标前移 N 列 | `LineEditor.redrawLine` — 定位到插入列 |
| `\r` | 回车（至列 0） | 所有行首定位 |

### 1.2 擦除

| 序列 | 效果 | 清除范围 |
|------|------|----------|
| `\033[K` | 清至行尾 | 仅当前行，从光标到行尾 |
| `\033[J` | 清至屏尾 | 从光标行到屏幕最底部 |
| `\033[2J` | 清全屏 | 整个屏幕（仅 `/clear` 命令使用） |
| `\033[0J` | 清至屏尾 | 同 `\033[J`，显式参数形式（折叠/展开使用） |

### 1.3 样式

| 序列 | 效果 |
|------|------|
| `\033[0m` | 重置所有属性 |
| `\033[1m` | 加粗 |
| `\033[2m` | 变暗 (dim) |
| `\033[7m` | 反转视频（前景/背景交换） |
| `\033[1;34m` | 加粗 + 蓝色（组合） |
| `\033[38;2;R;G;Bm` | 24-bit TrueColor 前景色 |
| `\033[90m` | 亮黑色 (bright black) |

### 1.4 终端协议

| 序列 | 效果 |
|------|------|
| `\033[?2004h` | 启用 bracketed paste 模式 |
| `\033[?2004l` | 禁用 bracketed paste 模式 |
| `\033[200~` | Paste 内容开始标记 |
| `\033[201~` | Paste 内容结束标记 |

---

## 2. 五种更新模式（源码证据）

### 模式 A：单行原地覆盖 — Spinner

**位置**：`ChatCommand.swift:627-633` (原版，现位于内联 agent 循环中)

```
时序：每 100ms 一帧，同一条终端行上覆盖

帧 N:   \r\033[K  ⠋ Thinking...
帧 N+1: \r\033[K  ⠙ Thinking...
帧 N+2: \r\033[K  ⠹ Thinking...
取消:   \r\033[K  (空行)
```

```swift
let line = "\r\u{001B}[K  \(renderer.spinnerFrame(index: frame)) \(display)"
print(line, terminator: "")
fflush(stdout)
```

**机制**：
1. `\r` — 回到行首
2. `\033[K` — 清除当前行（从列 0 到行尾）
3. 写入新帧内容
4. `fflush()` — 强制立即输出（`print` 默认行缓冲）

**开销**：每次 1 行写入。不碰任何其他行。

### 模式 B：输入区域边界重绘 — LineEditor

**位置**：`EditorRenderer.redraw()` (原 `LineEditor.redrawLine()`, L992-1074)。已重构至 `EditorRenderer.swift`。

这是 SwiftAgent 中最复杂的更新路径。每次按键后触发。

```
初始状态（对话历史上方，spinner 下方）：
  [历史输出...]
  You: hel█                         ← lastCursorRow = 5 (当前光标在此行)

用户按 'l' 后:
  步骤 1: \033[5A                    ← 光标上移 5 行到输入区起始行
  步骤 2: \r\033[J                   ← 回车 + 从该行清至屏尾
  步骤 3: 写入 "You: hell"           ← 重绘 prompt + 全部 buffer
  步骤 4: (无 ghost text, 无 popup)  ← 跳过
  步骤 5: \033[4A\r\033[6C           ← 光标定位到 'l' 后面
  步骤 6: drawnLines=2, lastCursorRow=5

结果：
  [历史输出...]
  You: hell█
```

**关键优化 — `lastCursorRow` 追踪**：

```swift
// 只在必要时上移——不到最顶部
if lastCursorRow > 0 {
    writeToStdout("\u{001B}[\(lastCursorRow)A")  // 精确 N 行
}
writeToStdout("\r\u{001B}[J")  // 从该行清至屏尾
```

不是盲目上移到 `drawnLines - 1`，而是用 `lastCursorRow`（光标上次所在的行号）。如果光标就在输入区第一行，上移 0 行——零开销。

**多行缓冲区的情况**：

```
You: line1
     line2█                         ← cursorPos 在第二行

重绘：
  \033[lastCursorRow A              → 上移到 "You: " 行
  \r\033[J                          → 清至屏尾
  写入 "You: line1"                 → 第一行
  \r\n + "     line2"               → 续行（与 prompt 对齐缩进）
  \033[1A\r\033[11C                 → 光标到 line2 的插入位置
```

**垂直布局计算**（`renderedRows()` + `cursorPosition()`）：

```swift
// 计算 buffer 占用的总终端行数（含自动换行）
private func renderedRows(promptWidth: Int, lines: [String]) -> Int {
    lines.reduce(0) { total, line in
        let width = promptWidth + TerminalDisplayWidth.width(line)
        return total + TerminalDisplayWidth.rows(forWidth: width, columns: terminalColumns)
    }
}

// offset → (row, column) 映射
private func cursorPosition(promptWidth: Int, prefix: String) -> (row: Int, column: Int) {
    let prefixLines = prefix.components(separatedBy: "\n")
    var row = 0
    for line in prefixLines.dropLast() {
        row += TerminalDisplayWidth.rows(forWidth: promptWidth + width(line), columns: cols)
    }
    let currentLine = prefixLines.last ?? ""
    let offset = promptWidth + TerminalDisplayWidth.width(currentLine)
    let position = TerminalDisplayWidth.cursorPosition(forOffset: offset, columns: cols)
    return (row + position.row, position.column)
}
```

**Ghost Text 渲染**（`EditorRenderer.redraw()`, 原 `LineEditor.swift:1029-1042`）：

选中 `/model` 后，`[model-name]` 以 dim 样式显示在光标后：

```
You: /model [model-name]█
              ↑ dim 样式幽灵文本
```

```swift
if let gt = ghostText, editorMode.isPopup == false {
    writeToStdout("\u{001B}[2m")        // dim
    writeToStdout("\u{001B}[90m")       // bright black
    writeToStdout(gt)                   // "[model-name]"
    writeToStdout("\u{001B}[0m")        // reset
    writeToStdout("\r")                 // 回到行首
    writeToStdout("\u{001B}[\(col)C")   // 移回插入位置
}
```

注意这里用 `\r` + `\033[N C` 将光标恢复到插入位置——幽灵文本被"跳过"但留在屏幕上。用户继续输入时，幽灵文本被实际字符自然覆盖。

### 模式 C：Popup 区域全量重绘 — InlinePopup

**位置**：`InlinePopup.swift:187-329`，由 `ComposerState.renderPopup()` 调用

```
You: /mod█
╭ /mod ─────────────────────────────────╮   ← popupStartRow
│ ↑ 3 more                              │
│ ▸ /model          Change model        │
│   /doctor         Diagnose install    │
│ ↓ 15 more                             │
╰───────────────────────────────────────╯
  (光标回到 "You: /mod█")
```

每次重绘整个 popup——所有边框、所有可见项目、滚动指示器、颜色。无 diff 对比。

**渲染流程**：
1. 从输入区末尾下移到 popup 区域：`\033[downToEnd B` + `\r\n`
2. 写顶部边框：`╭ <query> ───╮`
3. 若有向上滚动：写 `│ ↑ N more │`
4. 遍历 `scrollOffset..<endIndex` 的每个可见 item：
   - 左边框 `│`（dim cyan）
   - `▸ ` 选中指示器（若 selected）
   - 反转视频（若 selected）
   - 匹配位置黄色加粗高亮
   - 剩余空间 padding
   - 右侧 help 文本（dim）
5. 若有向下滚动：写 `│ ↓ N more │`
6. 写底部边框：`╰───╯`
7. 光标恢复：`\033[rowsUp A` + `\r` + `\033[col C` 回到插入位置

**为 popup 内容进行精确的光标恢复**：

```swift
// 不使用 \033[s / \033[u（跨终端不一致），而是显式计算
let rowsAfterPopup = popupStartRow + popupHeight
let rowsUp = rowsAfterPopup - target.row
if rowsUp > 0 { writeToStdout("\u{001B}[\(rowsUp)A") }
writeToStdout("\r")
if target.column > 0 { writeToStdout("\u{001B}[\(target.column)C") }
```

**视口管理**：`updateScroll()` (L151-163) 确保选中项始终在可见窗口内：

```swift
private mutating func updateScroll() {
    let visible = maxVisibleItems
    if selectedIndex < scrollOffset {
        scrollOffset = selectedIndex
    } else if selectedIndex >= scrollOffset + visible {
        scrollOffset = selectedIndex - visible + 1
    }
    scrollOffset = max(0, min(scrollOffset, max(0, items.count - visible)))
}
```

### 模式 D：纯追加（流式输出）— 零 ANSI 控制

**位置**：`ChatCommand.swift` 内联 agent 循环 (原 L674-746，现位于 `run()` 方法的流式处理循环中)

LLM 文本 delta 直接 `print()` 输出：

```
事件到达:
  .textDelta("Hello")   → print("Hello", terminator: "") + fflush()
  .textDelta(", world")  → print(", world", terminator: "") + fflush()
  .textDelta("!")        → print("!", terminator: "") + fflush()
```

**零 ANSI 转义序列**。文本直接追加到终端滚动缓冲区。这是绝对最高效的路径。

**Thinking delta** 略有不同——切换模式时需清除 spinner 行：

```swift
case .textDelta(let text):
    // thinking→text 切换：结束 dim 模式
    if showThinking {
        print("\u{001B}[0m\n")          // reset + 换行
    } else {
        print("\r\u{001B}[K", terminator: "")  // 清除 spinner 行
    }
    // 之后纯追加
    turnText += text

case .thinkingDelta(let text):
    if showThinking {
        if thinkingText == text {  // 首个 delta
            print("\r\u{001B}[K  \u{001B}[2m\(text)", terminator: "")
            //     清除spinner → 缩进 → 开始 dim 模式
        } else {
            print(text, terminator: "")  // 后续纯追加
        }
        fflush(stdout)
    }
```

**Markdown 后处理**：完整响应积累后，调用 `MarkdownRenderer.render()` 一次性生成 ANSI 字符串，然后 `emitBlock()` 输出。这是终端追加——不覆盖任何现有内容。

### 模式 E：区域清除 + 重绘 — 工具结果折叠/展开

**位置**：`ChatCommand.swift:1122-1164` (原版，现位于 `ChatCommand+ToolDisplay.swift` 中 `handleCtrlO` / `collapseExpandedOutput`)

**折叠**（Ctrl+O 在已展开状态下）：
```
步骤 1: \033[N+1 A              → 上移到展开内容顶部
步骤 2: \033[0J                 → 从该行清至屏尾
结果:    展开的 N 行内容被精确移除，不留残影
```

```swift
private func collapseExpandedOutput() {
    guard expandState.expandedLineCount > 0 else { return }
    let n = expandState.expandedLineCount
    writeToStdout("\u{001B}[\(n + 1)A")  // n 行内容 + 1 行 \r\n 偏移
    writeToStdout("\u{001B}[0J")         // 清至屏尾
    expandState.expandedGroupIndex = nil
    expandState.expandedLineCount = 0
}
```

**展开**（Ctrl+O 在无展开状态下）：
```
步骤 1: \033[clearLinesAbove A  → 上移到插入点
步骤 2: \033[0J                 → 清至屏尾
步骤 3: emitBlock(expanded)     → 打印完整展开内容（append）
```

`ExpandState` 跟踪展开的 group 索引和行数——用于折叠时精确清除。

---

## 3. 为什么不使用 `\033[s` / `\033[u`（Save/Restore Cursor）

SwiftAgent 代码中 **不使用** `saveCursor()` / `restoreCursor()` 进行重绘定位。原因：

> `\033[s` / `\033[u` 在滚动区域内行为不一致。某些终端模拟器在屏幕内容滚动后会将保存的位置作废。显式 `\033[N A` 移动是确定性的。

代价是 `LineEditor` 必须自行追踪 `drawnLines` 和 `lastCursorRow` 以计算正确的上移距离。

这两种方法仅在 `TerminalRenderer` 中保留，供外部调用者选择性使用的便捷方法。

---

## 4. 并发写入与线程安全

多条路径可以同时写入 stdout：

```
Spinner Task (100ms) ────┐
                          ├──→ Darwin.write(STDOUT_FILENO, ...)
Stream handler Task ──────┘
```

**当前状态：无互斥锁保护**。`writeToStdout()` 是原始 `Darwin.write()` 调用。如果两个 Task 交错写入，ANSI 序列可能会碎片化。

**实际缓解措施**：
1. Spinner 在流式文本到达时立即暂停（`currentTool.isThinking`）
2. Spinner 在用户交互提示时暂停（`SpinnerPauseFlag`）
3. 大多数路径使用 `print()`（Foundation 内部对其有缓冲保护）
4. 仅 `writeToStdout()`（用于原始 ANSI 控制）存在风险

在 P2 改进清单中，这是已知问题。

---

## 5. 与 Claude Code / Codex CLI 的更新策略对比

```
                 SwiftAgent              Claude Code              Codex CLI
                 ──────────              ───────────              ─────────
屏幕模型:        无（即时模式）          双缓冲 Screen            双缓冲 Buffer
                (2D 字符网格)          (2D 字符网格)

帧更新:         直接写入终端             Reconciler →            Widgets →
                                        DOM diff →              diff_buffers() →
                                        ANSI patch              DrawCommand → ANSI

输入行:         边界全量重绘             React 状态 →            Widget 状态 →
                (1-3行)                 diff → 仅变单元格        diff → 仅变单元格

Spinner:        单行覆盖                 React 组件 →            Shimmer 动画 →
                (\r\033[K)              diff → 仅变单元格        32ms 帧调度

Popup:          区域全量重绘             React fuzzy picker      自定义 widget →
                (≤12行)                 组件 → diff              diff → 仅变单元格

流式输出:       纯追加                  纯追加 +                 纯追加 +
                (相同)                  提交动画队列             表格暂缓

Diff 代码:      0 行                    ~3000+ 行                ~2000+ 行
                (reconciler +           (diff_buffers +
                 log-update 规则)        ClearToEnd 优化)
```

**核心权衡**：

SwiftAgent 的策略选择了"渲染面积小"这个事实来换取极简实现。popup 最多 12 行、输入行通常 1-3 行——全量重绘这些区域的实际开销与 diff 后仅写变化单元格相比，差异在人类感知阈值以下。代价是如果未来需要更大的面板（如 30+ 行的文件浏览器），会出现可见的闪烁。

Claude Code 和 Codex CLI 的 diff 引擎是通用解决方案——无论渲染面积多大都能保证最优写入量。代价是数千行 diff 代码和调试复杂性。

---

## 6. 性能特征

| 操作 | 写入字节数（典型） | 触发频率 | 瓶颈 |
|------|-------------------|----------|------|
| 按键 → 重绘输入 | ~50-200 字节 | ~10 Hz（打字速度） | 无（远低于终端带宽） |
| Spinner 帧 | ~30 字节 | 10 Hz | 无 |
| 流式文本 delta | ~1-100 字节 | ~50-200 Hz（burst） | `fflush()` 系统调用 |
| Popup 重绘 | ~500-2000 字节 | ~10 Hz（打字搜索时） | 无 |
| 折叠/展开 | ~100-5000 字节 | 偶尔 | 无 |

终端的典型吞吐量在 MB/s 级别——这些数字对其来说完全微不足道。真正的延迟来源是 **网络 I/O**（LLM API 调用），而非终端渲染。
