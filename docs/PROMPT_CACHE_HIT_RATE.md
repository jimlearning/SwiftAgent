# Prompt Cache Hit Rate（工程档案）

> **📖 新读者请阅读 [PROMPT_CACHE_GUIDE.md](./PROMPT_CACHE_GUIDE.md)**，那是从入门到精通的全面指南。
>
> 本文档保留为 SwiftAgent 缓存对齐的工程档案，包含完整的试错记录和 Claude Code capture 对比数据。

本文记录 SwiftAgent 对齐 Claude Code prompt cache 命中效果的研究结论、误区、试错过程和工程基线。它不是通用 API 说明，而是本项目后续修改 LLM request shape 时必须参考的工程档案。

## 目标

SwiftAgent 的目标不是"打开 prompt caching"这么简单，而是让发送给同一模型和同一网关的请求结构尽量与 Claude Code cache-equivalent。

缓存命中率受以下因素共同影响：

- system/messages/tools 的块结构和顺序
- `cache_control` marker 的数量、位置和字段内容
- body 顶层字段集合
- beta 是 header 还是 body 字段
- tool schema 的稳定性和是否使用 `defer_loading`
- conversation history 的长度和可复用 prefix 大小
- debug/CLI 展示命中率时使用的分母

不要把命中率问题直接归因于模型。本次排查已证明，模型相同的情况下，请求结构差异足以造成明显命中差异。

## 基础知识

### Prompt cache 缓存的是什么

Prompt cache 缓存的是一次请求中可复用的输入前缀，不是模型输出，也不是整个会话对象。对聊天式 coding agent 来说，这个输入前缀通常包含：

- system prompt blocks
- tool definitions
- conversation history 中较早的 messages
- 被 `cache_control` 标记覆盖到的 content blocks

服务端第一次看到某个可缓存前缀时，会把它写入缓存；后续请求如果发送了相同或等价的前缀，就可以从缓存读取这部分 token，减少重新处理成本和延迟。

### Cache marker 是什么

`cache_control` marker 是告诉 API "到这个位置为止可以作为缓存断点"的标记。它不是一个独立的缓存开关，而是嵌在 system、message content block 或 tool definition 上的结构字段。

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

### 代理/网关的缓存行为差异

Claude Code Switch / 第三方代理对缓存行为有额外影响：

- **系统块的开闭**：代理可能把 `cache_control` 存在/不存在的系统块之间的边界视为缓存前缀重置点。如果最后一个系统块没有 `cache_control`，代理可能在系统块之后就不再进行缓存匹配，导致 tools 和 messages 永远无法命中缓存。
- **开启思考参数的影响**：某些代理在缺少 `thinking` 参数时不创建任何缓存条目（`cache_creation_input_tokens = 0`）。
- **min cache threshold**：代理可能仅在请求超过一定大小时（如首个请求 > 1000 tokens）才激活缓存创建逻辑。
- **请求大小与缓存倾向**：系统提示越小，代理越不愿意为其创建缓存条目。

因此，在调试低命中率时，需同时检查 provider / proxy 的行为限制，而非仅关注 SwiftAgent 自身的请求结构。

### Cache key 为什么容易失效

Prompt cache 不是按"看起来差不多"匹配，而是依赖服务端对请求前缀的结构化匹配。下面这些变化都可能让缓存无法命中或只能命中更短的前缀：

- system blocks 拆分方式变化
- text 前后多一个换行、空格或动态时间戳
- tools 排序变化
- tool schema、description、`defer_loading` 字段变化
- message content block 顺序变化
- `cache_control` 数量、位置、字段变化
- body 顶层字段变化，例如多出 `temperature` 或 `tool_choice`
- beta 放在 header 还是 body

所以"同一个模型"不等于"同一个 cache key"。缓存命中率首先是 request shape 和 prefix 稳定性问题，其次才是模型配置问题。

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

这个口径衡量的是"本次输入总量里有多少来自缓存"。它仍然不是服务端内部真实 cache key 诊断，只是比 `cache_read / input` 更适合跨工具比较。

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

只要模型和网关相同，就不要把低命中率先归因于模型。更高概率的问题是 SwiftAgent 发送的请求和 Claude Code 不同。

## 实测基线

对比来源：

- SwiftAgent latest run: `/Users/jim/.swift-agent/logs/debug-*.jsonl`
- Claude Code prompt-gateway captures: `/Users/jim/SwiftAgent/.claude/prompt-gateway/captures/sessions/.../*.json`

### Claude Code 最新 capture 的稳定请求形态

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

### Claude Code system block shape

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

### Cache marker 基线

| Location | Count | Shape |
|---|---:|---|
| system | 2 | plain `{ "type": "ephemeral" }` |
| tools | 0 | no marker |
| latest message | 1 | plain `{ "type": "ephemeral" }` |
| total | 3 | no `scope:"global"` |

Claude Code 使用 non-global mode（org scope），即所有 system content 放在一个 cached "rest" block 中。

### Headers 基线

- `anthropic-beta` 是 header，不是 body 字段。
- `anthropic-beta` 包含：`claude-code-20250219`, `interleaved-thinking-2025-05-14`, `redact-thinking-2026-02-12`, `context-management-2025-06-27`, `prompt-caching-scope-2026-01-05`, `advisor-tool-2026-03-01`, `advanced-tool-use-2025-11-20`, `effort-2025-11-24`。
- Claude Code capture 使用 `authorization` header。SwiftAgent 当前同时保留 `authorization` 和 `x-api-key`，用于兼容 Anthropic-compatible endpoints。

---

## 试错全记录

### Phase 1: 原始状态（单块 system prompt，无缓存链）

原始 `apiFormattedSystem` 把整个 system prompt（含 boundary）合并成单个 text block，加 `cache_control`。理论上正确，但实际命中率仅 13.2%。

**根因**：不是单块的问题，而是缺少 CC 的 identity block 和 billing header block，与 CC 的 ISO 形态不同。但更重要的是 Phase 2 发现的问题。

### Phase 2: 第一次修复 Splitting — 动态块不加 cache_control（错误的方案）

**修改**：在 `SYSTEM_PROMPT_DYNAMIC_BOUNDARY` 处拆分，静态块加 `cache_control`，动态块**不加**。

**预期**：动态内容（session-specific guidance、memory、date）不缓存，静态内容缓存。匹配 CC 的 global mode。

**实际效果（通过 SAME proxy 对比）：**

| 场景 | cache_read | cache_creation | 命中率 |
|---|---|---|---|
| CC flash（deepseek-v4-flash） | 24K → 103K | 有 | 90%+ |
| SwiftAgent（修复后） | 7K（flat） | 0 | 6-16% |

**问题分析**：

1. **代理行为**：CC Switch 等代理把"有 cache_control 的系统块 → 无 cache_control 的系统块 → messages"中的 gap 视为缓存边界重置。从无缓存块的系统块之后的 tools 和 messages 完全不被匹配。
2. **CC 的实际模式**：CC 在 non-global mode（org scope）下把**所有** system content 放进一个 cached "rest" 块，没有 gap。
3. **测试误导**：Unit tests 全部通过，mock 不模拟代理行为，造成了"修复成功"的错觉。

### Phase 3: 第二次修复 — 双块均加 cache_control（正确的方案）

**修改**：静态块和动态块**都加** `cache_control: ephemeral`。形成连续的缓存链：

```
[billing 无缓存] [identity + 缓存] [static + 缓存] [dynamic + 缓存] [tools] [messages]
```

**验证（通过 unit tests）：**

- `testSystemPromptBoundaryCreatesClaudeCodeSystemBlocks`：期待 3 个块（billing + identity + combined rest），所有非 billing 块有 `cache_control`。
- cache marker 总数：system=2, total=3。
- 所有 258 个测试通过。

**实测结果（通过 SAME proxy 运行 `eval cache-hit-rate`）：**

```
Turn  Input  Cache Read  Cache Cre.  Hit Rate
  1     782           0           0     0.0%
  2      30         768           0    96.2%
  3     171         768           0    81.8%
```

- Turn 2 达到 **96.2% 命中率** — 系统提示的连续缓存链正常工作。
- `cache_read` 为 768 tokens，覆盖系统提示的全部三个缓存块。
- `cache_creation` 为 0 — 该会话未触发缓存创建（768 来自先前会话的预缓存）。
- Turn 3 命中率降至 81.8%，因为新的 user/assistant 消息使新增 token（171）增加，而缓存部分（768）不变。

**启示**：

- **Cache_creation != cache_read**。即使 cache_creation 为 0，先前预热过的系统提示块仍可通过 cache_read 获得命中。
- 消息级缓存取决于代理支持，与系统提示块结构无关。当前代理在此模型/参数组合下不创建消息级缓存条目。
- 如果请求太小（<1000 tokens），某些代理可能完全跳过缓存创建。

### Phase 4: messageStart 修复 — 用量日志缺失

**问题**：生产环境 debug 日志中 `usage` 条目始终为 0。调查发现 `ChatCommand.swift` 只在 `messageDelta` 事件处理中捕捉用量数据。但根据 Anthropic API 规范，`message_delta.usage` **仅包含 `output_tokens`**，而 `input_tokens`、`cache_read_input_tokens` 和 `cache_creation_input_tokens` 只在 `message_start.message.usage` 中出现。

**修复**：添加 `case .messageStart` 处理分支，从中捕获完整用量数据。

**效果**：从此每个 SwiftAgent 会话的 debug 日志将自动包含缓存的命中率统计。

### Phase 5: JSON key 排序修复（NSDictionary → JSONEncoder.sortedKeys）

**背景**：Phase 2-3 的缓存体验不稳定。`eval cache-hit-rate` 显示 turn 2 的 `cache_read` 仅为 768 tokens（仅系统提示），且从 turn 3 起缓存完全丢失。然而 Claude Code 在相同模型和网关上能达到 90%+ 持续命中。两工具的请求结构（system blocks、marker 位置、body 顶层字段）已对齐，但缓存效果依然不同。

**假设**：请求的字节级表示在 SwiftAgent 的不同轮次之间发生变化。由于 DeepSeek 的 KV-cache 要求 token prefix 字节完全一致，任何请求结构的微小变化都会导致缓存无法复用。

**排查过程**：

1. **比较 consecutive requests 的序列化输出**。将两个相邻请求的完整 message body 进行 `shasum` 发现：即便 `max_tokens`、`stream`、`system` 等顶层字段完全相同，它们的字节表示依然不同。

2. **缩小差异范围**。通过逐层 `diff` 确认差异不在系统提示或工具定义中（这些是稳定前缀），而在 `[String: Any]` 字典的 JSON 序列化结果中。

3. **固定测试复现**。以下测试确认了问题的存在：
   ```
   相同 dict：{"text": "billing", "type": "text"}
   JSONSerialization 输出（不同调用）：
     调用 1：{"text":"billing","type":"text"}
     调用 2：{"type":"text","text":"billing"}  ← 键顺序变了！
   ```

**根因**：`LLMClient` 使用 `NSDictionary(objects:forKeys:)` 对字典键排序，但该方法 **不保证消除所有键的顺序不一致**。Swift 的 `[String: Any]` 枚举顺序是非确定性的（基于内部哈希表布局），而 `NSDictionary` 桥接后同样使用哈希表，对某些键组合（如 `"text"` 与 `"type"`）会产生哈希碰撞导致排序反转。具体来说：

```
// 测试验证：
NSDictionary(objects: ["z_val","a_val","m_val"], forKeys: ["z","a","m"])
  → allKeys: [z, a, m]  ✓ 保持插入顺序

NSDictionary(objects: ["billing","text"], forKeys: ["text","type"])
  → allKeys: [type, text]  ✗ 顺序反转！
```

这意味着 `sortJSONKeys(_:)` 和 `sortKeysRecursively(_:)` **根本不可靠**。某些键排序正确，另一些（如 `type`/`text`）则产生非确定性结果。这导致请求体的字节表示在每次序列化时都可能不同，使 DeepSeek 的 KV-cache 永远无法匹配 prefix。

**修复**：用 `JSONEncoder` + `.sortedKeys` + `SortedJSON` Encodable wrapper 替换所有 `NSDictionary` 排序逻辑：

```swift
private func stableJSONData(from body: [String: Any]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(SortedJSON(value: body))
}

private struct SortedJSON: Encodable {
    let value: Any
    func encode(to encoder: Encoder) throws {
        if let dict = value as? [String: Any] {
            var container = encoder.container(keyedBy: _CodingKey.self)
            for (key, val) in dict.sorted(by: { $0.key < $1.key }) {
                try container.encode(SortedJSON(value: val), forKey: _CodingKey(stringValue: key))
            }
        } else if let arr = value as? [Any] {
            var container = encoder.unkeyedContainer()
            for item in arr { try container.encode(SortedJSON(value: item)) }
        } else {
            var container = encoder.singleValueContainer()
            if let str = value as? String { try container.encode(str) }
            else if let num = value as? Int { try container.encode(num) }
            else if let num = value as? Double { try container.encode(num) }
            else if let bool = value as? Bool { try container.encode(bool) }
            else if value is NSNull { try container.encodeNil() }
            else { try container.encodeNil() }
        }
    }
    // ...
}
```

`JSONEncoder` 的 `.sortedKeys` 选项在编码过程中递归对所有 `KeyedContainer` 的键进行排序，产生完全确定性的 JSON 输出。同一词典无论编码多少次，输出的字节序列完全相同。

**同时修复 DebugLogger**：`DebugLogger.sortKeysRecursively` 和 `expandJSONStrings` 中的同样问题，移除 `JSONSerialization.data(withJSONObject:)` 调用，改用 `SortedJSON` 编码。

**实测结果（通过 SAME proxy 对比，deepseek-v4-flash）：**

```
Turn  Input  Cache Read  Cache Cre.  Hit Rate
  1   1,646      31,744           0     95.1%  ← 系统提示已预热
  2     314      34,560           0     99.1%  ← 历史消息开始缓存
  3     168      34,816           0    99.5%  ← 几乎全部命中
```

与 CC flash 会话对比（同一模型）：

| 指标 | CC flash | SwiftAgent (修复后) |
|---|---|---|
| Turn 1 命中率 | 85-90% | 95.1% |
| Turn 2+ 命中率 | 90%+ | 99-100% |
| `cache_creation` | 有 | 0 |
| `cache_read` 增长趋势 | 随历史增长 | 随历史增长 |
| `eo-cache-status` | MISS (always) | MISS (always) |

**关键启示**：

1. **NSDictionary 不可信**。`NSDictionary(objects:forKeys:)` 不保证插入顺序——底层哈希表可能对某些键组合产生碰撞，导致顺序反转。永远不要用它替代 JSON 序列化中的确定性键排序。

2. **`JSONEncoder.sortedKeys` 是唯一可靠方案**。它递归地对所有键值容器进行稳定排序，产生完全确定性的 JSON 字节输出。

3. **缓存不靠"看起来一样"，要求字节级一致**。DeepSeek 的 KV-cache 以 token prefix 为 key——任何字节差异（包括键顺序）都会导致缓存 MISS。

4. **`eo-cache-status` 不反映内部 KV-cache 状态**。该 HTTP 头始终为 `MISS`，即使实际 `cache_read_input_tokens` 达到 95%+。不要依赖该头判断缓存效果。

5. **同一会话内缓存可持续增长**。Turn 3 的 99.5% 命中率证明：当请求前缀稳定时，DeepSeek KV-cache 在会话过程中持续有效并覆盖更长的前缀。

---

## SwiftAgent 当前对齐方案

### System prompt formatting（已确认正确）

当前 `apiFormattedSystem` 生成 3 个系统块（有 boundary 时静态+动态合并为一个 "rest" 块，与 CC non-global mode 等价）：

| 索引 | 内容 | `cache_control` |
|---|---|---|
| 0 | `x-anthropic-billing-header` | 无 |
| 1 | `You are Claude Code, Anthropic's official CLI for Claude.` | `{ type: "ephemeral" }` |
| 2 | 静态 + 动态内容（boundary 前后合并） | `{ type: "ephemeral" }` |

所有非 billing 块形成连续缓存链，没有 gap。

### Cache marker 计数（已确认）

| Location | Count | Shape |
|---|---:|---|
| system | 2 | plain `{ "type": "ephemeral" }` (identity + combined rest) |
| tools | 0 | no marker |
| latest message | 1 | plain `{ "type": "ephemeral" }` |
| total | 3 | no `scope:"global"` |

对比 CC 基线：一致。CC non-global mode 同样将 static+dynamic 合并为一个 cached "rest" 块，总 system marker = 2。

**验证方式**：
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

预期输出：`seq  3  0  1  4`

### Message cache marker

当前保留 exactly one latest-message marker：

- 每次请求优先在最后一条 message 的最后一个 `text` content block 上添加 `cache_control`。
- `thinking`、`redacted_thinking` 和 `tool_result` 不承载 message-level cache marker。
- tool-result 回合会追加一个稳定的 trailing `<system-reminder>` text block，使 breakpoint 落在 text 上。
- 这与 Claude Code 的 latest-message breakpoint 行为一致。

### Tool cache marker

当前 tools 不加 `cache_control`。实测 Claude Code capture 中 `tools[].cache_control` 为 0。

### Top-level body

当前 chat request 已满足：

- 有：`context_management`, `max_tokens`, `messages`, `metadata`, `model`, `output_config`, `stream`, `system`, `thinking`, `tools`
- 无：`temperature`, `tool_choice`, `anthropic_beta`
- `max_tokens = 32000`
- `thinking = { "type": "adaptive" }`
- `output_config = { "effort": "high" }`

### Beta placement

旧方案将 betas 放在 body 的 `anthropic_beta`。当前方案将 betas 放在 `anthropic-beta` header。body 中不允许出现 `anthropic_beta`，否则 request shape 与 Claude Code capture 不一致。

### Debug logging safety

- header 脱敏按 case-insensitive key 匹配。
- `x-api-key`, `authorization`, `api-key` 都必须脱敏。
- 已有受影响的本地日志应按敏感文件处理，不要提交、复制或分享。

---

## 验证工具

### 命令：`swift-agent eval cache-hit-rate`

```bash
# 快速验证（3 轮，默认 deepseek-v4-flash）
swift run --disable-sandbox swift-agent eval cache-hit-rate --turns 3

# 完整验证（5 轮，显示 debug 日志）
swift run --disable-sandbox swift-agent eval cache-hit-rate --turns 5 --verbose

# 指定模型和 base URL
swift run --disable-sandbox swift-agent eval cache-hit-rate --model claude-sonnet-4-6 \
  --base-url https://api.anthropic.com
```

**工作原理**：

1. 构建一个约 500+ tokens 的带 boundary 标记的系统提示
2. 定义工具（Read、Edit、Bash、Glob、Grep）— 使请求大小接近生产环境
3. 执行 N 轮对话，每轮发送递增的 user/assistant 消息序列
4. 从 `message_start.usage` 提取 `input_tokens`、`cache_read`、`cache_creation`
5. 如果助手调用了工具，自动合成 `tool_result` 以保持消息序列有效
6. 输出每轮和累计的命中率表格

**预期输出**（系统提示已预热）：

```
Turn  Input  Cache Read  Cache Cre.  Hit Rate
  1     782           0           0     0.0%
  2      30         768           0    96.2%
  3     171         768           0    81.8%
```

### Debug 日志

每个启用了 `--verbose` 或 `--debug` 的 SwiftAgent 会话都在以下位置生成日志：

```
~/.swift-agent/logs/debug-YYYYMMDD-HHmmss.jsonl
```

日志包含每个 SSE 原始事件（带展开后的 JSON）以及 token 用量摘要。

检查缓存的顶层字段：

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

检查缓存用量：

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

### 回归测试

```bash
# 仅缓存测试
swift test --disable-sandbox --no-parallel --filter CacheControlPlacementTests

# 全量
swift test --disable-sandbox --no-parallel
```

---

## 误区

### 误区 1：同模型就应该同命中

错误。Prompt cache key 依赖 request prefix 的实际结构和字节级稳定性。模型相同只是必要条件之一。

### 误区 2：`scope:"global"` 一定更好

错误。本次最大误判就是把 `scope:"global"` 当成 Claude Code 当前策略。实测 capture 显示 Claude Code 使用 plain ephemeral markers，没有 `scope:"global"`。

### 误区 3：只看 marker 数量就够

错误。marker 数量相同但位置不同，缓存 prefix 也不同。尤其 system prompt 是否有 gap（有缓存块→无缓存块），会直接影响代理是否继续为 tools/messages 创建缓存。

### 误区 4：工具 schema 加 cache marker 一定能提升命中

不一定。Claude Code 当前 chat request 没有 tool-level marker。SwiftAgent 要优先保持 request shape parity，而不是凭直觉增加 marker。

### 误区 5：message marker 放在 `tool_result` 上也等价

错误。Claude Code capture 中，同类请求的最后一条 user message 通常是 `tool_result, text, text, ...`，其中 `cache_control` 落在最后一个 `text` block。因此"总 marker 数一样"仍不够，marker 的 content block 类型也必须对齐。修正后的 SwiftAgent 规则：message-level marker 只放在 `text` block；tool-result-only message 不加 marker。

### 误区 6：`cache_read / input_tokens` 是可比命中率

错误。API raw `input_tokens` 不包含已 cache read 的 tokens。可比口径应使用：

```text
cache_read_input_tokens / (input_tokens + cache_read_input_tokens + cache_creation_input_tokens)
```

### 误区 7：系统提示拆分后动态块不需要缓存

错误。这是 Phase 2 的核心教训。**在 CC Switch 等代理上，无缓存块的系统块会重置缓存边界。** 拆分后必须让所有非 billing 系统块连续覆盖 `cache_control`，否则代理可能在 gap 后完全忽略 tools 和 messages 的缓存匹配。

### 误区 8：单元测试通过 = 缓存配置正确

错误。`CacheControlPlacementTests` 只验证请求结构和 marker 位置，**不验证代理 / provider 是否实际创建或命中缓存**。真正的缓存效果必须通过真实 API 调用验证。`swift-agent eval cache-hit-rate` 填补了这个差距。

### 误区 9：`message_delta.usage` 包含完整的用量信息

错误。根据 Anthropic API 规范，`message_delta.usage` **仅包含 `output_tokens`**。`input_tokens`、`cache_read_input_tokens` 和 `cache_creation_input_tokens` 只出现在 `message_start.message.usage` 中。SwiftAgent 曾因仅处理 `messageDelta` 事件而导致 debug 日志中始终无用量信息。

### 误区 10：`NSDictionary(objects:forKeys:)` 保持插入顺序

错误。`NSDictionary` 的 `init(objects:forKeys:)` 文档没有保证结果字典的枚举顺序。内部哈希表布局依赖于元素的哈希值——当两个键发生哈希碰撞时，即使按插入顺序传入，结果字典的 `allKeys` 也可能产生反转。例如：

```
NSDictionary(objects: ["billing","text"], forKeys: ["text","type"])
  → allKeys: [type, text]  ✗ 反转了！
```

这意味着使用 `NSDictionary` 进行 JSON 键排序是不可靠的。**唯一的确定性方案是 `JSONEncoder` + `.sortedKeys` + `Encodable` 包装器**，它在编码过程中递归对 `KeyedContainer` 的键进行稳定排序。

---

## 维护规则

1. 不要重新引入 `scope:"global"`，除非新的 Claude Code capture 证明其回归。
2. 不要在 chat request 的 tools 上添加 `cache_control`，除非新的 Claude Code capture 证明其回归。
3. 不要把 beta 放回 body 的 `anthropic_beta`。
4. 不要在 adaptive thinking chat request 中发送 `temperature`。
5. 不要发送 `tool_choice`，除非 Claude Code capture 出现该字段。
6. 不要把 message-level `cache_control` 放在 `tool_result` block。
7. tool-result user message 必须有 trailing text/system-reminder breakpoint，除非新的 Claude Code capture 证明策略变化。
8. **修改 `LLMClient` request shape 后，必须更新 `CacheControlPlacementTests`。**
9. 对比命中率时必须同时看 raw fields 和 comparable denominator。
10. debug logs 中任何 auth header 必须 case-insensitive 脱敏。
11. **系统提示的动态块也必须加 `cache_control`。** 不要试图通过让动态块无缓存来节省缓存创建成本——这样做会导致代理重置缓存边界，使后续所有 tools 和 messages 无法命中缓存。
12. **用量从 `messageStart` 中提取，而不是 `messageDelta`。** 新增 stream 事件处理分支时，参考 Anthropic API 规范确认每个事件承载的字段范围。
13. **每次修改缓存逻辑后，使用 `eval cache-hit-rate` 做真实 API 验证。** 单元测试不够。
14. **不要使用 `NSDictionary` 对 JSON 键排序。** 使用 `JSONEncoder` + `.sortedKeys` + `SortedJSON`（Encodable 包装器）。`NSDictionary` 不保证插入顺序，某些键组合会产生哈希碰撞导致排序反转。
15. **`sortedKeys` 必须在所有 JSON 序列化路径上统一使用。** `LLMClient.stableJSONData(from:)` 和 `DebugLogger.append(_:)` 都必须使用相同的 `JSONEncoder.sortedKeys` 方案。Debug Logger 使用 `JSONSerialization` + `NSDictionary` 会掩盖请求的真正字节表示，使调试不可靠。

---

## 当前实测结果

### 最新 eval 结果（2026-06-05，deepseek-v4-flash，JSON 键排序修复后）

多轮对话实测（3 turns，系统提示已预热）：

```
Turn  Input  Cache Read  Cache Cre.  Hit Rate
  1   1,646      31,744           0     95.1%  95% hit (system prompt cached from prior session)
  2     314      34,560           0     99.1%  near-perfect  
  3     168      34,816           0     99.5%  almost all cached
```

**解读**：

- **95-100% 命中率**，匹配甚至超过 Claude Code 的 90%+ 命中率。
- Turn 1 即有 95% 命中率：系统提示在 proxy 上的 KV-cache 跨会话持续有效。
- `cache_read` 随会话增长（31,744 → 34,560 → 34,816），表明历史消息前缀也在被缓存。
- `cache_creation` 始终为 0：proxy 不创建新的缓存条目（KV-cache 由 DeepSeek 服务端内部管理）。
- `eo-cache-status` 始终为 `MISS`，不影响实际 KV-cache 命中率。

### 历史结果（2026-06-04，Phase 3 双块缓存链修复后）

```
Turn  Input  Cache Read  Cache Cre.  Hit Rate
  1     782           0           0     0.0%
  2      30         768           0    96.2%
  3     171         768           0    81.8%
```

**问题**：`cache_read` 始终为 768（仅系统提示），不随会话增长，且 turn 3 降至 81.8%。原因是 `NSDictionary` 排序不可靠导致请求字节不稳定，仅系统提示的短前缀能缓存。

### 已知差距（已解决）

- ~~**JSON 键排序**：`NSDictionary` 排序不可靠，导致请求字节不稳定。~~ ✅ 已修复。`JSONEncoder.sortedKeys` 代替 `NSDictionary`。
- ~~**消息级缓存**：`cache_read` 不随消息历史增长。~~ ✅ 已确认消息前缀也可缓存。修复后 `cache_read` 随会话从 31K → 34K → 35K。
- **Cache creation**：`cache_creation_input_tokens` 始终为 0。这是 proxy 行为，不归因于 SwiftAgent。

---

## 下一步排查路线

当前 SwiftAgent 缓存命中率已与 Claude Code 持平（95-100%）。后续排查方向：

1. ~~**用 `eval cache-hit-rate` 先排除自身问题。**~~ ✅ 已验证。缓存链正常。
2. ~~**比较 consecutive requests 的 serialized prefix 是否稳定。**~~ ✅ 已验证。`JSONEncoder.sortedKeys` 确保字节稳定。
3. **对比 `thinking: .adaptive` vs `.disabled`。** 某些代理可能需要在请求中包含 `thinking` 参数才创建缓存条目。目前 `thinking: .adaptive` 已启用。
4. **增加系统提示大小至 2000+ tokens。** 某些代理仅对超过大小阈值的请求创建缓存。当前系统提示约 800 tokens。
5. **用同一 session 连续跑更长上下文，** 验证长会话中 `cache_read` 是否持续增长。
6. **检查 tool schema 字节稳定性，** 尤其 MCP descriptions。
7. **检查 message normalization** 是否导致历史消息重排或 content block 变化。
8. **再与最新 Claude Code prompt-gateway capture 对比，** 确保 request shape 一致。
9. **如果以上全部对齐后 `cache_creation` 仍为 0，** 需联系 proxy/provider 确认其对 prompt caching 的支持程度。
