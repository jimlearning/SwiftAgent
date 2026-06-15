# Phase 5 — Polish (Settings, shortcuts, animations, errors, a11y)

> **Source spec**: `/Users/jim/SwiftAgent/.mavis/plans/swiftagent-macos-product-doc.md` §16.5 + §6, §8, §9, §10.9, §15
> **Goal**: Ship-quality polish — full Settings page, complete shortcut table, animations, all 16 error states, accessibility, UI tests.
> **Done when**: All §10.9 settings tabs work, all §6 shortcuts bound, all §8 animations in place, all §9 error states handled, §15 a11y passes, UI tests cover core flows.

---

## Context

Phases 1-4 delivered a functional SwiftAgent macOS App. This phase polishes to ship quality:
- Complete Settings page (4 categories × 13 tabs) per §10.9
- Full keyboard shortcut table (25+ shortcuts) per §6
- Animation system per §8
- 16 error states per §9
- Accessibility (a11y) per §15
- Xcode UI Tests for core flows
- Documentation updates (CLAUDE.md, README.md, docs/)

---

## Acceptance Criteria

### A. Settings window (per §10.9)

- [ ] Settings is an **independent new window** (per §17 #23 anti-pattern), opened via `⚙ Settings` in sidebar or `⌘,`
- [ ] Window has: `← Back to app` link top-left, `Search settings...` search field top-right
- [ ] Left sidebar: 4 categories (Personal / Integrations / Coding / Archived) with 13 total tabs

#### Personal (5 tabs)

- [ ] **General** — Work mode picker, Permission default picker (4-tier), Theme picker, etc.
- [ ] **Appearance** — Theme: Light / Dark / System; 8 fields per theme: Theme preset, Accent, Background, Foreground, UI font, Code font, **Translucent sidebar toggle** (ON = NSVisualEffectView), **Contrast slider** (0-100)
- [ ] **Configuration** — Default model picker (DeepSeek 4 options), Default reasoning level, Default sandbox mode
- [ ] **Personalization** — Personality (Pragmatic / Friendly dropdown), Custom instructions (text area), Memory (list of saved memories with delete)
- [ ] **Keyboard shortcuts** — Full table (see §B below) with search/filter

#### Integrations (4 tabs)

- [ ] **Appshots** — Enable toggle, permission status, "Open System Settings" button
- [ ] **MCP servers** — List + Add/Edit/Delete (already exists from Phase 4, now in settings)
- [ ] **Browser** — Default search engine, homepage, allow-list
- [ ] **Computer use** — Placeholder "Coming in v1.1"

#### Coding (5 tabs)

- [ ] **Hooks** — Pre/post command hooks editor (TOML)
- [ ] **Connections** — SSH / remote dev machine list
- [ ] **Git** — Default branch, commit message template, push behavior
- [ ] **Environments** — Local / Worktree / Cloud (Cloud disabled in v1.0)
- [ ] **Worktrees** — Auto-cleanup toggle, base branch picker

#### Archived (1 tab)

- [ ] **Archived chats** — List of archived threads with Restore / Delete permanently

#### Visual spec for settings

- [ ] Per §10.9: left sidebar = category list, right = active tab content
- [ ] Top: `← Back to app` + `Search settings...`
- [ ] All text uses design system fonts
- [ ] Each setting has `accessibilityLabel` (per §15)

### B. Full keyboard shortcuts (per §6)

- [ ] All 25+ shortcuts from §6.1-§6.5 implemented as `keyboardShortcut` modifiers in `.commands`
- [ ] **Thread management** (8): `⌘N`, `⇧⌘O`, `⌥⌘N`, `⌥⌘S`, `⌥⌘P`, `⌥⌘R`, `⇧⌘A`, `⌘F`
- [ ] **Navigation** (6): `⌘L`, `⌘[`, `⌘]`, `^Tab`, `⇧⌘]`, `^⇧Tab`, `⇧⌘[`
- [ ] **Right multi-Tab panel** (5+ shortcuts that open new tabs): `^⇧G` (new Review tab), `⌃`` (new Terminal tab), `⌘T` (new Browser tab), `⌘P` (new Files tab), `⌥⌘S` (new Side chat tab), `⌘W` (close current tab), `^⇧}` / `⌥⌘→` (next tab), `^⇧{` / `⌥⌘←` (prev tab), `^⇧⌘→` (move tab right), `^⇧⌘←` (move tab left)
- [ ] **Panels** (3): `⌘J` (Composer), `⇧⌘B` (right panel), `⌘B` (left sidebar)
- [ ] **Environment** (2): `⇧⌘D` (env action 1)
- [ ] **Global** (5): `Cmd+Cmd` (Appshots), `Enter` (send), `Shift+Enter` (newline), `Esc+Esc` (edit last), `^M` (voice input — stub OK)
- [ ] Settings → Keyboard shortcuts tab shows the full table with custom shortcut rebinding

### C. Animation system (per §8)

- [ ] All animations from §8.1 implemented:
  - Appshots success ✓: 1.2s scale + opacity transition
  - Thread list add/remove: 200-300ms ease-in-out
  - Diff row expand/collapse: 150-200ms ease-out
  - Button hover: 100ms linear
  - Composer focus: 150ms linear
  - "Thought for Xs" status: 200ms opacity + move-from-top
  - Modal popup: 250ms spring
  - Toast: 200ms enter / 300ms exit (move from bottom + opacity)
- [ ] Per §8.2: nothing blocks user input, no spring bounce > 0.5, fail-silent fallbacks
- [ ] Honors macOS "Reduce motion" accessibility setting (auto-detect via `@Environment(\.accessibilityReduceMotion)`)

### D. Error states (per §9.1 — 16 categories)

All 16 must have UI handling:

- [ ] **1. Sandbox denied** — modal + clear action
- [ ] **2. Network reconnection** — top banner with auto-retry
- [ ] **3. 429 rate limit** — top banner with countdown
- [ ] **4. 5xx model error** — top banner + retry/switch model
- [ ] **5. Worktree conflict** — sidebar item with conflict marker + "Choose base" prompt
- [ ] **6. 401 invalid key** — top banner + "Update key" link → settings
- [ ] **7. 402 low balance** — top banner + "Top up" link
- [ ] **8. Appshot permission** — toast + "Open System Settings" button
- [ ] **9. Appshot capture failed** — toast "Cannot capture, try again"
- [ ] **10. MCP disconnected** — input bar above composer + auto-reconnect
- [ ] **11. Skill load failed** — log line in `~/.swiftagent/logs/`, skipped silently in UI
- [ ] **12. Diff merge failed** — error bubble in conversation + "Manual merge" option
- [ ] **13. /goal persistence failed** — toast warning, falls back to in-memory
- [ ] **14. Project switch data loss** — auto-stash + recover on return
- [ ] **15. Thread list > 1000** — virtual scrolling (LazyVStack)
- [ ] **16. Network proxy** — banner + "Configure HTTP_PROXY" link

Visual spec per §9.2:
- Fatal: modal + red icon
- Retryable: top banner + composer still usable
- Warning: bottom toast, 2-3s auto-dismiss
- Network/rate: persistent top banner with countdown

### E. Accessibility (per §15)

- [ ] All interactive elements have `accessibilityLabel`
- [ ] Composer has `accessibilityLabel("Send a message to SwiftAgent")` and `.isKeyboardKey` trait
- [ ] Status dots have textual alternatives ("executing", "failed", etc.)
- [ ] Tab/Enter/Space activate all buttons
- [ ] macOS **Increase Contrast** detected + honored (boost border contrast)
- [ ] macOS **Reduce Motion** detected + animations shortened/disabled
- [ ] macOS **Dynamic Type** honored (font sizes scale)
- [ ] All text uses semantic colors (no pure-color-only signaling)
- [ ] VoiceOver walkthrough test passes (manual or via UI test)

### F. UI Tests (Xcode)

- [ ] `Tests/SwiftAgentAppUITests/` exists with at least:
  - `LaunchAndSeeLayout` — app launches, all 3 panes visible
  - `NewThreadSendsMessage` — `⌘N` creates thread, type, send, see response placeholder
  - `SwitchPanel` — `⌃⇧G` opens Review, `⌃\`` opens Terminal, ESC closes
  - `SettingsOpens` — `⌘,` opens settings window
  - `ThemeSwitch` — toggle Light/Dark, verify bg color changes
- [ ] Tests can run via `xcodebuild test -scheme SwiftAgentApp` (Phase 5: tests are runnable but may skip if xcuitest env not available)

### G. Documentation (per CLAUDE.md / AGENTS.md / docs/)

- [ ] `CLAUDE.md` updated to mention the new SwiftAgentApp target and build commands
- [ ] `AGENTS.md` identical to CLAUDE.md
- [ ] `docs/ARCHITECTURE.md` updated with SwiftAgentApp module diagram
- [ ] `docs/ROADMAP.md` updated — Phase 1-5 marked complete, next priorities listed
- [ ] `README.md` updated — mentions macOS App alongside CLI
- [ ] `docs/AI_HANDOFF.md` appended with Phase 1-5 summary
- [ ] `CHANGELOG.md` (new) — entries for v0.1.0 (skeleton) through v0.5.0 (polish)

### H. Build & final verification

- [ ] `swift build --disable-sandbox` succeeds with zero warnings
- [ ] `swift test --disable-sandbox --no-parallel` passes
- [ ] Xcode build: `xcodebuild -scheme SwiftAgentApp -destination 'platform=macOS' build` succeeds
- [ ] Manual smoke: full flow works end-to-end (create project, create thread, run worktree, send message, capture appshot, switch panels, open settings, switch theme, see animations, hit error states, verify a11y)

---

## Critical Anti-Patterns to Avoid (per §17 v1.2)

| # | Don't do this |
|---|---------------|
| 23 | ❌ Don't make Settings an in-app popup — it must be an independent window |
| 24 | ❌ Don't share Accent color between Light/Dark — they should be independently configurable |
| 25 | ❌ Don't use Material Design style — macOS HIG + OpenAI-family visual language |

---

## Out of Scope (deferred to v1.1+)

- Computer Use (v1.1)
- 6 role plugins (v1.1)
- Face ID / password lock (v1.1)
- Mobile companion (v1.2)
- Sites deployment
- iOS Live Activities

---

## Files to Create / Modify

```
Sources/SwiftAgentApp/
├── Settings/
│   ├── SettingsWindow.swift                                       (NEW)
│   ├── SettingsSidebar.swift                                      (NEW)
│   ├── SettingsSearch.swift                                       (NEW)
│   ├── personal/
│   │   ├── GeneralSettings.swift                                  (NEW)
│   │   ├── AppearanceSettings.swift                               (NEW)
│   │   ├── ConfigurationSettings.swift                            (NEW)
│   │   ├── PersonalizationSettings.swift                          (NEW)
│   │   └── KeyboardShortcutsSettings.swift                        (NEW)
│   ├── integrations/
│   │   ├── AppshotsSettings.swift                                 (NEW)
│   │   ├── MCPServersSettings.swift                               (NEW)
│   │   ├── BrowserSettings.swift                                  (NEW)
│   │   └── ComputerUseSettings.swift                              (NEW — placeholder)
│   ├── coding/
│   │   ├── HooksSettings.swift                                    (NEW)
│   │   ├── ConnectionsSettings.swift                              (NEW)
│   │   ├── GitSettings.swift                                      (NEW)
│   │   ├── EnvironmentsSettings.swift                             (NEW)
│   │   └── WorktreesSettings.swift                                (NEW)
│   └── archived/
│       └── ArchivedChatsSettings.swift                            (NEW)
├── Animations/
│   ├── AnimationTokens.swift                                      (NEW — durations, easings)
│   └── ViewExtensions.swift                                       (NEW — .swiftuiFade, .swiftuiSlide)
├── Errors/
│   ├── ErrorBannerView.swift                                      (NEW)
│   ├── ErrorToastView.swift                                       (NEW)
│   ├── ErrorModalView.swift                                       (NEW)
│   └── ErrorPresenter.swift                                       (NEW)
├── Accessibility/
│   └── A11yExtensions.swift                                       (NEW)
└── Shortcuts/
    └── ShortcutRegistry.swift                                     (NEW — single source of truth)
Tests/SwiftAgentAppUITests/
├── LaunchAndSeeLayout.swift                                       (NEW)
├── NewThreadSendsMessage.swift                                    (NEW)
├── SwitchPanel.swift                                              (NEW)
├── SettingsOpens.swift                                            (NEW)
└── ThemeSwitch.swift                                              (NEW)
CHANGELOG.md                                                       (NEW)
CLAUDE.md                                                          (MODIFY)
AGENTS.md                                                          (MODIFY)
docs/ARCHITECTURE.md                                               (MODIFY)
docs/ROADMAP.md                                                    (MODIFY)
docs/AI_HANDOFF.md                                                 (MODIFY)
README.md                                                          (MODIFY)
```

---

## Commit Strategy

```
feat(app): polish settings, shortcuts, animations, errors, a11y (phase 5)
docs: update docs and changelog for v0.5.0
```

---

**Output when complete:** `<promise>DONE</promise>`
