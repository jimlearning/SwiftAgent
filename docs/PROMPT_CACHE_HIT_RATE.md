# Prompt Cache Hit Rate

本文记录 SwiftAgent 对齐 Claude Code prompt cache 命中效果的研究结论、误区、实测证据和维护规则。它不是通用 API 说明，而是本项目后续修改 LLM request shape 时必须参考的工程基线。

## 目标

SwiftAgent 的目标不是“打开 prompt caching”这么简单，而是让发送给同一模型和同一网关的请求结构尽量与 Claude Code cache-equivalent。

缓存命中率受以下因素共同影响：

- system/messages/tools 的块结构和顺序
- `cache_control` marker 的数量、位置和字段内容
- body 顶层字段集合
- beta 是 header 还是 body 字段
- tool schema 的稳定性和是否使用 `defer_loading`
- conversation history 的长度和可复用 prefix 大小
- debug/CLI 展示命中率时使用的分母

不要把命中率问题直接归因于 `deepseek-v4-pro`。本次排查已证明，模型相同的情况下，请求结构差异足以造成明显命中差异。

## 基础知识

### Prompt cache 缓存的是什么

Prompt cache 缓存的是一次请求中可复用的输入前缀，不是模型输出，也不是整个会话对象。对聊天式 coding agent 来说，这个输入前缀通常包含：

- system prompt blocks
- tool definitions
- conversation history 中较早的 messages
- 被 `cache_control` 标记覆盖到的 content blocks

服务端第一次看到某个可缓存前缀时，会把它写入缓存；后续请求如果发送了相同或等价的前缀，就可以从缓存读取这部分 token，减少重新处理成本和延迟。

### Cache marker 是什么

`cache_control` marker 是告诉 API “到这个位置为止可以作为缓存断点”的标记。它不是一个独立的缓存开关，而是嵌在 system、message content block 或 tool definition 上的结构字段。

例如：

```json
{
  "type": "text",
  "text": "You are Claude Code, Anthropic's official CLI for Claude.",
  "cache_control": { "type": "ephemeral" }
}
```

关键点：

- marker 的位置决定缓存前缀的边界。
- marker 的字段也参与 request shape；`{ "type": "ephemeral" }` 和 `{ "type": "ephemeral", "scope": "global" }` 不是同一个形态。
- marker 多不一定更好。多余 marker 会改变请求形状，也可能与 Claude Code 的策略不一致。
- `ephemeral` 表示缓存有短期生命周期；不要把它理解成永久缓存。

### Cache key 为什么容易失效

Prompt cache 不是按“看起来差不多”匹配，而是依赖服务端对请求前缀的结构化匹配。下面这些变化都可能让缓存无法命中或只能命中更短的前缀：

- system blocks 拆分方式变化
- text 前后多一个换行、空格或动态时间戳
- tools 排序变化
- tool schema、description、`defer_loading` 字段变化
- message content block 顺序变化
- `cache_control` 数量、位置、字段变化
- body 顶层字段变化，例如多出 `temperature` 或 `tool_choice`
- beta 放在 header 还是 body

所以“同一个模型”不等于“同一个 cache key”。缓存命中率首先是 request shape 和 prefix 稳定性问题，其次才是模型配置问题。

### First request、cache creation、cache read

一个新会话通常不会在第一轮就有高 `cache_read_input_tokens`，因为服务端还没有见过当前请求前缀。更常见的过程是：

1. 第一轮发送长 system prompt 和 tools，服务端创建缓存。
2. 第二轮及后续请求复用相同 system/tools/历史前缀，开始出现 `cache_read_input_tokens`。
3. 会话越长，可复用历史前缀越大，`cache_read_input_tokens` 通常越高。

因此，不能用一个很短的 SwiftAgent 两三轮日志直接对比 Claude Code 151 条 messages 的长会话 capture。

### Usage 字段怎么读

常见字段：

| Field | 含义 |
|---|---|
| `input_tokens` | 本次仍需要正常处理的输入 token |
| `cache_creation_input_tokens` | 本次写入缓存的输入 token |
| `cache_read_input_tokens` | 本次从缓存读取的输入 token |
| `output_tokens` | 模型输出 token |

一个容易犯的错误是用：

```text
cache_read_input_tokens / input_tokens
```

这不是可比命中率，因为 `input_tokens` 不包含已经从缓存读取的部分。更合理的输入侧可比口径是：

```text
cache_read_input_tokens / (input_tokens + cache_read_input_tokens + cache_creation_input_tokens)
```

这个口径衡量的是“本次输入总量里有多少来自缓存”。它仍然不是服务端内部真实 cache key 诊断，只是比 `cache_read / input` 更适合跨工具比较。

### Agent 为什么特别依赖 prompt cache

Coding agent 每轮请求都会重复携带大量稳定内容：

- 长 system prompt
- 安全规则和工具使用规范
- 数十个 tool schemas
- 项目 memory / system reminders
- 多轮对话历史

如果这些稳定前缀不能命中缓存，每轮都会重新处理大量 token，表现为成本高、延迟高、长会话越来越慢。Claude Code 的 cache 效果好，不只是因为启用了 cache，而是因为它的 request shape、工具 schema、message normalization 和 cache marker 策略共同保持了稳定前缀。

### 这份文档的判断原则

本项目的判断顺序是：

1. 先确认 SwiftAgent 与 Claude Code 的请求结构是否 cache-equivalent。
2. 再看 system/tools/messages 哪一段前缀不稳定。
3. 最后才评估模型、网关或 provider 差异。

只要模型和网关相同，就不要把低命中率先归因于 `deepseek-v4-pro`。更高概率的问题是 SwiftAgent 发送的请求和 Claude Code 不同。

## 实测基线

对比来源：

- SwiftAgent latest run: `/Users/jim/.swift-agent/logs/debug-20260603-004847.jsonl`
- Claude Code prompt-gateway captures: `/Users/jim/SwiftAgent/.claude/prompt-gateway/captures/sessions/.../*.json`

Claude Code 最新 capture 的稳定请求形态：

```json
{
  "bodyKeys": [
    "context_management",
    "max_tokens",
    "messages",
    "metadata",
    "model",
    "output_config",
    "stream",
    "system",
    "thinking",
    "tools"
  ],
  "max_tokens": 32000,
  "thinking": { "type": "adaptive" },
  "context_management": {
    "edits": [
      { "type": "clear_thinking_20251015", "keep": "all" }
    ]
  },
  "output_config": { "effort": "high" }
}
```

Claude Code system block shape:

```json
[
  {
    "type": "text",
    "text": "x-anthropic-billing-header: cc_version=2.1.143.7a0; cc_entrypoint=cli; cch=a12e4;"
  },
  {
    "type": "text",
    "text": "You are Claude Code, Anthropic's official CLI for Claude.",
    "cache_control": { "type": "ephemeral" }
  },
  {
    "type": "text",
    "text": "\nYou are an interactive agent ...",
    "cache_control": { "type": "ephemeral" }
  }
]
```

Cache marker 基线：

| Location | Count | Shape |
|---|---:|---|
| system | 2 | plain `{ "type": "ephemeral" }` |
| tools | 0 | no marker |
| latest message | 1 | plain `{ "type": "ephemeral" }` |
| total | 3 | no `scope:"global"` |

Headers 基线：

- `anthropic-beta` 是 header，不是 body 字段。
- `anthropic-beta` 包含：`claude-code-20250219`, `interleaved-thinking-2025-05-14`, `redact-thinking-2026-02-12`, `context-management-2025-06-27`, `prompt-caching-scope-2026-01-05`, `advisor-tool-2026-03-01`, `advanced-tool-use-2025-11-20`, `effort-2025-11-24`。
- Claude Code capture 使用 `authorization` header。SwiftAgent 当前同时保留 `authorization` 和 `x-api-key`，用于兼容 Anthropic-compatible endpoints。

## 已修正的 SwiftAgent 对齐方案

### System prompt formatting

旧方案：

- 在 `SYSTEM_PROMPT_DYNAMIC_BOUNDARY` 处拆成 static/dynamic 两块。
- static prefix 使用 `cache_control: { "type": "ephemeral", "scope": "global" }`。
- dynamic suffix 不缓存。

实测问题：

- Claude Code 最新 capture 没有 `scope:"global"`。
- Claude Code 将主 system prompt 整块作为 plain ephemeral cache block。
- SwiftAgent 旧方案把 dynamic suffix 排除在 cache block 外，导致大量 system tokens 每轮重新计费。

当前方案：

- wire request 固定为 3 个 system text blocks。
- billing header block 不加 cache marker。
- identity block 加 plain ephemeral marker。
- 主 system prompt block 加 plain ephemeral marker。
- `SYSTEM_PROMPT_DYNAMIC_BOUNDARY` 只保留为 prompt composition boundary，不再映射为 API cache boundary。

### Message cache marker

当前保留 exactly one latest-message marker：

- 每次请求只在最后一条 message 的最后一个可缓存 content block 上添加 `cache_control`。
- `thinking` 和 `redacted_thinking` 不承载 cache marker。
- 这与 Claude Code 的 latest-message breakpoint 行为一致。

### Tool cache marker

当前 tools 不加 `cache_control`。

实测 Claude Code capture：

- `tools[].cache_control` 为 0。
- MCP/deferred tools 通过 `defer_loading` 和 `ToolSearch` 控制，而不是靠 tool-level cache marker。

注意：`ToolDefinition.apiFormattedWithCache` 仍存在，但 chat request path 不应启用它，除非未来新的 Claude Code capture 证明 tool-level marker 回归。

### Top-level body

当前 chat request 应满足：

- 有：`context_management`, `max_tokens`, `messages`, `metadata`, `model`, `output_config`, `stream`, `system`, `thinking`, `tools`
- 无：`temperature`, `tool_choice`, `anthropic_beta`
- `max_tokens = 32000`
- `thinking = { "type": "adaptive" }`
- `output_config = { "effort": "high" }`

### Beta placement

旧方案将 betas 放在 body 的 `anthropic_beta`。

当前方案将 betas 放在 `anthropic-beta` header。body 中不允许出现 `anthropic_beta`，否则 request shape 与 Claude Code capture 不一致。

### Debug logging safety

发现的问题：

- `Authorization` header 曾因大小写不匹配没有被脱敏，完整 key 被写入 debug log。

修正：

- header 脱敏按 case-insensitive key 匹配。
- `x-api-key`, `authorization`, `api-key` 都必须脱敏。

已有受影响的本地日志应按敏感文件处理，不要提交、复制或分享。

## 误区

### 误区 1：同模型就应该同命中

错误。Prompt cache key 依赖 request prefix 的实际结构和字节级稳定性。模型相同只是必要条件之一。

### 误区 2：`scope:"global"` 一定更好

错误。本次最大误判就是把 `scope:"global"` 当成 Claude Code 当前策略。实测 capture 显示 Claude Code 使用 plain ephemeral markers，没有 `scope:"global"`。

### 误区 3：只看 marker 数量就够

错误。marker 数量相同但位置不同，缓存 prefix 也不同。尤其 system prompt 是否整块包含动态信息，会直接影响每轮重新计费的 token 数。

### 误区 4：工具 schema 加 cache marker 一定能提升命中

不一定。Claude Code 当前 chat request 没有 tool-level marker。SwiftAgent 要优先保持 request shape parity，而不是凭直觉增加 marker。

### 误区 5：`cache_read / input_tokens` 是可比命中率

错误。API raw `input_tokens` 不包含已 cache read 的 tokens。可比口径应使用：

```text
cache_read_input_tokens / (input_tokens + cache_read_input_tokens + cache_creation_input_tokens)
```

## 日志判读

检查 request shape：

```bash
jq -r '
  select(.type=="request") |
  [
    .seq,
    .body.max_tokens,
    (.body.system|length),
    (.body.tools|length),
    (.body.messages|length),
    ([.body | .. | objects | select(has("cache_control"))] | length),
    ([.body.system[]? | select(has("cache_control"))] | length),
    ([.body.tools[]? | select(has("cache_control"))] | length),
    ([.body.messages[]? | .. | objects | select(has("cache_control"))] | length)
  ] | @tsv
' ~/.swift-agent/logs/debug-*.jsonl
```

预期输出形态：

```text
seq  32000  3  <tool_count>  <message_count>  3  2  0  1
```

检查 top-level body keys：

```bash
jq -c '
  select(.type=="request") |
  {
    bodyKeys:(.body|keys),
    thinking:.body.thinking,
    context_management:.body.context_management,
    output_config:.body.output_config,
    temperature:.body.temperature,
    tool_choice:.body.tool_choice,
    anthropic_beta:.body.anthropic_beta
  }
' ~/.swift-agent/logs/debug-*.jsonl
```

检查 cache usage：

```bash
jq -r '
  select(.type=="stream_event" and .raw.type=="message_start") |
  [
    .seq,
    .raw.message.usage.input_tokens,
    .raw.message.usage.cache_read_input_tokens,
    .raw.message.usage.cache_creation_input_tokens
  ] | @tsv
' ~/.swift-agent/logs/debug-*.jsonl
```

检查 comparable hit rate：

```bash
jq -r '
  select(.type=="usage") |
  [
    .seq,
    .input_tokens,
    .cache_read_input_tokens,
    .cache_creation_input_tokens,
    .cache_comparable_input_tokens,
    .cache_hit_rate_pct
  ] | @tsv
' ~/.swift-agent/logs/debug-*.jsonl
```

## 当前实测结果

`debug-20260603-004847.jsonl` 显示：

- request shape 已基本达到 Claude Code parity。
- 每次请求都是 `systemLen=3`。
- cache marker 总数固定为 3。
- system marker 为 2，tool marker 为 0，message marker 为 1。
- `max_tokens=32000`。
- body 中不再出现 `temperature`, `tool_choice`, `anthropic_beta`。
- `cache_read_input_tokens` 从 0 增长到 7296/7808，最后一条 usage 到 22400。

这说明结构修复已生效，但短会话不能直接对比 Claude Code 长 capture 中 124800 到 128000 的 `cache_read_input_tokens`。Claude Code 那份 capture 有 151 条 messages，SwiftAgent 这份日志最多 13 条 messages，可复用 prefix 规模不同。

## 仍需跟踪的差异

### `metadata.user_id`

Claude Code capture 中 `metadata.user_id` 是 JSON string：

```json
{
  "metadata": {
    "user_id": "{\"device_id\":\"...\",\"account_uuid\":\"\",\"session_id\":\"...\"}"
  }
}
```

SwiftAgent debug logger 会递归展开 JSON string，因此日志中可能显示为 object。判断 wire body 时要注意区分 logger 展示和实际发送 body。

### Tool set

SwiftAgent 当前 tools count 与 Claude Code capture 不一定相同。工具集合不同会影响 cacheable prefix 大小和工具选择行为，但不应通过随意删工具来追求命中率。应优先保持工具行为正确，再用 deferred loading 控制工具 schema 膨胀。

### Deferred tools

Claude Code capture 中部分工具有 `defer_loading:true`，如 MCP codegraph tools。SwiftAgent 的具体 deferred tool 状态依赖本轮工具发现和 MCP bootstrap。如果命中率仍低，下一步应检查：

- `ToolRegistry.toolDefinitions()` 是否稳定排序。
- `ToolDefinition.apiFormatted` 是否稳定输出。
- MCP tool descriptions 是否包含每轮漂移内容。
- discovered deferred tools 是否在后续请求中稳定展开。

## 维护规则

1. 不要重新引入 `scope:"global"`，除非新的 Claude Code capture 证明其回归。
2. 不要在 chat request 的 tools 上添加 `cache_control`，除非新的 Claude Code capture 证明其回归。
3. 不要把 beta 放回 body 的 `anthropic_beta`。
4. 不要在 adaptive thinking chat request 中发送 `temperature`。
5. 不要发送 `tool_choice`，除非 Claude Code capture 出现该字段。
6. 修改 `LLMClient` request shape 后，必须更新 `CacheControlPlacementTests`。
7. 对比命中率时必须同时看 raw fields 和 comparable denominator。
8. debug logs 中任何 auth header 必须 case-insensitive 脱敏。

## 回归测试

核心测试：

```bash
swift test --disable-sandbox --no-parallel --filter CacheControlPlacementTests
```

全量测试：

```bash
swift test --disable-sandbox --no-parallel
```

已知环境风险：如果用户全局 `/Users/jim/.claude/CLAUDE.md` 存在，`ClaudeMdLoaderTests.loadAllReturnsEmptyForEmptyDirectory` 可能被全局 memory 污染而失败。这不是 prompt cache request shape 的回归。

## 下一步排查路线

如果请求结构达标但 cache hit 仍明显低：

1. 用同一 session 连续跑更长上下文，不要拿短会话和 Claude Code 151-message capture 直接比较。
2. 比较 consecutive requests 的 serialized prefix 是否稳定。
3. 检查 tool schema 字节稳定性，尤其 MCP descriptions。
4. 检查 message normalization 是否导致历史消息重排或 content block 变化。
5. 检查 debug logger 是否改变展示形态，但不要把 logger 展开后的 JSON object 误判为 wire body。
6. 再与最新 Claude Code prompt-gateway capture 对比，不要依赖旧印象。
