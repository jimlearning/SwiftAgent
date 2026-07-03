# MCP 对齐报告

**日期：** 2026-06-01（更新于 2026-06-01）
**范围：** SwiftAgent 与 Claude Code 之间的 MCP 工具 Schema 传递、指令注入、延迟加载、工具命名一致性以及系统提示结构对齐。

---

## 1. 背景

SwiftAgent 和 Claude Code 使用相同的 LLM 后端（通过 Anthropic 兼容 API 的 DeepSeek），但初始测试揭示了显著的行为差异：

- **Claude Code** 仅需约 5 次 codegraph 调用就能理解并回答代码库问题：`codegraph_context` -> `codegraph_search` -> `codegraph_explore` -> `codegraph_node` -> `codegraph_trace`。
- **SwiftAgent** 完成相同任务需要约 20 次调用：3 次 `codegraph_explore`、10 次 `codegraph_node`、2 次 `codegraph_search`、3 次 `Read`。模型在工具选择上出现抖动，无法收敛到正确的工具。

根本原因不在于模型，而在于结构：SwiftAgent 未能以 Claude Code 使用的格式和显著性向 LLM 传递工具元数据。本工作的目标是严格在结构上与 CC 的提示词、消息格式化方式和工具定义模式对齐，使两个系统向相同的模型后端提供等价信息。

---

## 2. 根因分析

发现四个独立的缺陷，各自独立地导致 LLM 工具选择退化。

### 缺陷 1：MCP 工具 inputSchema 被硬编码为空 `{}`

修复前，`MCPToolBridge` 对每个 MCP 工具都生成 `JSONSchema(type: "object")`。LLM 收到的工具定义形如：

```json
{
  "name": "mcp__codegraph__codegraph_node",
  "description": "...",
  "input_schema": { "type": "object" }
}
```

没有 `properties`、没有 `required` 字段、没有参数描述。LLM 无法知道工具期望什么参数，只能猜测参数名（结果往往猜错），导致无效的工具调用，或退而使用通用工具（如 `Bash` + `grep`）。

修复方法是在 `MCPClient.swift`（第 269–343 行）中添加 `parseMCPInputSchema()` 和 `parseMCPProperty()`，将 MCP `tools/list` 响应中的完整 JSON Schema 解析为 SwiftAgent 的 `JSONSchema` 类型，保留 `properties`、`required`、`enum`、`items`、`additionalProperties` 和 `description`。

### 缺陷 2：MCP 服务器 `instructions` 从未传递给 LLM

MCP 协议允许服务器在 `InitializeResult` 和 `tools/list` 响应中返回 `instructions`。这些指令告诉 LLM 如何使用服务器的工具。例如 codegraph 的指令说：

> "Answer DIRECTLY using 2-3 codegraph calls: `codegraph_context` first, then ONE `codegraph_explore`..."

SwiftAgent 解析了这些指令却将其丢弃。它们从未到达系统提示或对话中。

修复涉及：
- `MCPClient.swift`：从 `InitializeResult` 中捕获 `initializeInstructions`（第 36 行），并从 `listTools()` 返回 `instructions`（第 48 行）。
- `MCPBootstrapper.swift`：将指令收集到 `serverInstructions: [String: String]`（第 25 行），优先使用 `client.initializeInstructions` 而非 `tools/list` 版本（第 270 行）。
- `ChatCommand.swift`：将指令传递到新的 `buildMcpSystemReminder()`（第 555 行）。

### 缺陷 3：MCP 指令被放在系统提示的末尾（被埋没）

即使指令到达了系统提示，它们也放在了错误的位置。SwiftAgent 将 MCP 指令追加到系统提示的动态后缀——LLM 首轮之前最后一个部分。而 Claude Code 则将它们作为 `<system-reminder>` 块注入到对话本身中，使其具有高度显著性。

`<system-reminder>` 标签是 Anthropic API 约定。包裹在 `<system-reminder>` 块中的内容，无论出现在对话的哪个位置，都会被模型视为系统级指令。Claude Code 使用此机制来传递 MCP 指令、项目上下文和其他关键指导。

修复：`ChatCommand.swift` 现在将首条用户消息构建为 4 个独立的文本块：

1. **延迟工具公告** 作为 `<system-reminder>`
2. **MCP 服务器指令** 作为 `<system-reminder>`
3. **CLAUDE.md + 项目记忆 + 当前日期** 作为 `<system-reminder>`
4. **用户输入**（纯文本，无标签）

这完全匹配 CC 的消息结构。`SystemPromptBuilder` 现在包含一条注释，说明 MCP 指令通过对话块传递，而非系统提示（第 103–106 行）。

### 缺陷 4：通用 `MCPTool` 注册截获来自按工具划分的 `DynamicMCPTool` 实例的调用

SwiftAgent 同时注册了两条并行的 MCP 调用路径：

1. **`MCPTool`** (`MCPTool.swift:11`) — 一个通用的"元"工具，`name = "MCP"`。接受 `serverName`、`toolName` 和 `arguments`（JSON 字符串）作为参数。始终内联（不延迟），总是可用，名称简短。
2. **`DynamicMCPTool`** 实例 — 每个 MCP 服务器工具一个，命名为 `mcp__codegraph__codegraph_context` 等，带有工具的完整 JSON Schema。延迟加载，需要通过 ToolSearch 加载。

模型总是选择更简单的 `"MCP"` 工具。调试日志分析显示：

```
112 "name":"MCP"          ← 通用工具截获调用
 10 "name":"mcp__codegraph__codegraph_context"
 10 "name":"mcp__codegraph__codegraph_explore"
 10 "name":"mcp__codegraph__codegraph_node"
 10 "name":"mcp__codegraph__codegraph_search"
 10 "name":"mcp__codegraph__codegraph_trace"
```

这完全破坏了延迟加载机制，因为：

- 模型将 `"MCP"` 视为快捷方式——只需传递 `serverName: "codegraph"`、`toolName: "codegraph_search"`、`arguments: "{\"query\":\"...\"}"`，而无需学习正确的 `mcp__codegraph__codegraph_search` schema。
- 通用工具没有按工具划分的参数 schema，所以模型仍然需要猜测参数名——这正是缺陷 1 已经解决的问题。
- 终端显示为 `MCP → MCP`，使所有 MCP 调用无法区分实际调用了哪个工具。
- 模型从未学会正确使用 ToolSearch，因为 `"MCP"` 始终作为直接快捷方式可用。

**修复：**

1. **从 `ChatCommand.swift:1810` 移除 `registry.register(MCPTool())`**。MCP 引导过程中注册的 `DynamicMCPTool` 实例已覆盖所有 MCP 服务器工具，并带有正确的按工具划分的名称和完整 Schema。
2. **向 `MCPTool` 添加 `shouldDefer = true`** (`MCPTool.swift:17`)，作为安全措施，以防将来在其他地方被重新注册。

这匹配 Claude Code 的架构：CC 没有通用的 "MCP" 元工具。每个 MCP 服务器工具在工具列表中都使用其真实名称和 Schema 拥有自己的条目。

**验证：** 修复后，调试日志显示零次 `"MCP"` 调用。所有 MCP 工具使用都通过正确命名的 `mcp__<server>__<tool>` 工具及其完整 Schema 进行。

---

## 3. 已做出的变更

### 3.1 MCPClient.swift

- **`initializeInstructions` 属性**（第 12 行）：在 `connect()` 期间从 `InitializeResult` 响应中捕获。根据 MCP 规范，这是服务器级指令的规范来源。
- **`listTools()` 返回类型**（第 45 行）：从 `[MCPToolDescription]` 改为 `(tools: [MCPToolDescription], instructions: String?)`。该元组携带与工具列表一起返回的服务器级指令。
- **`parseMCPInputSchema()`**（第 269 行）：将 MCP `inputSchema` JSON 对象解析为 SwiftAgent 的 `JSONSchema` 结构的私有函数。提取 `type`、`properties`、`required`、`additionalProperties` 和 `description`。
- **`parseMCPProperty()`**（第 310 行）：解析单个 JSON Schema 属性的私有函数。提取 `type`、`description`、`enum` 和 `items`（数组元素类型）。

### 3.2 MCPBootstrapper.swift

- **`serverInstructions` 属性**（第 25 行）：`[String: String]` 字典，将服务器名称映射到其指令文本。
- **返回类型更新**：`connectAndDiscover()` 和 `doConnectAndDiscover()` 现在通过返回元组携带指令。
- **指令优先级**（第 270 行）：优先使用 `client.initializeInstructions` 而非 `tools/list` 指令。注释说明："InitializeResult.instructions is canonical per MCP spec."
- **Actor 隔离修复**（第 140 行）：在 `bootstrap()` 内部使用本地 `collectedInstructions` 字典，跨并发服务器连接累积指令，然后在最后（第 189 行）赋值给 actor 隔离的 `serverInstructions` 属性。

### 3.3 ChatCommand.swift

- **4 个独立文本块**（第 542–570 行）：首条用户消息现在构建为独立的 `ContentBlock.text()` 条目：
  - 块 1：延迟工具公告为 `<system-reminder>`（通过 `buildDeferredToolsReminder`）
  - 块 2：MCP 指令为 `<system-reminder>`（通过 `buildMcpSystemReminder`）
  - 块 3：CLAUDE.md + 项目记忆 + 日期为 `<system-reminder>`（通过 `buildClaudeMdReminder`）
  - 块 4：原始用户输入
- **`buildMcpSystemReminder()`**（第 1236 行）：将 MCP 服务器指令包裹在 `<system-reminder>` 标签中，带有 "MCP Server Instructions" 标题。匹配 CC 的 `wrapMessagesInSystemReminder` 格式。
- **`buildDeferredToolsReminder()`**（第 1260 行）：在 `<system-reminder>` 块中列出延迟工具名称，每个组带有显式的 `select:` 前缀，以便模型可以直接复制粘贴确切的 ToolSearch 查询。按服务器对 MCP 工具进行分组，高价值工具（`context`、`explore`）排在前面。
- **`buildClaudeMdReminder()`**（第 1277 行）：将 CLAUDE.md 文件、项目记忆和当前日期作为单个 `<system-reminder>` 块注入。匹配 CC 的 claudeMd + project-memory-context + currentDate 注入。
- **`buildSystemPrompt()`**（第 1226 行）：现在接受 `model` 和 `toolNames` 参数，由调用者传入。
- **移除了 `registry.register(MCPTool())`**（原第 1810 行）：通用 MCP 元工具不再注册。DynamicMCPTool 实例提供按工具划分的 Schema。见缺陷 4。

### 3.4 MCPTool.swift

- **`shouldDefer = true`**（第 17 行）：作为安全措施添加，以防 `MCPTool` 在其他地方被重新注册。该工具本身已从 ChatCommand.swift 中移除注册（见缺陷 4）。

### 3.5 SystemPromptBuilder.swift

- **`# Text output` 部分**（第 293 行）：添加了 `textOutputSection()`，匹配 CC 的 `getTextOutputSection`。包含关于文本输出是主要面向用户通道、轮次结束时摘要以及简洁性规则的指导。此前缺失。
- **MCP 指令移除**（第 103–106 行）：`mcpInstructionsSection()` 方法仍然存在但不再被调用。注释说明："MCP server instructions are now delivered as <system-reminder> blocks in conversation messages. This matches Claude Code's approach and makes instructions far more salient."
- **系统提示缓存**（在 `LLMClient.swift` 中）：`apiFormattedSystem()` 方法（第 512 行）现在将整个系统提示包装为单个缓存文本块，匹配 CC 的方法。之前使用 2 块分割（静态前缀缓存，动态后缀不缓存）。

### 3.6 LLMClient.swift (ToolDefinition)

- **`deferLoading: Bool` 字段**（第 594 行）：添加到 `ToolDefinition`。默认为 `false`。
- **`apiFormatted` 包含**（第 612 行）：当 `deferLoading` 为 true 时，向 API 格式的工具定义添加 `"defer_loading": true`。这是标准的 Anthropic API 延迟工具字段。
- **系统提示缓存**（第 512 行）：改为单块完整缓存，使用 `"cache_control": ["type": "ephemeral"]`。不再使用静态前缀的 2 块分割。

### 3.7 ToolExecutor.swift (ToolRegistry)

- **`toolDefinitions()`**（第 181 行）：使用 `tool.shouldDefer && !tool.alwaysLoad` 在每个 `ToolDefinition` 上设置 `deferLoading`。
- **`filterToolsByDenyRules()`**（第 213 行）：对过滤后的工具列表使用相同的延迟标志逻辑。

### 3.8 DynamicMCPTool.swift

- **`shouldDefer = true`**：所有 MCP 工具默认延迟，匹配 CC 的架构。模型必须在调用之前使用 ToolSearch 加载 MCP 工具 Schema。
- **`mcpInfo: MCPToolInfo?`**：携带服务器和工具名称元数据，用于显示和路由目的。

### 3.9 关键内联工具

以下 Claude Code **始终**保持内联的工具在 SwiftAgent 中确认没有 `shouldDefer` 覆盖：

| 工具 | `shouldDefer` | 状态 |
|------|---------------|------|
| `AskUserQuestionTool` | `false`（默认） | 内联 |
| `TodoWriteTool` | `false`（默认） | 内联 |
| `TaskCreateTool` | `false`（默认） | 内联 |
| `NotebookEditTool` | `false`（默认） | 内联 |
| `Agent`、`Bash`、`Edit`、`Read`、`Write`、`Skill`、`ToolSearch` | `false`（默认） | 内联 |

当前代码库约有 30 个工具带有 `shouldDefer: true`——MCP 工具（`DynamicMCPTool`、`MCPTool`）、不常用的专用工具（`ConfigTool`、`CronCreateTool`、`TaskGetTool`、`LSPTool`、`WebFetch`、`WebSearch`）和管理工具。

---

## 4. 延迟加载：尝试与策略调整

### 4.1 为什么尝试延迟加载

Claude Code 的首次 API 请求仅内联发送 9 个工具：

1. Agent
2. AskUserQuestion
3. Bash
4. Edit
5. Read
6. ScheduleWakeup
7. Skill
8. ToolSearch
9. Write

所有其他工具（包括约 35 个内置工具和所有 MCP 工具）都通过 `defer_loading: true` 延迟。LLM 通过 `ToolSearch` 发现它们，后者按需加载其 Schema。这种两步认知模式：

- 将初始提示减少数千个 token（工具 Schema 很昂贵）。
- 引导 LLM 进行审慎的工具选择，而非连续猜测。
- 匹配人类学习工具的方式：先了解少数核心工具，在需要时发现专用工具。

### 4.2 已构建的基础设施

延迟加载功能需要对多个文件进行更改：

- `ToolDefinition.deferLoading: Bool`——映射到 API 请求体中的 `defer_loading: true`。
- `ToolRegistry.toolDefinitions()`——根据 `shouldDefer && !alwaysLoad` 设置标志。
- `buildDeferredToolsReminder()`——在 `<system-reminder>` 块中列出可用的延迟工具，以便 LLM 知道它们的存在而无需看到 Schema。
- `DynamicMCPTool.shouldDefer = true`——设置为将所有 MCP 工具视为延迟。

### 4.3 延迟加载下的模型行为

在基础设施修复后（缺陷 1–4 全部解决），延迟加载在结构上是正确的，并且对 MCP 工具有效。然而，DeepSeek-v4-pro 没有像 Claude 原生模型那样高效地利用它：

- Claude 的模型读取 MCP 指令，通过 `select:` 查询一次加载多个工具，并使用最优的 `context → explore → trace` 链。
- DeepSeek 加载了工具，但倾向于链式调用单个 `codegraph_node`（每任务 30–50 次），而不是使用 `codegraph_explore`。它有时还会退回到手动 Read/Grep/Bash 操作，尽管指令明确要求优先使用 codegraph。

这是一个模型级别的行为差距，而非代码问题。基础设施是正确的。

### 4.4 当前状态

- **基础设施完全可用**：`deferLoading` 字段、`ToolRegistry` 支持、`buildDeferredToolsReminder()`、`extractDiscoveredToolNames()` 和 `filterDeferredTools()` 都功能正常且经过测试。
- **MCP 工具延迟**：`DynamicMCPTool.shouldDefer = true` 已激活。所有 MCP 工具需要通过 ToolSearch 发现。这匹配 CC 的架构。
- **ToolSearch 返回完整 Schema**：延迟提醒中显式的 `select:` 前缀导致模型在一次调用中加载所有 codegraph 工具。`extractDiscoveredToolNames()` 和 `filterDeferredTools()` 正确管理发现/取消延迟的生命周期。
- **通用 MCPTool 已移除**：旧的 `MCPTool(name: "MCP")` 元工具不再注册（缺陷 4）。所有 MCP 调用通过正确命名的按工具实例进行。
- **约 30 个工具延迟**：MCP 工具 + 不常用的专用工具（`ConfigTool`、`CronCreateTool`、`LSPTool`、`WebFetch`、`WebSearch` 等）。
- **已验证**：最新调试日志中零次 `"MCP"` 通用工具调用。工具名称正确显示为 `mcp__codegraph__codegraph_context` 等。

---

## 5. 结果

| 指标 | 之前 | 之后 |
|------|------|------|
| 通用 MCP 工具调用 | 112 次 "MCP" 调用（工具名称隐藏） | 0 — 已移除，所有调用使用正确名称 |
| MCP 工具显示 | `MCP → MCP`（不可读） | `mcp__codegraph__codegraph_context → task: ...` |
| MCP 工具 Schema | 空 `{}` | 完整 JSON Schema，包含 `properties`、`required`、`enum` |
| MCP 指令 | 未传递 | 作为 `<system-reminder>` 对话块传递 |
| 延迟工具发现 | 有缺陷：ToolSearch 关键词搜索，无 `select:` | 正常工作：显式 `select:` 查询一次加载 Schema |
| 用户消息结构 | 1 个合并文本块 | 4 个独立文本块（延迟工具 + MCP + CLAUDE.md + 用户输入） |
| 系统提示缓存 | 2 块分割（静态前缀缓存，动态后缀不缓存） | 单块完整缓存（CC 对齐） |
| `# Text output` 部分 | 缺失 | 已添加，匹配 CC 的 `getTextOutputSection` |
| `ToolDefinition` API 格式 | 无 `defer_loading` 字段 | 当 `shouldDefer && !alwaysLoad` 时设置 `defer_loading: true` |

---

## 6. 剩余工作

### 6.1 模型级别的工具选择优化

基础设施现在在结构上与 Claude Code 对齐。所有四个缺陷都已修复。然而，DeepSeek-v4-pro 没有像 Claude 原生模型那样可靠地遵循 codegraph 指令：

- DeepSeek 倾向于链式调用单个 `codegraph_node` 和 `codegraph_search`，而不是使用 `codegraph_explore`（调查区域的首选工具）。
- 它有时会退回到手动 Read/Grep/Bash 操作（某些会话中超过 90 次调用），尽管指令要求优先使用 codegraph。
- 指令确实已正确传递；这是模型行为差距，而非代码问题。

潜在的缓解措施：
- 简化/缩短 codegraph 指令，更积极地强调 `context -> explore` 链。
- 添加后处理步骤，检测重复的 `codegraph_node` 模式并提示模型改用 `codegraph_explore`。
- 当更强大的模型版本可用时进行升级。

### 6.2 关键工具的 `alwaysLoad` 标志

即使在启用延迟加载的情况下，Claude Code 也保持某些工具内联（`alwaysLoad: true`）。SwiftAgent 应该识别应该始终可用的工具，并适当地设置 `alwaysLoad`。候选工具：在会话启动期间运行的工具或对代理循环至关重要的工具（例如 `ScheduleWakeup`）。

### 6.3 对 superpowers/skills 的 SessionStart 钩子支持

Claude Code 使用 SessionStart 钩子将 superpowers 和 skills 作为 `<system-reminder>` 块注入。SwiftAgent 目前将 CLAUDE.md 加载硬编码在 `buildClaudeMdReminder()` 中。通用的 SessionStart 钩子机制将允许 skills 注册自己的 `<system-reminder>` 注入，使系统可扩展而无需修改 ChatCommand。

### 6.4 高级工具使用的 `anthropic-beta` 标头

SwiftAgent 目前为 `prompt-caching-scope` 和 `interleaved-thinking`（ChatCommand.swift 第 671 行）发送 beta 标头，并在存在延迟工具时有条件地发送 `advanced-tool-use-2025-11-20`。随着工具能力的扩展，可能需要额外的 beta 标头。
