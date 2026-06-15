# Phase 3 — Multi-Thread + Persistence (Threads survive app restart)

> **Source spec**: `/Users/jim/SwiftAgent/.mavis/plans/swiftagent-macos-product-doc.md` §16.3 + §12 + §2.2
> **Goal**: Multiple threads, projects, slash commands — and they all survive an app restart via SQLite.
> **Done when**: Create 3 threads, quit app, reopen — all 3 still there with their full message history.

---

## Context

Phase 2 has a single in-memory thread. This phase:
- Adds SQLite persistence (using `vapor/sqlite-kit` OR raw `sqlite3` C API — pick the simpler one)
- Populates the Sidebar with real Projects → Threads structure
- Adds the complete Composer (slash commands, send states)
- Adds Project management

Schema details in §12.2. Persisted fields include thread state, mode, sandbox mode, execution env, model, reuse state, etc. Reuse state machine (60s window) per §7.2.

---

## Acceptance Criteria

### A. SQLite schema & storage (per §12.1, §12.2)

- [ ] Database file location: `~/Library/Application Support/SwiftAgent/threads.db`
- [ ] `Sources/SwiftAgentApp/Storage/Database.swift` initializes SQLite with WAL mode
- [ ] Schema includes:
  - `projects` table: `id TEXT PRIMARY KEY, name TEXT, path TEXT, created_at REAL, updated_at REAL`
  - `threads` table: `id TEXT PRIMARY KEY, project_id TEXT, title TEXT, state TEXT, reuse_state TEXT, mode TEXT, sandbox_mode TEXT, execution_env TEXT, model TEXT, created_at REAL, updated_at REAL`
  - `messages` table: `id TEXT PRIMARY KEY, thread_id TEXT, role TEXT, content TEXT, metadata TEXT, created_at REAL` with `idx_messages_thread` index
- [ ] Migrations idempotent (safe to run on every launch)
- [ ] Foreign key `messages.thread_id` → `threads.id` with `ON DELETE CASCADE`

### B. Repository layer

- [ ] `ThreadRepository` — CRUD: create, read, update, archive, delete; list by project
- [ ] `ProjectRepository` — CRUD: create, read, update, delete
- [ ] `MessageRepository` — append, list-by-thread
- [ ] Repositories are actor-isolated for thread safety
- [ ] Auto-save: every message append + every thread state change persists immediately
- [ ] On launch: load all projects + threads + last 50 messages per thread into memory

### C. Sidebar (per §2.2, §5.2)

- [ ] `Sidebar/SidebarView.swift` (rewrite from Phase 1 placeholder) renders the real data
- [ ] Top 4 entries: New chat (⌘N), Search (⌘F), Plugins, Automations — clicking "New chat" creates a new thread
- [ ] "Projects" section header with `+` button (creates a new Project)
- [ ] Project rows: `folder` SF Symbol + name + 8pt indent
- [ ] Thread rows under each project: 24pt additional indent, title (white) + right-aligned relative timestamp ("2w", "1w", "3w", "1mo")
- [ ] Selected thread: row gets light gray highlight; if unread → 8pt blue solid dot on left
- [ ] Empty project: shows "No chats" gray text
- [ ] "Chats (global)" section: threads with no `project_id`
- [ ] `⚙ Settings` at the bottom
- [ ] Right-click context menu on thread: Rename, Archive, Pin, Open in new window (per §6.1)
- [ ] Right-click on project: Rename, Delete (with confirm)

### D. Thread list interactions (per §6.1)

- [ ] `⌘N` → new global thread (no project)
- [ ] `⇧⌘O` → new thread in current project
- [ ] `⌥⌘N` → new "quick chat" (in current project, ephemeral)
- [ ] `⌥⌘R` → rename current thread (inline edit)
- [ ] `⇧⌘A` → archive current thread
- [ ] `⌥⌘P` → pin thread (pinned threads show at top of project)
- [ ] `⌘F` → focus search field, filters threads by title
- [ ] Selecting a thread loads its messages into `ContentView`

### E. ContentView — full message list (per §5.1)

- [ ] `MessageListView` shows full thread history (loaded from SQLite)
- [ ] User messages: bubbles (per Phase 2 spec)
- [ ] Assistant messages: no bubble, monospace text, left-aligned
- [ ] Tool calls (if any) shown as inline cards (Phase 3 may have zero tools, but rendering layer should exist)
- [ ] Auto-scroll to bottom on new content
- [ ] Manual scroll-up: don't auto-scroll (pause auto-scroll behavior)
- [ ] Top toolbar: thread title (click to rename inline) + breadcrumb (project name / branch)

### F. Composer — full functionality (per §5.7)

- [ ] `ComposerView` already has the 4 controls from Phase 2; this phase adds slash commands
- [ ] Typing `/` opens a popup with commands: `/help`, `/goal`, `/plan`, `/skills`, `/mcp`, `/status`, `/compact`, `/clear`, `/personality`, `/exit`
- [ ] `/help` → shows all commands in a popover
- [ ] `/status` → shows thread id, context usage %, current model
- [ ] `/clear` → clears context (asks for confirm), persists new state
- [ ] `/compact` → triggers compaction (Phase 3: stub that just shows "compacted N tokens" message)
- [ ] `/plan` → toggles Plan mode (visual indicator in toolbar)
- [ ] `/personality` → toggles between Pragmatic / Friendly
- [ ] Slash command palette: arrow keys navigate, Enter selects, Esc dismisses
- [ ] Send states: idle (button ↑), sending (spinner), error (red dot)
- [ ] Shift+Enter = newline; Enter = send

### G. Project management

- [ ] Create project: prompts for name + folder path
- [ ] Switch project: click in sidebar → instantly loads threads
- [ ] Default project: "Uncategorized" (where global threads go)
- [ ] Delete project: confirm modal → moves threads to "Uncategorized" (don't delete threads)

### H. Thread state persistence (per §12.3)

- [ ] Thread state changes (idle ↔ executing ↔ done ↔ failed) persist immediately
- [ ] Mode change (Code / Plan / Goal / Side) persists
- [ ] Sandbox mode selection persists
- [ ] Execution env (Local / Worktree / Cloud) persists
- [ ] Reuse state machine (per §7.2) implemented: new / active / idle (>60s) / resumed / paused
- [ ] App quit + relaunch: all state restored

### I. URL Scheme handling (per §2.5)

- [ ] `swiftagent://threads/new?prompt=...&path=...` opens new thread with prefilled prompt
- [ ] `swiftagent://threads/<uuid>` opens that thread
- [ ] `swiftagent://settings` opens settings (Phase 5; Phase 3 can show a stub "Settings coming soon")

### J. Build & test verification

- [ ] `swift build --disable-sandbox` succeeds with zero warnings
- [ ] `swift test --disable-sandbox --no-parallel` passes
- [ ] Manual smoke test: create 3 threads in 2 projects, send messages, quit, relaunch → all 3 threads + messages restored
- [ ] Test coverage for `ThreadRepository` CRUD operations (≥3 tests)
- [ ] Test coverage for slash command parsing (≥2 tests)

---

## Critical Anti-Patterns to Avoid (per §17 v1.2)

| # | Don't do this |
|---|---------------|
| 5 | ❌ Don't add intermediate layers (Workspaces/Folders) between Projects and Threads |
| 6 | ❌ Don't show extra dot states in thread list — only unread blue dot |
| 9 | ❌ Don't show confirmation when switching projects — direct switch |
| 17 | ❌ Don't show "settings/members" UI on Project — Project is just a folder concept |
| 18 | ❌ Don't add other badges to thread list — unread dot is the only status |
| 19 | ❌ Don't paginate "Edited N files" card across pages (N/A this phase) |

---

## Out of Scope (deferred)

- Skills / MCP / Worktree / Appshots (Phase 4)
- Full Settings window (Phase 5)
- Computer's Use / Voice input / Multi-window sync (later)

---

## Files to Create / Modify

```
Sources/SwiftAgentApp/
├── Storage/
│   ├── Database.swift                          (NEW)
│   ├── Migrations.swift                        (NEW)
│   ├── ThreadRepository.swift                  (NEW)
│   ├── ProjectRepository.swift                 (NEW)
│   └── MessageRepository.swift                 (NEW)
├── Sidebar/
│   ├── SidebarView.swift                       (REWRITE)
│   ├── ProjectListView.swift                   (NEW)
│   ├── ProjectRowView.swift                    (NEW)
│   ├── ThreadListView.swift                    (NEW)
│   └── ThreadRowView.swift                     (NEW)
├── Content/
│   ├── ContentView.swift                       (MODIFY — load real thread)
│   └── MessageListView.swift                   (REWRITE — load from DB)
├── Modals/
│   ├── SlashCommandPalette.swift               (NEW)
│   ├── NewProjectSheet.swift                   (NEW)
│   └── RenameThreadSheet.swift                 (NEW)
├── ViewModels/
│   ├── AppViewModel.swift                      (MODIFY — load from DB on init)
│   ├── ThreadViewModel.swift                   (MODIFY — persist on changes)
│   └── ProjectViewModel.swift                  (NEW)
└── URLHandling/
    └── URLRouter.swift                         (NEW)
Tests/SwiftAgentAppTests/
├── ThreadRepositoryTests.swift                 (NEW)
├── SlashCommandTests.swift                     (NEW)
└── ReuseStateTests.swift                       (NEW)
```

---

## Commit Strategy

```
feat(app): add multi-thread persistence and sidebar navigation (phase 3)
```

---

**Output when complete:** `<promise>DONE</promise>`
