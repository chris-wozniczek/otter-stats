import Foundation
import XCTest
@testable import OtterStatsCore

final class AttributionTests: XCTestCase {
    func testClassifyRoot() {
        XCTAssertEqual(Attribution.classify(root: RootDescriptor(source: "sysprompt", operation: "normal", head: nil), model: "x").id, "lead")
        XCTAssertEqual(Attribution.classify(root: RootDescriptor(source: "sysprompt", operation: "plan", head: nil), model: "x").bucket, .lead)
        let reviewer = Attribution.classify(root: RootDescriptor(source: "sysprompt", operation: "reviewer", head: nil), model: "x")
        XCTAssertEqual(reviewer, Agent(id: "otter:reviewer", bucket: .otter, label: "reviewer", role: "reviewer"))
        XCTAssertEqual(Attribution.classify(root: RootDescriptor(source: "sysprompt", operation: "subagent_general", head: nil), model: "x"), Agent(id: "subagent:general", bucket: .subagent, label: "general"))
        XCTAssertEqual(Attribution.classify(root: RootDescriptor(source: "sysprompt", operation: "my-custom", head: nil), model: "x").id, "subagent:my-custom")
        XCTAssertEqual(Attribution.classify(root: RootDescriptor(source: "system", operation: "unknown", head: "You are the Sidekick subagent of Devin"), model: "x").id, "subagent:sidekick")
        XCTAssertEqual(Attribution.classify(root: RootDescriptor(source: "system", operation: "unknown", head: "\n   You are a Summarizer that summarizes"), model: "real").bucket, .housekeeping)
        XCTAssertEqual(Attribution.classify(root: RootDescriptor(source: "sysprompt", operation: "normal", head: nil), model: "compactor").bucket, .housekeeping)
        XCTAssertEqual(Attribution.classify(root: nil, model: "x").bucket, .unknown)
        XCTAssertEqual(Attribution.classify(root: RootDescriptor(source: "system", operation: "unknown", head: "something else"), model: "x").bucket, .unknown)
    }

    func testResolveRootsLongChainsOrphansCycles() {
        var nodes = [NodeRecord(nodeID: 1, parentNodeID: nil, role: nil, messageID: nil, toolCallID: nil, isUserInput: false, source: "sysprompt", operation: "normal", head: nil, ts: 0)]
        for i in 2...5000 {
            nodes.append(NodeRecord(nodeID: i, parentNodeID: i - 1, role: nil, messageID: nil, toolCallID: nil, isUserInput: false, source: "tool_result", operation: "exec", head: nil, ts: 0))
        }
        nodes.append(NodeRecord(nodeID: 9000, parentNodeID: 8999, role: nil, messageID: nil, toolCallID: nil, isUserInput: false, source: "assistant", operation: "inference", head: nil, ts: 0))
        nodes.append(NodeRecord(nodeID: 7000, parentNodeID: 7001, role: nil, messageID: nil, toolCallID: nil, isUserInput: false, source: "x", operation: "y", head: nil, ts: 0))
        nodes.append(NodeRecord(nodeID: 7001, parentNodeID: 7000, role: nil, messageID: nil, toolCallID: nil, isUserInput: false, source: "x", operation: "y", head: nil, ts: 0))
        let roots = Attribution.resolveRoots(nodes)
        XCTAssertEqual(roots[5000] ?? nil, RootDescriptor(source: "sysprompt", operation: "normal", head: nil))
        XCTAssertEqual(roots[9000] ?? RootDescriptor(source: "?", operation: nil, head: nil), nil)
        XCTAssertEqual(roots[7000] ?? RootDescriptor(source: "?", operation: nil, head: nil), nil)
    }
}

final class CubeTests: XCTestCase {
    static let now = 1_800_000_000
    var dbPath: String!
    var pricesURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("otter-stats-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("sessions.db").path
        pricesURL = dir.appendingPathComponent("prices.json")
        try FixtureDatabase.write(to: dbPath, nowSec: Self.now, days: 20, seed: 3)
        try FixtureDatabase.writeDemoPrices(to: pricesURL)
    }

    func testStoreOpensReadOnlyAndDedupes() throws {
        let store = try SessionsStore(path: dbPath)
        let fetch = try store.assistantTurns(sinceSec: Self.now - 30 * 86400)
        XCTAssertGreaterThan(fetch.turns.count, 50)
        XCTAssertGreaterThan(fetch.duplicates, 0, "fixture plants duplicate rows; they must be collapsed")
        XCTAssertFalse(fetch.truncated)
        let ids = Set(fetch.turns.map { "\($0.sessionID)/\($0.seq)" })
        XCTAssertEqual(ids.count, fetch.turns.count)
    }

    func testCubeBucketsSumToTotal() throws {
        let store = try SessionsStore(path: dbPath)
        let cube = try UsageCubeBuilder.build(store: store, nowSec: Self.now, pins: ["tester": "swe-1-7"], priceSnapshot: PriceSnapshot.read(from: pricesURL))
        XCTAssertEqual(cube.quality.turns, cube.facts.reduce(0) { $0 + $1.turns })
        let slice = UsageSlice(cube: cube, filter: UsageFilter(period: .all), now: Self.now)
        XCTAssertEqual(slice.totals.turns, cube.quality.turns)
        XCTAssertEqual(slice.byBucket.reduce(0) { $0 + $1.totals.turns }, slice.totals.turns)
        XCTAssertEqual(slice.byAgent.reduce(0) { $0 + $1.totals.turns }, slice.totals.turns)
        XCTAssertEqual(slice.byModel.reduce(0) { $0 + $1.totals.turns }, slice.totals.turns)
        XCTAssertTrue(slice.byBucket.contains { $0.key == .lead })
        XCTAssertTrue(slice.byBucket.contains { $0.key == .otter })
        XCTAssertTrue(slice.byBucket.contains { $0.key == .housekeeping })
        XCTAssertGreaterThan(slice.prompts, 0)
        XCTAssertGreaterThan(slice.tools.count, 0)
        XCTAssertGreaterThan(slice.totals.costUSD, 0)
        XCTAssertTrue(slice.totals.costComplete, "every fixture model is priced")
    }

    func testPricingClassesAndEquivalentCost() throws {
        let store = try SessionsStore(path: dbPath)
        var snapshot = PriceSnapshot.read(from: pricesURL)
        snapshot.prices["compactor"] = nil
        XCTAssertEqual(snapshot.referenceRate.model, "swe-1-7-medium", "Medium wins over Lightning")
        let cube = try UsageCubeBuilder.build(store: store, nowSec: Self.now, pins: [:], priceSnapshot: snapshot)
        XCTAssertEqual(cube.referenceModel, "swe-1-7-medium")
        let all = UsageSlice(cube: cube, filter: UsageFilter(period: .all), now: Self.now)
        let t = all.totals
        XCTAssertEqual(t.paidTokens + t.freeTokens + t.unknownTokens, t.tokens)
        XCTAssertGreaterThan(t.freeTokens, 0, "swe-2-high is free tier")
        XCTAssertGreaterThan(t.unknownTokens, 0, "compactor has no price")
        XCTAssertFalse(t.costComplete)
        XCTAssertGreaterThan(t.equivalentUSD, 0)

        let free = all.byModel.first { cube.models[$0.key].id == "swe-2-high" }!.totals
        let ref = snapshot.prices["swe-1-7-medium"]!
        XCTAssertEqual(ref.input, 0.5e-6); XCTAssertEqual(ref.cached, 0.2e-6); XCTAssertEqual(ref.output, 2.5e-6)
        XCTAssertEqual(free.costUSD, 0)
        XCTAssertEqual(free.equivalentUSD, ref.rate(input: free.input, cacheRead: free.cacheRead, cacheCreation: free.cacheCreation, output: free.output), accuracy: 1e-9)
        let freeTotal = all.byModel.filter { cube.models[$0.key].pricing == .free }.reduce(0.0) { $0 + $1.totals.equivalentUSD }
        XCTAssertEqual(t.equivalentUSD, freeTotal, accuracy: 1e-9, "only free-tier usage is simulated")

        for cls in PricingClass.allCases {
            var f = UsageFilter(period: .all); f.pricing = [cls]
            let s = UsageSlice(cube: cube, filter: f, now: Self.now)
            XCTAssertTrue(s.byModel.allSatisfy { cube.models[$0.key].pricing == cls }, "\(cls)")
            XCTAssertGreaterThan(s.totals.turns, 0, "\(cls)")
            XCTAssertTrue(s.sessions.allSatisfy { $0.totals.turns > 0 }, "\(cls): sessions without matching turns are out of scope")
            XCTAssertLessThanOrEqual(s.prompts, all.prompts)
        }
        let builtin = PriceSnapshot(prices: ["swe-2-high": ModelPrice(free: true, input: 0, cached: 0, output: 0)]).referenceRate
        XCTAssertEqual(builtin.model, "swe-1-7-medium", "falls back to the built-in SWE-1.7 Medium rate")
        XCTAssertEqual(builtin.price.rate(input: 1_000_000, cacheRead: 1_000_000, cacheCreation: 0, output: 1_000_000), 3.2, accuracy: 1e-9)
        let lightningOnly = PriceSnapshot(prices: ["swe-1-7-lightning": ModelPrice(free: false, input: 1, cached: 1, output: 1)]).referenceRate
        XCTAssertEqual(lightningOnly.model, "swe-1-7-medium", "Lightning is never the reference")
        let plain = PriceSnapshot(prices: ["swe-1-7": ModelPrice(free: false, input: 1, cached: 1, output: 1)]).referenceRate
        XCTAssertEqual(plain.model, "swe-1-7", "a paid plain swe-1-7 entry is used as listed")
    }

    func testPeriodFilterNarrows() throws {
        let store = try SessionsStore(path: dbPath)
        let cube = try UsageCubeBuilder.build(store: store, nowSec: Self.now, pins: [:], priceSnapshot: .empty)
        let all = UsageSlice(cube: cube, filter: UsageFilter(period: .all), now: Self.now)
        let week = UsageSlice(cube: cube, filter: UsageFilter(period: .week), now: Self.now)
        XCTAssertLessThan(week.totals.turns, all.totals.turns)
        XCTAssertGreaterThan(week.totals.turns, 0)
        XCTAssertFalse(all.totals.costComplete, "no snapshot → every turn unpriced")
        XCTAssertEqual(week.filledTimeline(now: Self.now).count, 7, "rolling presets cover exactly N calendar dates")
        XCTAssertEqual(UsageSlice(cube: cube, filter: UsageFilter(period: .month), now: Self.now).filledTimeline(now: Self.now).count, 30)
        XCTAssertEqual(UsageSlice(cube: cube, filter: UsageFilter(period: .today), now: Self.now).filledTimeline(now: Self.now).count, 1)
        var byBucket = UsageFilter(period: .all)
        byBucket.buckets = [.lead]
        let leadOnly = UsageSlice(cube: cube, filter: byBucket, now: Self.now)
        XCTAssertEqual(leadOnly.byBucket.map(\.key), [.lead])
    }

    func testFilledTimelineKeepsNewestDatesWhenCapped() throws {
        let store = try SessionsStore(path: dbPath)
        let cube = try UsageCubeBuilder.build(store: store, nowSec: Self.now, pins: [:], priceSnapshot: .empty)
        let cal = ISODay.calendar
        let today = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(Self.now)))
        let longAgo = cal.date(byAdding: .day, value: -600, to: today)!
        let slice = UsageSlice(cube: cube, filter: UsageFilter.custom(from: longAgo, to: today), now: Self.now)
        let points = slice.filledTimeline(now: Self.now)
        XCTAssertEqual(points.last?.day, isoDay(Self.now), "the newest date is never dropped")
        XCTAssertLessThanOrEqual(points.count, 400)
        XCTAssertGreaterThanOrEqual(points.first!.day, isoDay(cube.from), "start is clamped to the embedded window")
        let capped = slice.filledTimeline(now: Self.now, maxPoints: 10)
        XCTAssertEqual(capped.count, 10)
        XCTAssertEqual(capped.last?.day, isoDay(Self.now))
    }

    func testCustomRangeIsInclusiveByDay() throws {
        let store = try SessionsStore(path: dbPath)
        let cube = try UsageCubeBuilder.build(store: store, nowSec: Self.now, pins: [:], priceSnapshot: .empty)
        let all = UsageSlice(cube: cube, filter: UsageFilter(period: .all), now: Self.now)
        let nowDate = Date(timeIntervalSince1970: TimeInterval(Self.now))
        let cal = ISODay.calendar
        let today = cal.startOfDay(for: nowDate)
        let start = cal.date(byAdding: .day, value: -6, to: today)!

        let custom = UsageFilter.custom(from: today, to: start)
        XCTAssertEqual(custom.period, .custom)
        XCTAssertEqual(custom.fromSec, Int(start.timeIntervalSince1970), "endpoints are swapped and snapped")
        XCTAssertEqual(custom.toSec, Int(cal.date(byAdding: .day, value: 1, to: today)!.timeIntervalSince1970) - 1)

        let week = UsageSlice(cube: cube, filter: custom, now: Self.now)
        XCTAssertGreaterThan(week.totals.turns, 0)
        XCTAssertLessThan(week.totals.turns, all.totals.turns)
        XCTAssertEqual(week.filledTimeline(now: Self.now).count, 7)

        let single = UsageSlice(cube: cube, filter: .custom(from: today, to: today), now: Self.now)
        XCTAssertEqual(single.totals.turns, UsageSlice(cube: cube, filter: UsageFilter(period: .today), now: Self.now).totals.turns)

        var wide = UsageFilter.custom(from: Date(timeIntervalSince1970: 0), to: today)
        wide.buckets = [.lead]
        XCTAssertEqual(UsageSlice(cube: cube, filter: wide, now: Self.now).byBucket.map(\.key), [.lead])
    }

    func testPriceParsing() {
        let json = """
        {"families":[{"variants":[
          {"model_uid":"claude-opus-4-1","cost_tier":"Premium","cost_summary":"$15 / 1M Input · $1.5 / 1M Cached input · $75 / 1M Output"},
          {"model_uid":"swe-1-7","cost_tier":"Free","cost_summary":""},
          {"model_uid":"broken","cost_summary":"n/a"}
        ]}]}
        """
        let table = PriceSnapshot.parse(modelsList: Data(json.utf8))
        XCTAssertEqual(table["claude-opus-4-1"], ModelPrice(free: false, input: 15e-6, cached: 1.5e-6, output: 75e-6))
        XCTAssertEqual(table["swe-1-7"]?.free, true)
        XCTAssertNil(table["broken"])
    }

    func testFormatting() {
        XCTAssertEqual(Fmt.compact(1_234_567), "1.23M")
        XCTAssertEqual(Fmt.compact(12_300), "12.3k")
        XCTAssertEqual(Fmt.compact(999), "999")
        XCTAssertEqual(Fmt.usd(0.004), "$0.0040")
        XCTAssertEqual(Fmt.usd(12.3456), "$12.35")
        XCTAssertEqual(Fmt.usd(12.3456, complete: false), "≥$12.35")
        XCTAssertEqual(Fmt.duration(ms: 90_000), "1.5m")
        XCTAssertEqual(Fmt.percent(0.4567), "45.7%")
    }
}
