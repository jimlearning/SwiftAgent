# SwiftAgentApp — UI Freeze Debugging Guide

Diagnosing and preventing main-thread hangs in a SwiftUI + AppKit macOS app.

## Quick Diagnosis

When the UI freezes:

```bash
# Capture a 1-second process sample — shows every thread's call stack.
sample SwiftAgentApp 1 -file /tmp/hang-sample.txt
open /tmp/hang-sample.txt
```

Look at the **main thread** (`Thread 0x...  DispatchQueue: com.apple.main-thread`). Whatever function is at the top of its stack is what's blocking the UI.

If a freeze lasts 2+ seconds, the built-in `HangDetector` (`Sources/SwiftAgentApp/Content/MessageListView.swift`) auto-captures a sample to `~/Library/Logs/SwiftAgent/hang-*.txt`.

## Known Freeze Patterns

### 1. Streaming Response Freeze

**Trigger:** Any long LLM response (~100 tokens/sec streaming).

**Root cause:** `persistMessageWithBlocks` called `TranscriptStore.append()` every 5th streaming event from `@MainActor`. Internally, `append()` does `writeQueue.sync { FileHandle.write(...) }` — blocking the main thread on file I/O. Meanwhile 100 tokens/sec piled up behind it, saturating the MainActor executor. Compounded by `AgentSessionManager.run()` wrapping the entire agent loop in `Task { @MainActor }` and `AppKitChatBridge` missing a Combine throttle.

**Files:**
- `ViewModels/ThreadViewModel.swift` — `persistMessageWithBlocks`, `handleStreamEvent`
- `Agent/AgentSessionManager.swift` — `run()` with `Task { @MainActor }`
- `Content/AppKitChatBridge.swift` — missing `.throttle(16ms)` on message observation

**Fix:** Persistence offloaded to `Task.detached`. Agent loop offloaded to `Task.detached` with explicit `MainActor.run` hops. Message observation throttled to 16ms (~60fps).

### 2. Focus Mode Toggle + File Selection Freeze

**Trigger:** Toggle focus mode several times, then select a file.

**Root cause:** `ChatScrollContainer.setFrameSize` called `updateLayoutWidth` → `noteHeightOfRows` **synchronously inside AppKit's layout pass**. `noteHeightOfRows` triggers NSTableView to re-measure row heights, which can trigger another `setFrameSize` via AppKit's internal layout, creating an **infinite re-entrant layout loop**. The old `ChatScrollView` had an explicit comment warning against this pattern.

**Files:**
- `Content/ChatScrollContainer.swift` — `setFrameSize` calling `updateLayoutWidth` synchronously
- `Content/ChatTableView.swift` — `updateLayoutWidth` calling `noteHeightOfRows`

**Fix:** `setFrameSize` defers `updateLayoutWidth` to `DispatchQueue.main.async` — the layout pass completes before row heights are re-measured. `updateLayoutWidth` gained a re-entrancy guard (`isUpdatingLayout` flag).

### 3. Files Panel Scroll Freeze

**Trigger:** Open Files panel, expand a directory with 200+ entries (e.g., `Sources/SwiftAgentApp`), scroll quickly.

**Root cause:** The file tree used a **recursive `VStack`+`ForEach`** in `FileTreeRow`. Each expanded directory eagerly instantiated SwiftUI views for ALL children — 200+ `FileTreeRow` instances × ~15 internal view nodes each = 3000+ view hierarchy nodes. During scrolling, SwiftUI's layout diffing across this tree blocked the main thread. `LazyVStack` only lazily creates top-level rows, not nested children.

**Files:**
- `RightTabs/panels/FilesPanelView.swift` — recursive `FileTreeRow` with eager children rendering

**Fix:** Replaced `ScrollView` + `LazyVStack` + recursive `VStack` tree with `List` + `DisclosureGroup`. `List` has built-in cell reuse (like NSTableView); `DisclosureGroup` only creates child views when expanded. Only ~30 visible rows are instantiated regardless of total item count.

## Anti-Patterns (Never Do These)

| Anti-Pattern | Why | Example |
|-------------|-----|---------|
| **Call layout-triggering methods inside AppKit layout callbacks** | Re-entrant layout loop | `setFrameSize` → `noteHeightOfRows` → `setFrameSize` → ... |
| **Block the main thread on I/O** | Freezes UI until I/O completes; amplifies with concurrency | `FileManager.contentsOfDirectory` on `@MainActor`; `writeQueue.sync` on `@MainActor` |
| **Create massive SwiftUI view trees eagerly** | SwiftUI layout diffing is O(n) in the view count | 200+ recursive `FileTreeRow` instances |
| **Wrap async work in `Task { @MainActor }` unnecessarily** | Saturates the MainActor serial executor | Agent loop on `@MainActor` when it could be `Task.detached` |
| **Skip Combine throttle on high-frequency publishers** | Every change triggers full UI recomputation | `$messages.sink { ... }` without `.throttle(16ms)` |
| **Use recursive Views for large lists** | No cell reuse, no virtualization | `ForEach(children) { FileTreeRow(...) }` for 200 items |

## Check-Fix-Verify Workflow

When you encounter a freeze:

1. **Check** `~/Library/Logs/SwiftAgent/` for auto-captured `hang-*.txt` samples
2. **Read** the main thread's stack — what function is at the top?
3. **Match** against the known patterns above, or identify a new pattern
4. **Fix** the root cause, not the symptom (never just add a `DispatchQueue.main.async` band-aid without understanding WHY)
5. **Verify** by reproducing the trigger scenario — the UI must remain responsive
6. **Update** this document if you found a new freeze pattern

## HangDetector

`Sources/SwiftAgentApp/Content/MessageListView.swift` contains `HangDetector` — a background thread that pings the main thread every 50ms via `DispatchQueue.main.async` + semaphore:

- **100ms+ round-trip:** Soft micro-hang (not logged by default)
- **500ms+ round-trip:** Logged as warning — queue is saturated
- **2000ms+ timeout:** Logged as critical, auto-captures a 1-second `sample` to `~/Library/Logs/SwiftAgent/`

Started from `MessageListView.onAppear` (idempotent — starts once globally).

## Layout Re-entrancy: The Silent Killer

The most dangerous class of freeze is **re-entrant layout** — when a layout operation triggers another layout operation on the same runloop iteration. The stack trace looks like:

```
setFrameSize → updateLayoutWidth → noteHeightOfRows → layout → setFrameSize → ...
```

**Rule:** Never call anything that triggers `layoutSubtreeIfNeeded()`, `noteHeightOfRows()`, or `layout()` from inside `setFrameSize`, `layout()`, `updateConstraints()`, or `viewDidLayout()`. Defer to the next runloop iteration via `DispatchQueue.main.async`.
