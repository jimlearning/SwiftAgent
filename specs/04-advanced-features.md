# Phase 4 — Advanced Features (Skills / MCP / Worktree / Appshots)

> **Source spec**: `/Users/jim/SwiftAgent/.mavis/plans/swiftagent-macos-product-doc.md` §16.4 + §5.6, §10.1-§10.4, §10.7, §10.8, §13
> **Goal**: Skills / MCP / Worktree / Appshots all work; Composer `+` menu is complete with all 6 items.
> **Done when**: A user can load a Skill, register an MCP server, run a thread in a Worktree, and press `Cmd+Cmd` to capture a screen and inject it as context.

---

## Context

Phases 1-3 gave us a multi-thread chat app with DeepSeek. This phase reuses the existing `SwiftAgentCore` engines and wires them into the App:
- `SwiftAgentCore/Skills/` — skill loader + auto-routing (Phase 4: surface it in UI)
- `SwiftAgentCore/MCP/` — MCP server connection + tool registration
- `SwiftAgentCore/Tools/` (git) — worktree automation
- `SwiftAgentCore/Safety/` — 4-tier permission system
- macOS native APIs — global hotkey, screen capture, accessibility

The "reuse, don't reinvent" principle is critical here per §13.1.

---

## Acceptance Criteria

### A. Skills library (per §10.1)

- [ ] `Sources/SwiftAgentApp/Skills/SkillsView.swift` shows the Skills library
- [ ] Skills loaded from 3 scopes: `~/.swiftagent/skills/` (user), `.swiftagent/skills/` (project), `/etc/swiftagent/skills/` (system)
- [ ] Each skill is a folder with `SKILL.md` (per §10.1 SKILL.md structure: name, description, When to use, When NOT, Workflow, Output format, Notes)
- [ ] Skills list shows: name, description, scope badge (User/Project/System)
- [ ] Clicking a skill shows full SKILL.md content
- [ ] "Create skill" button opens a wizard: name, description, scope, template body
- [ ] User can invoke a skill explicitly with `$skill-name` in Composer
- [ ] AI auto-routing: when user sends a message, the SwiftAgentCore Skills engine matches description → injects skill body into context (no manual user action needed)
- [ ] Skills are NOT shown as a "plugin marketplace" — just a library (per §10.1 anti-patterns)

### B. MCP integration (per §10.8)

- [ ] `Sources/SwiftAgentApp/MCP/MCPConfigView.swift` shows MCP server list
- [ ] MCP config from `~/.swiftagent/config.toml` (TOML format with `[[mcp_servers]]` entries)
- [ ] User can add stdio MCP server (name, command, args, env)
- [ ] User can add SSE/HTTP MCP server (name, url, headers)
- [ ] Server list shows: name, type, status (connected/disconnected), tools exposed
- [ ] Click server → expand to show its tools (name + description)
- [ ] Connection status auto-refreshes (poll every 5s)
- [ ] Reuse `SwiftAgentCore/MCP/` engine — do not reimplement the protocol
- [ ] "Reconnect" button per server
- [ ] "Test connection" button per server
- [ ] Failed connections show last error in red text

### C. Worktree integration (per §10.3)

- [ ] Thread creation flow lets user pick execution env: `Local` / `Worktree` (Cloud deferred)
- [ ] When Worktree is chosen, the App creates a `git worktree` automatically using SwiftAgentCore's git tool
- [ ] Worktree path: `<repo>/../.swiftagent-worktrees/<thread-id>/`
- [ ] Branch name: `swiftagent/thread-<short-id>`
- [ ] Toolbar shows `Branch: swiftagent/thread-3c7e` instead of full path
- [ ] "Apply to main" button in thread → shows merge strategy options (merge / squash / rebase)
- [ ] After applying, worktree is cleaned up (branch kept, worktree removed)
- [ ] Per §10.3 anti-patterns: do NOT show `.git/worktrees/` paths; do NOT let user pick which worktree
- [ ] Worktree state visible in sidebar (small icon next to thread title)

### D. Appshots — global hotkey (per §5.6, §10.4)

- [ ] `Sources/SwiftAgentApp/Appshots/AppshotCapture.swift` implements screen capture
- [ ] Global hotkey: `Cmd+Cmd` (double-tap Command key, ~200ms window) — uses `KeyboardShortcuts` SPM dep OR NSEvent monitoring
- [ ] Capture target: currently active application window (NOT full screen, per §5.6 anti-patterns)
- [ ] After capture: image is injected as an attachment to the currently active thread (via `threadViewModel.addAttachment`)
- [ ] Success feedback: 1.2s animated ✓ checkmark in bottom-right of App window (per §5.6, §8.1)
- [ ] Capture also extracts text via macOS Accessibility API (`AXUIElementCopyAttributeValue` for `kAXValueAttribute`)
- [ ] Failure handling (per §9.1): permission denied → toast "Enable accessibility in System Settings"; window hidden → toast "Cannot capture"; quiet fallback
- [ ] First launch: show a one-time prompt "SwiftAgent needs screen recording permission" → opens System Settings
- [ ] 60s reuse: if active thread was interacted with in last 60s, attachment goes to that thread; else creates new thread (per §7.2)

### E. Composer `+` menu — complete (per §5.7)

- [ ] `+` button now opens the full 6-item menu (per §5.7 spec table)
- [ ] Items:
  1. Add photos & files (icon: paperclip) — opens file picker, attaches to composer
  2. Create → submenu (new file / new project) — wired to project manager
  3. Plan mode (toggle) — switches current thread to plan mode
  4. Pursue goal (toggle) — switches current thread to goal mode
  5. Plugins → submenu showing installed MCP servers + skills (count = N installed)
  6. (Optional) Appshot (icon: camera) — triggers Cmd+Cmd manually
- [ ] Menu styled to match Codex App visual spec (icon + label, dividers between groups)

### F. 4-tier permission system (per §5.4, §10.7, §14)

- [ ] `Modals/PermissionModal.swift` shows the 4-tier picker when `⚙️ Custom⌄` clicked
- [ ] 4 options (icon + main text + sub text):
  1. ✋ Ask for approval — "Always ask to edit external files and use the internet"
  2. ⏱ Approve for me — "Only ask for actions detected as potentially unsafe"
  3. 🛡 Full access — "Unrestricted access to the internet and any file on your computer"
  4. ⚙ Custom (config.toml) ✓ (default selected) — "Uses permissions defined in config.toml"
- [ ] Title: "How should SwiftAgent actions be approved?"
- [ ] "Learn more" link in top-right
- [ ] Selection persists per-thread in `sandbox_mode` column
- [ ] Project-level rules (`.swiftagent/rules/*.toml`) respected: read at thread start, apply during execution
- [ ] When agent triggers an action that requires approval, show modal asking user to approve/deny
- [ ] Per §17 anti-pattern: do NOT make the modal a system-level dialog — app-internal modal only

### G. Tools / tool calls in conversation (per §5.1, §5.3)

- [ ] When SwiftAgentCore agent invokes a tool (Bash / Read / Edit / etc.), the conversation stream shows a `ToolCallCard`
- [ ] Tool call card: tool name, args (collapsed by default), result (collapsed by default)
- [ ] Per §5.3: "Edited N files" card has `Undo⟲` and `Review` buttons (Review opens a NEW Review tab in the right pane multi-Tab workspace — does not toggle)
- [ ] Tool results shown as collapsible code blocks (monospace, dark bg, 1px border)
- [ ] No per-line Accept/Reject buttons (per §17 #3)

### H. Diff Review panel content (per §2.4, §5.3)

- [ ] When user clicks `Review` entry in right panel, `panels/ReviewPanelView.swift` opens
- [ ] Or: pressing the Review shortcut `⌃⇧G` opens a new Review tab in the right pane workspace (multi-Tab per §3.3 v1.2)
- [ ] Shows: top bar with `2 files edited +123 −42` (green/red) and `Review ↗` link
- [ ] File list: filename + `+X -Y` + status dot + chevron (clickable to expand)
- [ ] Expanded file: unified diff (green for `+`, red for `-`)
- [ ] No per-line Accept/Reject (per §17 #3)
- [ ] Each Review tab is independent: opening a second Review tab creates a fresh view (e.g. for comparing two different snapshots)

### I. Build & test verification

- [ ] `swift build --disable-sandbox` succeeds with zero warnings
- [ ] `swift test --disable-sandbox --no-parallel` passes
- [ ] Manual smoke: create a Skill, register a fake MCP server, run a thread in a worktree, capture a screen with Cmd+Cmd — all work
- [ ] Test coverage for skill auto-routing (≥2 tests)
- [ ] Test coverage for worktree creation/cleanup (≥2 tests)

---

## Critical Anti-Patterns to Avoid (per §17 v1.2)

| # | Don't do this |
|---|---------------|
| 3 | ❌ Don't add per-line Accept/Reject buttons in diff — only batch review |
| 4 | ❌ Don't make right panel "5 entry mutually exclusive" (v1.1 error) — it MUST be multi-Tab |
| 8 | ❌ Don't bury Appshots config 4 levels deep — Settings → Integrations → Appshots (1 level) |
| 10 | ❌ Don't remove the "Custom" permission option — it's the default |
| 15 | ❌ Don't make Appshots a full-screen capture — current active window only |
| 16 | ❌ Don't make Skills a "plugin marketplace" UI — it's a library |
| 20 | ❌ Don't make permission modal a system-level dialog — app-internal only |

---

## Out of Scope (deferred to Phase 5)

- Full Settings window with all 4 categories × 13 tabs
- 25+ keyboard shortcuts (Phase 4 has the essential ones, Phase 5 adds the rest)
- 16 error states
- Animations polish
- a11y audit
- Xcode UI Tests

---

## Files to Create / Modify

```
Package.swift                                                       (MODIFY — add KeyboardShortcuts dep)
Sources/SwiftAgentApp/
├── Skills/
│   ├── SkillsView.swift                                            (NEW)
│   ├── SkillCard.swift                                             (NEW)
│   ├── SkillCreatorSheet.swift                                     (NEW)
│   └── SkillScope.swift                                            (NEW)
├── MCP/
│   ├── MCPConfigView.swift                                         (NEW)
│   ├── MCPServerCard.swift                                         (NEW)
│   ├── AddMCPServerSheet.swift                                     (NEW)
│   └── MCPConfigStore.swift                                        (NEW — TOML reader/writer)
├── Worktree/
│   ├── WorktreeManager.swift                                       (NEW — wraps SwiftAgentCore git tool)
│   └── WorktreePickerSheet.swift                                   (NEW)
├── Appshots/
│   ├── AppshotCapture.swift                                        (NEW)
│   ├── GlobalHotkey.swift                                          (NEW)
│   ├── AXTextExtractor.swift                                       (NEW)
│   ├── AppshotToastView.swift                                      (NEW)
│   └── AppshotPermissionPrompt.swift                               (NEW)
├── Modals/
│   ├── PermissionModal.swift                                       (NEW)
│   ├── AddMenu.swift                                               (REWRITE — full 6 items)
│   └── PluginsSubmenu.swift                                        (NEW)
├── RightTabs/
│   ├── panels/
│   │   └── ReviewPanelView.swift                                   (NEW — diff display)
│   ├── TabContentView.swift                                        (MODIFY — wire to Review panel)
│   └── TabShortcutCommands.swift                                   (MODIFY — Review shortcut opens new tab)
├── Content/
│   ├── ToolCallCard.swift                                          (NEW)
│   ├── EditSummaryCard.swift                                       (NEW)
│   └── MessageListView.swift                                       (MODIFY — render tool calls + edit summaries)
└── ViewModels/
    └── ThreadViewModel.swift                                       (MODIFY — handle attachments, tool calls)
Tests/SwiftAgentAppTests/
├── SkillRoutingTests.swift                                         (NEW)
├── WorktreeTests.swift                                             (NEW)
└── PermissionFlowTests.swift                                       (NEW)
```

---

## Commit Strategy

```
feat(app): add skills, MCP, worktree, and appshots (phase 4)
```

---

**Output when complete:** `<promise>DONE</promise>`
