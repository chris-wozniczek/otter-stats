import Foundation

/// Read-only access to the Devin CLI sessions database. Port of Otter Swarm's
/// `scripts/telemetry.mjs` query layer: same schema sniff, same both-units
/// epoch handling, same duplicate collapsing.
public final class SessionsStore {
    public let path: String
    private let db: SQLiteDatabase
    public let hasNodeColumns: Bool

    private static let requiredTables: [String: [String]] = [
        "sessions": ["id", "model", "title", "created_at", "last_activity_at", "working_directory", "workspace_dirs"],
        "message_nodes": ["session_id", "chat_message", "created_at"],
    ]

    public init(path: String = DevinPaths.defaultSessionsDB.path) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw OtterStatsError.databaseMissing(path: path)
        }
        self.path = path
        db = try SQLiteDatabase(readOnlyPath: path)
        try Self.sniffSchema(db)
        let cols = Set(try db.query("PRAGMA table_info(message_nodes)").compactMap { $0["name"].string })
        hasNodeColumns = cols.contains("node_id") && cols.contains("parent_node_id")
    }

    private static func sniffSchema(_ db: SQLiteDatabase) throws {
        let tables = Set(try db.query("SELECT name FROM sqlite_master WHERE type='table'").compactMap { $0["name"].string })
        for (table, columns) in requiredTables {
            guard tables.contains(table) else { throw OtterStatsError.schemaDrift("table '\(table)' is missing") }
            let present = Set(try db.query("PRAGMA table_info(\(table))").compactMap { $0["name"].string })
            for c in columns where !present.contains(c) {
                throw OtterStatsError.schemaDrift("\(table).\(c) is missing")
            }
        }
        let rows = try db.scalarInt("SELECT COUNT(*) FROM message_nodes")
        if rows > 0 {
            let probed = try db.scalarInt("SELECT COUNT(*) FROM message_nodes WHERE json_extract(chat_message,'$.role') IS NOT NULL OR json_extract(chat_message,'$.metadata.generation_model') IS NOT NULL")
            if probed == 0 { throw OtterStatsError.schemaDrift("message_nodes rows no longer expose $.role / $.metadata.generation_model") }
        }
    }

    // MARK: turns

    public func assistantTurns(sessionIDs: [String]? = nil, sinceSec: Int? = nil, limit: Int = 500_000) throws -> TurnFetch {
        var clauses = ["json_extract(chat_message,'$.role')='assistant'", "json_extract(chat_message,'$.metadata.generation_model') IS NOT NULL"]
        var params: [SQLiteDatabase.Value] = []
        if let sessionIDs {
            if sessionIDs.isEmpty { return TurnFetch(turns: [], duplicates: 0, truncated: false) }
            clauses.append("session_id IN (\(Array(repeating: "?", count: sessionIDs.count).joined(separator: ",")))")
            params.append(contentsOf: sessionIDs.map { .text($0) })
        }
        if let sinceSec {
            clauses.append("((created_at <= 1000000000000 AND created_at >= ?) OR (created_at > 1000000000000 AND created_at >= ?))")
            params.append(.integer(Int64(sinceSec)))
            params.append(.integer(Int64(sinceSec) * 1000))
        }
        params.append(.integer(Int64(limit)))
        let nodeCol = hasNodeColumns ? "node_id," : "NULL AS node_id,"
        let sql = """
        SELECT session_id, rowid AS row_id, \(nodeCol)
               json_extract(chat_message,'$.message_id') AS message_id,
               json_extract(chat_message,'$.metadata.request_id') AS request_id,
               json_extract(chat_message,'$.metadata.generation_model') AS model,
               created_at,
               json_extract(chat_message,'$.metadata.metrics.input_tokens') AS input_tokens,
               json_extract(chat_message,'$.metadata.metrics.output_tokens') AS output_tokens,
               json_extract(chat_message,'$.metadata.metrics.cache_read_tokens') AS cache_read_tokens,
               json_extract(chat_message,'$.metadata.metrics.cache_creation_tokens') AS cache_creation_tokens,
               json_extract(chat_message,'$.metadata.metrics.total_time_ms') AS total_time_ms,
               json_extract(chat_message,'$.metadata.metrics.ttft_ms') AS ttft_ms
        FROM message_nodes WHERE \(clauses.joined(separator: " AND "))
        ORDER BY (CASE WHEN created_at > 1000000000000 THEN created_at / 1000 ELSE created_at END) DESC LIMIT ?
        """
        let rows = try db.query(sql, params)
        var seen = Set<String>()
        var duplicates = 0
        var turns: [Turn] = []
        turns.reserveCapacity(rows.count)
        for r in rows {
            let sid = r["session_id"].string ?? ""
            let key: String
            if let mid = r["message_id"].string { key = "\(sid)/\(mid)" }
            else if let rid = r["request_id"].string { key = "\(sid)/req:\(rid)" }
            else { key = "\(sid)/row:\(r["row_id"].int64 ?? 0)" }
            if seen.contains(key) { duplicates += 1; continue }
            seen.insert(key)
            guard let ts = epochSeconds(r["created_at"].double) else { continue }
            if let sinceSec, ts < sinceSec { continue }
            let inTok = r["input_tokens"]
            let outTok = r["output_tokens"]
            turns.append(Turn(
                sessionID: sid,
                nodeID: r["node_id"].int64.map(Int.init),
                model: r["model"].string ?? "",
                ts: ts,
                seq: Int(r["row_id"].int64 ?? 0),
                input: Int(inTok.int64 ?? 0),
                output: Int(outTok.int64 ?? 0),
                cacheRead: Int(r["cache_read_tokens"].int64 ?? 0),
                cacheCreation: Int(r["cache_creation_tokens"].int64 ?? 0),
                modelMs: Int(r["total_time_ms"].int64 ?? 0),
                ttftMs: Int(r["ttft_ms"].int64 ?? 0),
                metricsMissing: inTok.isNull && outTok.isNull
            ))
        }
        turns.sort { $0.ts != $1.ts ? $0.ts < $1.ts : $0.seq < $1.seq }
        return TurnFetch(turns: turns, duplicates: duplicates, truncated: rows.count == limit)
    }

    // MARK: sessions

    public func sessions(sessionIDs: [String]? = nil, sinceSec: Int? = nil, limit: Int = 500) throws -> [SessionRecord] {
        var clauses: [String] = []
        var params: [SQLiteDatabase.Value] = []
        if let sessionIDs {
            if sessionIDs.isEmpty { return [] }
            clauses.append("id IN (\(Array(repeating: "?", count: sessionIDs.count).joined(separator: ",")))")
            params.append(contentsOf: sessionIDs.map { .text($0) })
        }
        if let sinceSec {
            clauses.append("(created_at >= ? OR created_at >= ? OR last_activity_at >= ? OR last_activity_at >= ?)")
            let s = Int64(sinceSec)
            params.append(contentsOf: [.integer(s), .integer(s * 1000), .integer(s), .integer(s * 1000)])
        }
        var sql = "SELECT id, title, model, working_directory, workspace_dirs, created_at, last_activity_at FROM sessions"
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY created_at DESC"
        if sinceSec == nil { sql += " LIMIT ?"; params.append(.integer(Int64(limit))) }
        let rows = try db.query(sql, params)
        var out: [SessionRecord] = []
        for r in rows {
            var dirs: [String] = []
            if let raw = r["workspace_dirs"].string, let data = raw.data(using: .utf8) {
                if let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                    dirs = arr.compactMap { $0 as? String }
                } else if !raw.isEmpty {
                    dirs = [raw]
                }
            }
            let created = epochSeconds(r["created_at"].double)
            let last = epochSeconds(r["last_activity_at"].double)
            if let sinceSec, (created ?? 0) < sinceSec, (last ?? 0) < sinceSec { continue }
            out.append(SessionRecord(
                id: r["id"].string ?? "",
                title: r["title"].string ?? "",
                leadModel: r["model"].string ?? "",
                workingDirectory: r["working_directory"].string ?? "",
                workspaceDirs: dirs,
                createdSec: created,
                lastActivitySec: last
            ))
        }
        out.sort { ($0.createdSec ?? 0) > ($1.createdSec ?? 0) }
        return Array(out.prefix(limit))
    }

    /// Sessions active in the window plus any session the turns reference
    /// that the row cap dropped, so no turn is orphaned from its session.
    public func sessionsCovering(sinceSec: Int?, turns: [Turn], limit: Int = 300) throws -> [SessionRecord] {
        let listed = try sessions(sinceSec: sinceSec, limit: limit)
        let have = Set(listed.map(\.id))
        let missing = Array(Set(turns.map(\.sessionID)).subtracting(have))
        if missing.isEmpty { return listed }
        return listed + (try sessions(sessionIDs: missing))
    }

    // MARK: node graph

    private static let nodeSQL = """
    SELECT session_id, node_id, parent_node_id, created_at,
      json_extract(chat_message,'$.role') AS role,
      json_extract(chat_message,'$.message_id') AS message_id,
      json_extract(chat_message,'$.tool_call_id') AS tool_call_id,
      json_extract(chat_message,'$.metadata.is_user_input') AS is_user_input,
      json_extract(chat_message,'$.metadata.telemetry.source') AS src,
      json_extract(chat_message,'$.metadata.telemetry.operation') AS op,
      CASE WHEN parent_node_id IS NULL AND COALESCE(json_extract(chat_message,'$.metadata.telemetry.source'),'') != 'sysprompt'
           THEN substr(CASE WHEN json_type(chat_message,'$.content')='text' THEN json_extract(chat_message,'$.content') ELSE json_extract(chat_message,'$.content[0].text') END, 1, 80)
           ELSE NULL END AS head
      FROM message_nodes WHERE session_id IN (%IDS%)
    """

    public func nodeGraph(sessionIDs: [String]) throws -> [String: [NodeRecord]] {
        guard hasNodeColumns else {
            throw OtterStatsError.schemaDrift("message_nodes.node_id / parent_node_id missing — the agent tree cannot be walked")
        }
        var bySession: [String: [NodeRecord]] = [:]
        let ids = Array(Set(sessionIDs))
        var i = 0
        while i < ids.count {
            let chunk = Array(ids[i..<min(i + 400, ids.count)])
            i += 400
            let sql = Self.nodeSQL.replacingOccurrences(of: "%IDS%", with: Array(repeating: "?", count: chunk.count).joined(separator: ","))
            let rows = try db.query(sql, chunk.map { .text($0) })
            for r in rows {
                let sid = r["session_id"].string ?? ""
                let isInput: Bool = {
                    switch r["is_user_input"] {
                    case .integer(let v): return v == 1
                    case .text(let s): return s == "true" || s == "1"
                    default: return false
                    }
                }()
                bySession[sid, default: []].append(NodeRecord(
                    nodeID: Int(r["node_id"].int64 ?? 0),
                    parentNodeID: r["parent_node_id"].int64.map(Int.init),
                    role: r["role"].string,
                    messageID: r["message_id"].string,
                    toolCallID: r["tool_call_id"].string,
                    isUserInput: isInput,
                    source: r["src"].string,
                    operation: r["op"].string,
                    head: r["head"].string,
                    ts: epochSeconds(r["created_at"].double)
                ))
            }
        }
        return bySession
    }

    public func totalNodeCount() throws -> Int {
        Int(try db.scalarInt("SELECT COUNT(*) FROM message_nodes"))
    }
}
