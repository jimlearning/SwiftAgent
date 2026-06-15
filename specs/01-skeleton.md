# Phase 1 — Skeleton (Empty shell with Codex App 3-pane layout)

> **Source spec**: `/Users/jim/SwiftAgent/.mavis/plans/swiftagent-macos-product-doc.md` §16.1 (v1.2)
> **Goal**: Get a runnable empty shell that displays Codex App's 3-pane layout with dark mode theming.
> **Done when**: `swift build` succeeds, app launches, all 3 panes visible with correct colors + spacing.
> **Important v1.2 note**: Right pane is a **multi-Tab workspace** (multiple tabs coexist, each with × close button), NOT a "5 entry mutually exclusive list". See product doc §2.4 / §3.3 v1.2.

---

## Context

The project currently has:
- `Sources/SwiftAgentCore/` — reusable agent runtime (43 tools, LLM, Skills, MCP, Safety, Storage, etc.)
- `Sources/SwiftAgentCLI/` — CLI entry (`swift-agent` executable)
- `Tests/SwiftAgentCoreTests/`, `Tests/SwiftAgentCLITests/`
- Existing TUI rendering in `Sources/SwiftAgentCLI/` (terminal-based, not GUI)

This phase adds a new **macOS SwiftUI app target** `SwiftAgentApp` that sits alongside CLI and reuses `SwiftAgentCore`. It must NOT change any existing CLI/Core behavior.

---

## Acceptance Criteria

### A. Package & Target setup

- [ ] `Package.swift` adds a new `SwiftAgentApp` executable target depending on `SwiftAgentCore`
- [ ] `Package.swift` platforms stays at `.macOS(.v15)` (SwiftUI app requires macOS 15+)
- [ ] `swift build` succeeds with zero errors and zero warnings for all 3 targets
- [ ] `swift test` still passes (existing 232 tests, 57 suites) — no regressions
- [ ] `Sources/SwiftAgentApp/` directory created with subdirs: `Window/`, `Sidebar/`, `Content/`, `RightTabs/`, `DesignSystem/`, `ViewModels/`

### B. Entry point

- [ ] `Sources/SwiftAgentApp/EntryPoint.swift` exists with `@main struct SwiftAgentApp: App`
- [ ] App declares a single main `Window` with title "SwiftAgent", id "main"
- [ ] `MainContentView` is the root view, min frame 980×640pt
- [ ] Window uses standard macOS titlebar (NOT hidden)
- [ ] Traffic lights visible at standard macOS position
- [ ] Window resizability is `.contentMinSize`

### C. Three-pane layout (per §2.1, §3.2)

- [ ] Uses `NavigationSplitView` with 3 columns: sidebar / content / detail
- [ ] `SidebarView` — left, width `min:240 ideal:260 max:320` (currently 240-280pt range, use 260 ideal)
- [ ] `ContentView` — center, width `min:480 ideal:720`
- [ ] `RightTabsView` — right, width `min:380 ideal:420 max:520` (currently 380-440pt range, use 420 ideal)
- [ ] All 3 columns render side-by-side on first launch
- [ ] Sidebar uses `NSVisualEffectView` vibrancy (`.sidebar` material) — KEY per §3.1

### D. Design system (per §4)

- [ ] `DesignSystem/Color.swift` defines all dark-mode color tokens from §4.1 (bgSidebar #2A2A2A, bgContent #1C1C1C, bgRightPanel #000000, textPrimary #F5F5F5, textSecondary #999999, accentPrimary #339CFF, success #3FB950, danger #F85149, warning #E3B341, borderSubtle #2A2A2A, borderStrong #3A3A3A)
- [ ] `DesignSystem/Typography.swift` defines uiBody, uiLabel, uiHeadline, uiTitle, uiCaption, codeMono, codeTag per §4.2
- [ ] `DesignSystem/Spacing.swift` defines 8pt grid (space1=4 through space8=40) per §4.4
- [ ] `DesignSystem/Radius.swift` defines corner radii (4/8/12/16/20/999) per §4.3
- [ ] App default appearance is dark mode (per §4.6 — System default but dark is initial)
- [ ] All 100% SF Symbols (no custom icons per §4.5)

### E. Sidebar (per §2.2)

- [ ] `SidebarView.swift` renders 4 top entries: New chat, Search, Plugins, Automations (icon + label, left-aligned)
- [ ] Each entry has an SF Symbol icon (use placeholder icons from spec: pencil.tip.crop.circle for new chat, magnifyingglass for search, at-symbol for plugins, clock for automations)
- [ ] "Projects" section header visible (no projects in this phase, just the label)
- [ ] "Chats (global)" section header visible (empty state)
- [ ] `⚙ Settings` link at the bottom (clicking does nothing yet in this phase)
- [ ] Background = `Color.bgSidebar` (#2A2A2A) + vibrancy
- [ ] Text uses `Font.uiLabel` (13pt medium) or `Font.uiBody` (13pt regular)

### F. Center content (per §2.3)

- [ ] `ContentView.swift` shows a top 48pt toolbar with placeholder text "Hello, SwiftAgent" centered
- [ ] Toolbar has thread title placeholder + breadcrumb placeholder + 2 placeholder buttons (Z⌄ and ⚙️+✓)
- [ ] Below toolbar, displays a centered placeholder "Hello, SwiftAgent" using `Font.uiTitle` (28pt semibold)
- [ ] Background = `Color.bgContent` (#1C1C1C)
- [ ] A non-functional Composer placeholder at the bottom (~80pt height) showing 4 placeholder controls: + / ⚙️ Custom⌄ / 5.5 High⌄ / ↑

### G. Right panel — multi-Tab workspace (per §2.4, §3.3 v1.2)

- [ ] `Sources/SwiftAgentApp/RightTabs/` directory created with: `RightTabsView.swift`, `RightTab.swift`, `RightTabType.swift`, `RightTabsStore.swift`, `TabBarView.swift`, `TabLabel.swift`, `TabContentView.swift`, `AddTabMenu.swift`, `EmptyTabPlaceholder.swift`
- [ ] `RightTabType` enum with 5 cases: `review`, `terminal`, `browser`, `files`, `sideChat` — each has `title`, `icon` (SF Symbol), `shortcut`
- [ ] Icons: `checklist`, `terminal`, `globe`, `folder`, `plus.circle`
- [ ] Default shortcuts: `⌃⇧G`, `⌃\``, `⌘T`, `⌘P`, `⌥⌘S`
- [ ] `RightTabsStore` (`@MainActor ObservableObject`): holds `tabs: [RightTab]`, `activeTabID: UUID?`, `showAddPopover: Bool`
- [ ] `RightTab` model: `id: UUID`, `type: RightTabType`, `title: String` (user-editable), `createdAt: Date`
- [ ] `openTab(type:)` method: appends a new `RightTab`, sets `activeTabID` to it — supports opening MULTIPLE tabs of same type
- [ ] `close(_:)` method: removes tab; if closing active → falls back to last remaining tab
- [ ] `activate(_:)` method: sets `activeTabID`
- [ ] Default state on launch: empty `tabs` array, `activeTabID = nil` — only the `+` button visible
- [ ] Tab bar: horizontal `ScrollView` of `TabLabel`s + `+` button on the right
- [ ] Each `TabLabel` shows: SF Symbol icon + title + `×` close button (visible on hover OR when tab is active)
- [ ] Active tab visual: `bgRightPanel` (#000000) background + 2pt bottom border in `accentPrimary` (#339CFF)
- [ ] Inactive tab visual: transparent background, `#999999` text color
- [ ] Clicking a `TabLabel` activates that tab (content swaps below)
- [ ] `+` button opens `AddTabMenu` popover listing 5 panel types (icon + name) — selecting one creates a new tab
- [ ] `⌘W` closes the current active tab
- [ ] `ESC` closes the current active tab (if any)
- [ ] When all tabs are closed: shows `EmptyTabPlaceholder` (gray "Open a tab to get started" text) and only the `+` button remains in tab bar
- [ ] Tab bar overflow: if >5 tabs, the bar scrolls horizontally — never shrinks tab width below 80pt
- [ ] Tab content: `TabContentView` switches on `tab.type` to show corresponding panel (Phase 1: all panels are placeholders showing "<Type> panel — coming in phase N")
- [ ] Background = `Color.bgRightPanel` (#000000) — deepest of the 3 backgrounds

### H. Window & app metadata

- [ ] `Info.plist` (or Package.swift-equivalent for SPM) registers bundle id `com.swiftagent.app`
- [ ] `CFBundleURLTypes` registers URL scheme `swiftagent` (per §2.5) — required even if no URL handling yet
- [ ] `LSUIElement` is false (regular app, not accessory)
- [ ] App icon placeholder OK (don't need real icon)

### I. Tests

- [ ] `Tests/SwiftAgentAppTests/` directory created with at least 2 tests:
  - `RightTabTypeTests`: verifies the `RightTabType` enum has 5 cases and correct titles/icons/shortcuts
  - `RightTabsStoreTests`: verifies `openTab` adds tabs, `close` removes them, `activeTabID` updates correctly when closing active
- [ ] `swift test --disable-sandbox --no-parallel` passes for all 3 test targets

### J. Build verification

- [ ] `swift build --disable-sandbox` returns exit code 0 with **zero warnings**
- [ ] `swift test --disable-sandbox --no-parallel` returns exit code 0
- [ ] The app launches (verify with `swift run swift-agent-app` if non-interactive, or by inspecting build output for the executable)

---

## Critical Anti-Patterns to Avoid (per §17 v1.2)

| # | Don't do this |
|---|---------------|
| 4 | ❌ Don't make right panel "5 entry mutually exclusive single selection" (v1.1 error) — it MUST be multi-Tab (Chrome/VS Code style) |
| 5 | ❌ Don't add levels between Projects and Threads (no "Workspaces" or "Folders" middle layer) |
| 6 | ❌ Don't show dot state indicators in thread list — just row highlight + blue dot for unread only |
| 25 | ❌ Don't use Material Design style — must be macOS HIG + OpenAI-family visual language |
| 11 | ❌ Don't make AI responses use bubbles — only user messages have bubbles (N/A this phase) |

---

## Out of Scope (deferred to later phases)

- DeepSeek API integration (Phase 2)
- Multi-Thread persistence (Phase 3)
- Skills / MCP / Worktree / Appshots (Phase 4)
- Settings page (Phase 5)
- Real conversation flow (Phase 2)
- Composer functionality (Phase 2)

---

## Files to Create

```
Package.swift                                          (MODIFY — add SwiftAgentApp target)
Sources/SwiftAgentApp/
├── EntryPoint.swift                                    (NEW)
├── Window/
│   └── MainContentView.swift                           (NEW)
├── Sidebar/
│   └── SidebarView.swift                               (NEW)
├── Content/
│   └── ContentView.swift                               (NEW)
├── RightTabs/
│   ├── RightTabsView.swift                             (NEW)
│   ├── RightTab.swift                                  (NEW)
│   ├── RightTabType.swift                              (NEW)
│   ├── RightTabsStore.swift                            (NEW)
│   ├── TabBarView.swift                                (NEW)
│   ├── TabLabel.swift                                  (NEW)
│   ├── TabContentView.swift                            (NEW)
│   ├── AddTabMenu.swift                                (NEW)
│   └── EmptyTabPlaceholder.swift                       (NEW)
├── DesignSystem/
│   ├── Color.swift                                     (NEW)
│   ├── Typography.swift                                (NEW)
│   ├── Spacing.swift                                   (NEW)
│   └── Radius.swift                                    (NEW)
Tests/SwiftAgentAppTests/
├── RightTabTypeTests.swift                             (NEW)
└── RightTabsStoreTests.swift                           (NEW)
```

---

## Commit Strategy

Single Conventional Commits commit at end of phase:
```
feat(app): add SwiftAgentApp macOS SwiftUI skeleton (phase 1)
```

---

**Output when complete:** `<promise>DONE</promise>`
