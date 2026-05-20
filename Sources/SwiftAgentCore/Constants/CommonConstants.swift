import Foundation

/// Shared constants matching Claude Code's constants/messages.ts and constants/common.ts.
public enum CommonConstants {
    /// CC: NO_CONTENT_MESSAGE = "(no content)" — used when tool results contain no text.
    public static let noContentMessage = "(no content)"

    /// CC: getLocalISODate() — returns the current local time in ISO format.
    public static func getLocalISODate() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    /// CC: getSessionStartDate — memoized session start timestamp.
    public static let sessionStartDate: Date = Date()

    /// CC: getLocalMonthYear() — returns e.g. "January 2026".
    public static func getLocalMonthYear() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }
}

/// Spinner verbs matching Claude Code's constants/spinnerVerbs.ts.
public let SPINNER_VERBS: [String] = [
    "Analyzing", "Assembling", "Baking", "Brewing", "Building",
    "Calculating", "Checking", "Churning", "Clauding", "Cogitating",
    "Compiling", "Computing", "Cooking", "Crunching", "Decoding",
    "Deploying", "Digesting", "Discovering", "Enriching", "Evaluating",
    "Examining", "Exploring", "Fetching", "Figuring", "Gathering",
    "Generating", "Indexing", "Inspecting", "Loading", "Measuring",
    "Merging", "Modeling", "Optimizing", "Parsing", "Planning",
    "Preparing", "Processing", "Querying", "Reading", "Reasoning",
    "Refactoring", "Resolving", "Reticulating", "Retrieving",
    "Reviewing", "Scanning", "Searching", "Solving", "Sorting",
    "Synthesizing", "Testing", "Thinking", "Transforming", "Validating",
    "Verifying", "Working",
]

/// Turn completion verbs matching Claude Code's constants/turnCompletionVerbs.ts.
public let TURN_COMPLETION_VERBS: [String] = [
    "Baked", "Brewed", "Churned", "Cogitated", "Cooked",
    "Crunched", "Sauteed", "Worked",
]
