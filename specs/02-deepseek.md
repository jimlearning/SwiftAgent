# Phase 2 — DeepSeek Integration (Single conversation works)

> **Source spec**: `/Users/jim/SwiftAgent/.mavis/plans/swiftagent-macos-product-doc.md` §16.2 + §11
> **Goal**: User can send a message in the App and get a streaming response from DeepSeek V3.
> **Done when**: Type "你好" in Composer, see DeepSeek-V3 stream tokens into the message area in real time.

---

## Context

Phase 1 delivered the 3-pane UI shell. This phase wires it to a real LLM:
- A DeepSeek API client (OpenAI-compatible, baseURL = `https://api.deepseek.com/v1`)
- Keychain storage for the API key
- The Composer becomes functional
- A simplified conversation stream appears in the center pane (no Skills / MCP / tools yet)
- A single in-memory thread is fine — persistence is Phase 3

This phase ADDS a new `LLMProvider` implementation but does NOT remove the existing CLI/Core LLM. The new provider is for the App target.

---

## Acceptance Criteria

### A. DeepSeek config & keychain (per §11.1, §12.1)

- [ ] `Sources/SwiftAgentApp/DeepSeek/DeepSeekConfig.swift` defines:
  - `baseURL: URL = https://api.deepseek.com/v1`
  - `apiKey: String` (loadable from Keychain)
  - `defaultModel: DeepSeekModel = .v3`
- [ ] `DeepSeekModel` enum with cases: `v3` ("deepseek-chat"), `r1` ("deepseek-reasoner"), `v3_0324` ("deepseek-chat-0324"), `coderV2` ("deepseek-coder-v2") — 4 cases only
- [ ] `Sources/SwiftAgentApp/DeepSeek/KeychainStore.swift` uses Keychain (manual implementation OR KeychainAccess SPM dep) with service `com.swiftagent.api`, key `deepseek-api-key`
- [ ] `Package.swift` adds `KeychainAccess` SPM dependency (4.2.0+) and `swift-collections` (1.0.0+) if not already
- [ ] API key is NEVER logged or displayed in plaintext anywhere

### B. DeepSeek client (per §11.3)

- [ ] `Sources/SwiftAgentApp/DeepSeek/DeepSeekClient.swift` implements streaming chat completions
- [ ] Sends POST to `https://api.deepseek.com/v1/chat/completions`
- [ ] Auth: `Authorization: Bearer <api-key>` header
- [ ] Body shape: `{model, messages, stream: true, temperature: 0.7}` (R1 special-cased to omit temperature)
- [ ] Parses SSE `data: {...}` lines
- [ ] Handles `[DONE]` sentinel
- [ ] Decodes `choices[0].delta.content` for tokens
- [ ] Returns `AsyncThrowingStream<String, Error>` (or `AsyncStream<LLMEvent>`)
- [ ] Network errors throw with descriptive messages (timeout, 401, 429, 5xx)

### C. LLM provider integration

- [ ] `Sources/SwiftAgentApp/LLM/AppLLMProvider.swift` wraps `DeepSeekClient` and conforms to (or replaces) the existing `LLMProvider` protocol from SwiftAgentCore
- [ ] `AppState` (or `AppViewModel`) holds the current provider and config
- [ ] If API key is missing on launch, show a friendly setup screen (per §1.2 — "DeepSeek API Key 存 Keychain"): "Please add your DeepSeek API key in Settings → General" placeholder OK if Settings not yet implemented
- [ ] First-run UX: if no key, the App still launches with a banner suggesting to set the key — does NOT crash

### D. Composer (per §3.6, §5.7)

- [ ] `Content/ComposerView.swift` is now functional (replacing Phase 1 placeholder)
- [ ] 4 controls at the bottom of the composer (left to right):
  1. `+` button — opens an `AddMenu` (Phase 2 can have stub items: "Add photos & files" — disabled, plus a "Coming soon" divider item)
  2. `⚙️ Custom⌄` menu — opens permission picker (Phase 2: stub showing 4 labels per §5.4, all non-functional OK)
  3. `5.5 High⌄` double-layer menu — left = Reasoning strength (Low/Medium/High✓/Extra High), right = Model (DeepSeek-V3 ✓, DeepSeek-R1, DeepSeek-V3-0324, DeepSeek-Coder-V2) per §11.2 / §5.7
  4. `↑` send button — disabled when text empty, enabled when text non-empty; sends on click
- [ ] Send triggers `threadViewModel.send()` which calls `appLLMProvider.stream(...)`
- [ ] TextEditor (or TextField) with placeholder "Ask for follow-up changes"
- [ ] Enter sends, Shift+Enter inserts newline (per §6.5)
- [ ] Sending state: button shows spinner / disabled

### E. Conversation stream (per §5.1)

- [ ] `Content/MessageListView.swift` shows messages in order
- [ ] User messages: rounded bubble, `bgElevated` (#2A2A2A), right-aligned, corner radius 4pt (per §5.1)
- [ ] Assistant messages: NO bubble, just text directly on `bgContent` (#1C1C1C), left-aligned
- [ ] Streaming assistant message updates token-by-token (auto-scroll to bottom)
- [ ] Status row above streaming message: "Thought for Xs" (small gray text, `textSecondary` 12pt)
- [ ] For R1 model: show `reasoning_content` as a collapsible "Thinking..." block above the final answer
- [ ] MessageListView is scrollable, with auto-scroll on new content

### F. Thread state machine basics (per §7.1)

- [ ] `ThreadState` enum exists in `ViewModels/ThreadViewModel.swift` with at minimum: `.idle`, `.executing`, `.done`, `.failed`
- [ ] Sending message → `.executing`; stream complete → `.done`; error → `.failed`
- [ ] Composer disabled while `.executing`
- [ ] State changes visible in `MessageListView` (e.g., small status row)

### G. Error handling (per §9)

- [ ] `401 Unauthorized` → show error in composer area "API key invalid, please update in Settings"
- [ ] `402 Payment Required` → "DeepSeek balance low"
- [ ] `429 Rate Limit` → "Rate limit hit, retrying in Xs" with auto-retry (3 attempts, exponential backoff)
- [ ] `5xx` → auto-retry once, then surface error
- [ ] Network timeout → "Network error, please check connection"
- [ ] All errors never crash the app

### H. Build & test verification

- [ ] `swift build --disable-sandbox` succeeds with zero warnings
- [ ] `swift test --disable-sandbox --no-parallel` passes — no regressions to existing 232+ tests
- [ ] App launches, opens Composer, allows setting API key (or reading from env var `DEEPSEEK_API_KEY` as fallback)
- [ ] When key is set: typing "你好" + Enter streams a response from DeepSeek-V3

---

## Critical Anti-Patterns to Avoid (per §17 v1.2)

| # | Don't do this |
|---|---------------|
| 1 | ❌ Don't make "5 permission levels" — it's 4 (Ask for approval / Approve for me / Full access / Custom) |
| 13 | ❌ Don't put Z⌄ button in bottom-right of Composer — it lives in the toolbar (right side) |
| 14 | ❌ Don't use NSStatusBar — status is embedded in Composer |
| 21 | ❌ Don't include any OpenAI-family model names — DeepSeek ONLY |
| 22 | ❌ Don't let users type custom model names — only 4 fixed DeepSeek models |
| 11 | ❌ Don't give assistant messages bubbles — only user messages have bubbles |
| 12 | ❌ Don't colorize status row "Thought for Xs" — keep it small gray text |

---

## Out of Scope (deferred)

- Thread persistence across launches (Phase 3)
- Sidebar thread list population (Phase 3)
- Multiple Projects (Phase 3)
- Skills / MCP / Tools (Phase 4)
- Worktree / Appshots (Phase 4)
- Full Settings window (Phase 5)
- Slash commands (`/plan`, `/goal`, etc.) (Phase 4)

---

## Files to Create / Modify

```
Package.swift                                                          (MODIFY — add KeychainAccess, swift-collections deps)
Sources/SwiftAgentApp/
├── DeepSeek/
│   ├── DeepSeekConfig.swift                                            (NEW)
│   ├── DeepSeekModel.swift                                             (NEW)
│   ├── DeepSeekClient.swift                                            (NEW)
│   └── KeychainStore.swift                                             (NEW)
├── LLM/
│   └── AppLLMProvider.swift                                            (NEW)
├── Content/
│   ├── ComposerView.swift                                              (NEW — replace placeholder)
│   ├── MessageListView.swift                                           (NEW)
│   └── MessageBubbleView.swift                                         (NEW)
├── Modals/
│   ├── AddMenu.swift                                                   (NEW — stub)
│   ├── PermissionPicker.swift                                          (NEW — stub)
│   └── ModelPicker.swift                                               (NEW — the 5.5 High⌄ menu)
├── ViewModels/
│   ├── AppViewModel.swift                                              (NEW)
│   ├── ThreadViewModel.swift                                           (NEW)
│   └── ComposerViewModel.swift                                         (NEW)
└── DesignSystem/
    └── StatusDot.swift                                                 (NEW)
```

---

## Commit Strategy

```
feat(app): integrate DeepSeek API with streaming chat (phase 2)
```

---

**Output when complete:** `<promise>DONE</promise>`
