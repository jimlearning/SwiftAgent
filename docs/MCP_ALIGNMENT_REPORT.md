# MCP 对齐报告

**日期:** 2026-06-01（更新于 2026-06-01）
**范围:** MCP 工具 schema 传递、instructions 注入、延迟加载、工具命名对齐，以及 SwiftAgent 与 Claude Code 之间的系统提示结构对齐。

---

## 1. 背景

SwiftAgent 和 Claude Code 共享相同的 LLM 后端（DeepSeek，通过 Anthropic-compatible API），但初步测试揭示了一个显著的行为差距：

- **Claude Code** 使用大约 5 次 codegraph 调用来理解并回答关于代码库的问题：`codegraph_context` -> `codegraph_search` -> `codegraph_explore` -> `codegraph_node` -> `codegraph_trace`。
- **SwiftAgent** 对同一任务使用了大约 20 次调用：3 次 `codegraph_explore`、10 次 `codegraph_node`、2 次 `codegraph_search`、3 次 `Read`。模型在反复尝试——无法收敛到正确的工具。

根因不在于模型本身。这是结构性的：SwiftAgent 没有以 Claude Code 使用的格式和显著性向 LLM 传递工具元数据。本次工作的目标是与 CC 的提示、消息格式和工具定义模式进行严格的结构对齐，使两个系统向同一模型后端呈现等效信息。

---

## 2. 根因分析

发现了四个独立的 bug，每个都独立地导致 LLM 工具选择退化。

### Bug 1: MCP 工具 inputSchema 被硬编码为空 `{}`

修复前，`MCPToolBridge` 为每个 MCP 工具生成 `JSONSchema(type: "object")`。LLM 收到的工具定义如下：

```json
{
  "name": "mcp__codegraph__codegraph_node",
  "description": "...",
  "input_schema": { "type": "object" }
}
```

没有 `properties`，没有 `required` 字段，没有参数描述。LLM 无法知道工具期望什么参数。它会猜测参数名称且猜错，产生无效的工具调用或退回到通用工具（如带 `grep` 的 `Bash`）。

修复方案是在 `MCPClient.swift`（第 269-343 行）中添加 `parseMCPInputSchema()` 和 `parseMCPProperty()`，它们将 MCP `tools/list` 响应中的完整 JSON Schema 解析为 SwiftAgent 的 `JSONSchema` 类型，保留 `properties`、`required`、`enum`、`items`、`additionalProperties` 和 `description`。

### Bug 2: MCP 服务器 `instructions` 从未传递给 LLM

MCP 协议允许服务器在 `InitializeResult` 和 `tools/list` 响应中返回 `instructions`。这些 instructions 告诉 LLM **如何**使用该服务器的工具。例如，codegraph 的 instructions 写道：

> "Answer DIRECTLY using 2-3 codegraph calls: `codegraph_context` first, then ONE `codegraph_explore`..."

SwiftAgent 解析了这些 instructions 但丢弃了它们。它们从未到达系统提示或对话中。

修复涉及：
- `MCPClient.swift`：从 `InitializeResult` 中捕获 `initializeInstructions`（第 36 行），并从 `listTools()` 返回 `instructions`（第 48 行）。
- `MCPBootstrapper.swift`：将 instructions 收集到 `serverInstructions: [String: String]` 中（第 25 行），优先使用 `client.initializeInstructions` 而非 `tools/list` 版本（第 270 行）。
- `ChatCommand.swift`：将 instructions 传入新的 `buildMcpSystemReminder()`（第 555 行）。

### Bug 3: MCP instructions 被放置在系统提示的末尾（被淹没）

即使 instructions 到达了系统提示，它们也放错了位置。SwiftAgent 将 MCP instructions 追加到系统提示的动态后缀中——即 LLM 第一轮对话之前的最后一节。而 Claude Code 将其作为对话中的 `<system-reminder>` 块注入，在那里它们具有很高的显著性。

`<system-reminder>` 标签是 Anthropic API 的约定。包装在 `<system-reminder>` 块中的内容被视为系统级指令，无论它出现在对话中的什么位置。Claude Code 使用此机制来传递 MCP instructions、项目上下文和其他关键指导。

修复：`ChatCommand.swift` 现在将第一条用户消息构建为 4 个独立的文本块：

1. **Deferred tools 公告** 作为 `<system-reminder>`
2. **MCP 服务器 instructions** 作为 `<system-reminder>`
3. **CLAUDE.md + 项目 memory + 当前日期** 作为 `<system-reminder>`
4. **用户输入**（纯文本，无标签）

这完全匹配 CC 的消息结构。`SystemPromptBuilder` 现在包含一条注释，说明 MCP instructions 通过对话块传递，而非系统提示（第 103-106 行）。

### Bug 4: 通用 `MCPTool` 注册从每个工具的 `DynamicMCPTool` 实例中窃取调用

SwiftAgent 同时注册了两条并行的 MCP 调用路径：

1. **`MCPTool`**（`MCPTool.swift:11`）——一个通用的"元"工具，`name = "MCP"`。接受 `serverName`、`toolName` 和 `arguments`（JSON 字符串）作为参数。始终 inline（不延迟），始终可用，名称简短。
2. **`DynamicMCPTool`** 实例——每个 MCP 服务器工具一个，命名如 `mcp__codegraph__codegraph_context` 等，带有工具的完整 JSON Schema。延迟加载，需要使用 ToolSearch 加载。

模型总是选择更简单的 `"MCP"` 工具。调试日志分析显示：

```
112 "name":"MCP"          ← 通用工具窃取调用
 10 "name":"mcp__codegraph__codegraph_context"   ← 实际的每个工具 schema
 10 "name":"mcp__codegraph__codegraph_explore"
 10 "name":"mcp__codegraph__codegraph_node"
 10 "name":"mcp__codegraph__codegraph_search"
 10 "name":"mcp__codegraph__codegraph_trace"
```

这完全破坏了延迟加载，因为：

- 模型将 `"MCP"` 视为快捷方式——传递 `serverName: "codegraph"`、`toolName: "codegraph_search"`、`arguments: "{\"query\":\"...\"}"`，而不是学习正确的 `mcp__codegraph__codegraph_search` schema。
- 通用工具没有每个工具的参数 schema，所以模型仍然需要猜测参数名称——这正是 Bug 1 已经修复的问题。
- 终端显示对每个 MCP 调用显示 `MCP → MCP`，无法区分实际调用了哪个工具。
- 模型从未学会正确使用 ToolSearch，因为 `"MCP"` 始终作为直接快捷方式可用。

**修复：**

1. **从 `ChatCommand.swift:1810` 中移除 `registry.register(MCPTool())`**。在 MCP 启动期间注册的 `DynamicMCPTool` 实例已经以正确的每个工具名称和完整 schema 覆盖了每个 MCP 服务器工具。
2. **向 `MCPTool` 添加 `shouldDefer = true`**（`MCPTool.swift:17`）作为安全措施，以防它在未来被其他地方重新注册。

这匹配 Claude Code 的架构：CC 没有通用的"MCP"元工具。每个 MCP 服务器工具在工具列表中都有自己的条目，带有其真实名称和 schema。

**验证：** 修复后，调试日志显示零次 `"MCP"` 调用。所有 MCP 工具使用都通过正确命名的 `mcp__<server>__<tool>` 工具进行，具有完整 schema。

---

## 3. 所做变更

### 3.1 MCPClient.swift

- **`initializeInstructions` 属性**（第 12 行）：在 `connect()` 期间从 `InitializeResult` 响应中捕获。根据 MCP 规范，这是服务器级 instructions 的规范来源。
- **`listTools()` 返回类型**（第 45 行）：从 `[MCPToolDescription]` 改为 `(tools: [MCPToolDescription], instructions: String?)`。元组携带随工具列表返回的服务器级 instructions。
- **`parseMCPInputSchema()`**（第 269 行）：私有函数，将 MCP `inputSchema` JSON 对象解析为 SwiftAgent 的 `JSONSchema` 结构体。提取 `type`、`properties`、`required`、`additionalProperties` 和 `description`。
- **`parseMCPProperty()`**（第 310 行）：私有函数，解析单个 JSON Schema 属性。提取 `type`、`description`、`enum` 和 `items`（数组元素类型）。

### 3.2 MCPBootstrapper.swift

- **`serverInstructions` 属性**（第 25 行）：`[String: String]` 字典，将服务器名称映射到其 instructions 文本。
- **返回类型更新**：`connectAndDiscover()` 和 `doConnectAndDiscover()` 现在通过其返回元组携带 instructions。
- **Instructions 优先级**（第 270 行）：优先使用 `client.initializeInstructions` 而非 `tools/list` 的 instructions。注释说明："InitializeResult.instructions is canonical per MCP spec."
- **Actor 隔离修复**（第 140 行）：在 `bootstrap()` 内使用局部 `collectedInstructions` 字典，在并发服务器连接之间累积 instructions，然后在最后将其赋值给 actor 隔离的 `serverInstructions` 属性（第 189 行）。

### 3.3 ChatCommand.swift

- **4 个独立文本块**（第 542-570 行）：第一条用户消息现在构造为单独的 `ContentBlock.text()` 条目：
  - Block 1: Deferred tools `<system-reminder>`（通过 `buildDeferredToolsReminder`）
  - Block 2: MCP instructions `<system-reminder>`（通过 `buildMcpSystemReminder`）
  - Block 3: CLAUDE.md + memory + date `<system-reminder>`（通过 `buildClaudeMdReminder`）
  - Block 4: 原始用户输入
- **`buildMcpSystemReminder()`**（第 1236 行）：将 MCP 服务器 instructions 包装在 `<system-reminder>` 标签中，带有"MCP Server Instructions"标题。匹配 CC 的 `wrapMessagesInSystemReminder` 格式。
- **`buildDeferredToolsReminder()`**（第 1260 行）：在 `<system-reminder>` 块中列出延迟工具名称，每个分组前带显式的 `select:` 前缀，使模型可以复制粘贴确切的 ToolSearch 查询。按服务器分组 MCP 工具，将高价值工具（`context`、`explore`）放在前面。
- **`buildClaudeMdReminder()`**（第 1277 行）：将 CLAUDE.md 文件、项目 memory 和当前日期作为单个 `<system-reminder>` 块注入。匹配 CC 的 claudeMd + project-memory-context + currentDate 注入方式。
- **`buildSystemPrompt()`**（第 1226 行）：现在接受 `model` 和 `toolNames` 参数，从调用方传入。
- **移除 `registry.register(MCPTool())`**（原第 1810 行）：通用 MCP 元工具不再注册。DynamicMCPTool 实例提供每个工具的 schema。参见 Bug 4。

### 3.4 MCPTool.swift

- **`shouldDefer = true`**（第 17 行）：作为安全措施添加，以防 `MCPTool` 在其他地方被重新注册。该工具本身不再在 ChatCommand.swift 中注册（参见 Bug 4）。

### 3.5 SystemPromptBuilder.swift

- **`# Text output` 部分**（第 293 行）：添加了 `textOutputSection()`，匹配 CC 的 `getTextOutputSection`。包含关于文本输出是主要的用户面通道、回合结束摘要和简洁性规则的指导。此前缺失。
- **MCP instructions 已移除**（第 103-106 行）：`mcpInstructionsSection()` 方法仍然存在但不再调用。注释说明："MCP server instructions are now delivered as <system-reminder> blocks in conversation messages. This matches Claude Code's approach and makes instructions far more salient."
- **系统提示缓存**（在 `LLMClient.swift` 中）：`apiFormattedSystem()` 方法（第 512 行）现在将整个系统提示包装为单个缓存文本块，匹配 CC 的方式。此前使用 2-block 分割（静态前缀缓存，动态后缀不缓存）。

### 3.6 LLMClient.swift (ToolDefinition)

- **`deferLoading: Bool` 字段**（第 594 行）：添加到 `ToolDefinition`。默认为 `false`。
- **`apiFormatted` 包含**（第 612 行）：当 `deferLoading` 为 true 时，向 API 格式的工具定义中添加 `"defer_loading": true`。这是延迟工具的标准 Anthropic API 字段。
- **系统提示缓存**（第 512 行）：改为单块完整缓存，使用 `"cache_control": ["type": "ephemeral"]`。不再使用对静态前缀使用 `cacheScope:'global'` 的 2-block 分割。

### 3.7 ToolExecutor.swift (ToolRegistry)

- **`toolDefinitions()`**（第 181 行）：使用 `tool.shouldDefer && !tool.alwaysLoad` 在每个 `ToolDefinition` 上设置 `deferLoading: deferLoading`。
- **`filterToolsByDenyRules()`**（第 213 行）：对过滤后的工具列表使用相同的延迟标志逻辑。

### 3.8 DynamicMCPTool.swift

- **`shouldDefer = true`**：所有 MCP 工具默认延迟加载，匹配 CC 的架构。模型必须使用 ToolSearch 在调用 MCP 工具之前加载其 schema。
- **`mcpInfo: MCPToolInfo?`**：携带服务器和工具名称元数据，用于显示和路由。

### 3.9 关键 inline 工具

以下 Claude Code 始终保持 inline 的工具已确认在 SwiftAgent 中没有 `shouldDefer` 覆盖：

| 工具 | `shouldDefer` | 状态 |
|------|---------------|--------|
| `AskUserQuestionTool` | `false`（默认） | Inline |
| `TodoWriteTool` | `false`（默认） | Inline |
| `TaskCreateTool` | `false`（默认） | Inline |
| `NotebookEditTool` | `false`（默认） | Inline |
| `Agent`, `Bash`, `Edit`, `Read`, `Write`, `Skill`, `ToolSearch` | `false`（默认） | Inline |

当前代码库有约 30 个工具设置了 `shouldDefer: true`——MCP 工具（DynamicMCPTool、MCPTool）、很少使用的专用工具（ConfigTool、CronCreateTool、TaskGetTool、LSPTool、WebFetch、WebSearch）以及管理类工具。

---

## 4. 延迟加载：尝试与转向

### 4.1 为何尝试延迟加载

Claude Code 的首次 API 请求仅发送 9 个 inline 工具：

1. Agent
2. AskUserQuestion
3. Bash
4. Edit
5. Read
6. ScheduleWakeup
7. Skill
8. ToolSearch
9. Write

所有其他工具（包括约 35 个内置工具和所有 MCP 工具）使用 `defer_loading: true` 延迟加载。LLM 通过 `ToolSearch` 发现它们，后者按需加载其 schema。这种两步式认知模式：

- 将初始 prompt 减少数千个 token（工具 schema 成本高昂）。
- 引导 LLM 进行深思熟虑的工具选择，而非串行猜测。
- 匹配人类学习工具的方式：了解少数核心工具，根据需要发现专用工具。

### 4.2 构建的基础设施

延迟加载功能需要跨多个文件的变更：

- `ToolDefinition.deferLoading: Bool`——映射到 API 请求体中的 `defer_loading: true`。
- `ToolRegistry.toolDefinitions()`——基于 `shouldDefer && !alwaysLoad` 设置标志。
- `buildDeferredToolsReminder()`——在 `<system-reminder>` 块中列出可用的延迟工具，使 LLM 在不看到 schema 的情况下知晓它们的存在。
- `DynamicMCPTool.shouldDefer = true` 被设置为将所有 MCP 工具视为延迟加载。

### 4.3 延迟加载下的模型行为

在基础设施修复完成后（Bug 1-4 全部解决），延迟加载在结构上是正确的，并且对 MCP 工具激活。然而，DeepSeek-v4-pro 不像 Claude 的原生模型那样高效地利用它：

- Claude 的模型读取 MCP instructions，通过 `select:` 查询一次性加载多个工具，并使用最佳的 `context → explore → trace` 链。
- DeepSeek 加载了工具但倾向于链式调用单个 `codegraph_node` 调用（每个任务 30-50 次）而非使用 `codegraph_explore`。尽管有 instructions，它有时也会回退到手动 Read/Grep/Bash。

这是模型级别的行为差距，而非代码问题。基础设施是正确的。

### 4.4 当前状态

- **基础设施完全可用**：`deferLoading` 字段、`ToolRegistry` 支持、`buildDeferredToolsReminder()`、`extractDiscoveredToolNames()` 和 `filterDeferredTools()` 均已实现并通过测试。
- **MCP 工具延迟加载**：`DynamicMCPTool.shouldDefer = true` 已激活。所有 MCP 工具需要通过 ToolSearch 发现。这匹配 CC 的架构。
- **ToolSearch 返回完整 schema**：延迟提醒中带有显式前缀的 `select:` 查询使模型一次性加载所有 codegraph 工具。`extractDiscoveredToolNames()` 和 `filterDeferredTools()` 正确管理发现/取消延迟的生命周期。
- **通用 MCPTool 已移除**：遗留的 `MCPTool(name: "MCP")` 元工具不再注册（Bug 4）。所有 MCP 调用都通过正确命名的每个工具实例进行。
- **约 30 个工具延迟加载**：MCP 工具 + 很少使用的专用工具（ConfigTool、CronCreateTool、LSPTool、WebFetch、WebSearch 等）。
- **已验证**：最新调试日志中零次 `"MCP"` 通用工具调用。工具名称正确显示为 `mcp__codegraph__codegraph_context` 等。

---

## 5. 结果

| 指标 | 修复前 | 修复后 |
|--------|--------|-------|
| 通用 MCP 工具调用 | 112 次 "MCP" 调用（工具名称隐藏） | 0 — 已移除，所有调用使用正确名称 |
| MCP 工具显示 | `MCP → MCP`（不可读） | `mcp__codegraph__codegraph_context → task: ...` |
| MCP 工具 schema | 空 `{}` | 完整 JSON Schema，包含 `properties`、`required`、`enum` |
| MCP instructions | 未传递 | 作为 `<system-reminder>` 对话块传递 |
| Deferred 工具发现 | 损坏：ToolSearch keyword search，无 `select:` | 正常：显式 `select:` 查询一次性加载 schema |
| 用户消息结构 | 1 个合并文本块 | 4 个独立文本块（deferred tools + MCP + CLAUDE.md + 用户输入） |
| 系统提示缓存 | 2-block 分割（静态前缀缓存，动态不缓存） | 1-block 完整缓存（CC 对齐） |
| `# Text output` 部分 | 缺失 | 已添加，匹配 CC 的 `getTextOutputSection` |
| `ToolDefinition` API 格式 | 无 `defer_loading` 字段 | `defer_loading: true` 在 `shouldDefer && !alwaysLoad` 时设置 |

---

## 6. 剩余工作

### 6.1 模型级工具选择优化

基础设施现在与 Claude Code 在结构上对齐。所有四个 bug 已修复。然而，DeepSeek-v4-pro 不像 Claude 的原生模型那样可靠地遵循 codegraph instructions：

- DeepSeek 倾向于链式调用单个 `codegraph_node` 和 `codegraph_search`，而非使用 `codegraph_explore`（用于调查某个区域的首选工具）。
- 尽管有 instructions 建议优先使用 codegraph，它有时会回退到手动 Read/Grep/Bash 操作（某些 session 中多达 90+ 次调用）。
- Instructions 已正确传递；这是模型行为差距，而非代码问题。

潜在的缓解方案：
- 简化/缩短 codegraph instructions，更积极地强调 `context -> explore` 链。
- 后处理步骤，检测重复的 `codegraph_node` 模式并提示模型改用 `codegraph_explore`。
- 在更强大的版本可用时进行模型升级。

### 6.2 关键工具的 `alwaysLoad` 标志

Claude Code 即使启用延迟加载也会保持某些工具 inline（`alwaysLoad: true`）。SwiftAgent 应识别出应始终可用的工具并适当设置 `alwaysLoad`。候选工具：在 session 启动期间运行或对 agent loop 至关重要的工具（如 `ScheduleWakeup`）。

### 6.3 对 superpowers/skills 的 SessionStart hook 支持

Claude Code 使用 SessionStart hooks 将 superpowers 和 skills 作为 `<system-reminder>` 块注入。SwiftAgent 当前在 `buildClaudeMdReminder()` 中硬编码了 CLAUDE.md 加载。通用的 SessionStart hook 机制将允许 skills 注册自己的 `<system-reminder>` 注入，使系统可扩展而无需修改 ChatCommand。

### 6.4 用于高级工具使用的 `anthropic-beta` headers

SwiftAgent 当前发送 beta headers，包括 `prompt-caching-scope` 和 `interleaved-thinking`（ChatCommand 第 671 行），以及在存在延迟工具时有条件的 `advanced-tool-use-2025-11-20`。随着工具能力的扩展，可能需要额外的 beta headers。
