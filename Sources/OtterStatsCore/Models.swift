import Foundation

/// Where the Devin CLI keeps its data. Mirrors the paths Otter Swarm uses.
public enum DevinPaths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    public static var defaultSessionsDB: URL {
        if let override = ProcessInfo.processInfo.environment["OTTER_SESSIONS_DB"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return home.appendingPathComponent(".local/share/devin/cli/sessions.db")
    }

    public static var defaultPrices: URL {
        if let override = ProcessInfo.processInfo.environment["OTTER_PRICES_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return home.appendingPathComponent(".config/devin/otter/prices.json")
    }

    public static var agentsDirectory: URL { home.appendingPathComponent(".config/devin/agents") }
    public static var modelsSidecar: URL { home.appendingPathComponent(".config/devin/otter-models.json") }
}

/// Raw epochs in sessions.db mix seconds and milliseconds across CLI builds.
public func epochSeconds(_ raw: Double?) -> Int? {
    guard let raw, raw.isFinite, raw > 0 else { return nil }
    return raw > 1e12 ? Int(raw / 1000) : Int(raw)
}

public func isoDay(_ seconds: Int) -> String {
    ISODay.string(from: seconds)
}

/// Day bucketing uses the local timezone so "today" matches the user's clock
/// (otter-swarm buckets in UTC; totals are identical, day boundaries shift).
public enum ISODay {
    public static var timeZone: TimeZone = .current {
        didSet { formatter.timeZone = timeZone; calendar.timeZone = timeZone }
    }

    public static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from seconds: Int) -> String {
        formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    static func date(from day: String) -> Date? {
        formatter.date(from: day)
    }
}

public struct SessionRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let leadModel: String
    public let workingDirectory: String
    public let workspaceDirs: [String]
    public let createdSec: Int?
    public let lastActivitySec: Int?

    public init(id: String, title: String, leadModel: String, workingDirectory: String, workspaceDirs: [String], createdSec: Int?, lastActivitySec: Int?) {
        self.id = id
        self.title = title
        self.leadModel = leadModel
        self.workingDirectory = workingDirectory
        self.workspaceDirs = workspaceDirs
        self.createdSec = createdSec
        self.lastActivitySec = lastActivitySec
    }

    public var projectPath: String { workingDirectory }
    public var projectName: String {
        let name = (workingDirectory as NSString).lastPathComponent
        return name.isEmpty ? (workingDirectory.isEmpty ? "(none)" : workingDirectory) : name
    }
}

/// One assistant inference turn, deduplicated by session + message id.
public struct Turn: Hashable, Sendable {
    public let sessionID: String
    public let nodeID: Int?
    public let model: String
    public let ts: Int
    public let seq: Int
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheCreation: Int
    public let modelMs: Int
    public let ttftMs: Int
    public let metricsMissing: Bool

    public init(sessionID: String, nodeID: Int?, model: String, ts: Int, seq: Int, input: Int, output: Int, cacheRead: Int, cacheCreation: Int, modelMs: Int, ttftMs: Int, metricsMissing: Bool) {
        self.sessionID = sessionID
        self.nodeID = nodeID
        self.model = model
        self.ts = ts
        self.seq = seq
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
        self.modelMs = modelMs
        self.ttftMs = ttftMs
        self.metricsMissing = metricsMissing
    }
}

public struct TurnFetch {
    public let turns: [Turn]
    public let duplicates: Int
    public let truncated: Bool
}

/// A message_nodes row reduced to what the agent tree needs.
public struct NodeRecord: Sendable {
    public let nodeID: Int
    public let parentNodeID: Int?
    public let role: String?
    public let messageID: String?
    public let toolCallID: String?
    public let isUserInput: Bool
    public let source: String?
    public let operation: String?
    public let head: String?
    public let ts: Int?

    public init(nodeID: Int, parentNodeID: Int?, role: String?, messageID: String?, toolCallID: String?, isUserInput: Bool, source: String?, operation: String?, head: String?, ts: Int?) {
        self.nodeID = nodeID
        self.parentNodeID = parentNodeID
        self.role = role
        self.messageID = messageID
        self.toolCallID = toolCallID
        self.isUserInput = isUserInput
        self.source = source
        self.operation = operation
        self.head = head
        self.ts = ts
    }
}

public struct RootDescriptor: Hashable, Sendable {
    public let source: String?
    public let operation: String?
    public let head: String?

    public init(source: String?, operation: String?, head: String?) {
        self.source = source
        self.operation = operation
        self.head = head
    }
}

public enum AgentBucket: String, CaseIterable, Codable, Sendable, Identifiable {
    case lead, otter, subagent, housekeeping, unknown

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .lead: return "Lead"
        case .otter: return "Otter workers"
        case .subagent: return "Other subagents"
        case .housekeeping: return "Housekeeping"
        case .unknown: return "Unknown"
        }
    }
}

public struct Agent: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let bucket: AgentBucket
    public let label: String
    public let role: String?

    public init(id: String, bucket: AgentBucket, label: String, role: String? = nil) {
        self.id = id
        self.bucket = bucket
        self.label = label
        self.role = role
    }
}

public struct ModelPrice: Codable, Hashable, Sendable {
    public var free: Bool
    public var input: Double
    public var cached: Double
    public var output: Double
    public var cacheWrite: Double?

    public init(free: Bool, input: Double, cached: Double, output: Double, cacheWrite: Double? = nil) {
        self.free = free
        self.input = input
        self.cached = cached
        self.output = output
        self.cacheWrite = cacheWrite
    }

    enum CodingKeys: String, CodingKey {
        case free, input, cached, output
        case cacheWrite = "cache_write"
    }

    public func cost(of turn: Turn) -> Double {
        if free { return 0 }
        return rate(input: turn.input, cacheRead: turn.cacheRead, cacheCreation: turn.cacheCreation, output: turn.output)
    }

    /// The listed rates applied to raw token counts, ignoring `free`.
    public func rate(input i: Int, cacheRead: Int, cacheCreation: Int, output o: Int) -> Double {
        let write = cacheWrite ?? input
        return Double(i) * input + Double(cacheRead) * cached + Double(cacheCreation) * write + Double(o) * output
    }

    public var pricing: PricingClass { free ? .free : .paid }
}

/// How a model's usage is billed according to the local price snapshot.
public enum PricingClass: String, CaseIterable, Codable, Sendable, Identifiable {
    case paid, free, unknown

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .paid: return "Paid"
        case .free: return "Free tier"
        case .unknown: return "Unknown"
        }
    }

    public static func of(_ price: ModelPrice?) -> PricingClass { price?.pricing ?? .unknown }
}
