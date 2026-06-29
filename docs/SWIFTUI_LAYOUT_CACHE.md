# SwiftUI Layout Cache Bug: VStack → LazyVStack

## Symptom

Inside a `VStack` with `ForEach`, folding or expanding a child view (e.g., a thinking block or tool result block) causes **sibling views' heights to be confused**. The same height delta "transfers" between siblings, as if the VStack's layout cache maps children by positional index instead of identity.

### Measured evidence

```
Before fix (VStack):

  ▸ Thinking block expands:  ThinkHeight 79→185 (+106)
  ▸ Tool block appears:      ToolHeight 0→164,  ThinkHeight →185 (same +106 creep)
  ▸ Thinking block collapses: ThinkHeight 185→29 (-156)
                             ToolHeight 164→270 (+106)  ← same 106px transferred
                             BubbleHeight 1338→1288 (-50 = -156 + 106)

After fix (LazyVStack):

  ▸ Thinking block collapses: ThinkHeight 185→29 (-156)
                             ToolHeight 164→164 (unchanged!) ← no transfer
                             BubbleHeight →1338-156=1182 (expected)
```

## Root Cause

`VStack` in SwiftUI uses a **position-indexed layout cache**. When a child view changes height, the cache indices shift — a new (taller/shorter) child at position 0 displaces the cached frame of position 1, causing the old cached height to be applied to the wrong sibling.

`LazyVStack` uses **identity-based layout**. Each child is tracked by its `id`, so a height change in one child does not corrupt another child's cached size.

The `LazyVStack` identity mechanism relies on `ForEach` providing stable child identities via the `Identifiable` protocol or the `id:` parameter. In our case, `RenderItem` conforms to `Identifiable` with a stable `id` string per block (thinking block UUID, tool-use ID, or text block content hash), and the SUMMARY item uses the literal `"summary"`.

Both conditions are required:

1. **LazyVStack** (identity-based cache, not position-based)
2. **Stable ForEach `.id()`** on `RenderItem` (so LazyVStack can track per-child frames)

Without either, the bug reproduces.

## Debugging Process

### Hypothesis 1: `withAnimation` propagation

**Theory:** `withAnimation(.easeInOut(duration: 0.2))` in child button handlers creates an animation transaction that propagates up to the parent `VStack`, causing it to animate sibling positions with incorrect intermediate values.

**Test:** Removed all `withAnimation` calls from `ThinkingBlockView`, `ToolResultView`, and `transientToolSummary`.

**Result:** No change. Height transfer identical.

### Hypothesis 2: `.animation(value:)` propagation

**Theory:** `.animation(.easeInOut(duration: 0.2), value: isExpanded)` on child views also creates propagating transactions.

**Test:** Removed `.animation(value:)` modifiers from both block views (added in previous attempt).

**Result:** No change.

### Hypothesis 3: Width change → text reflow

**Theory:** Showing the tool result changes the VStack's width (via `ScrollView` / `maxHeight: 200` / `.frame(maxWidth: .infinity)`), causing text in the thinking block to reflow at a different width and change height.

**Test:** Added `GeometryReader` frame logging to `BubbleFrame`, `ThinkFrame`, `ToolFrame`.

**Result:** Bubble width **constant at 778.0pt** throughout all state changes. All block widths constant at **738.0pt**. Width reflow disproved.

### Hypothesis 4: VStack position-indexed layout cache (correct)

**Theory:** `VStack` internally caches child heights by positional index. When child 0 (thinking block) changes height, the cached value for child 1 (tool/summary) may be stale or from a different index. The height delta "transfers" between siblings because the cache maps by position, not identity.

**Test:** Replaced `VStack` → `LazyVStack` (identity-based cache). Kept `withAnimation` calls removed.

**Result:** Height transfer zero. Tool height stays at 164 before and after thinking block collapse. ✓

### Verification: animations safe with LazyVStack

**Test:** Re-added `withAnimation(.easeInOut(duration: 0.2))` to ThinkingBlockView, ToolResultView, and transientToolSummary headers.

**Result:** Animations smooth, height transfer still zero. ✓

## The Fix

### Changed files

| File | Change |
|------|--------|
| `Packages/Sources/ClarcChatKit/MessageBubble.swift` | `VStack` → `LazyVStack` (line 34) |
| `Packages/Sources/ClarcChatKit/MessageBubble.swift` | Removed `withAnimation` from `assistantTextBubble` `onTapGesture` (redundant secondary toggle) |
| `Packages/Sources/ClarcChatKit/MessageBubble.swift` | Removed `withAnimation` from user message `isLongTextExpanded` |
| `Packages/Sources/ClarcChatKit/ThinkingBlockView.swift` | `withAnimation` kept in header button |
| `Packages/Sources/ClarcChatKit/ToolResultView.swift` | `withAnimation` kept in header button |

The only structural change is **`VStack` → `LazyVStack`** on MessageBubble's block container. Everything else was diagnostic noise or secondary cleanup.

### Stable identity chain

The fix depends on stable ForEach IDs. The identity chain works as follows:

```
AgentMessageBlock.id (UUID / toolUseID / TextBlockIDCache)
    → convertMessages() → MessageBlock.id (ClarcCore)
    → RenderItem.id (MessageBubble.RenderItem.Identifiable)
    → ForEach(renderItems) (identity for LazyVStack layout cache)
```

Each link in this chain must produce consistent IDs across re-renders. The critical points:

- **Thinking block IDs**: `AgentMessageBlock.thinking(id:)` passes the original UUID through `convertMessages()` to `MessageBlock.id`. The `fromCore()` / `fromTurns()` converters preserve this UUID.
- **Tool call IDs**: Tool-use IDs (`tb.toolUseID`) are stable per tool invocation, set by the LLM.
- **Text block IDs**: `TextBlockIDCache` generates content-hash-keyed UUIDs, so identical text gets the same ID across conversion runs.
- **SUMMARY**: The literal string `"summary"` is used as `RenderItem.id` for the transient tool summary, which is always a single (collapsible) item.

## Edge Cases

1. **Nested LazyVStack inside ScrollView**: LazyVStack is designed for lazy loading when it's a direct child of ScrollView. When nested deeper (as in our case: `ScrollView > VStack > MessageBubble > LazyVStack`), the lazy behavior doesn't apply — it just acts as an identity-based layout container. No performance regression.

2. **LazyVStack proposed height**: Unlike VStack, LazyVStack may expand to fill the entire proposed height when it has `.frame(maxHeight: .infinity)` on the parent. MessageBubble's HStack doesn't propose infinite height, so this is not an issue.

3. **Animation within identity-based layout**: `withAnimation` in child views inside LazyVStack is safe because sibling frame recalculation uses per-identity cached sizes, not positional index lookups.

## Prevention

When adding new collapsible/expandable child views inside a layout container (VStack, List, Grid):

1. **Prefer LazyVStack over VStack** when children have dynamic heights driven by `@State`.
2. **Always provide stable `.id()`** on ForEach items. Use content-derived or origin-derived identifiers, not random UUIDs that change across re-evaluations.
3. **Avoid `withAnimation` inside VStack** if any child's height change can affect sibling layout. Use LazyVStack or animate only visual (non-layout) properties.
4. **Test with GeometryReader** when investigating sibling frame confusion — log both width and height. If width is stable but height transfers, suspect position-indexed cache.

## Diagnostic Logging

The following `[DBG]` log points were added during diagnosis and can be left in place for future debugging:

| Prefix | Location | Values |
|--------|----------|--------|
| `BubbleFrame` | MessageBubble HStack | `w= h= y=` |
| `ThinkFrame` | ThinkingBlockView VStack | `w= h= y= expanded=` |
| `ToolFrame` | ToolResultView VStack | `w= h= y= expanded=` |
| `buildRenderItems` | MessageBubble | `items=[...] hidden=[...]` |
| `MessageBubble body` | MessageBubble | `role= id= streaming= blocks=` |
