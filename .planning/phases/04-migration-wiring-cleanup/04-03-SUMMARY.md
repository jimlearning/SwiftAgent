# Plan 04-03 Summary: Tool Protocol Deletion + Batch 2+3 Migration

**Status:** Complete

## What was done

1. **Deleted old Tool protocol from Types/Tool.swift** per D-06. File reduced from 1010 lines to 25 lines.
   - Removed: Tool protocol + extension, CanUseToolFn, ToolPermissionContext, ToolDescriptionOptions, MCPToolInfo, ValidationResult, ToolResultBlockParam, ToolUseContext (400+ line struct), ToolOutput, NotebookCell, PDFPage, ToolResult, MCPMeta, SearchOrReadResult, PermissionMatcher
   - Kept: ToolProgressData protocol, ToolProgress struct, ToolCallProgress typealias (referenced by ChatCommand.swift — will be removed in Plan 04-05)

2. **Migrated 4 Batch 2 tools** (file mutation) to RuntimeAgentTool:
   - FileWriteTool (workingDirectory), FileEditTool (workingDirectory), NotebookEditTool, SnipTool
   - All use typed Arguments with CodingKeys, capture context at init, return ToolOutputValue

3. **Migrated 5 Batch 3 tools** (command execution) to RuntimeAgentTool:
   - BashTool (workingDirectory, shell), LSPTool (workingDirectory), PowerShellTool, TerminalCaptureTool, TungstenTool
   - BashTool preserves all Process execution logic, timeout handling, danger detection

4. **Deleted 10 old tool files** from Sources/SwiftAgentCore/Tools/:
   - Batch 1: BundledSkills.swift
   - Batch 2: FileWriteTool, FileEditTool, NotebookEditTool, SnipTool
   - Batch 3: BashTool, LSPTool, PowerShellTool, TerminalCaptureTool, TungstenTool

5. **Created Batch23ToolRegistry.swift** with 9 entries (isReadOnly: false for destructive tools, requiresApproval: true for file mutation and command execution)

## Verification

- All 9 new tools conform to RuntimeAgentTool with zero ToolUseContext/ToolResult leaks
- Batch23ToolRegistry has 9 ToolMetadata entries
- 39 old files remain in Sources/SwiftAgentCore/Tools/ (36 tool files + 3 shared type files)
- Old Tool protocol completely removed from Types/Tool.swift
- Build does NOT pass — 36 old tool files fail to compile against deleted Tool protocol (intentional per D-06)

## Next: Plan 04-04

36 remaining tools need migration. The pattern is validated across 24 tools (15 Batch 1 + 9 Batch 2+3). Plan 04-04 will handle the final migration wave.
