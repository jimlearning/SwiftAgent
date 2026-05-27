import Testing
import Darwin
@testable import SwiftAgentCLI

struct TerminalDisplayWidthTests {
    @Test
    func countsWideCharactersAsTwoColumns() {
        #expect(TerminalDisplayWidth.width("abc") == 3)
        #expect(TerminalDisplayWidth.width("中文") == 4)
        #expect(TerminalDisplayWidth.width("a中b") == 4)
    }

    @Test
    func calculatesWrappedRowsFromVisibleColumns() {
        #expect(TerminalDisplayWidth.rows(forWidth: 10, columns: 10) == 1)
        #expect(TerminalDisplayWidth.rows(forWidth: 11, columns: 10) == 2)
        #expect(TerminalDisplayWidth.cursorPosition(forOffset: 10, columns: 10).row == 0)
        #expect(TerminalDisplayWidth.cursorPosition(forOffset: 11, columns: 10).row == 1)
    }
}

struct TerminalModeTests {
    @Test
    func escapeWatcherRawModePreservesOutputPostProcessing() {
        var attrs = termios()
        attrs.c_oflag = tcflag_t(OPOST)

        let raw = LineEditor.rawInputAttributes(from: attrs, preserveOutputProcessing: true)

        #expect((raw.c_oflag & tcflag_t(OPOST)) != 0)
    }

    @Test
    func lineEditingRawModeCanDisableOutputPostProcessing() {
        var attrs = termios()
        attrs.c_oflag = tcflag_t(OPOST)

        let raw = LineEditor.rawInputAttributes(from: attrs, preserveOutputProcessing: false)

        #expect((raw.c_oflag & tcflag_t(OPOST)) == 0)
    }
}

struct MarkdownRendererTableTests {
    @Test
    func tableRowsUseVisibleColumnWidths() {
        let renderer = MarkdownRenderer(
            capability: TerminalCapability(isTTY: false, supportsColor: false, columns: 80, rows: 24),
            theme: .monochrome
        )

        let rendered = renderer.render("""
        | 名称 | Count |
        | --- | ---: |
        | 中文 | 12 |
        | ASCII | 3 |
        """)

        let tableLines = rendered
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        #expect(tableLines.count == 4)
        let widths = Set(tableLines.map(TerminalDisplayWidth.visibleWidth))
        #expect(widths.count == 1)
        #expect(tableLines[0].contains("│ "))
        #expect(tableLines[0].contains(" │"))
    }
}

struct PastePlaceholderTests {
    @Test
    func multilinePasteDisplaysPlaceholderButExpandsToOriginalText() {
        let pasted = "first line\nsecond line\nthird line"
        let placeholder = LineEditor.makePastePlaceholder(pasteIndex: 2, content: pasted)
        let display = "Please inspect \(placeholder)"
        let expanded = LineEditor.expandPastePlaceholders(
            in: display,
            expansions: [placeholder: pasted]
        )

        #expect(placeholder == "[Pasted text #2 +2 lines]")
        #expect(display.contains("[Pasted text #2 +2 lines]"))
        #expect(expanded == "Please inspect first line\nsecond line\nthird line")
    }

    @Test
    func pastePlaceholderReportsAdditionalLineCount() {
        let pasted = """
        刚把 TUI 的功能初步完成。
        现在需要继续更新接下来的功能。
        /help 里显示的菜单功能除了 clear 其他都不能用。
        """

        #expect(LineEditor.makePastePlaceholder(pasteIndex: 1, content: pasted) == "[Pasted text #1 +2 lines]")
    }
}
