# Phase 1: Core Types & Domain Model

## Requirements
- 建立整个项目的类型基础（对应 Claude Code `bootstrap/state.ts` + `types/` 目录）
- 所有核心类型必须 `Codable` + `Sendable`
- 使用 `actor` 封装全局状态
- 使用嵌套 `enum` 建模权限模式，不用裸字符串

## Technical Notes
- 借鉴 Claude Code Source Study 第 3 章（状态管理）和第 9 章（工具系统设计）
- 工具协议借鉴 `buildTool()` 构建器模式，用 Swift protocol 实现
- 权限用 `enum PermissionMode` 嵌套建模

## Files to Create

### Types/ 子目录
| 文件 | 说明 | 核心类型 |
|---|---|---|
| `Conversation.swift` | 对话模型 | Message, Conversation, Turn, Role (enum) |
| `Tool.swift` | 工具协议 | ToolProtocol, ToolResult, ToolSchema, ToolInput |
| `Permission.swift` | 权限类型 | PermissionMode(enum), PermissionDecision, PermissionRule |
| `Config.swift` | 配置模型 | Settings, ModelConfig, FeatureFlags |
| `Agent.swift` | Agent 定义 | AgentDefinition, AgentContext, AgentRole |
| `Session.swift` | 会话模型 | Session, SessionMetadata, ConversationHistory |
| `SlashCommand.swift` | 命令类型 | SlashCommand, CommandType, CommandContext |
| `StreamEvent.swift` | 流事件 | StreamEvent 枚举（thinking, text_delta, tool_use, error 等）|

### State/ 子目录
| 文件 | 说明 |
|---|---|
| `AppState.swift` | 全局状态 actor（对应 bootstrap/state.ts） |
| `AppStateStore.swift` | 发布/订阅桥接（对应 store.ts） |

## Acceptance Criteria
- [ ] `swift build` 编译通过
- [ ] 所有类型有 `Codable` 和 `Sendable` 一致性
- [ ] `enum PermissionMode` 包含 default/plan/acceptEdits/bypass 四种模式
- [ ] `ToolProtocol` 定义完整：name, description, inputSchema, execute, isReadOnly, checkPermissions
- [ ] `AppState` 使用 actor 封装
- [ ] 每个文件有对应的单元测试
- [ ] `swift test` 全部通过

**Output when complete:** `<promise>DONE</promise>`
