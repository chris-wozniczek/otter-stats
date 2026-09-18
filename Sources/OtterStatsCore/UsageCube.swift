import Foundation

/// Every inference turn in the sessions database attributed to exactly one
/// agent and pre-aggregated by day × session × agent × model. The UI slices
/// this in memory; nothing goes back to the database until the next refresh.
public struct UsageCube: Sendable {
    public struct Fact: Sendable, Hashable {
        public let day: String
        public let session: Int
        public let agent: Int
        public let model: Int
        public var turns: Int
        public var input: Int
        public var output: Int
        public var cacheRead: Int
        public var cacheCreation: Int
        public var modelMs: Int
        public var ttftMs: Int
        public var costUSD: Double
        /// What the tokens would cost at the snapshot's reference (SWE-1.7) rate; only set for free-tier models.
        public var equivalentUSD: Double
        public var priced: Bool
        public var pricing: PricingClass
        public var metricsMissing: Int
    }

    public struct ToolFact: Sendable, Hashable {
        public let day: String
        public let session: Int
        public let agent: Int
        public let tool: String
        public var calls: Int
    }

    public struct PromptFact: Sendable, Hashable {
        public let day: String
        public let session: Int
        public var prompts: Int
    }

    public struct Project: Sendable, Hashable, Identifiable {
        public let path: String
        public let name: String
        public var id: String { path }
    }

    public struct SessionDim: Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        public let project: Int
        public let leadModel: String
        public let created: Int?
        public let last: Int?
    }

    public struct ModelDim: Sendable, Hashable, Identifiable {
        public let id: String
        public let price: ModelPrice?
        public var pricing: PricingClass { PricingClass.of(price) }
    }

    public struct Quality: Sendable, Hashable {
        public var turns = 0
        public var duplicates = 0
        public var truncated = false
        public var metricsMissing = 0
        public var unknownTurns = 0
        public var unpricedTurns = 0
        public var totalNodes = 0
    }

    public struct PinDrift: Sendable, Hashable, Identifiable {
        public let role: String
        public let pinned: String
        public let model: String
        public var turns: Int
        public var id: String { "\(role)|\(model)" }
    }

    public let generatedAt: Date
    public let source: String
    public let from: Int
    public let to: Int
    public let capDays: Int
    public let sessions: [SessionDim]
    public let projects: [Project]
    public let agents: [Agent]
    public let models: [ModelDim]
    public let facts: [Fact]
    public let tools: [ToolFact]
    public let prompts: [PromptFact]
    public let quality: Quality
    public let priceSnapshotAt: Date?
    public let unpricedModels: [String]
    /// Paid model whose listed rate is used for `Fact.equivalentUSD`, if the snapshot has one.
    public let referenceModel: String?
    public let pins: [String: String]
    public let pinDrift: [PinDrift]

    public static let empty = UsageCube(generatedAt: Date(), source: "", from: 0, to: 0, capDays: 0, sessions: [], projects: [], agents: [], models: [], facts: [], tools: [], prompts: [], quality: Quality(), priceSnapshotAt: nil, unpricedModels: [], referenceModel: nil, pins: [:], pinDrift: [])

    public var isEmpty: Bool { facts.isEmpty && sessions.isEmpty }
}

// MARK: - Builder

private final class Dim<Element> {
    private var index: [String: Int] = [:]
    private(set) var list: [Element] = []

    func id(_ key: String, make: () -> Element) -> Int {
        if let i = index[key] { return i }
        let i = list.count
        index[key] = i
        list.append(make())
        return i
    }
}

public enum UsageCubeBuilder {
    public static let defaultCapDays = 365

    public static func build(
        store: SessionsStore,
        nowSec: Int = Int(Date().timeIntervalSince1970),
        capDays: Int = defaultCapDays,
        pins: [String: String] = Pins.load(),
        priceSnapshot: PriceSnapshot = PriceSnapshot.read()
    ) throws -> UsageCube {
        let since = nowSec - capDays * 86400
        let fetch = try store.assistantTurns(sinceSec: since)
        let sessions = try store.sessionsCovering(sinceSec: since, turns: fetch.turns)
        let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let graph = try store.nodeGraph(sessionIDs: sessions.map(\.id))
        var roots: [String: [Int: RootDescriptor?]] = [:]
        for (sid, nodes) in graph { roots[sid] = Attribution.resolveRoots(nodes) }

        let sessionsDim = Dim<UsageCube.SessionDim>()
        let projectsDim = Dim<UsageCube.Project>()
        let agentsDim = Dim<Agent>()
        let modelsDim = Dim<UsageCube.ModelDim>()

        func sessionIndex(_ s: SessionRecord) -> Int {
            sessionsDim.id(s.id) {
                let proj = projectsDim.id(s.projectPath) { UsageCube.Project(path: s.projectPath, name: s.projectName) }
                return UsageCube.SessionDim(id: s.id, title: s.title, project: proj, leadModel: s.leadModel, created: s.createdSec, last: s.lastActivitySec)
            }
        }
        func agentIndex(_ a: Agent) -> Int { agentsDim.id(a.id) { a } }
        func modelIndex(_ m: String) -> Int {
            modelsDim.id(m) { UsageCube.ModelDim(id: m, price: priceSnapshot.prices[m]) }
        }

        let reference = priceSnapshot.referenceRate
        var facts: [String: UsageCube.Fact] = [:]
        var quality = UsageCube.Quality()
        quality.duplicates = fetch.duplicates
        quality.truncated = fetch.truncated
        quality.totalNodes = (try? store.totalNodeCount()) ?? 0
        var drift: [String: UsageCube.PinDrift] = [:]

        for t in fetch.turns {
            guard let s = byID[t.sessionID] else { continue }
            var root: RootDescriptor?
            if let nid = t.nodeID, let rootMap = roots[t.sessionID], let r = rootMap[nid] { root = r }
            let agent = Attribution.classify(root: root, model: t.model)
            let day = isoDay(t.ts)
            let si = sessionIndex(s), ai = agentIndex(agent), mi = modelIndex(t.model)
            let key = "\(day)|\(si)|\(ai)|\(mi)"
            let price = modelsDim.list[mi].price
            var f = facts[key] ?? UsageCube.Fact(day: day, session: si, agent: ai, model: mi, turns: 0, input: 0, output: 0, cacheRead: 0, cacheCreation: 0, modelMs: 0, ttftMs: 0, costUSD: 0, equivalentUSD: 0, priced: true, pricing: PricingClass.of(price), metricsMissing: 0)
            f.turns += 1
            f.input += t.input
            f.output += t.output
            f.cacheRead += t.cacheRead
            f.cacheCreation += t.cacheCreation
            f.modelMs += t.modelMs
            f.ttftMs += t.ttftMs
            if t.metricsMissing { f.metricsMissing += 1; quality.metricsMissing += 1 }
            if let price {
                f.costUSD += price.cost(of: t)
                if price.free {
                    f.equivalentUSD += reference.price.rate(input: t.input, cacheRead: t.cacheRead, cacheCreation: t.cacheCreation, output: t.output)
                }
            } else { f.priced = false; quality.unpricedTurns += 1 }
            facts[key] = f
            quality.turns += 1
            if agent.bucket == .unknown { quality.unknownTurns += 1 }
            if let role = agent.role, let pin = pins[role], pin != t.model {
                let k = "\(role)|\(t.model)"
                var d = drift[k] ?? UsageCube.PinDrift(role: role, pinned: pin, model: t.model, turns: 0)
                d.turns += 1
                drift[k] = d
            }
        }

        var tools: [String: UsageCube.ToolFact] = [:]
        var prompts: [String: UsageCube.PromptFact] = [:]
        var seenTool = Set<String>()
        var seenPrompt = Set<String>()
        for (sid, nodes) in graph {
            guard let s = byID[sid] else { continue }
            let rootMap = roots[sid] ?? [:]
            for n in nodes {
                guard let ts = n.ts, ts >= since else { continue }
                let day = isoDay(ts)
                if n.source == "tool_result" {
                    let dedupe = "\(sid)/\(n.toolCallID ?? "node:\(n.nodeID)")"
                    if seenTool.contains(dedupe) { continue }
                    seenTool.insert(dedupe)
                    let agent = Attribution.classify(root: rootMap[n.nodeID] ?? nil, model: nil)
                    let si = sessionIndex(s), ai = agentIndex(agent)
                    let tool = n.operation ?? "unknown"
                    let key = "\(day)|\(si)|\(ai)|\(tool)"
                    var row = tools[key] ?? UsageCube.ToolFact(day: day, session: si, agent: ai, tool: tool, calls: 0)
                    row.calls += 1
                    tools[key] = row
                } else if n.role == "user", n.isUserInput {
                    let dedupe = "\(sid)/\(n.messageID ?? "node:\(n.nodeID)")"
                    if seenPrompt.contains(dedupe) { continue }
                    seenPrompt.insert(dedupe)
                    let si = sessionIndex(s)
                    let key = "\(day)|\(si)"
                    var row = prompts[key] ?? UsageCube.PromptFact(day: day, session: si, prompts: 0)
                    row.prompts += 1
                    prompts[key] = row
                }
            }
        }
        for s in sessions { _ = sessionIndex(s) }

        let sortedFacts = facts.values.sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            if $0.session != $1.session { return $0.session < $1.session }
            if $0.agent != $1.agent { return $0.agent < $1.agent }
            return $0.model < $1.model
        }
        return UsageCube(
            generatedAt: Date(timeIntervalSince1970: TimeInterval(nowSec)),
            source: store.path,
            from: since,
            to: nowSec,
            capDays: capDays,
            sessions: sessionsDim.list,
            projects: projectsDim.list,
            agents: agentsDim.list,
            models: modelsDim.list,
            facts: sortedFacts,
            tools: tools.values.sorted { $0.day < $1.day },
            prompts: prompts.values.sorted { $0.day < $1.day },
            quality: quality,
            priceSnapshotAt: priceSnapshot.generatedAt,
            unpricedModels: modelsDim.list.filter { $0.price == nil }.map(\.id),
            referenceModel: reference.model,
            pins: pins,
            pinDrift: drift.values.sorted { $0.turns > $1.turns }
        )
    }
}
