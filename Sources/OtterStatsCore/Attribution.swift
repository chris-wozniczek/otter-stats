import Foundation

/// Structural agent attribution over the message_nodes forest. Each agent that
/// ran inside a session owns a subtree rooted at a `sysprompt/<profile>` node;
/// walking parent_node_id to the root names the agent that produced a turn.
public enum Attribution {
    public static let auxModels: Set<String> = ["summarizer", "compactor"]
    public static let otterRoles = ["planner", "researcher", "implementer", "reviewer", "tester", "interrogator"]
    public static let leadProfiles: Set<String> = ["normal", "plan", "ask"]

    public static func classify(root: RootDescriptor?, model: String?) -> Agent {
        if let model, auxModels.contains(model) {
            return Agent(id: "housekeeping", bucket: .housekeeping, label: "housekeeping")
        }
        guard let root else {
            return Agent(id: "unknown:orphan", bucket: .unknown, label: "unknown (orphan chain)")
        }
        if root.source == "sysprompt" {
            let op = root.operation ?? ""
            if leadProfiles.contains(op) { return Agent(id: "lead", bucket: .lead, label: "lead") }
            if otterRoles.contains(op) { return Agent(id: "otter:\(op)", bucket: .otter, label: op, role: op) }
            var name = op
            if name.hasPrefix("subagent_") { name.removeFirst("subagent_".count) }
            if name.isEmpty { name = "subagent" }
            return Agent(id: "subagent:\(name)", bucket: .subagent, label: name)
        }
        let head = (root.head ?? "").drop(while: { $0.isWhitespace })
        if let match = head.range(of: #"^You are the (\w+) subagent"#, options: [.regularExpression, .caseInsensitive]) {
            let words = head[match].split(separator: " ")
            if words.count >= 4 {
                let name = words[3].lowercased()
                return Agent(id: "subagent:\(name)", bucket: .subagent, label: name)
            }
        }
        if head.range(of: #"^You are a Summarizer"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return Agent(id: "housekeeping", bucket: .housekeeping, label: "housekeeping")
        }
        let src = root.source ?? "?"
        let op = root.operation ?? "?"
        return Agent(id: "unknown:\(src)/\(op)", bucket: .unknown, label: "unknown (\(src)/\(op))")
    }

    /// Map<node_id, root | nil> for one session. Memoized path compression,
    /// no hop cap, cycle-safe. A `nil` value means the chain is broken.
    public static func resolveRoots(_ nodes: [NodeRecord]) -> [Int: RootDescriptor?] {
        var parent: [Int: Int?] = [:]
        var meta: [Int: RootDescriptor] = [:]
        parent.reserveCapacity(nodes.count)
        for n in nodes {
            parent[n.nodeID] = .some(n.parentNodeID)
            meta[n.nodeID] = RootDescriptor(source: n.source, operation: n.operation, head: n.head)
        }
        var rootOf: [Int: RootDescriptor?] = [:]
        rootOf.reserveCapacity(nodes.count)
        for start in parent.keys {
            if rootOf[start] != nil { continue }
            var trail: [Int] = []
            var onPath = Set<Int>()
            var cur = start
            var root: RootDescriptor?
            while true {
                if let known = rootOf[cur] { root = known; break }
                if onPath.contains(cur) { root = nil; break }
                onPath.insert(cur)
                trail.append(cur)
                guard let p = parent[cur] else { root = nil; break }
                guard let pid = p else { root = meta[cur]; break }
                if parent[pid] == nil { root = nil; break }
                cur = pid
            }
            for id in trail { rootOf[id] = .some(root) }
        }
        return rootOf
    }
}

/// Current Otter role pins from `~/.config/devin/agents/*.md`, used only to
/// flag pin drift (a role that ran a model other than the one pinned for it).
public enum Pins {
    public static func load(agentsDir: URL = DevinPaths.agentsDirectory, sidecar: URL = DevinPaths.modelsSidecar) -> [String: String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: agentsDir.path) else { return [:] }
        var sidecarRoles: Set<String>?
        if let data = try? Data(contentsOf: sidecar),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let roles = json["roles"] as? [String: Any] {
            sidecarRoles = Set(roles.keys)
        }
        var pinByRole: [String: String] = [:]
        for f in files where f.hasSuffix(".md") {
            let role = String(f.dropLast(3))
            guard let body = try? String(contentsOf: agentsDir.appendingPathComponent(f), encoding: .utf8) else { continue }
            if let sidecarRoles { if !sidecarRoles.contains(role) { continue } }
            else if !body.contains("Otter Swarm") { continue }
            for line in body.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("model:") {
                    let model = trimmed.dropFirst("model:".count).trimmingCharacters(in: .whitespaces)
                    if !model.isEmpty { pinByRole[role] = model }
                    break
                }
            }
        }
        return pinByRole
    }
}
