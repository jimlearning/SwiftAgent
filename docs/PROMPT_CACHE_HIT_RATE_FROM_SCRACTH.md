# Prompt Cache 命中率 — 从入门到精通

本文是 SwiftAgent prompt cache 命中率的全面指南，涵盖原理、架构、调优、排查和维护。它不是通用 Anthropic API 说明，而是本项目实际落地缓存优化的工程档案。

---

## 目录

1. [快速入门](#快速入门)
2. [Prompt Cache 原理](#prompt-cache-原理)
3. [Cache Key 是什么](#cache-key-是什么)
4. [命中率计算](#命中率计算)
5. [SwiftAgent 的缓存架构](#swiftagent-的缓存架构)
6. [请求形状对齐](#请求形状对齐)
7. [代理与网关的影响](#代理与网关的影响)
8. [诊断低命中率](#诊断低命中率)
9. [常见误区与反模式](#常见误区与反模式)
10. [工具定义与缓存稳定性](#工具定义与缓存稳定性)
11. [消息构造与缓存](#消息构造与缓存)
12. [测试与验证](#测试与验证)
13. [生产监控](#生产监控)
14. [高级主题](#高级主题)
15. [维护规则速查](#维护规则速查)
16. [已知问题与待解决](#已知问题与待解决)
17. [试错档案](#试错档案)

---

## 快速入门

### 一句话

**Prompt cache 缓存的是 API 请求的前缀部分（system prompt + tools + conversation history），让后续请求跳过已处理过的 token，降低延迟和成本。**

### 核心概念 (30 秒)

- **缓存什么**：请求中可复用的前缀 token（不是输出，不是会话对象）
- **怎么标记**：在请求中用 `cache_control: { type: "ephemeral" }` 标记缓存断点
- **何时命中**：后续请求发送了与缓存完全一致的前缀
- **命中率公式**：`cache_read / (input + cache_read + cache_creation)`

### 首次接触需要知道的三个事实







1. **同模型不等于同命中率**。缓存 key 依赖请求结构的字节级匹配，不仅依赖模型。
2. **第一轮不会有高命中**。服务端需要先见过这个前缀才能创建缓存。
3. **会话越长，可缓存的历史越多**，命中率通常越高（假设前缀稳定）。

---

## Prompt Cache 原理

### 什么是 Prefix-based Caching

Anthropic Messages API 使用 **prefix-based**（基于前缀的）缓存策略。对于每个请求，服务端检查请求的输入（system → tools → messages）是否能匹配到已存储的缓存条目。匹配从前缀开始，一旦某个位置不匹配，后续部分就无法命中缓存。




```
请求 A: [system-aaaaaaa][tools-aaaaa][msg1-aaa][msg2-aaa]
                                                  ^ 断点

请求 B: [system-aaaaaaa][tools-aaaaa][msg1-bbb]  ← 从 msg1 开始不匹配
         ↑ 可命中          ↑ 可命中  ↑ 不匹配 → 后续都无法命中
```

### Cache Marker 的作用

`cache_control` 标记告诉 API"到这里为止可以作为一个缓存边界"：

```json
{
  "type": "text",
  "text": "You are Claude Code...",
  "cache_control": { "type": "ephemeral" }
}
```

**关键点**：
- 标记嵌在 content block 上，**不是独立的请求字段**
- 标记的位置决定缓存前缀的边界，**不是"在这里缓存这一条"**
- `ephemeral` 表示短期缓存（默认 TTL 5 分钟，续期后可达 1 小时）
- 标记**多不一定好**——多余的标记改变请求形状，可能反而破坏对齐

### 缓存生命周期

```
首次请求（cache miss）
  → API 处理全量 token，将前缀写入缓存
  → cache_creation_input_tokens > 0

后续请求（cache hit）
  → API 从缓存读取已匹配前缀
  → cache_read_input_tokens > 0

缓存过期
  → 所有请求恢复满量处理
  → 下一个请求会再次触发 cache_creation
```

### Cache Key 为什么容易失效

以下是会**打破缓存前缀**的常见变化，哪怕只差一个字符：

| 类别        | 示例                                                |
| ----------- | --------------------------------------------------- |
| 文本差异    | 多一个换行、空格、"now" 变成当时时间戳              |
| 排序变化    | tools 数组顺序变化、content block 顺序变化          |
| Schema 变化 | tool description 更新、input_schema 增减字段        |
| 块结构变化  | system 块拆分/合并方式改变                          |
| 字段变化    | 新增/删除 `defer_loading`、`scope` 字段             |
| 顶层字段    | 多出 `temperature`、`tool_choice`、`anthropic_beta` |
| 标记变化    | cache_control 数量、位置、字段内容变化              |

**核心原则**：缓存命中率首先是 prefix 稳定性问题，其次才是模型/网关问题。

---


## Cache Key 是什么

### Cache Key 的构成

Cache key 并不是某个简单的 hash 值，而是服务端对请求前缀执行的**结构化序列化匹配**。大致构成如下：

```
cache_key ≈ hash(
    model_id +
    serialized(system blocks, 含 cache_control marker) +
    serialized(tools, 含 cache_control marker, defer_loading, schema) +
    serialized(messages prefix, 含 cache_control marker, content block 类型与顺序) +
    一些顶层字段（beta headers 等）
)
```

### 什么不参与 Cache Key

- `max_tokens`（输出预算）
- `stream`（是否流式）
- `metadata`（用户标识、session ID）
- `stop_sequences`
- 大多数 HTTP headers（但 `anthropic-beta` 相关 feature flags 可能参与）




> **注意**：以上是常见规则，精确的 key 构成由 API 实现决定。不同 proxy 可能有不同行为。

### 为什么"看起来一样"不等于"能命中"

```
请求 A:  { "text": "Hello\n" }         ← 末尾有 \n
请求 B:  { "text": "Hello" }           ← 末尾无 \n
缓存匹配: ❌ 不匹配
```

JSON 序列化的每个字节都参与匹配。`"\n"` 和 `""` 是两个不同的前缀。



---

## 命中率计算

### API 返回的 Usage 字段

| Field                         | 含义                                                   |
| ----------------------------- | ------------------------------------------------------ |
| `input_tokens`                | 本次仍需正常处理的输入 token（**不包含**已缓存的部分） |
| `cache_creation_input_tokens` | 本次写入缓存的 token 数                                |
| `cache_read_input_tokens`     | 本次从缓存读取的 token 数                              |
| `output_tokens`               | 模型输出的 token 数                                    |

### 正确的命中率公式

**错误（常见）**：

```text
cache_read_input_tokens / input_tokens
```

问题：`input_tokens` 不包含已缓存读取的部分。如果 768 token 被缓存、30 token 新输入，这个公式变成 `768/30 = 2560%`——无意义。

**正确（可比口径）**：

```text
cache_read_input_tokens / (input_tokens + cache_read_input_tokens + cache_creation_input_tokens)
```

这个公式衡量：**本次请求的总输入 token 中有多高比例来自缓存**。

### 快速判断指南

```
Turn 1:  cache_read=0,    cache_creation>0  → 首次请求，正在创建缓存 ✅
Turn 1:  cache_read=0,    cache_creation=0  → 代理可能不支持缓存或请求太小 ⚠️
Turn 2+: cache_read>0,    cache_creation=0  → 缓存命中，正常 ✅
Turn 2+: cache_read=0,    cache_creation=0  → 缓存未命中，prefix 不匹配 ❌
Any:     cache_read=flat, cache_creation=0  → 系统缓存可用，消息级缓存不可用 ⚠️
```

### 什么算"好"的命中率

| 命中率 | 评级 | 说明                                     |
| ------ | ---- | ---------------------------------------- |
| > 90%  | 优秀 | 大部分稳定前缀被缓存，仅最新消息需要处理 |
| 70-90% | 良好 | 可接受的缓存效率                         |
| 50-70% | 中等 | 有改进空间                               |
| 30-50% | 低   | 需要检查结构和标记位置                   |
| < 30%  | 极低 | 代理可能不支持缓存，或请求形状完全不同   |

这些阈值是经验值。实际效果取决于会话长度、模型和代理。

---

## SwiftAgent 的缓存架构

### 总览

SwiftAgent 对齐 Claude Code 的请求形状，目标是让发送到同一 API 的请求与 Claude Code 有 **cache-equivalent** 的前缀结构。

```
┌─────────────────────────────────────────────────────────┐
│                    HTTP Request Body                     │
├─────────────────────────────────────────────────────────┤
│ system: [                                                │
│   [0] billing header text (无 cache_control)             │
│   [1] "You are Claude Code..." (+ cache_control)  ← ┐   │
│   [2] 静态内容 (+ cache_control)                   │   │
│   [3] 动态内容 (+ cache_control)  ← 连续链 ─┘          │
│ ]                                                        │
│ tools: [Read, Edit, Bash, ...] (无 cache_control)        │
│ messages: [                                              │
│   ...较早历史...                                         │
│   [last].content: [                                      │
│     tool_result ...                                      │
│     text "<system-reminder>..." (+ cache_control) ← ┐   │
│   ]                                          断点 ──┘   │
│ ]                                                        │
│ 顶层字段: thinking, context_management, output_config    │
│   (无 temperature, 无 tool_choice, 无 anthropic_beta)    │
└─────────────────────────────────────────────────────────┘
```

### 三层缓存的策略

#### 层 1：System Prompt 缓存链

所有非 billing 的 system 块形成**连续的** `cache_control` 链：

| 索引 | 内容                                                        | `cache_control` | 说明                 |
| ---- | ----------------------------------------------------------- | :-------------: | -------------------- |
| 0    | `x-anthropic-billing-header: cc_version=2.1.143...`         |        ❌        | 计费追踪，不参与缓存 |
| 1    | `You are Claude Code, Anthropic's official CLI for Claude.` |        ✅        | Identity 块          |
| 2    | 静态内容（工具规则、风格、安全规则等）                      |        ✅        | 跨会话不变           |
| 3    | 动态内容（session guidance, CLAUDE.md, environment 等）     |        ✅        | 每会话可能不同       |

**设计原因**：所有非 billing 块都有 `cache_control`，形成连续链。无 gap 意味着代理不会在 system prompt 之后重置缓存边界，tools 和 messages 前缀有机会被继续匹配。

#### 层 2：Tool Definitions

工具定义不加 `cache_control`。Claude Code 当前 capture 中 `tools[].cache_control` 为 0。工具以名称排序保证稳定（见 [工具定义与缓存稳定性](#工具定义与缓存稳定性)）。





#### 层 3：Message-level Cache Breakpoint

请求的最后一条 message 的最后一个 **text** content block 上放置 `cache_control`：

- 缓存标记不放在 `tool_result`、`thinking`、`redacted_thinking` 上
- 当 message 只在 tool_result 后面没有 text 时，**追加**一个稳定的 `<system-reminder>` text block 作为断点
- `lastCacheableBlockIndex()` 从消息末尾向前查找第一个 text 块

### 代码路径

```
ChatCommand.run()
  └─ ToolRegistry.toolDefinitions()      → 工具列表（按名称排序）
  └─ buildSystemPrompt()                 → 含 boundary marker 的系统提示文本
  └─ LLMClient.send(messages:..., systemPrompt:..., tools:..., thinking:.adaptive)
       └─ buildMessagesRequestBody()
            └─ apiFormattedSystem()      → 4 个 system blocks（含连续 cache_control）
            └─ apiFormattedTools()       → 工具列表（enablePromptCaching: false）
            └─ apiFormattedMessages()    → 最后一条 message 加 cache_control
       └─ applyClaudeCodeRequestShape()  → thinking/context_management/output_config
  └─ 收到 tool_result 后:
       └─ appendToolResultCacheBreakpointReminder() → 追加 <system-reminder> text 块
```

### 关键实现文件

| 文件                        | 职责                                                         |
| --------------------------- | ------------------------------------------------------------ |
| `LLMClient.swift`           | `apiFormattedSystem()`, `apiFormattedMessages()`, `apiFormattedTools()`, `applyClaudeCodeRequestShape()` |
| `ToolExecutor.swift`        | `ToolRegistry.toolDefinitions()` — 工具列表生成（排序、缓存） |
| `SystemPromptBuilder.swift` | `build()` — 构建带 boundary 的系统提示文本                   |
| `MessageFactory.swift`      | `appendToolResultCacheBreakpointReminder()` — 追加断点 text 块 |
| `MessageNormalizer.swift`   | `normalizeMessagesForAPI()` — 17 步归一化 pipeline           |
| `EvalCommand.swift`         | `CacheHitRateCommand` — 缓存命中率评估工具                   |
| `ChatCommand.swift`         | 主循环 — 组装请求、使用 `.adaptive` thinking                 |

---

## 请求形状对齐


### 顶层字段（与 Claude Code capture 对齐）

```json
{
  "model": "claude-sonnet-4-6",









  "max_tokens": 32000,
  "stream": true,
  "system": [...],
  "messages": [...],
  "tools": [...],
  "thinking": { "type": "adaptive" },
  "context_management": {
    "edits": [{ "type": "clear_thinking_20251015", "keep": "all" }]

  },
  "output_config": { "effort": "high" },
  "metadata": { "user_id": "..." }
}
```

**不允许出现的字段**：
- `temperature` — 与 `thinking: adaptive` 冲突，会被移除
- `tool_choice` — Claude Code 当前 capture 中不存在，会被移除
- `anthropic_beta` — beta 在 HTTP header，不在 body

### Beta Headers

```text
anthropic-beta: claude-code-20250219,
  interleaved-thinking-2025-05-14,
  redact-thinking-2026-02-12,
  context-management-2025-06-27,
  prompt-caching-scope-2026-01-05,
  advisor-tool-2026-03-01,
  advanced-tool-use-2025-11-20,
  effort-2025-11-24




```
当工具列表包含 deferred tools 时，追加 `tool-search-1p-2025-05-14`。

### Static Headers



```text
anthropic-dangerous-direct-browser-access: true
x-stainless-arch: arm64
x-stainless-lang: js
x-stainless-os: MacOS
x-stainless-package-version: 0.94.0
x-stainless-retry-count: 0
x-stainless-runtime: node
x-stainless-runtime-version: v24.3.0
x-stainless-timeout: 600
```

### Cache Marker 计数基线

| Location       | Claude Code | SwiftAgent | 说明                                       |
| -------------- | ----------: | ---------: | ------------------------------------------ |
| system blocks  |           2 |          3 | SA 拆分为 static+dynamic 两块，CC 合二为一 |
| tools          |           0 |          0 | CC 不用 tool-level marker                  |
| latest message |           1 |          1 | 最后 text block                            |
| total          |           3 |          4 | SA 多 1 个 system marker，不影响缓存一致性 |

### 验证命令

检查缓存 marker 数量：

```bash
jq -r '
  select(.type=="request") |
  [
    .seq,
    ([.body.system[]? | select(has("cache_control"))] | length),
    ([.body.tools[]? | select(has("cache_control"))] | length),
    ([.body.messages[]? | .. | objects | select(has("cache_control"))] | length),
    ([.body | .. | objects | select(has("cache_control"))] | length)
  ] | @tsv
' ~/.swift-agent/logs/debug-*.jsonl
```

预期输出（非 MCP 会话）：`seq  3  0  1  4`

---

## 代理与网关的影响

### 第三方代理/网关的行为差异

Claude Code Switch 和第三方代理对缓存行为有额外影响，**不能假设它们的行为与官方 Anthropic API 完全一致**：

| 行为              | 影响                                                         |
| ----------------- | ------------------------------------------------------------ |
| **Gap 检测**      | 无 `cache_control` 的系统块 → 有 `cache_control` 的块 → 无 `cache_control` 的块的 gap 可能被视为边界重置 |
| **thinking 依赖** | 某些代理仅在 `thinking: adaptive` 存在时创建缓存条目         |
| **大小阈值**      | 请求 < 约 1000 tokens 时，代理可能跳过缓存创建               |
| **消息级缓存**    | 代理可能不支持消息级缓存（仅支持系统级缓存）                 |

### 系统提示 Gap 问题（Phase 2 核心教训）




如果把系统块拆分为"有缓存"和"无缓存"：

```
[block-1: cache] [block-2: no cache] [block-3: no cache] [tools] [messages]
                  ↑ 此处有 gap → 代理重置缓存边界
```

代理在 gap 之后可能**完全停止缓存匹配**，导致 tools 和 messages 永远无法命中缓存。

**正确做法**：所有非 billing 系统块连续覆盖 `cache_control`：

```
[billing: no cache] [identity: cache] [static: cache] [dynamic: cache] → 无 gap
```

### 消息级缓存支持

实测表明，SwiftAgent 通过当前代理（deepseek-v4-flash）的系统提示缓存链正常工作（96.2% 命中），但 **消息级缓存不可用**——`cache_read` 不随消息历史增长。这与 Claude Code flash 会话（`cache_read` 从 24K 增长到 103K）存在差距。



可能原因：
- 代理差异（C 端订阅版 vs CLI 版）
- thinking 参数前提条件
- 请求大小阈值未达到

---

## 诊断低命中率

### 诊断流程图

```
cache_read == 0 且 cache_creation == 0?
  ├─ Yes → 代理不支持缓存 (或请求太小 < 1000 tokens)
  │        → 尝试更大请求、检查 provider 文档
  │
  └─ No → cache_creation > 0 但 cache_read == 0?
  │       └─ Yes → 缓存被创建但后续未命中
  │                → 检查 prefix 稳定性（见下文）
  │
  └─ No → cache_read > 0?
          ├─ 不随回合增长 → 系统缓存 OK, 消息级缓存不可用
          │                  → 检查代理/thinking/请求大小
          └─ 随回合增长 → ✅ 一切正常
```

### 检查清单

按顺序执行：


1. **确认代理支持缓存**：首回合 `cache_creation` > 0 或次回合 `cache_read` > 0。
2. **运行 `eval cache-hit-rate`**：排除自身代码问题。
3. **检查 system block 结构**：所有非 billing 块都有 `cache_control`（无 gap）。
4. **检查 top-level body**：无 `temperature`, `tool_choice`, `anthropic_beta`。
5. **检查 beta placement**：在 header 不在 body。
6. **检查 thinking 配置**：`.adaptive` 可能触发缓存创建。
7. **检查请求大小**：如果总 token < 1000，增加 system prompt 长度测试。
8. **对比 consecutive requests**：连续两轮的序列化 JSON 前缀是否逐字节一致。
9. **检查 tool schema 稳定性**：description 是否有动态内容（重要！）。
10. **检查 MCP tool descriptions**：是否每轮都变化。
11. **用同一 session 跑更长上下文**：不要用 3 轮对比 151 轮的 capture。

### 使用 eval 命令



```bash
# 快速验证（3 轮）
swift run --disable-sandbox swift-agent eval cache-hit-rate --turns 3

# 完整验证（5 轮，显示 debug 日志）
swift run --disable-sandbox swift-agent eval cache-hit-rate --turns 5 --verbose

# 指定模型
swift run --disable-sandbox swift-agent eval cache-hit-rate --model claude-sonnet-4-6 \
  --base-url https://api.anthropic.com
```

**注意**：eval 命令当前使用 `thinking: .disabled`（`EvalCommand.swift:219`），这在某些代理上可能阻止缓存创建。如果 eval 结果中 `cache_creation` 始终为 0，将 `thinking` 切换为 `.adaptive` 测试。

### 从 Debug 日志提取缓存信息

```bash
# 检查顶层请求结构
jq -c '
  select(.type=="request") |
  {
    bodyKeys: (.body|keys),
    thinking: .body.thinking,
    temp: .body.temperature,
    tool_choice: .body.tool_choice
  }
' ~/.swift-agent/logs/debug-*.jsonl

# 提取每轮缓存用量
jq -r '
  select(.type=="stream_event" and .raw.type=="message_start") |
  [.seq, .raw.message.usage.input_tokens,
   .raw.message.usage.cache_read_input_tokens,
   .raw.message.usage.cache_creation_input_tokens] | @tsv
' ~/.swift-agent/logs/debug-*.jsonl
```

---

## 常见误区与反模式

### 误区 1：同模型就应该同命中率

**错误**。Cache key 依赖请求 prefix 的字节级稳定性。模型是必要条件，不是充分条件。

### 误区 2：`scope: "global"` 更好






**错误**。Claude Code 当前 capture 使用 plain `{ "type": "ephemeral" }`，无 `scope` 字段。添加 `scope: "global"` 会改变请求形状，反而可能破坏对齐。

### 误区 3：只看 marker 总数

**错误**。marker 数量和位置同样重要。system prompt 中有 gap（有缓存→无缓存）会重置代理的缓存边界。






### 误区 4：给 tools 加 marker 能提高命中

**不一定**。CC 当前不做 tool-level marker。优先保持 request shape 对齐，而非凭直觉增加 marker。











### 误区 5：message marker 可以放在 tool_result 上

**错误**。CC capture 中标记始终落在 text 块，不在 tool_result 块。SwiftAgent 的 `lastCacheableBlockIndex()` 正确实现了这一点。

### 误区 6：用 `cache_read/input_tokens` 计算命中率

**错误**。`input_tokens` 不包含已缓存的部分。必须用 `cache_read / (input + cache_read + cache_creation)`。




### 误区 7：动态块不需要 cache_control（Phase 2 核心教训）

**错误**。拆分系统提示后，如果动态块不加 `cache_control`，代理会在 gap 后重置缓存边界，导致 tools 和 messages 永远无法命中。

### 误区 8：单元测试通过 = 缓存生效

**错误**。`CacheControlPlacementTests` 只验证结构和标记位置，不验证代理是否实际缓存。必须用真实 API 调用验证。

### 误区 9：`message_delta.usage` 包含完整用量






**错误**。`message_delta.usage` 仅含 `output_tokens`。完整用量（`input_tokens`, `cache_read`, `cache_creation`）在 `message_start.message.usage` 中。

### 误区 10：不加 marker 的块不影响缓存

**错误**。不加标记的文本块仍然参与前缀序列化。如果某块的 text 每轮都变（如时间戳），它会破坏之后所有块的缓存匹配，无论之后是否有标记。

### 误区 11：cache_creation == 0 = 缓存不工作

**错误**。`cache_creation` 只在新建缓存条目时 > 0。如果缓存条目已在更早的请求中创建（预热），后续请求可以只有 `cache_read` 而没有 `cache_creation`。

---

## 工具定义与缓存稳定性

### 排序保证

`ToolRegistry.toolDefinitions()` 按工具名称排序返回（`ToolExecutor.swift:186`）：



```swift
return tools.values.sorted { $0.name < $1.name }




```
这确保同一 session 内工具序列化顺序稳定。测试 `ToolRegistryCachingTests` 验证了排序稳定性。

### Description 稳定性







每个工具的 API 描述通过 `tool.prompt()` → `tool.description(input:options:)` 获取。大多数工具的 description 返回固定字符串，但需要注意：

- **MCP 工具**：描述来自远程 MCP server，可能包含动态内容（session ID、时间戳等）。如果 MCP server 的描述在 session 间变化，会导致缓存 miss。
- **Description 缓存**：`ToolRegistry` 内部有 `schemaCache`（`ToolExecutor.swift:215-224`），首次调用后缓存所有工具定义。同一 session 内后续调用直接返回缓存。这保证了 session 内稳定性，但也意味着 permission context 变化不会反映到已缓存的 schema 中。





### Deferred Tools

deferred tools 在首次请求中不发送完整 schema（`defer_loading: true`）。当模型通过 `ToolSearch` 发现并请求某个 deferred tool 后，后续请求会包含其完整 schema（`deferLoading: false`）。这意味着：

1. 首次含 deferred tool 的请求：schema 较少，前缀较短
2. 发现 deferred tool 后的请求：schema 较多，前缀较长
3. 这种前缀变化可能导致缓存 miss

务必确保 deferred tool 的 description 在被发现后保持稳定。

### 工具集差异

SwiftAgent 和 Claude Code 的工具集不一定完全相同（MCP 工具、自定义工具等）。工具集不同会影响 cacheable prefix 的大小和结构。

---

## 消息构造与缓存

### Message Normalization Pipeline

`normalizeMessagesForAPI()` 执行 17 步归一化（`MessageNormalizer.swift`），目标不仅是 API 兼容性，也保障缓存稳定性：

```
1.  过滤虚拟消息                   (仅展示，不发往 API)
2.  过滤进度消息                   (不发往 API)
3.  过滤系统消息                   (不发往 API)
4.  按 UUID 去重                   (首次出现为准)
5.  归一化 tool_use input          (去除内部字段)
6.  去除不可用工具                  (移除 tool_reference blocks)
7.  过滤孤立 thinking-only         (thinking-only → 跳过)
8.  过滤尾部 thinking              (最后一条 msg → 去除尾部 thinking)
9.  过滤纯空白消息                  (替换为 NO_CONTENT_MESSAGE)
10. 合并连续 user 消息              (所有连续的 → 合并)
11. 按 message ID 合并 assistant    (反向遍历, 相同 requestId)
12. 折叠 system reminders           (折叠进 tool_result content)
13. 清理错误 tool_results           (is_error 中非 text → 去除)
14. 确保非空 assistant              (空数组用占位符)
15. 归一化 content                  (去除空 text blocks)
16. 应用 tool result 预算           (MAX_TOOL_RESULTS_PER_MESSAGE_CHARS)
17. 确保 tool_use/result 配对       (插入/移除合成 blocks)
```

### 影响缓存的关键步骤

- **Pass 5**：归一化 tool_use input（去除 plan/planFilePath 等内部字段）。如果输入未被归一化，不同的内部字段会导致 cache miss。
- **Pass 6**：去除不可用工具。如果 tool 可用性在不同请求中变化，message content 可能变化。
- **Pass 12**：折叠 system reminders。将 `<system-reminder>` text blocks 折叠进 tool_result content 中。如果折叠位置不同，message 序列化会变化。
- **Pass 13**：清理 error tool_results。确保 is_error 块只有 text 内容。

### Tool Result Cache Breakpoint














`appendToolResultCacheBreakpointReminder()` 在所有 tool-result user message 后追加一个稳定的 text 块：

```swift
public let TOOL_RESULT_CACHE_BREAKPOINT_REMINDER = """
<system-reminder>
PostToolUse context: Tool results above were generated by SwiftAgent.
Continue using them as the latest observed tool outputs.
</system-reminder>
"""

```
这个块的文本是**硬编码常量**，不会变化，因此是稳定的 prefix 断点。CC 的等价实现也是在 tool_result 后追加 system-reminder text。

### Message 顺序的重要性

API 要求 message 交替（user → assistant → user → ...）。如果 normalize 步骤改变了 message 顺序（如合并 consecutive user messages），可能改变 prefix 的结构。SwfitAgent 的合并（Pass 10）是有意的——CC 也做同样的合并。

---

## 测试与验证

### 单元测试：`CacheControlPlacementTests`

验证请求结构的正确性（在 `Phase2LLMTests.swift`）：

| 测试                                                         | 验证内容                                    |
| ------------------------------------------------------------ | ------------------------------------------- |
| `systemPromptBoundaryCreatesClaudeCodeSystemBlocks`          | 4 个块，billing 无缓存，其余有缓存          |
| `systemPromptWithoutBoundaryUsesClaudeCodeSystemBlocks`      | 3 个块，正确分布                            |
| `requestBodyMatchesClaudeCodeCacheControlShape`              | marker 计数正确（system=3, tools=0, msg=1） |
| `sentRequestBodyMatchesClaudeCodeTopLevelShape`              | 顶层字段集合匹配 CC capture                 |
| `sentRequestBodyKeepsThreeMarkersForToolResultTurns`         | tool-result 回合 marker 正确                |
| `cacheControlOnLastTextBlock`                                | marker 正确落在 text 块                     |
| `noCacheControlOnToolResultOnlyMessage`                      | tool_result-only 消息无 marker              |
| `cacheControlPrefersTrailingTextAfterToolResults`            | marker 跳过 tool_result                     |
| `toolResultCacheBreakpointReminderCreatesTrailingTextMarker` | 断点 text 块正确追加                        |
| `skipsThinkingBlockForCacheControl`                          | marker 跳过 thinking                        |
| `skipsRedactedThinkingBlock`                                 | marker 跳过 redacted_thinking               |
| `allThinkingBlocksNoCacheControl`                            | 纯 thinking 消息无 marker                   |

### 单元测试：`ToolRegistryCachingTests`

验证工具定义排序稳定性。

### 单元测试：`SystemPromptCachingTests`

验证 system prompt 结构（boundary 存在、静态/动态内容分布正确）。

### 运行测试

```bash
# 仅缓存相关测试
swift test --disable-sandbox --no-parallel --filter CacheControlPlacementTests
swift test --disable-sandbox --no-parallel --filter ToolRegistryCachingTests
swift test --disable-sandbox --no-parallel --filter SystemPromptCachingTests

# 所有测试
swift test --disable-sandbox --no-parallel
```

### 集成测试：`swift-agent eval cache-hit-rate`

真实 API 调用验证。参见 [诊断低命中率](#诊断低命中率)。

---

## 生产监控

### Debug 日志

启用 `--debug` 或 `--verbose` 的会话自动生成日志：

```
~/.swift-agent/logs/debug-YYYYMMDD-HHmmss.jsonl
```

每个请求/响应的完整信息，包括：
- Request body（JSON）
- Response status + headers
- Raw SSE events
- Token usage per turn

### 日志脱敏

所有 auth header 必须 case-insensitive 脱敏：
- `x-api-key`
- `authorization`
- `api-key`

已有日志是敏感文件，不要提交、复制或分享。

### 监控指标

| 指标                  | 获取方式              | 告警条件                                          |
| --------------------- | --------------------- | ------------------------------------------------- |
| 每回合 cache_read     | `message_start.usage` | N/A（信息指标）                                   |
| 每回合 cache_creation | `message_start.usage` | N/A（信息指标）                                   |
| 可比命中率            | 公式计算              | < 50% 持续 3+ 回合                                |
| 请求顶层字段          | debug log body keys   | 出现 `temperature`/`tool_choice`/`anthropic_beta` |
| Cache marker 数量     | jq 检查               | 不等于预期值（4）                                 |
| System blocks 结构    | debug log system keys | 非 billing 块缺少 cache_control                   |

---

## 高级主题

### System Prompt 的静态/动态边界

`SystemPromptBuilder` 用 `__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__` 分隔静态前缀和动态后缀。这个 boundary 用于：



1. **Prompt 组合**：清晰地划分哪些内容是跨 session 不变的
2. **API 格式化**：在 `apiFormattedSystem()` 中拆分，并为两部分都加 `cache_control`
3. **缓存策略**：虽然两部分都缓存，但动态部分的稳定性取决于 session 参数

### CLAUDE.md 与缓存

CLAUDE.md 的内容在 dynamic 部分（boundary 之后），因为不同的项目有不同的 CLAUDE.md。但同一 session 内 CLAUDE.md 内容不变，所以加了 `cache_control` 后可以在 session 内被缓存复用。

### MCP 工具与缓存

MCP 工具是缓存稳定性的重要变量：

- MCP 工具在启动时注册，`toolDefinitions()` 在 MCP bootstrap 之后调用（`ChatCommand.swift:157`）
- 如果 MCP 工具的 description 包含动态内容（如 session ID、连接状态），会导致 cache miss
- 建议 MCP server 作者确保 tool description 是确定性的

### Compaction 与缓存

当 conversation history 太长触发 compaction（消息压缩）时，被压缩的旧消息会被 summary 替代。这会改变 messages 前缀，可能导致缓存 miss。这是正常的 tradeoff——用一次性的 cache miss 换取更小的请求。

### 多 Provider 差异

| Provider       | 缓存行为                                    |
| -------------- | ------------------------------------------- |
| Anthropic 官方 | 完全支持 prompt caching，ephemeral 5min TTL |
| DeepSeek 代理  | 支持系统级缓存，消息级缓存视情况而定        |
| 其他第三方代理 | 行为不确定，需实测                          |

---

## 维护规则速查

### 不要做的事

1. ❌ 不要引入 `scope: "global"`（除非 CC capture 证明回归）
2. ❌ 不要在 tools 上加 `cache_control`（除非 CC capture 证明回归）
3. ❌ 不要把 beta 放回 body 的 `anthropic_beta`
4. ❌ 不要在 adaptive thinking 请求中发 `temperature`
5. ❌ 不要发 `tool_choice`（除非 CC capture 出现）
6. ❌ 不要把 message-level `cache_control` 放在 `tool_result` block
7. ❌ 不要让动态 system 块失去 `cache_control`（会形成 gap）
8. ❌ 不要从 `message_delta` 提取完整的 input token 用量

### 必须做的事

1. ✅ tool-result user message 必须有 trailing text breakpoint
2. ✅ 修改 `LLMClient` request shape 后必须更新 `CacheControlPlacementTests`
3. ✅ 对比命中率时必须同时看 raw fields 和 comparable denominator
4. ✅ debug logs 中 auth header 必须 case-insensitive 脱敏
5. ✅ 每次修改缓存逻辑后使用 `eval cache-hit-rate` 做真实 API 验证
6. ✅ 所有非 billing system prompt 块连续加 `cache_control`
7. ✅ 用量必须从 `messageStart` 中提取（不是 `messageDelta`）
8. ✅ `ToolRegistry.toolDefinitions()` 的输出必须稳定排序

### 修改 LLMClient 后的检查清单

- [ ] `buildMessagesRequestBody` 的顶层字段集合是否仍与 CC capture 一致
- [ ] `apiFormattedSystem` 的 block 数、marker 数是否正确
- [ ] `apiFormattedMessages` 的 marker 是否在正确位置
- [ ] `apiFormattedTools` 的 enablePromptCaching 是否为 false
- [ ] `applyClaudeCodeRequestShape` 是否移除了 forbidden 字段
- [ ] `anthropic-beta` header 是否包含了所有需要的 betas
- [ ] 运行 `CacheControlPlacementTests`
- [ ] 运行 `eval cache-hit-rate`

---

## 已知问题与待解决

### 1. `apiFormattedTools` 包含永不执行的死代码

`LLMClient.swift:654-667` 的 `apiFormattedTools` 方法有添加 `cache_control` 到最后一个 tool 的逻辑，但调用点（line 489）始终传 `enablePromptCaching: false`。该分支永不执行。这不影响缓存行为（CC 也不在 tools 上加 marker），但代码误导读者。

**建议**：简化方法，移除死代码，或者保留但加注释说明。




### 2. `EvalCommand` 使用 `thinking: .disabled`

`EvalCommand.swift:219` 使用 `.disabled`。某些代理仅在 `thinking` 存在时创建缓存条目，这可能导致 eval 命令的 `cache_creation` 始终为 0。





**建议**：将 eval 命令的 thinking 改为 `.adaptive`，或添加 `--thinking` 参数让用户指定。

### 3. 生产环境 ChatCommand 未显式传递 `enablePromptCaching`

`ChatCommand.swift:518-526` 依赖 `send()` 的默认参数值 `enablePromptCaching: true`。虽然没有功能问题，但不显式传递降低了代码可读性。

**建议**：显式添加 `enablePromptCaching: true` 参数。



### 4. `ToolRegistry.schemaCache` 可能返回过时的 definition

如果 permission context 或 tool list 在 session 中变化，`cachedToolDefinition(named:)` 会返回旧的缓存值，而不是用新 context 重新计算。当前实践中 context 很少变化，但潜在风险存在。

**建议**：当 context 变化时显式 invalidate cache。

### 5. 消息级缓存不可用

实测 SwiftAgent 通过当前代理（deepseek-v4-flash）无法获得消息级缓存命中。这与 Claude Code flash 会话（命中率持续随历史增长）存在差距。

- **可能原因**：代理差异、thinking 参数前提条件、请求大小阈值
- **验证方式**：用 Claude Code 原版 + 同一代理测试，或换用 Anthropic 官方 API 测试

---

## 试错档案

SwiftAgent 对齐 prompt cache 的历史经验教训。

### Phase 1：原始状态（单块系统提示）

原始 `apiFormattedSystem` 把整个 system prompt 合并为单个 text block 加 `cache_control`。命中率仅 13.2%。

**教训**：单块无法与 CC 对齐，缺少 billing header 和 identity 块。

### Phase 2：第一次修复 — 动态块无缓存（失败）

在 `SYSTEM_PROMPT_DYNAMIC_BOUNDARY` 处拆分，静态块有 `cache_control`，动态块没有。预期：动态内容不缓存，静态内容缓存。

**结果**：

| 场景       | cache_read | 命中率 |
| ---------- | ---------- | ------ |
| CC flash   | 24K → 103K | 90%+   |
| SwiftAgent | 7K flat    | 6-16%  |

**根因**：代理把"有缓存块 → 无缓存块"的 gap 视为缓存边界重置，tools 和 messages 完全不被缓存匹配。

**教训**：Gap 是致命的——代理不填充 gap。

### Phase 3：第二次修复 — 连续缓存链（成功）

所有非 billing 系统块都加 `cache_control`。形成连续缓存链：`[billing无缓存] [identity+缓存] [static+缓存] [dynamic+缓存]`。

**结果**（通过同一代理测试）：

```
Turn  Input  Cache Read  Cache Cre.  Hit Rate
  1     782           0           0     0.0%
  2      30         768           0    96.2%
  3     171         768           0    81.8%
```

Turn 2 达到 96.2%，系统提示连续缓存链正常工作。

### Phase 4：messageStart 修复 — 用量日志缺失

生产环境中 `usage` 始终为 0 ——只从 `messageDelta` 事件提取用量，但 `input_tokens`/`cache_read`/`cache_creation` 只在 `messageStart.message.usage` 中存在。

**修复**：添加 `case .messageStart` 处理分支。

---

## 参考链接

- [Anthropic Prompt Caching 文档](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- [Claude Code 源码](~/CLI/claude-code/) — 对齐参考
- `docs/ARCHITECTURE.md` — SwiftAgent 架构概览
- `docs/ROADMAP.md` — 进度与优先级
- `docs/AI_HANDOFF.md` — 对齐快照

---

*最后更新：2026-06-04*
