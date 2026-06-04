# Prompt Cache Hit Rate — 从入门到精通

> SwiftAgent 的 prompt cache 完全指南：从 API 基础概念到生产级工程实践。

## 目录

1. [快速上手：我在看什么](#1-快速上手我在看什么)
2. [什么是 Prompt Cache](#2-什么是-prompt-cache)
3. [Cache 如何工作](#3-cache-如何工作)
4. [cache_control Marker 详解](#4-cache_control-marker-详解)
5. [Usage 字段完全解读](#5-usage-字段完全解读)
6. [命中率：如何计算和比较](#6-命中率如何计算和比较)
7. [Agent 为什么特别依赖缓存](#7-agent-为什么特别依赖缓存)
8. [缓存失效的 N 种方式](#8-缓存失效的-n-种方式)
9. [代理/网关的特殊行为](#9-代理网关的特殊行为)
10. [SwiftAgent 实战：缓存策略演进全记录](#10-swiftagent-实战缓存策略演进全记录)
11. [当前对齐方案（速查表）](#11-当前对齐方案速查表)
12. [验证与调试工具](#12-验证与调试工具)
13. [十大常见误区](#13-十大常见误区)
14. [维护规则清单](#14-维护规则清单)
15. [实测性能基准](#15-实测性能基准)
16. [排查指南](#16-排查指南)
17. [术语速查](#17-术语速查)

---

## 1. 快速上手：我在看什么

**如果你是第一次接触 prompt cache**：从第 2 节读到第 7 节，约 20 分钟建立完整认知。

**如果你想调试缓存命中率**：直接跳到第 12 节（验证工具）和第 16 节（排查指南）。

**如果你要修改 LLM 请求结构**：必读第 8-11 节和第 14 节（维护规则）。

**如果你想理解 SwiftAgent 为什么这样做**：第 10 节记录了完整的试错过程。

---

## 2. 什么是 Prompt Cache

### 一句话定义

Prompt cache 是 LLM API 服务端对**请求输入前缀**的缓存机制。当两次请求的前缀完全相同时，服务端跳过重复的 attention 计算，直接复用之前的 KV-cache 结果。

### 缓存的是什么

缓存的是**输入前缀的中间计算结果（KV-cache）**，不是模型输出，也不是整个会话对象。

对 coding agent 而言，典型前缀包括：

```
[system prompt blocks] → [tool definitions] → [conversation history 前缀]
```

每次请求，服务端从头逐 token 匹配前缀。匹配越深，缓存收益越大。

### 不缓存什么

- 模型输出（output tokens）
- 不构成前缀的中间部分
- 与前次请求字节不一致的任何内容

---

## 3. Cache 如何工作

### 三步过程

```
第一轮请求（冷启动）:
  发送:  [system (1000 tokens)] [tools (2000 tokens)] [user msg (50 tokens)]
  结果:  cache_creation_input_tokens = 3000  ← 前缀写入缓存
         cache_read_input_tokens = 0

第二轮请求（缓存命中）:
  发送:  [system (1000)] [tools (2000)] [history (200)] [new user msg (50)]
  匹配:  ✓ 前缀 3200 tokens 完全匹配
  结果:  cache_read_input_tokens = 3200    ← 前缀从缓存读取
         input_tokens = 50                ← 仅新消息需要计算
```

### 关键约束

- **字节级匹配**：任何差异（空格、换行、JSON 键顺序）都会中断匹配
- **前缀匹配**：只能从请求开头匹配，不能跳过中间部分
- **会话级生命周期**：ephemeral cache 有 TTL（通常几分钟到数十分钟）

---

## 4. cache_control Marker 详解

### 什么是 marker

`cache_control` 是一个嵌在 content block 或 tool definition 上的字段，告诉 API："到这为止可以作为缓存断点"。

```json
{
  "type": "text",
  "text": "You are Claude Code...",
  "cache_control": { "type": "ephemeral" }
}
```

### Marker 的位置决定一切

```
正确的缓存链：
[block A + cache] [block B + cache] [block C + cache]
✓ A → B → C 是连续的缓存前缀

错误的缓存链（有 gap）：
[block A + cache] [block B 无缓存] [block C + cache]
✗ B 没有缓存 → 代理可能在 B 处重置 → C 之后的 tools/messages 永远不命中
```

### Marker 的形态

| 形态 | 适用场景 | SwiftAgent 使用 |
|------|----------|:---:|
| `{"type": "ephemeral"}` | 短期缓存（默认） | ✅ 所有 marker |
| `{"type": "ephemeral", "scope": "global"}` | 跨组织共享 | ❌ CC 不使用 |

### Marker 数量不是越多越好

- 每个 marker 定义了一个缓存断点，也改变了请求形状
- 多余 marker 可能让请求与 CC 的策略偏离
- 关键是 marker 的**位置**和**连续性**，而非数量

---

## 5. Usage 字段完全解读

### 字段表

| 字段 | 出现位置 | 含义 |
|------|----------|------|
| `input_tokens` | `message_start.usage` | 本次仍需计算的输入 token |
| `cache_read_input_tokens` | `message_start.usage` | 本次从缓存读取的 token |
| `cache_creation_input_tokens` | `message_start.usage` | 本次新写入缓存的 token |
| `output_tokens` | `message_start.usage` + `message_delta.usage` | 模型输出 token |

### 关键区别

```
message_start.usage  → 包含 input_tokens + cache_read + cache_creation + output_tokens
message_delta.usage  → 仅包含 output_tokens（！）
```

**这是最常见的数据源错误**：从 `message_delta` 读 `input_tokens` / `cache_read` 会得到 0。

### 为什么 cache_creation 可能始终为 0

有些代理/网关（如 CC Switch）不创建自己的缓存条目，而是依赖上游提供商的内部 KV-cache。此时：

- `cache_creation_input_tokens = 0` — 正常
- `cache_read_input_tokens > 0` — 仍然有效
- **不要用 `cache_creation = 0` 判断"缓存不工作"**

---

## 6. 命中率：如何计算和比较

### 错误公式

```
❌ cache_read_input_tokens / input_tokens
```

问题：`input_tokens` **不包含**已从缓存读取的 token。分母太小，结果不可比。

### 正确公式

```
✅ cache_read_input_tokens / (input_tokens + cache_read_input_tokens + cache_creation_input_tokens)
```

这个口径衡量"本次输入总量里有多少来自缓存"，适合跨工具、跨模型比较。

### 什么算"好"

| 场景 | 期望命中率 | 说明 |
|------|:---:|------|
| Turn 1（冷启动） | 0% | 服务端首次见到此前缀 |
| Turn 2+（同会话，短上下文） | 80-95% | 系统提示 + 工具已缓存 |
| Turn 3+（同会话，历史累积） | 95-99% | 历史消息前缀也开始缓存 |
| Turn 1（系统提示已预热） | 85-95% | 代理的 KV-cache 跨会话持久化 |

---

## 7. Agent 为什么特别依赖缓存

Coding agent 每轮请求携带大量**稳定但昂贵的**内容：

- 长 system prompt（800-2000+ tokens）
- 数十个 tool schemas（2000-5000+ tokens）
- 安全规则和工具使用规范
- 项目 memory / CLAUDE.md
- 多轮对话历史

**无缓存时**：每轮处理 ~8000+ tokens 输入 → 延迟高、成本高
**有缓存时**：每轮仅处理 ~100-300 tokens 新增输入 → 延迟低、成本低

对于 100 轮的长会话，无缓存的输入处理量是 ~800K tokens，有缓存是 ~20K tokens——**约 40 倍差异**。

---

## 8. 缓存失效的 N 种方式

### 结构层面

| 变化 | 影响 |
|------|------|
| system blocks 拆分方式变化 | 整个系统前缀失效 |
| text 前后多一个换行/空格 | 该 block 起失效 |
| 动态时间戳注入 | 每次都失效 |
| tools 排序变化 | 工具段起失效 |
| tool schema 描述变化 | 该 tool 起失效 |
| `defer_loading` 字段变化 | 该 tool 起失效 |
| message content block 顺序变化 | 消息段起失效 |

### 请求形状层面

| 变化 | 影响 |
|------|------|
| `cache_control` 数量或位置变化 | 缓存断点位移 |
| body 顶层字段增减（如 `temperature`） | 整个请求形状不同 |
| beta 放 header vs body | 网关路由可能不同 |
| `thinking` 参数缺失 | 某些代理完全不创建缓存 |

### 序列化层面（最隐蔽）

| 变化 | 病因 |
|------|------|
| JSON 键顺序不一致 | `[String: Any]` + `JSONSerialization` 的非确定性 |
| 相同 dict 两次序列化字节不同 | Swift Dictionary 的哈希表布局差异 |
| NSDictionary 排序不可靠 | 已证实的哈希碰撞导致键序反转 |

---

## 9. 代理/网关的特殊行为

### CC Switch / 第三方代理的已知行为

1. **缓存边界重置**：有 `cache_control` 的系统块 → 无 `cache_control` 的系统块之间，代理可能视为缓存边界重置点。此后的 tools/messages 永远不会被缓存匹配。

2. **thinking 参数门控**：某些代理在缺少 `thinking` 参数时不创建任何缓存条目。

3. **最小缓存阈值**：某些代理仅在首请求 > 1000 tokens 时才激活缓存创建逻辑。

4. **eo-cache-status 不可信**：此 HTTP 头可能始终为 `MISS`，即使实际 `cache_read` 达到 99%+。

5. **跨会话 KV-cache 持久化**：DeepSeek 等提供商的 KV-cache 可能跨会话持续存在，使 Turn 1 也获得高命中率。

---

## 10. SwiftAgent 实战：缓存策略演进全记录

### Phase 1：原始状态（单块 system prompt）

**状态**：整个 system prompt 合并为单个 text block + `cache_control`
**结果**：命中率 13.2%
**根因**：缺少 CC 的 identity block 和 billing header block，与 CC 的 ISO 形态不同

### Phase 2：动态块不加 cache_control（❌ 错误方案）

**修改**：在 `SYSTEM_PROMPT_DYNAMIC_BOUNDARY` 拆分，静态块加 cache，动态块不加
**结果**：命中率降至 6-16%，`cache_read` = 7K flat，`cache_creation` = 0
**根因**：代理将"有缓存块 → 无缓存块"之间的边界视为缓存重置点。动态块后的 tools/messages 完全不被匹配。

**教训**：系统提示中的缓存 gap 是致命的。所有非 billing 系统块必须连续覆盖 `cache_control`。

### Phase 3：双块均加 cache_control（✅ 正确方案）

**修改**：static + dynamic 合并为一个 cached block（匹配 CC non-global "rest" block）
**结果**：

```
Turn  Input  Cache Read  Cache Cre.  Hit Rate
  1     782           0           0     0.0%
  2      30         768           0    96.2%  ← 系统提示缓存正常工作
  3     171         768           0    81.8%
```

**关键发现**：
- Turn 2 达到 96.2%，系统提示的连续缓存链验证通过
- `cache_read = 768` 固定不变 — 仅系统提示缓存，消息历史未缓存
- `cache_creation = 0`：代理不创建缓存条目，但可以读取上游 KV-cache

### Phase 4：messageStart 修复

**问题**：生产环境 debug 日志中 usage 字段始终为 0
**发现**：`ChatCommand` 仅从 `messageDelta` 事件提取用量，但 `messageDelta.usage` 仅含 `output_tokens`。`input_tokens` / `cache_read` / `cache_creation` 只在 `message_start.message.usage` 中出现。
**修复**：添加 `messageStart` 处理分支（`ChatCommand.swift:597-604`）

### Phase 5：JSON 键排序修复（决定性突破）

**背景**：Phase 3 后缓存体验仍不稳定 — Turn 2 命中到 Turn 3 缓存完全丢失
**排查**：
1. 对比相邻请求的 shasum → 字节不同
2. 逐层 diff → 差异在 `[String: Any]` 字典 JSON 序列化
3. 固定测试复现 → `NSDictionary(objects:forKeys:)` 对某些键组合产生哈希碰撞导致排序反转

**根因**：DeepSeek KV-cache 要求 token prefix 字节完全一致。`NSDictionary` 排序不可靠 → 每次序列化字节可能不同 → 缓存永远无法匹配。

**修复**：`JSONEncoder` + `.sortedKeys` + `SortedJSON` Encodable wrapper 替代所有 `NSDictionary` 排序。

**最终结果**：

```
Turn  Input  Cache Read  Cache Cre.  Hit Rate
  1   1,646      31,744           0     95.1%  ← 跨会话系统提示缓存
  2     314      34,560           0     99.1%  ← 历史消息开始缓存
  3     168      34,816           0     99.5%  ← 几乎全部命中
```

---

## 11. 当前对齐方案（速查表）

### System Prompt（3 个 blocks）

| 索引 | 内容 | cache_control |
|:---:|------|:---:|
| 0 | `x-anthropic-billing-header` | — |
| 1 | `You are Claude Code...` (identity) | ✅ ephemeral |
| 2 | static + dynamic 合并 (rest) | ✅ ephemeral |

### Cache Marker 分布

| 位置 | 数量 | 形态 |
|------|:---:|------|
| system | 2 | `{"type": "ephemeral"}` |
| tools | 0 | — |
| latest message | 1 | `{"type": "ephemeral"}`，仅在 text block |
| **总计** | **3** | 无 `scope:"global"` |

### 顶层 Body 字段

- ✅ 有：`context_management`, `max_tokens`, `messages`, `metadata`, `model`, `output_config`, `stream`, `system`, `thinking`, `tools`
- ❌ 无：`temperature`, `tool_choice`, `anthropic_beta`

### Headers

- `anthropic-beta`：header 字段（非 body）
- `authorization`：按 Anthropic 标准
- `x-api-key`：兼容非 Anthropic endpoints
- `x-stainless-*`：CC 对齐的元信息头

### Message cache marker 规则

- 每次请求**仅**最后一条 message 的最后一个 `text` content block 承载 `cache_control`
- `thinking`、`redacted_thinking`、`tool_result` blocks **不**承载 message-level marker
- tool-result 回合追加 trailing `<system-reminder>` text block，使 breakpoint 落在 text 上
- 仅含 tool_result 的 message 不加任何 marker

---

## 12. 验证与调试工具

### eval cache-hit-rate 命令

```bash
# 快速验证（3 轮，默认 deepseek-v4-flash）
swift run --disable-sandbox swift-agent eval cache-hit-rate --turns 3

# 完整验证（5 轮，显示 debug 日志）
swift run --disable-sandbox swift-agent eval cache-hit-rate --turns 5 --verbose

# 指定模型和 base URL
swift run --disable-sandbox swift-agent eval cache-hit-rate \
  --model claude-sonnet-4-6 --base-url https://api.anthropic.com
```

**工作原理**：
1. 构建带 boundary 的系统提示（~800 tokens）
2. 注册 5 个工具（Read / Edit / Bash / Glob / Grep）模拟生产请求大小
3. 执行 N 轮递增对话
4. 从 `message_start.usage` 提取用量
5. 自动合成 `tool_result` 保持消息序列有效
6. 输出每轮和累计命中率表格

### Debug 日志

```bash
# 日志位置
~/.swift-agent/logs/debug-YYYYMMDD-HHmmss.jsonl

# 检查请求顶层字段形状
jq -c 'select(.type=="request") | {
  bodyKeys:(.body|keys),
  thinking:.body.thinking,
  output_config:.body.output_config
}' ~/.swift-agent/logs/debug-*.jsonl

# 检查缓存用量
jq -r '
  select(.type=="stream_event" and .raw.type=="message_start") |
  [.seq, .raw.message.usage.input_tokens,
   .raw.message.usage.cache_read_input_tokens,
   .raw.message.usage.cache_creation_input_tokens] | @tsv
' ~/.swift-agent/logs/debug-*.jsonl

# 统计 cache_control marker 分布
jq -r '
  select(.type=="request") | [.seq,
    ([.body.system[]? | select(has("cache_control"))] | length),
    ([.body.tools[]? | select(has("cache_control"))] | length),
    ([.body.messages[]? | .. | objects | select(has("cache_control"))] | length)
  ] | @tsv
' ~/.swift-agent/logs/debug-*.jsonl
```

### 回归测试

```bash
# 缓存专项测试
swift test --disable-sandbox --no-parallel --filter CacheControlPlacementTests

# 全量测试
swift test --disable-sandbox --no-parallel
```

### 字节稳定性验证

```bash
# 提取两次相邻请求的 body 并比较 shasum
jq -c 'select(.type=="request") | .body' debug.jsonl | head -5 | shasum
```

---

## 13. 十大常见误区

### ❌ 误区 1：同模型就应该同命中率

缓存 key 依赖 request prefix 的实际结构和字节级稳定性。模型相同只是必要条件之一，请求结构差异才是主因。

### ❌ 误区 2：`scope:"global"` 一定更好

CC 当前使用 plain `{"type": "ephemeral"}`。添加 `scope:"global"` 会改变请求形状，反而可能与 CC 策略不一致。

### ❌ 误区 3：marker 数量相同就够了

位置比数量重要。system prompt 中有缓存 gap（有缓存 → 无缓存）会直接导致代理重置缓存边界。

### ❌ 误区 4：工具 schema 加 cache marker 能提升命中

CC 当前 chat request 没有 tool-level marker。添加多余 marker 改变请求形状可能降低兼容性。

### ❌ 误区 5：message marker 放 tool_result 上也等价

CC 的 latest-message breakpoint 始终落在最后一个 `text` block 上。`tool_result` 不承载 message-level cache marker。

### ❌ 误区 6：`cache_read / input_tokens` 是可比命中率

`input_tokens` 不包含已缓存读取的 token。分母过小导致结果不可比。

### ❌ 误区 7：系统提示拆分后动态块不需要缓存

Phase 2 的核心教训。无缓存块的系统块会重置代理的缓存边界。

### ❌ 误区 8：单元测试通过 = 缓存配置正确

`CacheControlPlacementTests` 只验证请求结构，不验证代理是否实际创建/命中缓存。真实效果必须通过 API 调用验证。

### ❌ 误区 9：`message_delta.usage` 包含完整用量

按 API 规范，`message_delta.usage` 仅含 `output_tokens`。`input_tokens` / `cache_read` / `cache_creation` 只在 `message_start.message.usage` 中。

### ❌ 误区 10：`NSDictionary(objects:forKeys:)` 保持插入顺序

已证实不可靠。底层哈希表碰撞会导致键序反转。`JSONEncoder.sortedKeys` + Encodable wrapper 是唯一确定性方案。

---

## 14. 维护规则清单

修改 LLM 请求结构时，必须遵守以下规则：

1. ❌ 不要重新引入 `scope:"global"`（除非新 CC capture 证明其回归）
2. ❌ 不要在 chat request 的 tools 上加 `cache_control`（同上）
3. ❌ 不要把 beta 放回 body 的 `anthropic_beta`
4. ❌ 不要在 adaptive thinking 请求中发送 `temperature`
5. ❌ 不要发送 `tool_choice`（除非 CC capture 出现该字段）
6. ❌ 不要把 message-level `cache_control` 放在 `tool_result` block
7. ✅ tool-result user message 必须有 trailing text/system-reminder breakpoint
8. ✅ 系统提示的动态块也必须加 `cache_control`（无 gap 原则）
9. ✅ 用量数据从 `messageStart` 提取，不要仅依赖 `messageDelta`
10. ✅ 修改 `LLMClient` request shape 后必须更新 `CacheControlPlacementTests`
11. ✅ 使用 `JSONEncoder.sortedKeys` + `SortedJSON` 进行所有 JSON 序列化
12. ✅ 每次修改缓存逻辑后用 `eval cache-hit-rate` 做真实 API 验证
13. ✅ 对比命中率时同时看 raw fields 和 comparable denominator
14. ✅ debug logs 中所有 auth header 必须 case-insensitive 脱敏
15. ✅ `sortedKeys` 在所有 JSON 序列化路径上统一使用（LLMClient + DebugLogger）

---

## 15. 实测性能基准

### 当前最佳结果（2026-06-05，deepseek-v4-flash）

```
Turn  Input  Cache Read  Cache Cre.  Hit Rate
  1   1,646      31,744           0     95.1%
  2     314      34,560           0     99.1%
  3     168      34,816           0     99.5%
```

- **95-100% 命中率**，匹配并超过 CC 的 90%+
- `cache_read` 随会话增长（31,744 → 34,560 → 34,816），历史消息前缀持续缓存
- `cache_creation = 0`：代理不创建新缓存条目（DeepSeek KV-cache 内部管理）

### 与 Claude Code 的对比

| 指标 | CC flash | SwiftAgent | 评判 |
|------|----------|------------|------|
| Turn 1 命中率 | 85-90% | 95.1% | ✅ 持平或更优 |
| Turn 2+ 命中率 | 90%+ | 99-100% | ✅ 持平或更优 |
| cache_creation | 有 | 0 | ⚠️ 代理差异 |
| cache_read 增长趋势 | 随历史增长 | 随历史增长 | ✅ 一致 |
| eo-cache-status | MISS | MISS | ✅ 一致（均不可信） |

### 历史结果（Phase 3，JSON 键排序修复前）

```
Turn  Input  Cache Read  Cache Cre.  Hit Rate
  1     782           0           0     0.0%
  2      30         768           0    96.2%
  3     171         768           0    81.8%
```

`cache_read` 始终为 768（仅系统提示），不随会话增长。原因是 `NSDictionary` 排序不可靠 → 请求字节不稳定 → 仅短前缀能缓存。

---

## 16. 排查指南

### 标准化诊断流程

```
命中率 < 50%？
  ↓
  1. 先跑 eval cache-hit-rate（排除代码修改引入的问题）
  ↓
  2. 比较 consecutive requests 的 shasum（排除字节不稳定）
  ↓
  3. 检查 cache_control marker 分布是否与基线一致
  ↓
  4. 检查是否有 body 顶层字段偏离（temperature/tool_choice/anthropic_beta）
  ↓
  5. 检查 thinking 参数是否存在，type 是否为 adaptive
  ↓
  6. 增加系统提示大小至 2000+ tokens（排除代理的最小阈值问题）
  ↓
  7. 用同一 session 连续跑更长上下文（验证 cache_read 增长）
  ↓
  8. 对比最新 CC prompt-gateway capture（确保 request shape 一致）
  ↓
  9. 如以上全部对齐但 cache_creation 仍为 0，联系 proxy/provider
```

### 常见症状速查

| 症状 | 最可能原因 | 参考 |
|------|-----------|------|
| Turn 1 命中 0%，后续始终 0% | 请求字节不稳定 | Phase 5（JSON 键排序） |
| Turn 1 命中 0%，Turn 2 命中 96%+ 但后续不增长 | 仅系统提示缓存，消息级缓存不工作 | 代理行为 |
| Turn 2 命中后 Turn 3 完全丢失 | 请求关键字段变化 | 检查顶层 body shape |
| cache_read 有值但突然归零 | 会话间隔过长（KV-cache TTL 过期） | 重连即可 |
| debug 日志 usage 全部为 0 | 仅从 messageDelta 取用量 | Phase 4 |

---

## 17. 术语速查

| 术语 | 定义 |
|------|------|
| **KV-cache** | Key-Value cache，Transformer 推理中的中间计算结果缓存 |
| **cache_control** | API 请求中标记缓存断点的字段 |
| **ephemeral** | 短期缓存模式（有 TTL，会话级生命周期） |
| **cache_read_input_tokens** | 从缓存读到的 token 数 |
| **cache_creation_input_tokens** | 新写入缓存的 token 数 |
| **input_tokens** | 仍需计算的输入 token（不含已缓存部分） |
| **output_tokens** | 模型输出 token |
| **prefix** | 请求的前缀部分，按 token 顺序从头匹配 |
| **缓存断点** | cache_control marker 所在位置，定义了前缀边界 |
| **缓存 gap** | 连续两个系统块之间一个有 cache_control 一个没有，导致边界重置 |
| **CC non-global mode** | Claude Code 使用的 org-scope 缓存模式（所有系统内容在一个 cached rest block） |
| **SortedJSON** | SwiftAgent 的确定性 JSON 编码 wrapper |
| **CC Switch** | 第三方 Claude Code 代理/网关 |
| **eval cache-hit-rate** | SwiftAgent 的缓存命中率验证命令 |

---

## 附录 A：SortedJSON 实现

```swift
// Sources/SwiftAgentCore/LLM/LLMClient.swift:722
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

    struct _CodingKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
```

## 附录 B：Claude Code Capture 参考结构

```json
{
  "bodyKeys": [
    "context_management", "max_tokens", "messages", "metadata",
    "model", "output_config", "stream", "system", "thinking", "tools"
  ],
  "max_tokens": 32000,
  "thinking": { "type": "adaptive" },
  "context_management": {
    "edits": [{ "type": "clear_thinking_20251015", "keep": "all" }]
  },
  "output_config": { "effort": "high" },
  "system": [
    { "type": "text", "text": "x-anthropic-billing-header: cc_version=2.1.143..." },
    { "type": "text", "text": "You are Claude Code...", "cache_control": { "type": "ephemeral" } },
    { "type": "text", "text": "\nYou are an interactive agent...", "cache_control": { "type": "ephemeral" } }
  ]
}
```

## 附录 C：Betas 列表

```swift
// Sources/SwiftAgentCore/LLM/LLMClient.swift
static let claudeCodeRequestHeaders = [
    "claude-code-20250219",
    "interleaved-thinking-2025-05-14",
    "redact-thinking-2026-02-12",
    "context-management-2025-06-27",
    "prompt-caching-scope-2026-01-05",
    "advisor-tool-2026-03-01",
    "advanced-tool-use-2025-11-20",
    "effort-2025-11-24",
]
```

## 附录 D：相关文件索引

| 文件 | 作用 |
|------|------|
| `Sources/SwiftAgentCore/LLM/LLMClient.swift` | 请求构建、system prompt 格式化、JSON 序列化、cache marker 放置 |
| `Sources/SwiftAgentCore/Agent/ToolExecutor.swift` | 工具注册、tool definition 生成、defer_loading 标记 |
| `Sources/SwiftAgentCLI/ChatCommand.swift` | 主 agent 循环、用量提取 |
| `Sources/SwiftAgentCLI/EvalCommand.swift` | `eval cache-hit-rate` 命令实现 |
| `Sources/SwiftAgentCLI/DebugLogger.swift` | JSONL debug 日志、SortedJSON |
| `Tests/SwiftAgentCoreTests/Phase2LLMTests.swift` | `CacheControlPlacementTests` — 缓存结构回归测试 |
| `docs/PROMPT_CACHE_GUIDE.md` | 本文档 |
| `docs/PROMPT_CACHE_HIT_RATE.md` | 旧版工程档案（已被本文档取代） |
