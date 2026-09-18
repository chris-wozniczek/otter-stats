import Foundation
import SQLite3

/// Writes a synthetic sessions.db with the live schema shape so the app can be
/// demoed and tested on machines without the Devin CLI. Never touches the real
/// database path.
public enum FixtureDatabase {
    public static func write(to path: String, nowSec: Int = Int(Date().timeIntervalSince1970), days: Int = 45, seed: UInt64 = 7) throws {
        _ = try? FileManager.default.removeItem(atPath: path)
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else { throw OtterStatsError.databaseOpenFailed(path: path, message: "cannot create fixture") }
        defer { sqlite3_close(db) }
        func exec(_ sql: String) throws {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw OtterStatsError.query(String(cString: sqlite3_errmsg(db))) }
        }
        try exec("CREATE TABLE sessions (id TEXT PRIMARY KEY, working_directory TEXT, model TEXT, created_at INTEGER, last_activity_at INTEGER, title TEXT, workspace_dirs TEXT)")
        try exec("CREATE TABLE message_nodes (row_id INTEGER PRIMARY KEY, session_id TEXT, node_id INTEGER, parent_node_id INTEGER, chat_message TEXT, created_at INTEGER)")
        try exec("BEGIN")

        var rng = SplitMix64(seed: seed)
        let projects = ["/Users/me/code/otter-swarm", "/Users/me/code/chris-website", "/Users/me/code/llm-visual-bench", "/Users/me/code/devin-macos"]
        let leadModels = ["claude-opus-4-1", "swe-2-high", "gpt-5"]
        let workerModels = ["swe-1-7", "claude-sonnet-4-5", "gemini-2-5-pro"]
        let titles = ["Fix flaky e2e tests", "Add usage dashboard", "Refactor telemetry engine", "Ship menu bar app", "Write launch post", "Investigate cache misses", "Migrate CI to Actions", "Polish onboarding"]
        let tools = ["exec", "read", "edit", "grep", "write", "git", "browser", "computer"]

        func insertSession(_ id: String, _ wd: String, _ model: String, _ created: Int, _ last: Int, _ title: String) throws {
            try exec("INSERT INTO sessions VALUES ('\(id)', '\(wd)', '\(model)', \(created), \(last), '\(title.replacingOccurrences(of: "'", with: "''"))', '[\"\(wd)\"]')")
        }
        func insertNode(_ sid: String, _ node: Int, _ parent: Int?, _ body: [String: Any], _ created: Int) throws {
            let data = try JSONSerialization.data(withJSONObject: body)
            let json = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "'", with: "''")
            try exec("INSERT INTO message_nodes (session_id, node_id, parent_node_id, chat_message, created_at) VALUES ('\(sid)', \(node), \(parent.map(String.init) ?? "NULL"), '\(json)', \(created))")
        }
        func sys(_ src: String, _ op: String, _ content: String = "") -> [String: Any] {
            ["role": "system", "content": content, "metadata": ["telemetry": ["source": src, "operation": op]]]
        }
        func user(_ content: String, input: Bool = true) -> [String: Any] {
            ["role": "user", "content": content, "metadata": ["is_user_input": input, "telemetry": ["source": "user", "operation": "unknown"]]]
        }
        func tool(_ op: String, _ callID: String) -> [String: Any] {
            ["role": "tool", "content": "ok", "tool_call_id": callID, "metadata": ["telemetry": ["source": "tool_result", "operation": op]]]
        }
        var msgSeq = 0
        func turn(_ model: String, input: Int, output: Int, cache: Int, ms: Int, ttft: Int) -> [String: Any] {
            msgSeq += 1
            return [
                "message_id": "m\(msgSeq)",
                "role": "assistant",
                "content": "…",
                "metadata": [
                    "generation_model": model,
                    "request_id": "r-\(msgSeq)",
                    "metrics": ["input_tokens": input, "output_tokens": output, "cache_read_tokens": cache, "cache_creation_tokens": 0, "total_time_ms": ms, "ttft_ms": ttft],
                    "telemetry": ["source": "assistant", "operation": "inference"],
                ],
            ]
        }

        var sessionCounter = 0
        for dayOffset in stride(from: days - 1, through: 0, by: -1) {
            let weekday = (nowSec / 86400 - dayOffset) % 7
            let sessionsToday = weekday >= 5 ? Int(rng.next(upperBound: 2)) : 1 + Int(rng.next(upperBound: 3))
            for _ in 0..<sessionsToday {
                sessionCounter += 1
                let sid = "sess-\(String(format: "%04d", sessionCounter))"
                let start = nowSec - dayOffset * 86400 - Int(rng.next(upperBound: 14 * 3600)) - 3600
                let project = projects[Int(rng.next(upperBound: UInt64(projects.count)))]
                let lead = leadModels[Int(rng.next(upperBound: UInt64(leadModels.count)))]
                let title = titles[Int(rng.next(upperBound: UInt64(titles.count)))]
                var node = 0
                var ts = start
                var lastTs = start
                func nextNode() -> Int { node += 1; return node }

                // lead subtree
                let root = nextNode()
                try insertNode(sid, root, nil, sys("sysprompt", "normal"), ts)
                var parent = root
                let prompts = 1 + Int(rng.next(upperBound: 4))
                for p in 0..<prompts {
                    ts += 30 + Int(rng.next(upperBound: 600))
                    let u = nextNode(); try insertNode(sid, u, parent, user("prompt \(p + 1)"), ts); parent = u
                    let turns = 2 + Int(rng.next(upperBound: 7))
                    for _ in 0..<turns {
                        ts += 5 + Int(rng.next(upperBound: 90))
                        let a = nextNode()
                        let tokIn = 2_000 + Int(rng.next(upperBound: 30_000))
                        let msgBody = turn(lead, input: tokIn, output: 100 + Int(rng.next(upperBound: 2_500)), cache: Int(rng.next(upperBound: 60_000)), ms: 1_500 + Int(rng.next(upperBound: 20_000)), ttft: 200 + Int(rng.next(upperBound: 2_000)))
                        try insertNode(sid, a, parent, msgBody, ts)
                        if rng.next(upperBound: 10) == 0 { try insertNode(sid, nextNode(), a, msgBody, ts) } // duplicate persistence
                        parent = a
                        let t = nextNode()
                        try insertNode(sid, t, parent, tool(tools[Int(rng.next(upperBound: UInt64(tools.count)))], "call-\(t)"), ts + 2)
                        parent = t
                        lastTs = ts + 2
                    }
                    if rng.next(upperBound: 4) == 0 {
                        ts += 20
                        let c = nextNode()
                        try insertNode(sid, c, parent, turn("compactor", input: 40_000 + Int(rng.next(upperBound: 60_000)), output: 1_500, cache: 0, ms: 8_000, ttft: 900), ts)
                        parent = c
                    }
                }
                // otter workers
                if project.hasSuffix("otter-swarm") || rng.next(upperBound: 3) == 0 {
                    for role in ["researcher", "implementer", "reviewer", "tester"] where rng.next(upperBound: 2) == 0 {
                        let r = nextNode()
                        try insertNode(sid, r, nil, sys("sysprompt", role), ts)
                        var wp = r
                        let model = workerModels[Int(rng.next(upperBound: UInt64(workerModels.count)))]
                        for _ in 0..<(3 + Int(rng.next(upperBound: 12))) {
                            ts += 5 + Int(rng.next(upperBound: 60))
                            let a = nextNode()
                            try insertNode(sid, a, wp, turn(model, input: 1_000 + Int(rng.next(upperBound: 15_000)), output: 100 + Int(rng.next(upperBound: 1_500)), cache: Int(rng.next(upperBound: 20_000)), ms: 1_000 + Int(rng.next(upperBound: 12_000)), ttft: 150 + Int(rng.next(upperBound: 1_500))), ts)
                            wp = a
                            let t = nextNode()
                            try insertNode(sid, t, wp, tool(tools[Int(rng.next(upperBound: 4))], "call-\(t)"), ts + 1)
                            wp = t
                            lastTs = ts + 1
                        }
                    }
                }
                // devin subagents
                if rng.next(upperBound: 2) == 0 {
                    let e = nextNode()
                    try insertNode(sid, e, nil, sys("sysprompt", "subagent_explore"), ts)
                    var ep = e
                    for _ in 0..<(2 + Int(rng.next(upperBound: 6))) {
                        ts += 10
                        let a = nextNode()
                        try insertNode(sid, a, ep, turn(lead, input: 3_000 + Int(rng.next(upperBound: 8_000)), output: 50 + Int(rng.next(upperBound: 400)), cache: 0, ms: 2_000, ttft: 300), ts)
                        ep = a
                    }
                }
                if rng.next(upperBound: 5) == 0 {
                    let sk = nextNode()
                    try insertNode(sid, sk, nil, sys("system", "unknown", "You are the Sidekick subagent of Devin, an AI software engineer"), ts)
                    let a = nextNode()
                    try insertNode(sid, a, sk, turn("swe-2-high", input: 2_000, output: 200, cache: 0, ms: 1_000, ttft: 200), ts + 5)
                }
                if rng.next(upperBound: 12) == 0 {
                    try insertNode(sid, nextNode(), 99_999, turn(lead, input: 500, output: 20, cache: 0, ms: 700, ttft: 100), ts + 9) // orphan
                }
                try insertSession(sid, project, lead, start, lastTs, title)
            }
        }
        try exec("COMMIT")
    }

    public static func writeDemoPrices(to url: URL) throws {
        let snapshot = PriceSnapshot(prices: [
            "claude-opus-4-1": ModelPrice(free: false, input: 15e-6, cached: 1.5e-6, output: 75e-6),
            "claude-sonnet-4-5": ModelPrice(free: false, input: 3e-6, cached: 0.3e-6, output: 15e-6),
            "gpt-5": ModelPrice(free: false, input: 1.25e-6, cached: 0.125e-6, output: 10e-6),
            "gemini-2-5-pro": ModelPrice(free: false, input: 1.25e-6, cached: 0.31e-6, output: 10e-6),
            "swe-1-7": ModelPrice(free: true, input: 0, cached: 0, output: 0),
            "swe-2-high": ModelPrice(free: false, input: 2e-6, cached: 0.2e-6, output: 8e-6),
            "compactor": ModelPrice(free: true, input: 0, cached: 0, output: 0),
        ], generatedAt: Date(), source: url.path)
        try snapshot.write(to: url)
    }
}

struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func next(upperBound: UInt64) -> UInt64 { upperBound == 0 ? 0 : next() % upperBound }
}
