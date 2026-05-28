# SwiftAgent TUI Architecture

## Overview

SwiftAgent's TUI is a zero-dependency, pure-Swift terminal UI built directly on ANSI escape codes and raw-mode terminal I/O. It follows the "Nanobot" REPL pattern (also used by Claude Code): a persistent read-eval-print loop with streaming LLM responses, inline tool execution, spinner status, markdown rendering, and popup completions.

No external TUI framework (ncurses, SwiftTerm, TermKit) is used. The only external dependency is Apple's `swift-argument-parser` for CLI entry point wiring. All rendering is done via `print()` with embedded ANSI sequences.

## Architecture Layers

```
EntryPoint (ArgumentParser)
  └─ ChatCommand ── REPL orchestration, agent loop, tool execution
       ├─ LineEditor ── raw-mode input, history, popup completions
       ├─ TerminalRenderer ── ANSI output primitives, spinner, panels
       ├─ MarkdownRenderer ── Markdown → ANSI with syntax highlighting
       ├─ StatusLine ── bottom status bar
       ├─ CurrentToolTracker ── thread-safe spinner tool state
       └─ ChatToolInputAccumulator ── streaming JSON assembly
```

---

## 1. Entry Point & REPL Loop

### `EntryPoint.swift`

Root `AsyncParsableCommand`. Registers `chat` as the sole subcommand. Prints banner on bare `swift-agent` invocation.

### `ChatCommand.swift` — The Central Orchestrator

This ~890-line file is the heart of the TUI. It manages:

**REPL Loop** (`while true`):
1. Call `editor.readLine(prompt: "You: ")` — blocks in raw mode
2. If input starts with `/`, dispatch to slash command handler
3. Otherwise, append user message to `conversationHistory`
4. Enter **inline agent loop**

**Inline Agent Loop** (no artificial iteration limit):
1. Stream LLM response via `LLMClient.send()`
2. Dispatch stream events: text/thinking deltas, tool use blocks, message metadata
3. After stream ends:
   - If `tool_use` blocks present → execute tools, append results, loop back
   - If no tool calls → model finished, break to REPL
   - If `stop_reason == "max_tokens"` → send continuation hint, loop back

**Spinner Task** (100ms interval):
- When no tool is running: shows `⠋ Thinking...`
- When tools are active: shows `⠋ <tool command>`
- When thinking deltas arrive: switches to dim-mode text rendering

**ESC Cancellation**: A background task polls stdin for ESC in raw mode, sets `isCancelled` flag. The flag is checked at every stream event boundary and before tool execution.

---

## 2. Terminal Primitives Layer

### `TerminalCapability.swift`

Detects terminal capabilities at startup:
- **isTTY**: `isatty()` on STDIN/STDOUT
- **supportsColor**: Checks `COLORTERM` env var and `TERM` content
- **size**: `ioctl(TIOCGWINSZ)`, fallback to `COLUMNS`/`LINES` env vars, then 80×24

Provides `color(_:color:style:)` — wraps text in ANSI codes if color is supported, returns plain text otherwise. This is the single choke point for degrade-to-plain-text behavior.

### `ColorTheme.swift`

Semantic color mapping:
- `.primary` (blue), `.secondary` (cyan), `.success` (green), `.warning` (yellow), `.error` (red), `.dim` (bright black), `.bold`
- `.default` and `.monochrome` presets
- `ANSIColor` enum: 16 standard colors + `trueColor(r:g:b:)`
- `ANIStyle` enum: reset, bold, dim, italic, underline, blink, reverse
- Top-level `ansi()` function: wraps text with color/style prefixes and `\033[0m` reset

### `TerminalDisplayWidth.swift`

Unicode-aware column width measurement. Critical for correct cursor positioning:
- Zero-width characters: control chars, combining marks, variation selectors, ZWJ
- Full-width characters: CJK ideographs, Hangul, emoji
- Tab → width 4
- ANSI escape stripping before measurement
- `cursorPosition(forOffset:columns:)` → (row, col) for cursor placement

---

## 3. Input System

### `LineEditor.swift` — Raw-Mode Line Editor

The most complex single file (~1100 lines). Implements a full line editor in raw terminal mode.

**Raw Mode Setup** (`enterRawMode()`):
- Uses `termios` via `tcsetattr` to disable: ICANON (line buffering), ECHO, ISIG (signal generation), IXON (flow control), ICRNL (`\r`→`\n` translation)
- Enables bracketed paste mode (`\033[?2004h`)

**Key Bindings**:
| Key | Action |
|-----|--------|
| Left/Right | Cursor movement |
| Up/Down | Line navigation in multi-line; history navigation at boundaries |
| Alt+Left/Right | Word navigation |
| Ctrl+A/E | Line start/end |
| Ctrl+U | Clear line |
| Ctrl+K | Delete to end of line |
| Ctrl+W | Delete previous word |
| Alt+Backspace | Bash-style backward-kill-word |
| Alt+Enter | Insert literal newline |
| Tab | Insert 4 spaces |
| Ctrl+C | Cancel popup; if no popup, return nil (exit) |
| ESC | Intercept mode: cancel current LLM generation |

**Escape Sequence Parser** (lines 609-725):
- Timeout-based disambiguation: waits ~5ms after receiving `\033` to determine if it's a bare ESC or the start of a CSI/SS3 sequence
- Supports standard CSI arrows, Home/End (H/F variants)
- Supports SS3 (tmux-style `ESC O ...`) arrows
- Kitty keyboard protocol (`CSI ... u`) for Shift+Enter and other modified keys
- Bracketed paste: reads `\033[200~ ... \033[201~` delimited content

**Paste Handling** (lines 471-557):
- Burst detection: characters arriving within 50ms are treated as paste
- Multi-line paste: shows placeholder `[Pasted text #1 +3 lines]`, expands to original content on submit
- Preserves original newlines for subsequent editing

**History System**:
- Null-byte (`\0`) separated file format for multi-line entry support
- Legacy `\n`-separated format auto-detected and migrated
- Stashed buffer: when user types text then presses Up, the typed text is saved and restored when pressing Down past the newest entry
- 500-entry cap

**Redraw Strategy** (`redrawLine()`):
1. Move cursor to start of input area (`\033[lastCursorRowA`)
2. Clear from cursor to end of screen (`\r\033[J`)
3. Render prompt + first line of input
4. Render continuation lines with padding matching prompt width
5. Render popup below input area if active
6. Position cursor at correct insertion point

Key design choice: uses **cursor-up movement** rather than save/restore. Save/restore can be unreliable across terminal emulators; explicit cursor positioning is deterministic.

### `InlinePopup.swift` — Inline Completion Popup

Renders below the input line during `/` (command) or `@` (file) completion.

**Rendering**:
```
╭─ Commands ──────────────────────────────╮
│ /help     Show available commands       │
│ /exit     Exit the current session      │
│ /skills   List all available skills     │
╰─────────────────────────────────────────╯
```
- Selected item: ANSI reverse video (`\033[7m`)
- Match characters: yellow bold
- Box: dark cyan, drawn with Unicode box-drawing characters
- Scroll indicators: `↑ N more` / `↓ N more`

**State**:
- `items`: All matches for current query
- `selectedIndex`: Currently highlighted item
- `scrollOffset`: Virtual scroll position (max 12 visible items)

**Navigation**: Up/Down arrows move selection; auto-scrolls when selection goes out of viewport. Tab commits, Ctrl+C cancels.

### `PopupDataSource.swift` — Completion Data Sources

**`CommandDataSource`** (`/` trigger):
- Pre-populated with 22 built-in commands
- Dynamically loaded skills from `SkillFileLoader`
- Fuzzy matches against command names and aliases

**`FileDataSource`** (`@` trigger):
- Dual search mode:
  - **Directory-scoped** (query contains path separator): searches within specific directory
  - **Recursive** (query without separator): traverses entire working tree
- Hides dot-files unless query starts with `.`
- Excludes VCS directories
- Directories shown first, trailing `/` appended

### `FuzzyMatcher.swift`

Four-tier scoring:
1. **1.0** — exact match (case-insensitive)
2. **0.9** — prefix match
3. **0.7** — substring match (anywhere)
4. **~0.5 × coverage** — ordered subsequence match (all query chars appear in order, scaled by coverage ratio)
5. **0.0** — no match

Returns match positions for highlighting matched characters in the popup.

---

## 4. Output Rendering

### `TerminalRenderer.swift`

ANSI output primitives:

- **Banner**: Box-drawing character welcome screen with version
- **Status line**: Full-width reverse-video bar showing session info
- **Panels**: Boxed content with `╭── title ──╮` header, 80-column width, word wrapping
- **Left border**: `│ ` prefix for AI response display (Nanobot-style)
- **Spinner**: Braille dot sequence (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`), returns `\r\033[K  <frame> Thinking...`
- **Screen control**: clear screen, cursor up/down, save/restore cursor, horizontal rule
- **TTY drain**: `tcflush(TCIFLUSH)` to discard buffered keystrokes typed during generation

### `MarkdownRenderer.swift` — Markdown → ANSI

Block-level state machine:

| Block | Rendering |
|-------|-----------|
| H1 | Overline + `═══` underline |
| H2 | Text + `───` underline |
| H3 | Bold + colored |
| H4+ | Plain bold |
| Code fence | Boxed with `┌── lang ──┐` header, syntax highlighted |
| Table | Parsed columns, centered bold headers, `├───┼───┤` separators |
| Blockquote | `▎` prefix, dim style |
| Horizontal rule | Full-width `───` |
| List item | `•` prefix, theme color |

Inline processing:
- `` `code` `` → dim underline
- `**bold**` → ANSI bold
- `*italic*` → ANSI italic
- `[text](url)` → underlined, theme color

Code blocks pass through `RegexSyntaxHighlighter` → `TokenANSIRenderer` → `CodeTheme` for language-specific syntax coloring.

### `StatusLine.swift`

Renders a reverse-video status bar at the bottom of the terminal:
1. Gets snapshot from `AppStateStore`
2. Moves cursor to bottom row (`\033[NB`)
3. Writes full-width reverse-video line
4. Restores cursor position

### `StreamRenderer.swift` (Core)

Formats `StreamEvent` values for display. Maps:
- `.textDelta` → plain text
- `.thinkingDelta` → empty (CLI handles dim mode separately)
- `.contentBlockStart(.toolUse)` → `[Calling tool: ...]`
- `.messageDelta` → `[Tokens: ...] [Stop: ...]`

Note: `ChatCommand` handles streaming display directly in its event loop rather than delegating to this renderer. The renderer exists as a reusable Core component for alternative display paths.

---

## 5. Syntax Highlighting

### `RegexSyntaxHighlighter` (`SyntaxHighlighter.swift`)

Zero-dependency regex-based syntax highlighter. Single-pass, context-aware scanner:

1. **First pass**: Block comments, line comments, strings, numbers
2. **Word tokens**: Checks against language keyword dictionary
3. **Context-aware classification**: Previous token sets context:
   - `.declaration` → next word is `function.declaration`
   - `.typeAnnotation` → next word is `type`
4. **Heuristics**: PascalCase → `type`, followed by `(` → `function.call`

Supports 13 languages: Swift, Python, JavaScript, TypeScript, Bash, JSON, Go, Rust, C, C++, Ruby, SQL, YAML, Markdown.

### `TokenANSIRenderer`

Walks source text linearly, inserting ANSI-colored segments at token boundaries. Uses `CodeTheme` to map capture names (e.g., `keyword`, `string`, `function`) to colors.

### `CodeTheme`

Monokai and GitHub presets. Maps tree-sitter-style capture names to `ANSIColor` values with pattern matching (e.g., `keyword*` matches `keyword`, `keyword.function`, etc.).

---

## 6. Tool Execution Display

### `CurrentToolTracker`

Thread-safe (`NSLock`-protected) tracker for active tool execution. Powers the spinner display:

- `start(id:name:)` — registers a running tool
- `update(id:status:)` — updates progress message (used by AgentTool, TaskOutput)
- `finish(id:)` — removes completed tool
- `displayLine` — computed property for the status line:
  - 1 tool: `Running <name>...` or custom status
  - 2-3 tools: `<name> running; <name> running`
  - 4+ tools: `N tools running | ...; ... +M more`

### `ChatToolInputAccumulator`

Builds tool input JSON incrementally from streaming `inputJSONDelta` events:
1. `startTool(name:id:)` — begins accumulation for a new tool call
2. `appendInputJSONDelta(_:)` — appends JSON fragment
3. `stopCurrentBlock()` — parses accumulated JSON into `[String: JSONValue]`
4. `finish(stopReason:)` — handles truncation by `max_tokens`

Error handling:
- Invalid JSON → `ChatToolInputError.invalidJSON`
- Truncated by token limit → `ChatToolInputError.truncatedByMaxTokens`

### `ChatToolExecutionScheduler`

Optimistic parallel execution of tool calls:
- Concurrency-safe tools are batched and run in `TaskGroup`
- Non-safe tools run sequentially in order
- Preserves original call order in results for conversation history

---

## 7. ANSI Escape Code Reference

### Styles
| Code | Effect | Usage |
|------|--------|-------|
| `\033[0m` | Reset | Every styled segment suffix |
| `\033[1m` | Bold | Headings, strong text |
| `\033[2m` | Dim | Thinking text, blockquotes, code backgrounds |
| `\033[3m` | Italic | Emphasis |
| `\033[4m` | Underline | Links, inline code |
| `\033[7m` | Reverse | Status bar, popup selection |

### Colors
| Code | Effect |
|------|--------|
| `\033[30m`–`\033[37m` | Standard foreground (black–white) |
| `\033[90m`–`\033[97m` | Bright foreground |
| `\033[38;2;R;G;Bm` | TrueColor foreground |
| `\033[40m`–`\033[47m` | Standard background (+10 from foreground) |

### Cursor & Screen
| Code | Effect |
|------|--------|
| `\033[N A` | Cursor up N rows |
| `\033[N B` | Cursor down N rows |
| `\033[N C` | Cursor forward N columns |
| `\r` | Carriage return (column 0) |
| `\033[K` | Clear to end of line |
| `\033[J` | Clear to end of screen |
| `\033[2J\033[H` | Clear screen + home |

### Bracketed Paste
| Code | Effect |
|------|--------|
| `\033[?2004h` | Enable bracketed paste |
| `\033[?2004l` | Disable bracketed paste |
| `\033[200~` | Paste start marker |
| `\033[201~` | Paste end marker |

---

## 8. Data Flow

### Sequence Diagram: A Complete Turn

```
┌──────────┐     ┌───────────┐     ┌──────────┐     ┌────────────┐     ┌───────────┐
│LineEditor│     │ChatCommand│     │LLMClient │     │ ToolExecutor│    │Terminal   │
│ (raw tty)│     │(orchestr.)│     │  (HTTP)  │     │(core logic) │    │ Renderer  │
└────┬─────┘     └─────┬─────┘     └────┬─────┘     └─────┬──────┘     └─────┬─────┘
     │                 │                │                  │                  │
     │ readLine()      │                │                  │                  │
     │────────────────>│                │                  │                  │
     │                 │                │                  │                  │
     │   "User: help"  │                │                  │                  │
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
     │                 │────────────────┼──────────────────┼── dim text ─────>│
     │                 │                │                  │                  │
     │                 │ .textDelta     │                  │                  │
     │                 │────────────────┼──────────────────┼── plain text ───>│
     │                 │                │                  │                  │
     │                 │ .contentBlockStart(toolUse)       │                  │
     │                 │────────────────┼───── ChatToolInputAccumulator ──>│
     │                 │                │       .startTool()                │
     │                 │                │                  │                  │
     │                 │ .inputJSONDelta│                  │                  │
     │                 │────────────────┼─ .appendJSON() ─>│                  │
     │                 │                │                  │                  │
     │                 │ .contentBlockStop                 │                  │
     │                 │────────────────┼─ .stopBlock() ──>│                  │
     │                 │                │                  │                  │
     │  (stream ends)  │                │                  │                  │
     │                 │                │                  │                  │
     │                 │ executable(name, input, ctx)      │                  │
     │                 │────────────────┼─────────────────>│                  │
     │                 │                │                  │                  │
     │                 │ currentTool    │                  │                  │
     │                 │ .start(id,name)│    spinner: ─────┼── "Running X">│
     │                 │                │                  │                  │
     │                 │                │                  │ toolResult()     │
     │                 │                │                  │──── "output" ──>│
     │                 │                │                  │                  │
     │                 │ currentTool    │                  │                  │
     │                 │ .finish(id)    │    spinner: ─────┼── clear ───────>│
     │                 │                │                  │                  │
     │                 │ toolResultSummary(name, in, out)  │                  │
     │                 │────────────────┼──────────────────┼── "Bash → ...">│
     │                 │                │                  │                  │
     │                 │ (tool results appended to history, loop back to send)
     │                 │───────────────>│                  │                  │
     │                 │                │                  │                  │
     │  (or: no tools → break to REPL)  │                  │                  │
     │                 │                │                  │                  │
     │                 │ responseText   │                  │                  │
     │                 │────────────────┼──────────────────┼── markdown ────>│
     │                 │                │                  │    rendered     │
     │<────────────────│                │                  │                  │
     │  draw prompt    │                │                  │                  │
```

### Stream Event Processing Pipeline

```
                        ┌──────────────────────────────────────┐
                        │        AsyncThrowingStream            │
                        │         <StreamEvent>                 │
                        └──────────┬───────────────────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    ▼              ▼              ▼
              ┌───────────┐ ┌───────────┐ ┌──────────────┐
              │ thinking  │ │  text     │ │  tool_use    │
              │  delta    │ │  delta    │ │  + inputJSON │
              └─────┬─────┘ └─────┬─────┘ └──────┬───────┘
                    │              │              │
                    ▼              ▼              ▼
           ┌─────────────┐ ┌───────────┐ ┌─────────────────┐
           │ dim-mode    │ │ accum to  │ │ ChatToolInput   │
           │ text output │ │ turnText  │ │ Accumulator     │
           └──────┬──────┘ └─────┬─────┘ │ .appendJSON()   │
                  │              │       └────────┬────────┘
                  ▼              ▼                ▼
           ┌─────────────┐ ┌───────────┐ ┌─────────────────┐
           │ thinkingText│ │           │ │ parsed tool     │
           │ in history  │ │           │ │ calls with      │
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
                    │        Has tool_use blocks?           │
                    └──────┬──────────────────┬────────────┘
                           │ YES              │ NO
                           ▼                  ▼
              ┌─────────────────────┐  ┌──────────────┐
              │  ChatToolExecution  │  │   stopReason │
              │  Scheduler          │  │   == max_    │
              │  (parallel/serial)  │  │   tokens?    │
              └──────────┬──────────┘  └──┬────────┬──┘
                         │                │ YES    │ NO
                         ▼                ▼        ▼
              ┌──────────────────┐ ┌────────┐ ┌─────────┐
              │  ToolExecutor    │ │continue│ │  break  │
              │  .execute()      │ │  loop  │ │to REPL  │
              └────────┬─────────┘ └────────┘ └─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │  ToolResult      │
              │  → history       │
              │  → loop back     │
              └──────────────────┘
```

### Redraw Pipeline (Input Side)

```
┌─────────┐    ┌────────────┐    ┌──────────────┐    ┌──────────────┐
│ readByte│    │EscapeParser│    │ handleChar   │    │  redrawLine  │
│ (stdin) │───>│(CSI/SS3/   │───>│ (insert/del/ │───>│ (ANSI cursor │
│         │    │ kitty/paste)│   │  nav/popup)  │    │  positioning)│
└─────────┘    └────────────┘    └──────────────┘    └──────┬───────┘
                                                            │
                              ┌─────────────────────────────┘
                              ▼
              ┌─────────────────────────────┐
              │  1. \033[lastCursorRowA     │ move to input start row
              │  2. \r\033[J                │ clear to end of screen
              │  3. prompt + buffer[0]      │ draw first line
              │  4. pad + buffer[1..]       │ draw continuation lines
              │  5. popup.render()          │ draw popup if active
              │  6. \033[row;colH           │ position cursor
              └─────────────────────────────┘
```

### Spinner / Status Loop

```
┌──────────────────────┐
│  Spinner Task        │  every 100ms
│  (background Task)   │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐     ┌──────────────────┐
│ CurrentToolTracker   │────>│ displayLine      │
│ (NSLock-protected)   │     │ computed property │
│                      │     └────────┬─────────┘
│ .name (thinking)     │              │
│ .entries (tools)     │     ┌────────▼─────────┐
└──────────────────────┘     │ 1 tool:           │
                             │   "Running X..."  │
                             │ 2-3 tools:        │
                             │   "X; Y running"  │
                             │ 0 tools:          │
                             │   "⠋ Thinking..." │
                             └────────┬─────────┘
                                      │
                                      ▼
                             ┌──────────────────┐
                             │ \r\033[K <frame> │
                             │ <status text>    │
                             │ fflush(stdout)   │
                             └──────────────────┘
```

---

## 9. Design Decisions & Rationale

### Why zero-dependency ANSI instead of ncurses/TermKit?

1. **Portability**: ANSI escape codes are the universal terminal language. No C library linking, no platform-specific builds.
2. **Control**: Direct ANSI gives precise control over partial updates, cursor positioning, and streaming output — essential for the spinner/thinking/inline-tool-result pattern.
3. **CC alignment**: Claude Code itself uses direct ANSI codes, not a framework.

### Why cursor-up movement instead of save/restore?

`\033[s` (save) / `\033[u` (restore) behavior varies across terminal emulators, especially with scroll regions. Explicit `\033[N A` (cursor up) is deterministic. The cost is that `LineEditor` must track its own `drawnLines` count.

### Why a separate spinner task?

The spinner runs at 100ms intervals independently from the async stream. This keeps the animation smooth even when stream events arrive in bursts. The spinner reads `CurrentToolTracker` state to adapt its display.

### Why bracket paste detection?

Without it, pasted multi-line text would be interpreted as multiple `readLine()` returns. The bracket paste protocol (`\033[200~...\033[201~`) lets the editor capture the full paste as a single operation.

### Why null-byte history separators?

Newline-separated history can't store multi-line entries (a pasted code block would become N separate history entries). Null bytes are not valid in user input, making them a safe delimiter.

### Why ESC timeout disambiguation?

A bare `\033` (ESC key) and a CSI sequence starting with `\033[` both begin with `\033`. Without a timeout, the editor can't distinguish "user pressed ESC" from "user pressed Left Arrow (`\033[D`)". A ~5ms read timeout after `\033` handles this: if more bytes arrive, it's a sequence; if not, it's a bare ESC.

---

## 10. Module Classification

### Input Layer
| File | Role |
|------|------|
| `LineEditor.swift` | Raw-mode line editor, history, popup integration |
| `InlinePopup.swift` | Inline completion menu rendering |
| `PopupDataSource.swift` | `/` command and `@` file completion sources |
| `FuzzyMatcher.swift` | Fuzzy string matching engine |

### Output Layer
| File | Role |
|------|------|
| `TerminalRenderer.swift` | ANSI output primitives, spinner, panels |
| `TerminalCapability.swift` | TTY and color detection |
| `TerminalDisplayWidth.swift` | Unicode-aware column measurement |
| `ColorTheme.swift` | Semantic color palette, ANSI color codes |
| `StatusLine.swift` | Bottom status bar |
| `MarkdownRenderer.swift` | Markdown → ANSI with syntax highlighting |

### Syntax Highlighting
| File | Role |
|------|------|
| `SyntaxHighlighter.swift` | Regex-based tokenizer |
| `TokenANSIRenderer.swift` | Token → ANSI color mapping |
| `CodeTheme.swift` | Capture name → color presets |
| `LanguageRegistry.swift` | Language grammar definitions |

### Orchestration
| File | Role |
|------|------|
| `ChatCommand.swift` | REPL loop, agent loop, tool dispatch |
| `ChatToolInputAccumulator.swift` | Streaming JSON assembly |
| `ChatToolExecutionScheduler.swift` | Parallel/serial tool scheduling |
| `CurrentToolTracker` (inner class) | Thread-safe tool status for spinner |

### Support
| File | Role |
|------|------|
| `DebugLogger.swift` | JSONL debug logging |
| `EntryPoint.swift` | ArgumentParser wiring |

---

## 11. Extension Points

### Adding a new slash command
1. Add to `commandEntries` array in `ChatCommand.run()`
2. Add handler in `handleCommand()` method

### Adding a new popup data source
1. Implement `PopupDataSource` protocol
2. Call `editor.setPopupDataSources()` or extend `LineEditor` to support a new trigger character

### Adding a new syntax language
1. Add `LanguageGrammar` to `LanguageRegistry.languages`
2. Add keyword sets, comment styles, string delimiters
3. No regex changes needed — the scanner is language-agnostic

### Adding a new code theme
1. Add static preset to `CodeTheme` (e.g., `.dracula`)
2. Map capture names to `ANSIColor` values

### Adding a new tool display mode
1. Check `call.name` in the execute closure in `ChatCommand`
2. Customize `CurrentToolTracker` display or skip it entirely (as done for `SendUserMessage`)

---

## 12. Known Challenges

1. **Terminal emulator variance**: Not all terminals support TrueColor, italic, or bracket paste. The `TerminalCapability` degradation path handles missing features gracefully, but edge cases remain.

2. **Unicode width**: `TerminalDisplayWidth` uses hardcoded ranges for CJK/emoji detection. This doesn't cover all Unicode versions and may mis-measure rare characters.

3. **ESC key vs escape sequences**: The timeout-based disambiguation (~5ms) works well on local terminals but can fail over high-latency connections (SSH, tmux).

4. **Resize handling**: No `SIGWINCH` handler is registered. Terminal resize during a long output may cause misalignment until the next redraw cycle.

5. **Streaming vs buffering**: `fflush(stdout)` is called manually after thinking deltas. Swift's `print()` uses line buffering by default; explicit flushes are needed for mid-line updates.

6. **Thread safety**: `CurrentToolTracker` and `SessionState` use `NSLock` for thread safety between the spinner task and the main agent loop. Actor isolation is used for `AppState`.

---

## 13. Comparison: Claude Code vs Codex CLI vs SwiftAgent

- **Claude Code** builds its TUI on a custom React reconciler with Yoga Flexbox layout, trading startup cost and dependency complexity for maximal visual expressiveness and component reusability. 
- **Codex CLI** takes the Rust systems path — a custom ratatui/crossterm fork with a handwritten cell-level diff engine and 187K lines of widget code, delivering native performance at the cost of maintaining a large codebase and custom terminal backend forks. 
- **SwiftAgent** pursues radical simplicity: no framework, no diff engine, just raw ANSI strings and procedural logic — achieving instant startup and trivial debuggability at the cost of limited visual richness and per-frame full redraws.

### Architectural Philosophy

| | Claude Code | Codex CLI | SwiftAgent |
|---|---|---|---|
| **Language** | TypeScript (Node.js) | Rust (native binary) | Swift (native) |
| **TUI approach** | Retained-mode React | Retained-mode (ratatui widgets) | Immediate-mode direct ANSI |
| **Framework** | Custom Ink fork (~90 files) | Custom ratatui 0.29 fork + crossterm 0.28 fork | None (from scratch) |
| **Layout engine** | Yoga Flexbox (WASM) | ratatui Constraint-based Rect (no Flexbox) | None (manual positioning) |
| **Render pipeline** | Reconciler → DOM → Screen → Diff → ANSI | Widgets → `Buffer` → `diff_buffers()` → `DrawCommand` → ANSI | String → `print()` |
| **Update strategy** | Cell-level diff with damage regions | Cell-level diff (prev/next `Buffer` compare), `ClearToEnd` optimization | Full redraw per frame |

### Rendering

| | Claude Code | Codex CLI | SwiftAgent |
|---|---|---|---|
| **Render model** | Double-buffered Screen (2D char grid) | Double-buffered `ratatui::Buffer` (2D char grid) | Single-pass string output |
| **Frame rate** | ~60fps throttled | Event-driven, 32ms frame scheduling for animation | Event-driven (no frame concept) |
| **Diff algorithm** | LogUpdate: prev/next screen diff, 8 optimizer rules, DECSTBM hardware scroll | Custom `diff_buffers()`: per-cell prev/next compare, emits `Put` (changed cells) + `ClearToEnd` (row tail optimization) | None |
| **Markdown** | React components (`Box`/`Text`) | pulldown-cmark 0.10 → custom `markdown_render.rs` → ratatui `Line`/`Span` | Custom ANSI string renderer |
| **Code blocks** | React + Shikiji (tree-sitter) | syntect 5 + two-face 0.5 (~250 languages, ~32 themes) | Custom regex + ANSI box-drawing |
| **Syntax themes** | Shikiji theme system | two-face theme system (syntect-compatible, 32 themes) | `CodeTheme` (monokai, github) |
| **Streaming** | React state updates → diff → ANSI patches | `StreamCore` two-region (stable + tail), `MarkdownStreamCollector`, commit-animation queue, table holdback | `print()` + `fflush()` per delta |

### Input Handling

| | Claude Code | Codex CLI | SwiftAgent |
|---|---|---|---|
| **Raw mode** | Node.js stdin raw mode | crossterm event stream (custom fork) | POSIX `termios` + `tcsetattr` |
| **Keyboard parser** | Custom: kitty protocol, SGR mouse, xterm modifyOtherKeys, terminal responses, bracketed paste | crossterm event stream + custom `keymap.rs` (95K lines) with extensive keybinding config | Custom: CSI, SS3, kitty protocol, xterm modified, bracketed paste |
| **Mouse support** | SGR mouse, X10 mouse | SGR mouse via crossterm | None |
| **ESC disambiguation** | Not needed (Ink event system) | Handled by crossterm event stream | Timeout-based (~5ms poll) |
| **Paste detection** | Bracketed paste + custom burst logic | Bracketed paste via crossterm | Bracketed paste + 50ms burst timer |

### Component Model

| | Claude Code | Codex CLI | SwiftAgent |
|---|---|---|---|
| **Component system** | React functional components | ratatui `WidgetRef` trait + custom `Renderable` trait, functional composition | Procedural functions |
| **State management** | React hooks + Zustand stores | ratatui stateful widgets + tokio channels + `AppEventSender` | Manual + `CurrentToolTracker` (NSLock) |
| **Popup/dialog** | React components (fuzzy picker, select, dialog) | Custom ratatui widgets (resume_picker 210K, pager_overlay, theme_picker) | `InlinePopup` (ANSI box-drawing) |
| **Status bar** | React `StatusLine` component | Custom ratatui `StatusIndicatorWidget` with shimmer animation, elapsed timer | `StatusLine` (ANSI reverse video) |
| **Spinner** | React `Spinner` component | `StatusIndicatorWidget`: shimmer_text animation, `Instant` elapsed timer, 32ms frame scheduling, `ReducedMotionIndicator` | Background Swift Task + ANSI overwrite |
| **Composer/input** | React `Composer` component hierarchy | Custom ratatui widget + keymap system (95K `keymap.rs` + 65K `keymap_setup.rs`), `mention_codec`, `slash_command` | `LineEditor` (raw-mode procedural) |

### Codebase Scale & Dependencies

| | Claude Code | Codex CLI | SwiftAgent |
|---|---|---|---|
| **TUI codebase** | ~90 files (ink/) + ~150 components + ~80 hooks | ~297 `.rs` files in `tui/src/`, 110+ top-level modules | ~15 files (SwiftAgentCLI/) |
| **External deps** | react, react-reconciler, yoga (WASM), @shikiji, lodash, log-update | ratatui (custom fork), crossterm (custom fork), pulldown-cmark, syntect, two-face, tokio, + 60+ internal codex-* crates | None (only `swift-argument-parser`) |
| **Lines (TUI)** | ~30,000+ (estimated) | ~187,000 lines of Rust in `tui/src/` | ~4,000 |
| **Platform** | Cross-platform (Node.js) | Cross-platform (Rust + tokio) | macOS 15+ only |

### Strengths & Tradeoffs

| Aspect | Claude Code | Codex CLI | SwiftAgent |
|---|---|---|---|
| **Visual richness** | High — Flexbox layout, smooth animations, mouse interaction, complex dialog layouts | High — ratatui widget system, syntect syntax highlighting, shimmer animations, pager overlay, mouse support, theme picker | Moderate — ANSI box-drawing, spinner, popup, markdown. No flex layout, no mouse |
| **Update efficiency** | Excellent — cell-level diff only writes changed chars. Hardware scroll for content shifts | Excellent — custom `diff_buffers()` per-cell diff with `ClearToEnd` optimization, `SynchronizedUpdate` flicker-free, `scroll_region_up` for content shifts | Basic — full-line overwrite via `\r\033[K` and cursor positioning |
| **Code complexity** | Very high — custom React reconciler, Yoga WASM, double-buffered screen, diff optimizer | Very high — custom terminal backend fork, custom diff engine, 95K keymap system, two-region streaming, 297 Rust source files | Low — direct ANSI strings, no framework, no diff engine |
| **Startup time** | Slow — WASM instantiation, React tree construction | Fast — native Rust binary, no VM/JIT overhead | Instant — no framework initialization |
| **Dependency risk** | High — fork must be maintained, Yoga WASM compatibility issues, React version lock-in | Medium — custom ratatui/crossterm forks must track upstream, 60+ internal crate dependency graph | Minimal — only `swift-argument-parser` |
| **Debuggability** | Complex — React devtools needed, reconciler tracing | Moderate — Rust debugging tools, ratatui buffer inspection, `--debug` flag | Simple — `print()` is trivially debuggable, `--debug` flag for API logs |
| **Extensibility** | Component-based — add features by composing React components | Widget-based — implement `WidgetRef`/`Renderable` traits, compose into layouts; clear separation: `app/`, `chatwidget/`, `bottom_pane/`, `streaming/` | Function-based — add rendering in procedural code; clear extension points documented |
| **SSH/tmux compatibility** | Good — ANSI output is standard; mouse requires SGR support | Good — ANSI output via crossterm; mouse requires SGR support | Good — pure ANSI, no mouse, no advanced protocols |
