import Foundation
import Combine
import SwiftUI
import OtterStatsCore

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cost, tokens, turns, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cost: return "Estimated cost"
        case .tokens: return "Tokens"
        case .turns: return "Turns"
        case .none: return "Icon only"
        }
    }
}

enum SettingsKeys {
    static let dbPath = "sessionsDBPath"
    static let pricesPath = "pricesPath"
    static let refreshMinutes = "refreshMinutes"
    static let menuBarMetric = "menuBarMetric"
    static let menuBarPeriod = "menuBarPeriod"
    static let popoverPeriod = "popoverPeriod"
    static let demoMode = "demoMode"
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var cube: UsageCube = .empty
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var lastRefresh: Date?
    private var loadedSource: String?
    @Published var filter = UsageFilter(period: .week) {
        didSet { reslice() }
    }
    @Published private(set) var slice: UsageSlice = UsageSlice(cube: .empty, filter: UsageFilter())
    @Published private(set) var todaySlice: UsageSlice = UsageSlice(cube: .empty, filter: UsageFilter(period: .today))
    @Published private(set) var weekSlice: UsageSlice = UsageSlice(cube: .empty, filter: UsageFilter(period: .week))
    @Published private(set) var fortnightSlice: UsageSlice = UsageSlice(cube: .empty, filter: Self.fortnightFilter())

    @AppStorage(SettingsKeys.dbPath) var dbPathOverride: String = ""
    @AppStorage(SettingsKeys.pricesPath) var pricesPathOverride: String = ""
    @AppStorage(SettingsKeys.refreshMinutes) var refreshMinutes: Int = 5
    @AppStorage(SettingsKeys.menuBarMetric) var menuBarMetricRaw: String = MenuBarMetric.cost.rawValue
    @AppStorage(SettingsKeys.menuBarPeriod) var menuBarPeriodRaw: String = Period.today.rawValue
    @AppStorage(SettingsKeys.demoMode) var demoMode: Bool = false

    private var timer: Timer?
    private var fileSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var inflight = false
    private var refreshQueued = false

    var menuBarMetric: MenuBarMetric { MenuBarMetric(rawValue: menuBarMetricRaw) ?? .cost }
    var menuBarPeriod: Period { Period(rawValue: menuBarPeriodRaw) ?? .today }

    var resolvedDBPath: String {
        if demoMode { return Self.demoDBURL.path }
        return dbPathOverride.isEmpty ? DevinPaths.defaultSessionsDB.path : (dbPathOverride as NSString).expandingTildeInPath
    }

    var resolvedPricesURL: URL {
        if demoMode { return Self.demoPricesURL }
        return pricesPathOverride.isEmpty ? DevinPaths.defaultPrices : URL(fileURLWithPath: (pricesPathOverride as NSString).expandingTildeInPath)
    }

    var dbExists: Bool { FileManager.default.fileExists(atPath: resolvedDBPath) }

    static var demoDBURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OtterStats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("demo-sessions.db")
    }
    static var demoPricesURL: URL { demoDBURL.deletingLastPathComponent().appendingPathComponent("demo-prices.json") }

    private static func fortnightFilter(now: Int = Int(Date().timeIntervalSince1970)) -> UsageFilter {
        var f = UsageFilter(period: .month)
        let start = ISODay.calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(now)))
        f.fromSec = Int((ISODay.calendar.date(byAdding: .day, value: -13, to: start) ?? start).timeIntervalSince1970)
        return f
    }

    var menuBarTitle: String? {
        let s = menuBarPeriod == .today ? todaySlice : weekSlice
        switch menuBarMetric {
        case .none: return nil
        case .cost: return Fmt.usd(s.totals.costUSD, complete: s.totals.costComplete)
        case .tokens: return Fmt.compact(s.totals.tokens)
        case .turns: return Fmt.int(s.totals.turns)
        }
    }

    func start() {
        refresh()
        scheduleTimer()
        watchFile()
    }

    func scheduleTimer() {
        timer?.invalidate()
        let minutes = max(1, refreshMinutes)
        timer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func settingsChanged() {
        scheduleTimer()
        watchFile()
        refresh()
    }

    func refresh() {
        guard !inflight else { refreshQueued = true; return }
        inflight = true
        loading = true
        let path = resolvedDBPath
        let pricesURL = resolvedPricesURL
        let demo = demoMode
        Task.detached(priority: .userInitiated) {
            let result: Result<UsageCube, Error>
            do {
                if demo, !FileManager.default.fileExists(atPath: path) {
                    try FixtureDatabase.write(to: path)
                    try FixtureDatabase.writeDemoPrices(to: pricesURL)
                }
                let store = try SessionsStore(path: path)
                let cube = try UsageCubeBuilder.build(store: store, priceSnapshot: PriceSnapshot.read(from: pricesURL))
                result = .success(cube)
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inflight = false
                self.loading = false
                switch result {
                case .success(let cube):
                    self.cube = cube
                    self.loadedSource = path
                    self.error = nil
                    self.lastRefresh = Date()
                    self.reslice()
                case .failure(let err):
                    if self.loadedSource != path {
                        self.cube = .empty
                        self.loadedSource = nil
                        self.reslice()
                    }
                    self.error = Self.describe(err)
                }
                if self.refreshQueued {
                    self.refreshQueued = false
                    self.refresh()
                }
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? OtterStatsError)?.errorDescription ?? (error as NSError).localizedDescription
    }

    private func reslice() {
        slice = UsageSlice(cube: cube, filter: filter)
        todaySlice = UsageSlice(cube: cube, filter: UsageFilter(period: .today))
        weekSlice = UsageSlice(cube: cube, filter: UsageFilter(period: .week))
        fortnightSlice = UsageSlice(cube: cube, filter: Self.fortnightFilter())
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = nil
        if fileDescriptor >= 0 { close(fileDescriptor); fileDescriptor = -1 }
        let fd = open(resolvedDBPath, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.debouncedRefresh()
        }
        source.resume()
        fileSource = source
    }

    private var debounce: DispatchWorkItem?
    private func debouncedRefresh() {
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refresh() }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    // MARK: - Filter helpers

    func toggleAgent(_ id: String) { toggle(&filter.agents, id) }
    func toggleBucket(_ b: AgentBucket) { toggle(&filter.buckets, b) }
    func toggleModel(_ i: Int) { toggle(&filter.models, i) }
    func toggleProject(_ i: Int) { toggle(&filter.projects, i) }
    func toggleSession(_ i: Int) { toggle(&filter.sessions, i) }
    func clearSlicers() {
        var f = filter
        f.agents = []; f.buckets = []; f.models = []; f.projects = []; f.sessions = []; f.query = ""
        filter = f
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ v: T) {
        if set.contains(v) { set.remove(v) } else { set.insert(v) }
    }

    var activeChips: [(String, () -> Void)] {
        var chips: [(String, () -> Void)] = []
        for b in filter.buckets.sorted(by: { $0.rawValue < $1.rawValue }) { chips.append((b.label, { self.toggleBucket(b) })) }
        for a in filter.agents.sorted() {
            let label = cube.agents.first { $0.id == a }?.label ?? a
            chips.append((label, { self.toggleAgent(a) }))
        }
        for m in filter.models.sorted() where m < cube.models.count { chips.append((cube.models[m].id, { self.toggleModel(m) })) }
        for p in filter.projects.sorted() where p < cube.projects.count { chips.append((cube.projects[p].name, { self.toggleProject(p) })) }
        for s in filter.sessions.sorted() where s < cube.sessions.count {
            let t = cube.sessions[s].title
            chips.append((t.isEmpty ? String(cube.sessions[s].id.prefix(8)) : t, { self.toggleSession(s) }))
        }
        return chips
    }

    func refreshPrices() {
        let url = resolvedPricesURL
        Task.detached {
            _ = try? PriceSnapshot.refreshFromCLI(to: url)
            await MainActor.run { [weak self] in self?.refresh() }
        }
    }
}
