# Technology Stack

**Analysis Date:** 2026-06-25

## Languages

**Primary:**
- Swift 6.3 - All source code across Core, CLI, and App targets. Target: arm64-apple-macosx26.0.

**Secondary:**
- Bash - Build and utility scripts (`scripts/build.sh`, `scripts/test.sh`, `scripts/ralph-loop.sh`)

## Runtime

**Environment:**
- Swift Package Manager (SPM) with swift-tools-version: 6.2
- macOS 15.0 minimum deployment target (macOS Sequoia)
- Xcode 26.4 / swiftlang-6.3.0.123.5 / clang-2100.0.123.102

**Package Manager:**
- Swift Package Manager (built into Swift toolchain)
- Lockfile: `Package.resolved` (present, tracks dependency versions)
- Local package defined at `Packages/Package.swift` for ClarcCore + ClarcChatKit

## Frameworks

**Core:**
- SwiftUI + AppKit - macOS app UI framework (`Sources/SwiftAgentApp/`)
- ArgumentParser 1.5.0 - CLI argument parsing (`Sources/SwiftAgentCLI/EntryPoint.swift`)
- Swift Collections 1.0.0 - Efficient data structures (OrderedSet, OrderedDictionary)
- KeychainAccess 4.2.0 - macOS Keychain API wrapper for secure API key storage
- KeyboardShortcuts 2.0.0 - Global keyboard shortcut handling for the macOS app
- SwiftTerm 1.3.0 - Terminal emulation backend (`Sources/SwiftAgentCLI/TerminalRenderer.swift`)
- ClarcCore (local) - Core chat data types and shared models (`Packages/Sources/ClarcCore`)
- ClarcChatKit (local) - Chat UI framework with `@MainActor` isolation (`Packages/Sources/ClarcChatKit`)
- WebKit - Browser panel (`Sources/SwiftAgentApp/RightTabs/panels/BrowserPanelView.swift`)

**System Frameworks (linked):**
- AppKit - Window management, native controls, NSApplication lifecycle
- SwiftUI - Declarative UI, `@StateObject`, `@EnvironmentObject`, `@main` entry point
- Foundation - Core types, URLSession, FileManager, Process, JSONSerialization
- Darwin - Terminal I/O, signal handling, raw mode (`Sources/SwiftAgentCLI/`)
- CryptoKit - OAuth PKCE (`Sources/SwiftAgentCore/MCP/OAuthPKCE.swift`)
- CoreGraphics - Screen coordinates and layout (`Sources/SwiftAgentCLI/LineEditor.swift`)
- SQLite3 (libsqlite3) - Embedded database (`Sources/SwiftAgentApp/Storage/Database.swift`)

**Testing:**
- XCTest - Native Swift testing framework. 258+ tests across 60+ suites.
- Test targets: `SwiftAgentCoreTests`, `SwiftAgentCLITests`, `SwiftAgentAppTests`, `SwiftAgentAppUITests`

**Build/Dev:**
- SPM `swift build --disable-sandbox` - Build all targets
- SPM `swift test --disable-sandbox --no-parallel` - Run all tests
- `xcodebuild -scheme SwiftAgentApp -destination 'platform=macOS' build` - Xcode build

## Key Dependencies

**Critical:**
- `swift-argument-parser` 1.5.0 - CLI entry point. All commands (ChatCommand, EvalCommand) use `@main` + `ParsableCommand`.
- `KeychainAccess` 4.2.0 - Secure API key persistence in macOS Keychain. Used by `KeychainStore` (`Sources/SwiftAgentApp/DeepSeek/KeychainStore.swift`).
- `SwiftTerm` 1.3.0 - Terminal emulation in the CLI target and App terminal panel (`Sources/SwiftAgentApp/RightTabs/panels/TerminalView.swift`).

**Infrastructure:**
- `swift-collections` 1.0.0 - OrderedDictionary for JSON value types and ordered collections
- `KeyboardShortcuts` 2.0.0 - Global hotkey registration (Cmd+Cmd for Appshots)
- `ClarcCore` (local) - Shared chat message types between Core and App
- `ClarcChatKit` (local) - Chat UI components with @MainActor isolation

## Configuration

**Environment:**
- No `.env` file detected. Configuration is resolved at runtime from:
  - Environment variables (`ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL`, `DEEPSEEK_API_KEY`, `OPENAI_API_KEY`)
  - macOS Keychain entries (`com.swiftagent.api` service, legacy "Claude Code" entry)
  - `~/.claude.json` file (Claude Code auth migration path)
- Config validation via `ConfigSchema` (`Sources/SwiftAgentCore/Config/ConfigSchema.swift`)
- Settings persisted via `UserDefaults` and SQLite

**Build:**
- `Package.swift` - SPM manifest (swift-tools-version 6.2)
- `Sources/SwiftAgentApp/Info.plist` - App bundle metadata, URL scheme registration, entitlements descriptions
- No `.swift-version`, `.swift-format`, `.swiftlint.yml`, or `.swiftformat` detected — no automated formatting/linting configs committed

## Platform Requirements

**Development:**
- macOS 15.0+ (Sequoia)
- Xcode 26.4 or later
- Swift 6.3 toolchain
- `--disable-sandbox` flag required for file system tests

**Production:**
- macOS 15.0+ desktop application
- CLI binary: `swift-agent` executable
- App binary: `SwiftAgentApp.app` with bundle ID `com.swiftagent.app`
- No containerization/Docker detected
- No server-side deployment detected (local-first agent)

---

*Stack analysis: 2026-06-25*
