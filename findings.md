# Findings & Decisions

## Requirements
- Replace chat view with ClarcChatKit architecture: ChatView → VStack { messageScrollView, InputBarView, StatusLineView }
- messageScrollView = MessageListView (ScrollView + LazyVStack of MessageBubble with streaming support)
- InputBarView = text composer with slash commands, @file mentions, attachments, send/stop buttons
- StatusLineView = bottom status bar with project path, model, rate limits, context%, duration
- Must work with existing AppViewModel / ThreadViewModel data flow

## Research Findings
- ClarcChatKit is an SPM package at /Users/jim/CLI/Clarc/Packages/Sources/ClarcChatKit/ (21 Swift files)
- Core views: ChatView (99 lines), MessageListView (457 lines), InputBarView (773 lines), StatusLineView (183 lines)
- MessageBubble (480 lines) handles user/assistant/error/compact-boundary rendering with block iteration
- ClarcChatKit depends on ClarcCore for types: ChatMessage, ToolCall, MessageBlock, ChatBridge, WindowState, ClaudeTheme
- ClarcChatKit uses @Observable (iOS 17+/macOS 14+) with @Environment for dependency injection
- SwiftAgent uses @ObservableObject with @EnvironmentObject (traditional SwiftUI)
- Current SwiftAgent chat uses AppKit NSTableView via AppKitChatBridge → needs complete replacement
- ClaudeTheme uses static properties for all design tokens (colors, fonts, spacing, corner radii)
- SwiftAgent has its own DesignSystem with Color, Typography, Spacing, Radius tokens
- The BubbleStyle modifier uses AnyInsettableShape type erasure for uneven rounded rectangles
- MessageListView has sophisticated streaming/settled message partitioning with transient tool grouping
- InputBarView uses IMETextView (NSTextView wrapper) for proper IME support
- MarkdownView has its own block parser + syntax highlighting + code block rendering

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| Create ChatBridge as @Observable adapter | Decouples chat views from AppViewModel; enables gradual migration |
| Map ClaudeTheme → existing DesignSystem | Avoids duplicate design token system; SwiftAgent tokens already exist |
| Place new views in Content/ChatView/ | Clean separation during transition; easy to remove old files later |
| Keep Composer/ directory for now | InputBarView subsumes composer functionality; remove old Composer after Phase 6 |
| Use @Environment for ChatBridge, @EnvironmentObject for AppViewModel | ChatBridge is new; AppViewModel stays for window-level state |
| Port MarkdownView as-is with DesignSystem mapping | Too complex to rewrite; token mapping is sufficient |

## Issues Encountered
| Issue | Resolution |
|-------|------------|
|       |            |

## Resources
- ClarcChatKit source: /Users/jim/CLI/Clarc/Packages/Sources/ClarcChatKit/
- Current SwiftAgent chat: /Users/jim/SwiftAgent/Sources/SwiftAgentApp/Content/
- SwiftAgent DesignSystem: /Users/jim/SwiftAgent/Sources/SwiftAgentApp/DesignSystem/
- ClarcCore types: /Users/jim/CLI/Clarc/Packages/Sources/ClarcCore/
---
