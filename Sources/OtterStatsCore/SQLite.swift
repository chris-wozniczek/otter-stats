import Foundation
import SQLite3

/// Minimal read-only SQLite wrapper. The sessions database belongs to the Devin
/// CLI; this app never opens it with write access.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    public init(readOnlyPath path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let uri = "file:\(path)?immutable=0&mode=ro"
        let rc = sqlite3_open_v2(uri, &db, flags | SQLITE_OPEN_URI, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let db { sqlite3_close(db) }
            throw OtterStatsError.databaseOpenFailed(path: path, message: message)
        }
        handle = db
        sqlite3_busy_timeout(db, 2000)
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    public enum Value: Equatable {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob(Data)

        public var string: String? {
            switch self {
            case .text(let s): return s
            case .integer(let i): return String(i)
            case .real(let d): return String(d)
            default: return nil
            }
        }

        public var int64: Int64? {
            switch self {
            case .integer(let i): return i
            case .real(let d): return Int64(d)
            case .text(let s): return Int64(s) ?? Double(s).map { Int64($0) }
            default: return nil
            }
        }

        public var double: Double? {
            switch self {
            case .integer(let i): return Double(i)
            case .real(let d): return d
            case .text(let s): return Double(s)
            default: return nil
            }
        }

        public var isNull: Bool { self == .null }
    }

    public struct Row {
        public let columns: [String: Int]
        public let values: [Value]

        public subscript(_ name: String) -> Value {
            guard let i = columns[name], i < values.count else { return .null }
            return values[i]
        }
    }

    public func query(_ sql: String, _ params: [Value] = []) throws -> [Row] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw OtterStatsError.query(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .null: sqlite3_bind_null(stmt, idx)
            case .integer(let v): sqlite3_bind_int64(stmt, idx, v)
            case .real(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, transient)
            case .blob(let d): _ = d.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(d.count), transient) }
            }
        }
        let count = Int(sqlite3_column_count(stmt))
        var columns: [String: Int] = [:]
        for i in 0..<count { columns[String(cString: sqlite3_column_name(stmt, Int32(i)))] = i }
        var rows: [Row] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw OtterStatsError.query(String(cString: sqlite3_errmsg(handle))) }
            var values: [Value] = []
            values.reserveCapacity(count)
            for i in 0..<count {
                let c = Int32(i)
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: values.append(.integer(sqlite3_column_int64(stmt, c)))
                case SQLITE_FLOAT: values.append(.real(sqlite3_column_double(stmt, c)))
                case SQLITE_TEXT: values.append(.text(String(cString: sqlite3_column_text(stmt, c))))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(stmt, c))
                    if let base = sqlite3_column_blob(stmt, c) { values.append(.blob(Data(bytes: base, count: n))) } else { values.append(.blob(Data())) }
                default: values.append(.null)
                }
            }
            rows.append(Row(columns: columns, values: values))
        }
        return rows
    }

    public func scalarInt(_ sql: String, _ params: [Value] = []) throws -> Int64 {
        try query(sql, params).first?.values.first?.int64 ?? 0
    }
}

public enum OtterStatsError: LocalizedError, Equatable {
    case databaseMissing(path: String)
    case databaseOpenFailed(path: String, message: String)
    case schemaDrift(String)
    case query(String)

    public var errorDescription: String? {
        switch self {
        case .databaseMissing(let path):
            return "Devin CLI sessions database not found at \(path). Install the Devin CLI or point Otter Stats at the database in Settings."
        case .databaseOpenFailed(let path, let message):
            return "Could not open \(path): \(message)"
        case .schemaDrift(let detail):
            return "sessions.db schema changed: \(detail)"
        case .query(let message):
            return "Query failed: \(message)"
        }
    }
}
