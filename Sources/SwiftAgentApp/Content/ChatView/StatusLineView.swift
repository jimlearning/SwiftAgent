import SwiftUI

/// Bottom status bar showing project path, model, rate limits, context%, duration.
/// Ported from ClarcChatKit's `StatusLineView`.
struct StatusLineView: View {
    @Environment(ChatBridge.self) private var chatBridge
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var rateLimit: RateLimitUsage?

    private var modelDisplayName: String {
        chatBridge.modelDisplayName
    }

    private var totalResponseDuration: Double {
        chatBridge.sessionStats.durationMs
    }

    private var contextPercentage: Double? {
        guard let pct = chatBridge.lastTurnContextUsedPercentage else { return nil }
        return min(pct, 100)
    }

    var body: some View {
        HStack(spacing: 10) {
            if let project = appViewModel.selectedProject {
                segment(icon: "folder.fill", text: abbreviatePath(project.path), color: ChatTheme.statusWarning)
            }

            segment(icon: "cpu", text: modelDisplayName, color: ChatTheme.statusSuccess)

            Divider().frame(height: 12)

            rateLimitSegment(label: "5h", icon: "clock", percent: rateLimit?.fiveHourPercent, resetsAt: rateLimit?.fiveHourResetsAt)
            rateLimitSegment(label: "7d", icon: "calendar", percent: rateLimit?.sevenDayPercent, resetsAt: rateLimit?.sevenDayResetsAt)

            Divider().frame(height: 12)

            HStack(spacing: 4) {
                Image(systemName: "memorychip")
                    .font(.system(size: ChatTheme.size(10)))
                Text("context")
                if let ctxPct = contextPercentage {
                    miniBar(percent: ctxPct)
                    Text("\(Int(ctxPct))%")
                        .foregroundStyle(colorForPercent(ctxPct))
                } else {
                    Text("--")
                }
            }
            .foregroundStyle(ChatTheme.textTertiary)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "stopwatch")
                    .font(.system(size: ChatTheme.size(10)))
                Text(formatTotalDuration(totalResponseDuration))
            }
            .foregroundStyle(ChatTheme.textTertiary)
        }
        .font(.system(size: ChatTheme.size(12), weight: .medium, design: .monospaced))
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .frame(height: 28)
        .padding(.bottom, 4)
        .background(ChatTheme.surfacePrimary)
        .overlay(alignment: .top) {
            ChatTheme.borderSubtle.frame(height: 0.5)
        }
        .task {
            await refreshRateLimit()
            if rateLimit == nil {
                try? await Task.sleep(for: .seconds(5))
                await refreshRateLimit()
            }
        }
        .onChange(of: chatBridge.isStreaming) { old, new in
            if old && !new {
                Task { await refreshRateLimit() }
            }
        }
    }

    private func segment(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: ChatTheme.size(10)))
            Text(text)
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private func rateLimitSegment(label: String, icon: String, percent: Double?, resetsAt: Date?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: ChatTheme.size(10)))
            Text(label)
                .foregroundStyle(ChatTheme.textTertiary)
            if let pct = percent {
                miniBar(percent: pct)
                Text("\(Int(pct))%")
                    .foregroundStyle(colorForPercent(pct))
                if let resets = resetsAt {
                    Text(shortCountdown(until: resets))
                        .foregroundStyle(ChatTheme.textTertiary)
                }
            } else {
                Text("--")
                    .foregroundStyle(ChatTheme.textTertiary)
            }
        }
    }

    private func miniBar(percent: Double, width: Int = 5) -> some View {
        let filled = max(0, min(width, Int((percent / 100.0) * Double(width))))
        let empty = width - filled
        let color = colorForPercent(percent)

        return HStack(spacing: 1) {
            ForEach(0..<filled, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 4, height: 10)
            }
            ForEach(0..<empty, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(ChatTheme.borderSubtle)
                    .frame(width: 4, height: 10)
            }
        }
    }

    private func colorForPercent(_ pct: Double) -> Color {
        if pct >= 90 { return ChatTheme.statusError }
        if pct >= 70 { return ChatTheme.statusWarning }
        return ChatTheme.statusSuccess
    }

    private func shortCountdown(until date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return "" }
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        f.allowedUnits = [.day, .hour, .minute]
        f.calendar = Calendar.current
        return f.string(from: remaining) ?? ""
    }

    private func formatTotalDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        f.allowedUnits = [.hour, .minute, .second]
        return f.string(from: seconds) ?? "—"
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func refreshRateLimit() async {
        rateLimit = await chatBridge.fetchRateLimit()
    }
}
