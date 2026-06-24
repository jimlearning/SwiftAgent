# Task Plan: Replace Chat View with ClarcChatKit Architecture

## Goal
Replace the existing AppKit NSTableView-based chat view in SwiftAgentApp with the ClarcChatKit architecture (ChatView → messageScrollView + InputBarView + StatusLineView), porting ~20 files from /Users/jim/CLI/Clarc/Packages/Sources/ClarcChatKit/ and adapting them to SwiftAgent's type system.

## Current Phase
Phase 6 — Integration complete, build passing

## Phases

### Phase 1: Type Bridge & Design System Mapping ✅
- [x] Create ChatBridge.swift — @Observable bridge wrapping AppViewModel/ThreadViewModel
- [x] Map ClaudeTheme → existing DesignSystem tokens (ChatTheme.swift)
- [x] Create ChatDisplayMessage, ChatMessageBlock, ChatToolCall type adapters (ChatTypes.swift)
- [x] AtFileEntry, AtFileSearch, SlashCommandAdapter, SlashCommandFilter
- **Status:** complete

### Phase 2: Core Chat Views (ChatView, MessageListView) ✅
- [x] Port SwiftAgentChatView.swift — VStack { messageScrollView, InputBarView, StatusLineView }
- [x] Port MessageListView.swift — ScrollView + LazyVStack + streaming + fold
- [x] Port supporting subviews: StreamingMessageView, TransientGroupSummaryView, EmptySessionView, StreamingIndicatorView, PulseRingView, ElapsedTimeView
- **Status:** complete

### Phase 3: Message Bubble & Content Rendering ✅
- [x] Port MessageBubbleView.swift — user/assistant/error/compact-boundary bubbles
- [x] Port BubbleStyle.swift — bubble shape + background modifier
- [x] Port ThinkingBlockView.swift — expandable thinking display
- [x] Port ToolResultView.swift — expandable tool call display + diff view
- [ ] Port MarkdownView.swift / CodeBlockView — rich text rendering (deferred, non-blocking)
- **Status:** complete (core rendering done; Markdown deferred)

### Phase 4: InputBarView & Composer ✅
- [x] Port InputBarView.swift — text input + attachment previews + slash/at popups + send/stop
- [x] SlashCommandPopup, AtFilePopup for slash/@ autocomplete
- [ ] IMETextView (deferred — using SwiftUI TextField for now)
- **Status:** complete

### Phase 5: StatusLineView & Auxiliary ✅
- [x] Port StatusLineView.swift — project path, model, rate limits, context %, duration
- [ ] WebPreviewButton, FileDiffView, AskUserQuestionView (deferred, non-blocking)
- **Status:** complete (core status bar done)

### Phase 6: Integration & Cleanup ✅
- [x] Rewire ContentView.swift to use SwiftAgentChatView
- [x] Remove composerDragHeight and scrollToBottomButton from ContentView
- [x] Build & verify zero errors
- [ ] Remove old AppKit chat views (AppKitChatBridge, ChatTableView, etc.) — deferred until new views validated at runtime
- [ ] Remove LegacyMessageListView, LegacyMessageBubbleView — deferred until new views validated at runtime
- [ ] Remove ComposerView, ComposerViewModel — deferred until new views validated at runtime
- **Status:** integration complete, old files retained for safety

## New Files Created (Content/ChatView/)
| File | Purpose |
|------|---------|
| ChatTypes.swift | Type adapters (ChatDisplayMessage, ChatMessageBlock, ChatToolCall, ToolCategory, AtFileEntry, AtFileSearch, SlashCommandAdapter, SlashCommandFilter) |
| ChatTheme.swift | Design token mapping (ClaudeTheme → DesignSystem) |
| ChatBridge.swift | @Observable bridge + AppViewModel associated-object extensions |
| SwiftAgentChatView.swift | Top-level ChatView: messageScrollView + InputBarView + StatusLineView |
| MessageListView.swift | ScrollView + LazyVStack with streaming/settled partitioning |
| MessageBubbleView.swift | MessageBubbleView + BubbleStyle + ThinkingBlockView + AnyInsettableShape |
| InputBarView.swift | Text input + SlashCommandPopup + AtFilePopup + attachments + send/stop |
| StatusLineView.swift | Bottom status bar (project path, model, rate limits, context %, duration) |
| ToolResultView.swift | Expandable tool call display with diff view |
| PulseRingView.swift | Animated pulse ring indicator |

## Existing Files Modified
| File | Change |
|------|--------|
| Content/ContentView.swift | Replaced AppKitChatBridge + ComposerView with SwiftAgentChatView |
| Content/ChatBlockViews.swift | Renamed ThinkingBlockView → LegacyThinkingBlockView |
| Content/ChatTableRowView.swift | Updated references to LegacyThinkingBlockView |
| Content/MessageListView.swift → LegacyMessageListView.swift | Renamed to avoid naming conflict |
| Content/MessageBubbleView.swift → LegacyMessageBubbleView.swift | Renamed to avoid naming conflict |

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Create ChatBridge as @Observable adapter | Minimizes changes to existing AppViewModel/ThreadViewModel |
| Put new views in Content/ChatView/ | Clean separation during transition |
| Map ClaudeTheme → DesignSystem | SwiftAgent already has a design system |
| Keep existing data flow (AppViewModel → ThreadViewModel) | Avoids rewriting the entire app state management |
| Use associated objects for AppViewModel extensions | Don't modify original source; noninvasive |
| Rename old views with Legacy prefix | Avoid SPM "multiple producers" errors without deleting code |
| Defer MarkdownView port | Non-blocking; basic text rendering works |
| Defer old code removal | Keep old views until new ones validated at runtime |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| SlashCommandRegistry invalid redeclaration | 1 | Renamed to SlashCommandFilter |
| ChatMessage ambiguous redeclaration | 1 | Renamed to ChatDisplayMessage |
| View/Color not in scope (ChatTypes.swift) | 1 | Added import SwiftUI |
| static var concurrency error | 1 | Changed to nonisolated(unsafe) |
| Multiple producers for MessageListView.swift.o | 1 | Renamed old file to LegacyMessageListView.swift |
| Multiple producers for MessageBubbleView.swift.o | 1 | Renamed old file to LegacyMessageBubbleView.swift |
| ThinkingBlockView invalid redeclaration | 1 | Renamed old class to LegacyThinkingBlockView |
| JSONValue has no subscripts | 1 | Added JSONValue subscript + stringValue helpers |
| ToolCategory has no member 'execution' | 1 | Changed to switch on .kind property |
| AtFileEntry undefined | 1 | Added AtFileEntry + AtFileSearch to ChatTypes.swift |
| Bindable requires @Observable | 1 | Used Binding(get:set:) for @ObservableObject compatibility |
| fileListCache concurrency unsafe | 1 | Added nonisolated(unsafe) |
