import Foundation

/// Period presets the menu bar and dashboard share.
public enum Period: String, CaseIterable, Codable, Sendable, Identifiable {
    case today, week, month, quarter, year, all

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .today: return "Today"
        case .week: return "7 days"
        case .month: return "30 days"
        case .quarter: return "90 days"
        case .year: return "365 days"
        case .all: return "All embedded"
        }
    }

    public var shortLabel: String {
        switch self {
        case .today: return "today"
        case .week: return "7d"
        case .month: return "30d"
        case .quarter: return "90d"
        case .year: return "365d"
        case .all: return "all"
        }
    }

    public var days: Int? {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .all: return nil
        }
    }

    /// Epoch seconds of the period start, or nil for everything embedded.
    public func fromSec(now: Int = Int(Date().timeIntervalSince1970)) -> Int? {
        switch self {
        case .today:
            return Int(ISODay.calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(now))).timeIntervalSince1970)
        case .all:
            return nil
        default:
            return now - (days ?? 0) * 86400
        }
    }
}

public struct UsageFilter: Hashable, Sendable {
    public var period: Period = .week
    public var fromSec: Int?
    public var toSec: Int?
    public var projects: Set<Int> = []
    public var sessions: Set<Int> = []
    public var agents: Set<String> = []
    public var buckets: Set<AgentBucket> = []
    public var models: Set<Int> = []
    public var pricing: Set<PricingClass> = []
    public var query: String = ""

    public init(period: Period = .week) {
        self.period = period
    }

    public var hasSlicers: Bool {
        !projects.isEmpty || !sessions.isEmpty || !agents.isEmpty || !buckets.isEmpty || !models.isEmpty || !pricing.isEmpty || !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public mutating func clearSlicers() {
        projects = []; sessions = []; agents = []; buckets = []; models = []; pricing = []; query = ""
    }
}

public struct UsageTotals: Hashable, Sendable {
    public var turns = 0
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheCreation = 0
    public var modelMs = 0
    public var ttftMs = 0
    /// Actual estimated charge: paid models at their listed rate, free tier as $0, unknown excluded.
    public var costUSD = 0.0
    /// What free-tier usage would have cost at the reference (SWE-1.7) rate. Simulation, not a charge.
    public var equivalentUSD = 0.0
    public var pricedTurns = 0
    public var unpricedTurns = 0
    public var paidTokens = 0
    public var freeTokens = 0
    public var unknownTokens = 0
    public var freeTurns = 0
    public var metricsMissing = 0

    public var tokens: Int { input + output + cacheRead }
    public var costComplete: Bool { unpricedTurns == 0 }
    public var hasFree: Bool { freeTurns > 0 }
    /// Actual cost plus the simulated value of free-tier usage.
    public var billedEquivalentUSD: Double { costUSD + equivalentUSD }
    public var avgTurnMs: Double { turns > 0 ? Double(modelMs) / Double(turns) : 0 }
    public var avgTTFTMs: Double { turns > 0 ? Double(ttftMs) / Double(turns) : 0 }
    public var cacheHitRatio: Double { input + cacheRead > 0 ? Double(cacheRead) / Double(input + cacheRead) : 0 }

    mutating func add(_ f: UsageCube.Fact) {
        turns += f.turns
        input += f.input
        output += f.output
        cacheRead += f.cacheRead
        cacheCreation += f.cacheCreation
        modelMs += f.modelMs
        ttftMs += f.ttftMs
        metricsMissing += f.metricsMissing
        if f.priced { costUSD += f.costUSD; pricedTurns += f.turns } else { unpricedTurns += f.turns }
        equivalentUSD += f.equivalentUSD
        let toks = f.input + f.output + f.cacheRead
        switch f.pricing {
        case .paid: paidTokens += toks
        case .free: freeTokens += toks; freeTurns += f.turns
        case .unknown: unknownTokens += toks
        }
    }
}

public struct KeyedTotals<Key: Hashable & Sendable>: Hashable, Sendable {
    public let key: Key
    public var totals: UsageTotals
    public var share: Double
}

public struct DayPoint: Hashable, Sendable, Identifiable {
    public let day: String
    public var date: Date { ISODay.date(from: day) ?? Date(timeIntervalSince1970: 0) }
    public var totals: UsageTotals
    public var byBucket: [AgentBucket: UsageTotals]
    public var id: String { day }
}

public struct SessionSummary: Hashable, Sendable, Identifiable {
    public let index: Int
    public let session: UsageCube.SessionDim
    public let project: UsageCube.Project
    public var totals: UsageTotals
    public var prompts: Int
    public var agents: [KeyedTotals<Int>]
    public var models: [KeyedTotals<Int>]
    public var id: Int { index }
}

public struct ToolSummary: Hashable, Sendable, Identifiable {
    public let tool: String
    public var calls: Int
    public var id: String { tool }
}

public struct Efficiency: Hashable, Sendable {
    public var prompts: Int
    public var turns: Int
    public var turnsPerPrompt: Double?
    public var tokensPerPrompt: Double?
    public var outputPerTurn: Double
    public var cacheHitRatio: Double
    public var avgTTFTMs: Double
    public var avgTurnMs: Double
    public var modelTimeMs: Int
    public var toolCalls: Int
}

/// The full dashboard state for one filter, computed once per filter change.
public struct UsageSlice: Sendable {
    public let filter: UsageFilter
    public let cube: UsageCube
    public let totals: UsageTotals
    public let byBucket: [KeyedTotals<AgentBucket>]
    public let byAgent: [KeyedTotals<Int>]
    public let byModel: [KeyedTotals<Int>]
    public let byProject: [KeyedTotals<Int>]
    public let timeline: [DayPoint]
    public let sessions: [SessionSummary]
    public let tools: [ToolSummary]
    public let toolsByAgent: [KeyedTotals<Int>]
    public let prompts: Int
    public let activeSessions: Int
    public let sessionsWithTurns: Int
    public let efficiency: Efficiency
    public let fromDay: String?
    public let toDay: String?

    public init(cube: UsageCube, filter: UsageFilter, now: Int = Int(Date().timeIntervalSince1970)) {
        self.cube = cube
        self.filter = filter
        let from = filter.fromSec ?? filter.period.fromSec(now: now)
        let to = filter.toSec
        let fromDay = from.map(isoDay)
        let toDay = to.map(isoDay)
        self.fromDay = fromDay
        self.toDay = toDay
        let q = filter.query.trimmingCharacters(in: .whitespaces).lowercased()

        var sessionOK: [Int: Bool] = [:]
        func sessionPasses(_ si: Int) -> Bool {
            if let cached = sessionOK[si] { return cached }
            guard si < cube.sessions.count else { return false }
            let s = cube.sessions[si]
            var ok = true
            if !filter.projects.isEmpty, !filter.projects.contains(s.project) { ok = false }
            if ok, !filter.sessions.isEmpty, !filter.sessions.contains(si) { ok = false }
            if ok, !q.isEmpty {
                let proj = cube.projects[s.project]
                let hay = "\(s.id) \(s.title) \(proj.name) \(proj.path) \(s.leadModel)".lowercased()
                ok = hay.contains(q)
            }
            sessionOK[si] = ok
            return ok
        }
        func dayPasses(_ day: String) -> Bool {
            if let fromDay, day < fromDay { return false }
            if let toDay, day > toDay { return false }
            return true
        }
        func agentPasses(_ ai: Int) -> Bool {
            let a = cube.agents[ai]
            if !filter.agents.isEmpty, !filter.agents.contains(a.id) { return false }
            if !filter.buckets.isEmpty, !filter.buckets.contains(a.bucket) { return false }
            return true
        }

        var totals = UsageTotals()
        var bucketMap: [AgentBucket: UsageTotals] = [:]
        var agentMap: [Int: UsageTotals] = [:]
        var modelMap: [Int: UsageTotals] = [:]
        var projectMap: [Int: UsageTotals] = [:]
        var dayMap: [String: DayPoint] = [:]
        var sessionMap: [Int: UsageTotals] = [:]
        var sessionAgents: [Int: [Int: UsageTotals]] = [:]
        var sessionModels: [Int: [Int: UsageTotals]] = [:]

        for f in cube.facts {
            guard dayPasses(f.day), sessionPasses(f.session), agentPasses(f.agent) else { continue }
            if !filter.models.isEmpty, !filter.models.contains(f.model) { continue }
            if !filter.pricing.isEmpty, !filter.pricing.contains(f.pricing) { continue }
            totals.add(f)
            let bucket = cube.agents[f.agent].bucket
            bucketMap[bucket, default: UsageTotals()].add(f)
            agentMap[f.agent, default: UsageTotals()].add(f)
            modelMap[f.model, default: UsageTotals()].add(f)
            projectMap[cube.sessions[f.session].project, default: UsageTotals()].add(f)
            sessionMap[f.session, default: UsageTotals()].add(f)
            sessionAgents[f.session, default: [:]][f.agent, default: UsageTotals()].add(f)
            sessionModels[f.session, default: [:]][f.model, default: UsageTotals()].add(f)
            var point = dayMap[f.day] ?? DayPoint(day: f.day, totals: UsageTotals(), byBucket: [:])
            point.totals.add(f)
            point.byBucket[bucket, default: UsageTotals()].add(f)
            dayMap[f.day] = point
        }

        // Prompts, tools and sessions have no model; under a model-level filter keep only sessions with matching turns.
        let modelScoped = !filter.models.isEmpty || !filter.pricing.isEmpty
        let matchedSessions = Set(sessionMap.keys)
        func sessionInScope(_ si: Int) -> Bool { !modelScoped || matchedSessions.contains(si) }

        var promptTotal = 0
        var promptsBySession: [Int: Int] = [:]
        for p in cube.prompts where dayPasses(p.day) && sessionPasses(p.session) && sessionInScope(p.session) {
            promptTotal += p.prompts
            promptsBySession[p.session, default: 0] += p.prompts
        }

        var toolMap: [String: Int] = [:]
        var toolAgentMap: [Int: Int] = [:]
        var toolCalls = 0
        for t in cube.tools where dayPasses(t.day) && sessionPasses(t.session) && agentPasses(t.agent) && sessionInScope(t.session) {
            toolMap[t.tool, default: 0] += t.calls
            toolAgentMap[t.agent, default: 0] += t.calls
            toolCalls += t.calls
        }

        let denom = Double(max(totals.tokens, 1))
        func keyed<K: Hashable & Sendable>(_ map: [K: UsageTotals]) -> [KeyedTotals<K>] {
            map.map { KeyedTotals(key: $0.key, totals: $0.value, share: Double($0.value.tokens) / denom) }
                .sorted { $0.totals.tokens != $1.totals.tokens ? $0.totals.tokens > $1.totals.tokens : $0.totals.turns > $1.totals.turns }
        }

        self.totals = totals
        self.byBucket = AgentBucket.allCases.compactMap { b in
            bucketMap[b].map { KeyedTotals(key: b, totals: $0, share: Double($0.tokens) / denom) }
        }
        self.byAgent = keyed(agentMap)
        self.byModel = keyed(modelMap)
        self.byProject = keyed(projectMap)
        self.timeline = dayMap.values.sorted { $0.day < $1.day }
        self.prompts = promptTotal
        self.tools = toolMap.map { ToolSummary(tool: $0.key, calls: $0.value) }.sorted { $0.calls != $1.calls ? $0.calls > $1.calls : $0.tool < $1.tool }
        let toolDenom = Double(max(toolCalls, 1))
        self.toolsByAgent = toolAgentMap.map { entry in
            var t = UsageTotals(); t.turns = entry.value
            return KeyedTotals(key: entry.key, totals: t, share: Double(entry.value) / toolDenom)
        }.sorted { $0.totals.turns > $1.totals.turns }

        // Sessions active in the period (created or touched) even with zero turns.
        var active: [SessionSummary] = []
        for (si, s) in cube.sessions.enumerated() {
            guard sessionPasses(si), sessionInScope(si) else { continue }
            let hasFacts = sessionMap[si] != nil || promptsBySession[si] != nil
            let touched: Bool = {
                let created = s.created ?? 0, last = s.last ?? 0
                if let from, created < from, last < from { return false }
                if let to, created > to { return false }
                return true
            }()
            guard hasFacts || touched else { continue }
            let sTotals = sessionMap[si] ?? UsageTotals()
            let sDenom = Double(max(sTotals.tokens, 1))
            let agents = (sessionAgents[si] ?? [:]).map { KeyedTotals(key: $0.key, totals: $0.value, share: Double($0.value.tokens) / sDenom) }.sorted { $0.totals.tokens > $1.totals.tokens }
            let models = (sessionModels[si] ?? [:]).map { KeyedTotals(key: $0.key, totals: $0.value, share: Double($0.value.tokens) / sDenom) }.sorted { $0.totals.tokens > $1.totals.tokens }
            active.append(SessionSummary(index: si, session: s, project: cube.projects[s.project], totals: sTotals, prompts: promptsBySession[si] ?? 0, agents: agents, models: models))
        }
        active.sort { $0.totals.tokens != $1.totals.tokens ? $0.totals.tokens > $1.totals.tokens : ($0.session.last ?? 0) > ($1.session.last ?? 0) }
        self.sessions = active
        self.activeSessions = active.count
        self.sessionsWithTurns = active.filter { $0.totals.turns > 0 }.count

        self.efficiency = Efficiency(
            prompts: promptTotal,
            turns: totals.turns,
            turnsPerPrompt: promptTotal > 0 ? Double(totals.turns) / Double(promptTotal) : nil,
            tokensPerPrompt: promptTotal > 0 ? Double(totals.input + totals.output) / Double(promptTotal) : nil,
            outputPerTurn: totals.turns > 0 ? Double(totals.output) / Double(totals.turns) : 0,
            cacheHitRatio: totals.cacheHitRatio,
            avgTTFTMs: totals.avgTTFTMs,
            avgTurnMs: totals.avgTurnMs,
            modelTimeMs: totals.modelMs,
            toolCalls: toolCalls
        )
    }

    public func agent(_ index: Int) -> Agent { cube.agents[index] }
    public func model(_ index: Int) -> UsageCube.ModelDim { cube.models[index] }
    public func project(_ index: Int) -> UsageCube.Project { cube.projects[index] }

    /// Continuous day series (zero-filled) between the period start and today.
    public func filledTimeline(now: Int = Int(Date().timeIntervalSince1970)) -> [DayPoint] {
        let start: Int
        if let fromDay, let d = ISODay.date(from: fromDay) { start = Int(d.timeIntervalSince1970) }
        else if let first = timeline.first { start = Int(first.date.timeIntervalSince1970) }
        else { return [] }
        let end = toSec ?? now
        var out: [DayPoint] = []
        var cursor = Date(timeIntervalSince1970: TimeInterval(start))
        let map = Dictionary(timeline.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        while Int(cursor.timeIntervalSince1970) <= end && out.count < 400 {
            let day = isoDay(Int(cursor.timeIntervalSince1970))
            out.append(map[day] ?? DayPoint(day: day, totals: UsageTotals(), byBucket: [:]))
            guard let next = ISODay.calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    private var toSec: Int? { filter.toSec }
}

// MARK: - Formatting

public enum Fmt {
    public static func trim(_ x: Double) -> String {
        var s: String
        if x >= 100 { s = String(Int(x.rounded())) }
        else if x >= 10 { s = String(format: "%.1f", x) }
        else { s = String(format: "%.2f", x) }
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    public static func compact(_ n: Int) -> String { compact(Double(n)) }

    public static func compact(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1e9 { return trim(v / 1e9) + "B" }
        if a >= 1e6 { return trim(v / 1e6) + "M" }
        if a >= 1e3 { return trim(v / 1e3) + "k" }
        return int(Int(v.rounded()))
    }

    public static func int(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    public static func usd(_ v: Double, complete: Bool = true) -> String {
        let prefix = complete ? "" : "≥"
        if v == 0 { return prefix + "$0" }
        if v < 0.01 { return prefix + String(format: "$%.4f", v) }
        if v < 1 { return prefix + String(format: "$%.3f", v) }
        if v < 100 { return prefix + String(format: "$%.2f", v) }
        return prefix + "$" + int(Int(v.rounded()))
    }

    public static func duration(ms: Int) -> String {
        let s = Double(ms) / 1000
        if s < 60 { return trim(s) + "s" }
        let m = s / 60
        if m < 60 { return trim(m) + "m" }
        let h = m / 60
        if h < 48 { return trim(h) + "h" }
        return trim(h / 24) + "d"
    }

    public static func percent(_ v: Double) -> String {
        let p = v * 100
        if p >= 99.95 { return "100%" }
        if p < 0.05 && p > 0 { return "<0.1%" }
        return trim(p) + "%"
    }

    public static func relative(_ sec: Int?, now: Int = Int(Date().timeIntervalSince1970)) -> String {
        guard let sec else { return "—" }
        let d = max(0, now - sec)
        if d < 60 { return "just now" }
        if d < 3600 { return "\(d / 60)m ago" }
        if d < 86400 { return "\(d / 3600)h ago" }
        if d < 86400 * 14 { return "\(d / 86400)d ago" }
        return isoDay(sec)
    }
}
