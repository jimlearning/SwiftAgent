import Foundation

/// A scheduled cron job.
public struct CronTask: Codable, Sendable, Identifiable {
    public let id: String
    public let cron: String
    public let prompt: String
    public let recurring: Bool
    public let durable: Bool
    public let agentId: String?
    public let createdAt: Date

    public init(id: String = UUID().uuidString, cron: String, prompt: String, recurring: Bool = true, durable: Bool = false, agentId: String? = nil) {
        self.id = id
        self.cron = cron
        self.prompt = prompt
        self.recurring = recurring
        self.durable = durable
        self.agentId = agentId
        self.createdAt = Date()
    }
}

/// Thread-safe store for scheduled cron tasks.
public actor CronStore {
    private var tasks: [CronTask] = []
    private let maxJobs = 50

    public init() {}

    public func add(_ task: CronTask) throws -> String {
        guard tasks.count < maxJobs else {
            throw CronError.tooManyJobs
        }
        tasks.append(task)
        return task.id
    }

    public func listAll() -> [CronTask] {
        tasks
    }

    public func remove(ids: [String]) {
        tasks.removeAll { ids.contains($0.id) }
    }

    public func find(id: String) -> CronTask? {
        tasks.first { $0.id == id }
    }
}

public enum CronError: Error {
    case tooManyJobs
    case invalidExpression
    case notFound
}

/// Parse a 5-field cron expression and return a human-readable description.
func cronToHuman(_ expr: String) -> String {
    let fields = expr.split(separator: " ")
    guard fields.count == 5 else { return "Invalid expression" }
    let parts: [String] = fields.map(String.init)
    let minute = parts[0], hour = parts[1], dom = parts[2], month = parts[3], dow = parts[4]

    if minute == "*" && hour == "*" && dom == "*" && month == "*" && dow == "*" {
        return "every minute"
    }
    if minute.hasPrefix("*/") {
        let n = String(minute.dropFirst(2))
        return "every \(n) minutes"
    }
    var desc = ""
    if minute != "*" { desc += "at minute \(minute) " }
    if hour != "*" { desc += "at \(hour):00 " }
    if dom != "*" { desc += "on day \(dom) " }
    if month != "*" { desc += "in month \(month) " }
    if dow != "*" { desc += "on weekday \(dow) " }
    return desc.trimmingCharacters(in: .whitespaces)
}

/// Validate a 5-field cron expression.
func isValidCron(_ expr: String) -> Bool {
    let fields = expr.split(separator: " ")
    guard fields.count == 5 else { return false }
    for field in fields {
        let pattern = /^(\*|\*\/\d+|\d+(-\d+)?(,\d+(-\d+)?)*)$/
        if field.firstMatch(of: pattern) == nil { return false }
    }
    return true
}
