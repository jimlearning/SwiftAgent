# SwiftUI 布局缓存 Bug: VStack → LazyVStack

## 症状

在使用 `VStack` 配合 `ForEach` 时，折叠或展开子视图（如 thinking block 或 tool result block）会导致**兄弟视图的高度发生错乱**。同样的高度增量在兄弟视图之间"转移"，就好像 VStack 的布局缓存是按位置索引而不是按标识来映射子视图的。

### 实测证据

```
修复前 (VStack):

  ▸ Thinking block 展开:  ThinkHeight 79→185 (+106)
  ▸ Tool block 出现:      ToolHeight 0→164,  ThinkHeight →185 (同样 +106 偏移量)
  ▸ Thinking block 折叠:  ThinkHeight 185→29 (-156)
                           ToolHeight 164→270 (+106)  ← 同样的 106px 转移了
                           BubbleHeight 1338→1288 (-50 = -156 + 106)

修复后 (LazyVStack):

  ▸ Thinking block 折叠:  ThinkHeight 185→29 (-156)
                           ToolHeight 164→164 (未变化!) ← 无转移
                           BubbleHeight →1338-156=1182 (符合预期)
```

## 根因

SwiftUI 中的 `VStack` 使用**基于位置索引的布局缓存**。当子视图高度发生变化时，缓存索引会偏移——位置 0 处的新（更高/更矮的）子视图会替换位置 1 处缓存的 frame，导致旧的缓存高度被应用到错误的兄弟视图上。

`LazyVStack` 使用**基于标识的布局**。每个子视图按其 `id` 追踪，因此一个子视图的高度变化不会破坏另一个子视图的缓存尺寸。

`LazyVStack` 的标识机制依赖于 `ForEach` 通过 `Identifiable` 协议或 `id:` 参数提供稳定的子视图标识。在我们的场景中，`RenderItem` 遵循 `Identifiable` 协议，每个 block 都有稳定的 `id` 字符串（thinking block UUID、tool-use ID 或文本 block 内容哈希），SUMMARY 项使用字面量 `"summary"`。

两个条件缺一不可：

1. **LazyVStack**（基于标识的缓存，而非基于位置）
2. **稳定的 ForEach `.id()`** 作用于 `RenderItem`（使 LazyVStack 能按子视图追踪 frame）

缺少任一条件，bug 都会复现。

## 调试过程

### 假设 1: `withAnimation` 传播

**理论:** 子视图按钮处理器中的 `withAnimation(.easeInOut(duration: 0.2))` 创建了动画事务，向上传播到父级 `VStack`，导致其以错误的中间值对兄弟位置进行动画。

**测试:** 从 `ThinkingBlockView`、`ToolResultView` 和 `transientToolSummary` 中移除所有 `withAnimation` 调用。

**结果:** 无变化。高度转移相同。

### 假设 2: `.animation(value:)` 传播

**理论:** 子视图上的 `.animation(.easeInOut(duration: 0.2), value: isExpanded)` 也会创建传播性事务。

**测试:** 从两个 block 视图中移除 `.animation(value:)` 修饰符（在之前的尝试中添加的）。

**结果:** 无变化。

### 假设 3: 宽度变化 → 文本重排

**理论:** 显示 tool result 会改变 VStack 的宽度（通过 `ScrollView` / `maxHeight: 200` / `.frame(maxWidth: .infinity)`），导致 thinking block 中的文本在不同宽度下重排从而改变高度。

**测试:** 向 `BubbleFrame`、`ThinkFrame`、`ToolFrame` 添加 `GeometryReader` frame 日志。

**结果:** Bubble 宽度在**所有状态变化中恒定为 778.0pt**。所有 block 宽度恒定为 **738.0pt**。宽度重排假说被否定。

### 假设 4: VStack 基于位置索引的布局缓存（正确）

**理论:** `VStack` 内部按位置索引缓存子视图高度。当子视图 0（thinking block）高度变化时，子视图 1（tool/summary）的缓存值可能已过期或来自不同的索引。高度增量在兄弟视图之间"转移"是因为缓存按位置而非按标识映射。

**测试:** 将 `VStack` 替换为 `LazyVStack`（基于标识的缓存）。保持 `withAnimation` 调用已移除。

**结果:** 高度转移为零。在 thinking block 折叠前后，Tool 高度保持在 164。✓

### 验证: LazyVStack 下动画是安全的

**测试:** 重新向 ThinkingBlockView、ToolResultView 和 transientToolSummary 的 header 中添加 `withAnimation(.easeInOut(duration: 0.2))`。

**结果:** 动画流畅，高度转移仍然为零。✓

## 修复方案

### 修改的文件

| 文件 | 变更 |
|------|------|
| `Packages/Sources/ClarcChatKit/MessageBubble.swift` | `VStack` → `LazyVStack`（第 34 行） |
| `Packages/Sources/ClarcChatKit/MessageBubble.swift` | 从 `assistantTextBubble` 的 `onTapGesture` 中移除 `withAnimation`（冗余的二次 toggle） |
| `Packages/Sources/ClarcChatKit/MessageBubble.swift` | 从用户消息的 `isLongTextExpanded` 中移除 `withAnimation` |
| `Packages/Sources/ClarcChatKit/ThinkingBlockView.swift` | `withAnimation` 保留在 header 按钮中 |
| `Packages/Sources/ClarcChatKit/ToolResultView.swift` | `withAnimation` 保留在 header 按钮中 |

唯一的结构性变更是 MessageBubble 的 block 容器上的 **`VStack` → `LazyVStack`**。其余的都是诊断噪音或次要清理。

### 稳定的标识链

修复依赖于稳定的 ForEach ID。标识链工作方式如下：

```
AgentMessageBlock.id (UUID / toolUseID / TextBlockIDCache)
    → convertMessages() → MessageBlock.id (ClarcCore)
    → RenderItem.id (MessageBubble.RenderItem.Identifiable)
    → ForEach(renderItems) (LazyVStack 布局缓存的标识)
```

这条链中的每个环节都必须在多次重新渲染中产生一致的 ID。关键点：

- **Thinking block ID**: `AgentMessageBlock.thinking(id:)` 通过 `convertMessages()` 将原始 UUID 传递给 `MessageBlock.id`。`fromCore()` / `fromTurns()` 转换器保留此 UUID。
- **Tool call ID**: Tool-use ID（`tb.toolUseID`）在每个工具调用中是稳定的，由 LLM 设置。
- **Text block ID**: `TextBlockIDCache` 生成基于内容哈希的 UUID，因此相同的文本在多次转换中会得到相同的 ID。
- **SUMMARY**: 字面量字符串 `"summary"` 用作临时 tool summary 的 `RenderItem.id`，它始终是单个（可折叠的）项。

## 边界情况

1. **嵌套在 ScrollView 内的 LazyVStack**: LazyVStack 设计为作为 ScrollView 的直接子视图时进行懒加载。当嵌套更深时（如我们的情况：`ScrollView > VStack > MessageBubble > LazyVStack`），懒加载行为不会生效——它仅充当基于标识的布局容器。无性能退化。

2. **LazyVStack proposed height**: 与 VStack 不同，当父级有 `.frame(maxHeight: .infinity)` 时，LazyVStack 可能会扩展到填满整个 proposed height。MessageBubble 的 HStack 不会提出无限高度，因此这不是问题。

3. **基于标识布局内的动画**: LazyVStack 内子视图中的 `withAnimation` 是安全的，因为兄弟 frame 重新计算使用每个标识的缓存大小，而非位置索引查找。

## 预防措施

在布局容器（VStack, List, Grid）内添加新的可折叠/可展开子视图时：

1. **优先使用 LazyVStack 而非 VStack**，当子视图具有由 `@State` 驱动的动态高度时。
2. **始终为 ForEach 项提供稳定的 `.id()`**。使用基于内容或来源的标识符，而非在重新求值时变化的随机 UUID。
3. **避免在 VStack 内使用 `withAnimation`**，如果子视图的高度变化可能影响兄弟布局。使用 LazyVStack 或仅对视觉（非布局）属性进行动画。
4. **使用 GeometryReader 进行测试**，当调查兄弟 frame 混淆时——同时记录宽度和高度。如果宽度稳定但高度转移，则怀疑是基于位置的缓存。

## 诊断日志

以下 `[DBG]` 日志点在诊断过程中添加，可保留供将来调试使用：

| 前缀 | 位置 | 值 |
|--------|----------|--------|
| `BubbleFrame` | MessageBubble HStack | `w= h= y=` |
| `ThinkFrame` | ThinkingBlockView VStack | `w= h= y= expanded=` |
| `ToolFrame` | ToolResultView VStack | `w= h= y= expanded=` |
| `buildRenderItems` | MessageBubble | `items=[...] hidden=[...]` |
| `MessageBubble body` | MessageBubble | `role= id= streaming= blocks=` |
