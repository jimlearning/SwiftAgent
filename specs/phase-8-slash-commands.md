# Phase 8: Slash 命令系统

## Requirements
- Slash command registry with lazy loading
- Built-in commands: /help, /clear, /exit, /model, /config, /memory
- ArgumentParser-based command dispatch

## Files to Create
| 文件 | 说明 |
|---|---|
| CoreCommands/HelpCommand.swift | /help |
| CoreCommands/ClearCommand.swift | /clear |
| CoreCommands/ConfigCommand.swift | /config show/set |
| CoreCommands/SlashCommandRegistry.swift | 命令注册和发现 |

## Acceptance Criteria
- [ ] 所有内置 slash 命令可用
- [ ] SlashCommandRegistry 支持注册和查找
- [ ] `swift build` + `swift test` 通过

**Output when complete:** `<promise>DONE</promise>`
