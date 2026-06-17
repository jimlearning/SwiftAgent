# Changelog

All notable changes to SwiftAgent will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed (macOS App — 3-pane layout rework)

- **Layout primitive**: Switched `MainContentView` from `NavigationSplitView` to `HSplitView`. Two real problems with `NavigationSplitView` for the 3-toggle model: (1) `.navigationSplitViewColumnWidth(min: 0)` collapses a column to 0pt but still reserves its layout slot, so neighboring columns can't expand to fill the gap; (2) `NavigationSplitViewVisibility` is a 4-case enum with no value meaning "sidebar + detail, hide content" (which is exactly focus mode). `HSplitView` (NSSplitView wrapper) has fixed-order columns with flex widths — collapse a column to 0pt and the remaining columns naturally expand to fill.
- **Focus mode**: Replaced the width-zero trick (`.frame(minWidth: 0, idealWidth: 0, maxWidth: 0)`) with `if !focusMode { ContentView() }`. With `ContentView`'s `layoutPriority(1)`, collapsing to width 0 still claimed the leading layout slot and pushed `SidebarView` to the middle of the window. Removing `ContentView` from the tree entirely lets `HSplitView` relayout sidebar + right so sidebar is back at the leading edge and right expands across the freed space.
- **Toolbar**: `.toolbar { ToolbarItem(placement: .navigation) { } }` + `ToolbarItemGroup(placement: .primaryAction) { }` give the three pane toggles the native macOS toolbar (title-bar integration, accessibility, hover affordances, ⌘ shortcut hints) without any custom chrome.
- **State**: 3 independent `@Published` flags on `AppViewModel` — `sidebarVisible`, `rightVisible`, `focusMode` — each directly controls its own column's width (or in focus mode, whether `ContentView` is in the tree). `.animation(.easeInOut(duration: 0.18))` on each flag for smooth transitions.

## [v0.5.0] — 2026-06-16

### Added (Phase 5 — Polish)

- **Settings window**: Independent Settings window with 4 categories / 13 tabs
  - Personal: General, Appearance, Configuration, Personalization, Keyboard shortcuts
  - Integrations: Appshots, MCP Servers, Browser, Computer Use (placeholder)
  - Coding: Hooks, Connections, Git, Environments, Worktrees
  - Archived: Archived chats with restore/delete
- **Full keyboard shortcuts**: 27+ shortcuts across 6 categories (thread management, navigation, right tabs, panels, environment, global)
- **Animation system**: Duration tokens, easing functions, view extensions, reduce-motion support
- **Error handling**: 16 error states with banner, toast, and modal presentation
- **Accessibility**: a11y labels, keyboard navigation, high contrast support, reduce motion detection, dynamic type support
- **UI Tests**: 5 XCUITest suites for core flows (launch, new thread, panel switch, settings, theme)
- Settings window opens via ⌘, shortcut or sidebar ⚙ Settings link

### Changed

- Sidebar: Settings link now opens settings as independent window
- EntryPoint: Wired keyboard shortcuts via `.commands` modifiers
- Package.swift: Added SwiftAgentAppUITests target

## [v0.4.0] — 2026-06-15

### Added (Phase 4 — Advanced Features)

- Skills library with creation wizard
- MCP server integration (config, add/edit/delete)
- Worktree isolation with git worktree automation
- Appshots (Cmd+Cmd global shortcut + accessibility API capture)
- Composer + menu with 6 items and plugins submenu
- 4-tier permission system (Ask / Approve / Full / Custom)
- Right multi-tab system (Review, Terminal, Browser, Files, Side chat)
- DeepSeek 4-model support (V3, R1, V3-0324, Coder-V2)

## [v0.3.0] — 2026-06-14

### Added (Phase 3 — Multi-Thread + Persistence)

- Multi-thread support with sidebar list
- Thread create/rename/archive/delete
- SQLite persistence (Projects, Threads, Messages)
- Project management (create/rename/delete)
- Composer with slash commands (/help, /status, /clear, /compact)
- Thread state persistence across app restarts

## [v0.2.0] — 2026-06-13

### Added (Phase 2 — DeepSeek Integration)

- DeepSeekConfig + Keychain API key storage
- DeepSeekClient with streaming Chat Completions
- AppLLMProvider integration with SwiftAgentCore
- Composer 4 controls (+, Custom, model picker, send)
- Basic conversation flow with streaming responses

## [v0.1.0] — 2026-06-12

### Added (Phase 1 — Skeleton)

- SwiftAgentApp macOS SwiftUI target
- NavigationSplitView three-pane layout
- Design system (Color, Typography, Spacing, Radius)
- Sidebar with project and thread structure
- Content view with toolbar and empty state
- Right panel placeholder
- DeepSeek color scheme (dark mode)
