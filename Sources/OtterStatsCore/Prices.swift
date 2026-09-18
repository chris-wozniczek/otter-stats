import Foundation

/// Price snapshot compatible with Otter Swarm's `~/.config/devin/otter/prices.json`
/// (`otter-prices/1`). Otter Stats reads and writes the same file so both tools
/// agree on costs.
public struct PriceSnapshot: Sendable {
    public static let schema = "otter-prices/1"

    public var prices: [String: ModelPrice]
    public var generatedAt: Date?
    public var source: String?

    public init(prices: [String: ModelPrice] = [:], generatedAt: Date? = nil, source: String? = nil) {
        self.prices = prices
        self.generatedAt = generatedAt
        self.source = source
    }

    public static let empty = PriceSnapshot()

    /// SWE-1.7 (Medium) list price, $0.50 / $0.20 / $2.50 per 1M input / cached / output.
    public static let swe17Medium = (model: "swe-1-7-medium", price: ModelPrice(free: false, input: 0.5e-6, cached: 0.2e-6, output: 2.5e-6))

    /// The paid rate free-tier usage is compared against: the snapshot's explicit
    /// SWE-1.7 Medium entry when listed as paid, otherwise the built-in SWE-1.7
    /// Medium list price. Plain `swe-1-7` and Lightning entries are never used.
    public var referenceRate: (model: String, price: ModelPrice) {
        let candidates = prices.filter { Self.isSWE17Medium($0.key) && !$0.value.free }
        return candidates.min { $0.key < $1.key }.map { (model: $0.key, price: $0.value) } ?? Self.swe17Medium
    }

    private static func isSWE17Medium(_ id: String) -> Bool {
        let s = id.lowercased()
        let swe17 = s.hasPrefix("swe-1.7") || s.hasPrefix("swe-1-7") || s.hasPrefix("swe-17")
        return swe17 && s.contains("medium")
    }

    /// Tolerant read: a missing or corrupt file is an empty snapshot.
    public static func read(from url: URL = DevinPaths.defaultPrices) -> PriceSnapshot {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .empty }
        var prices: [String: ModelPrice] = [:]
        for (uid, raw) in json["prices"] as? [String: Any] ?? [:] {
            guard let p = raw as? [String: Any] else { continue }
            let free = p["free"] as? Bool ?? false
            let input = (p["input"] as? NSNumber)?.doubleValue ?? 0
            prices[uid] = ModelPrice(
                free: free,
                input: input,
                cached: (p["cached"] as? NSNumber)?.doubleValue ?? input,
                output: (p["output"] as? NSNumber)?.doubleValue ?? 0,
                cacheWrite: (p["cache_write"] as? NSNumber)?.doubleValue
            )
        }
        let generated = (json["generated_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return PriceSnapshot(prices: prices, generatedAt: generated, source: url.path)
    }

    public func write(to url: URL = DevinPaths.defaultPrices, now: Date = Date()) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var table: [String: Any] = [:]
        for (uid, p) in prices {
            var row: [String: Any] = ["free": p.free, "input": p.input, "cached": p.cached, "output": p.output]
            if let w = p.cacheWrite { row["cache_write"] = w }
            table[uid] = row
        }
        let payload: [String: Any] = [
            "schema": Self.schema,
            "generated_at": ISO8601DateFormatter().string(from: now),
            "source": "devin models list",
            "prices": table,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let tmp = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        try data.write(to: tmp)
        _ = try? fm.removeItem(at: url)
        try fm.moveItem(at: tmp, to: url)
    }

    /// Parses `devin models list --format json`. `cost_summary` looks like
    /// "$3 / 1M Input · $0.3 / 1M Cached input · $15 / 1M Output".
    public static func parse(modelsList data: Data) -> [String: ModelPrice] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        let families: [[String: Any]]
        if let arr = json as? [[String: Any]] { families = arr }
        else if let obj = json as? [String: Any], let arr = obj["families"] as? [[String: Any]] { families = arr }
        else { return [:] }
        var out: [String: ModelPrice] = [:]
        for family in families {
            for v in family["variants"] as? [[String: Any]] ?? [] {
                guard let uid = v["model_uid"] as? String else { continue }
                if let tier = v["cost_tier"] as? String, tier.lowercased() == "free" {
                    out[uid] = ModelPrice(free: true, input: 0, cached: 0, output: 0)
                    continue
                }
                let summary = v["cost_summary"] as? String ?? ""
                func grab(_ label: String) -> Double? {
                    let pattern = #"\$([0-9.]+)\s*/\s*1M\s*"# + label
                    guard let r = summary.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
                    let matched = String(summary[r])
                    guard let dollar = matched.firstIndex(of: "$") else { return nil }
                    let num = matched[matched.index(after: dollar)...].prefix { $0.isNumber || $0 == "." }
                    return Double(num).map { $0 / 1e6 }
                }
                guard let input = grab("Input"), let output = grab("Output") else { continue }
                out[uid] = ModelPrice(free: false, input: input, cached: grab("Cached input") ?? input, output: output)
            }
        }
        return out
    }

    /// Runs the Devin CLI to refresh the snapshot. Returns the number of priced models.
    @discardableResult
    public static func refreshFromCLI(to url: URL = DevinPaths.defaultPrices) throws -> PriceSnapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["devin", "models", "list", "--format", "json"]
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ACP_BACKEND")
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(DevinPaths.home.path)/.local/bin"]
        env["PATH"] = (extraPaths + [(env["PATH"] ?? "/usr/bin:/bin")]).joined(separator: ":")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw OtterStatsError.query("`devin models list` exited with status \(process.terminationStatus). Is the Devin CLI installed and signed in?")
        }
        let table = parse(modelsList: data)
        guard !table.isEmpty else { throw OtterStatsError.query("`devin models list` returned no priced models") }
        let snapshot = PriceSnapshot(prices: table, generatedAt: Date(), source: url.path)
        try snapshot.write(to: url)
        return snapshot
    }
}
