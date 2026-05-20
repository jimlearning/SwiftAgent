# Phase 0: 项目脚手架与基础设施

## Requirements
- 创建可编译的空 Swift 项目骨架
- 定义两个 SwiftPM target：SwiftAgentCore（库）+ SwiftAgentCLI（可执行文件）
- 建立文档目录结构
- 创建构建/测试脚本

## Technical Notes
- 使用 SPM (Swift Package Manager)，最低 Swift 6.0
- 依赖：`swift-argument-parser`
- Target 结构：
  - `SwiftAgentCore` — library target（共享运行时、类型、LLM 适配器、工具）
  - `SwiftAgentCLI` — executable target（依赖 SwiftAgentCore + ArgumentParser）
- 文档：`docs/ARCHITECTURE.md`、`docs/ROADMAP.md`、`docs/README.md`

## Acceptance Criteria
- [ ] `swift build` 编译通过
- [ ] `swift test` 运行通过（至少一个占位测试）
- [ ] `Package.swift` 定义了两个 target，依赖关系正确
- [ ] `docs/` 目录存在，三个文档文件内容完整
- [ ] `scripts/build.sh` 和 `scripts/test.sh` 可执行且能正常运行
- [ ] CLI 入口打印 "SwiftAgent" 版本信息

## Files to Create
- `Package.swift`
- `Sources/SwiftAgentCore/CoreTypes.swift` (占位)
- `Sources/SwiftAgentCLI/EntryPoint.swift` (ArgumentParser 入口)
- `Tests/SwiftAgentCoreTests/CoreTypesTests.swift` (占位测试)
- `docs/ARCHITECTURE.md`
- `docs/ROADMAP.md`
- `docs/README.md`
- `scripts/build.sh`
- `scripts/test.sh`

**Output when complete:** `<promise>DONE</promise>`
