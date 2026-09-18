import SwiftUI
import Charts
import OtterStatsCore

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview, agents, models, timeline, projects, sessions, tools, efficiency, quality
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .agents: return "Agents"
        case .models: return "Models"
        case .timeline: return "Timeline"
        case .projects: return "Projects"
        case .sessions: return "Sessions"
        case .tools: return "Tools"
        case .efficiency: return "Efficiency"
        case .quality: return "Methodology"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .agents: return "person.3"
        case .models: return "cpu"
        case .timeline: return "chart.bar.xaxis"
        case .projects: return "folder"
        case .sessions: return "list.bullet.rectangle"
        case .tools: return "wrench.and.screwdriver"
        case .efficiency: return "gauge.with.dots.needle.67percent"
        case .quality: return "checkmark.shield"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var store: UsageStore
    @State private var section: DashboardSection? = .overview
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.filter.period == .custom { dateRangeBar }
                    pricingBar
                    if !store.activeChips.isEmpty { slicerBar }
                    if let error = store.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(Theme.fail)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.fail.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    content
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle(section?.title ?? "Otter Stats")
            .toolbar { toolbar }
        }
        .frame(minWidth: 940, minHeight: 620)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .tint(Theme.cyan)
        .searchable(text: $query, placement: .toolbar, prompt: "Search sessions, projects, models")
        .onChange(of: query) { _, new in store.filter.query = new }
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                HStack(spacing: 10) {
                    OtterLogo(size: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Otter Stats").font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("Devin usage, locally").font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }
            Section("Report") {
                ForEach(DashboardSection.allCases) { s in
                    Label(s.title, systemImage: s.icon).tag(s)
                }
            }
            Section("Summary") {
                sidebarStat("Sessions", "\(store.slice.sessionsWithTurns)")
                sidebarStat("Turns", Fmt.int(store.slice.totals.turns))
                sidebarStat("Tokens", Fmt.compact(store.slice.totals.tokens))
                sidebarStat("Est. cost", Fmt.usd(store.slice.totals.costUSD, complete: store.slice.totals.costComplete))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
    }

    private func sidebarStat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Period", selection: Binding(get: { store.filter.period }, set: { store.setPeriod($0) })) {
                ForEach(Period.allCases) { p in Text(p.label).tag(p) }
            }
            .pickerStyle(.segmented)
        }
        ToolbarItem {
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh")
                .disabled(store.loading)
        }
        ToolbarItem {
            SettingsLink { Image(systemName: "gearshape") }.help("Settings")
        }
    }

    private var pricingBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "dollarsign.circle").foregroundStyle(Theme.amber)
            Text("Pricing").foregroundStyle(Theme.muted)
            Picker("Pricing", selection: Binding(get: { store.pricingSelection }, set: { store.setPricing($0) })) {
                Text("All").tag(PricingClass?.none)
                ForEach(PricingClass.allCases) { p in Text(p.label).tag(PricingClass?.some(p)) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Text(store.equivalentBasis.map { "Equivalent paid cost \($0) · simulation, not a Devin charge" }
                 ?? "Equivalent paid cost unavailable · no paid SWE model in the price snapshot")
                .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .font(.callout)
        .controlSize(.small)
        .padding(10)
        .background(Theme.glass, in: RoundedRectangle(cornerRadius: 10))
    }

    private var dateRangeBar: some View {
        let today = ISODay.calendar.startOfDay(for: Date())
        let days = (ISODay.calendar.dateComponents([.day], from: ISODay.calendar.startOfDay(for: store.customStart), to: ISODay.calendar.startOfDay(for: store.customEnd)).day ?? 0) + 1
        return HStack(spacing: 10) {
            Image(systemName: "calendar").foregroundStyle(Theme.cyan)
            Text("From").foregroundStyle(Theme.muted)
            CalendarButton(date: Binding(get: { store.customStart }, set: { store.customStart = $0 }), range: Date.distantPast...store.customEnd)
            Text("To").foregroundStyle(Theme.muted)
            CalendarButton(date: Binding(get: { store.customEnd }, set: { store.customEnd = $0 }), range: min(store.customStart, today)...today)
            Text("\(days) day\(days == 1 ? "" : "s")").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
            Spacer()
            ForEach([7, 30, 90], id: \.self) { n in
                Button("Last \(n)") {
                    store.customEnd = today
                    store.customStart = ISODay.calendar.date(byAdding: .day, value: -(n - 1), to: today) ?? today
                }
            }
            Button("This month") {
                store.customEnd = today
                store.customStart = ISODay.calendar.dateInterval(of: .month, for: today)?.start ?? today
            }
        }
        .font(.callout)
        .controlSize(.small)
        .padding(10)
        .background(Theme.glass, in: RoundedRectangle(cornerRadius: 10))
    }

    private struct CalendarButton: View {
        @Binding var date: Date
        let range: ClosedRange<Date>
        @State private var open = false

        var body: some View {
            Button {
                open.toggle()
            } label: {
                Text(date, format: .dateTime.day().month(.abbreviated).year())
                    .monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(open ? Theme.cyan : Theme.line))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                DatePicker("", selection: $date, in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(10)
                    .preferredColorScheme(.dark)
                    .tint(Theme.cyan)
            }
        }
    }

    private var slicerBar: some View {
        HStack(spacing: 6) {
            Text("Filters").font(.caption).foregroundStyle(Theme.muted)
            ForEach(Array(store.activeChips.enumerated()), id: \.offset) { _, chip in
                Chip(text: chip.0, onRemove: chip.1)
            }
            Spacer()
            Button("Clear") { store.clearSlicers(); query = "" }.controlSize(.small)
        }
    }

    @ViewBuilder private var content: some View {
        let s = store.slice
        switch section ?? .overview {
        case .overview: OverviewSection(slice: s)
        case .agents: AgentsSection(slice: s)
        case .models: ModelsSection(slice: s)
        case .timeline: TimelineSection(slice: s)
        case .projects: ProjectsSection(slice: s)
        case .sessions: SessionsSection(slice: s)
        case .tools: ToolsSection(slice: s)
        case .efficiency: EfficiencySection(slice: s)
        case .quality: QualitySection(slice: s)
        }
    }
}

// MARK: - Sections

struct OverviewSection: View {
    @EnvironmentObject var store: UsageStore
    let slice: UsageSlice

    var body: some View {
        let t = slice.totals
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            KPI(label: "Turns", value: Fmt.int(t.turns), sub: "\(Fmt.int(slice.prompts)) prompts", accent: Theme.teal)
            KPI(label: "Tokens", value: Fmt.compact(t.tokens), sub: tokenSplit(t), accent: Theme.cyan)
            KPI(label: "Actual est. cost", value: Fmt.usd(t.costUSD, complete: t.costComplete),
                sub: t.costComplete ? (t.hasFree ? "paid models only · free tier = $0" : "all turns priced") : "\(t.unpricedTurns) turns with unknown pricing", accent: Theme.amber)
            KPI(label: "Equivalent paid cost", value: equivalentValue(t), sub: equivalentSub(t), accent: Theme.ok)
            KPI(label: "Model time", value: Fmt.duration(ms: t.modelMs), sub: "avg \(Fmt.duration(ms: Int(t.avgTurnMs)))/turn", accent: Theme.violet)
            KPI(label: "Sessions", value: "\(slice.sessionsWithTurns)", sub: "\(slice.activeSessions) active · cache hit \(Fmt.percent(t.cacheHitRatio))", accent: Theme.pink)
        }
        HStack(alignment: .top, spacing: 16) {
            Panel(title: "Who burned it", subtitle: "share of tokens by bucket") {
                ShareBar(segments: slice.byBucket.map { (Theme.color(for: $0.key), $0.share) }, height: 12)
                ForEach(slice.byBucket, id: \.key) { k in
                    RowBar(label: k.key.label, value: Fmt.compact(k.totals.tokens), share: k.share, color: Theme.color(for: k.key),
                           detail: "\(k.totals.turns) turns · \(Fmt.usd(k.totals.costUSD, complete: k.totals.costComplete))",
                           selected: store.filter.buckets.contains(k.key)) { store.toggleBucket(k.key) }
                }
                if slice.byBucket.isEmpty { EmptyHint() }
            }
            Panel(title: "Tokens per day", subtitle: "stacked by bucket") {
                TimelineChart(points: slice.filledTimeline(), height: 220)
            }
        }
        HStack(alignment: .top, spacing: 16) {
            Panel(title: "Top agents") {
                ForEach(slice.byAgent.prefix(6), id: \.key) { k in
                    let a = slice.agent(k.key)
                    RowBar(label: a.label, value: Fmt.compact(k.totals.tokens), share: k.share, color: Theme.color(for: a.bucket),
                           detail: "\(k.totals.turns) turns", selected: store.filter.agents.contains(a.id)) { store.toggleAgent(a.id) }
                }
                if slice.byAgent.isEmpty { EmptyHint() }
            }
            Panel(title: "Top models") {
                ForEach(Array(slice.byModel.prefix(6).enumerated()), id: \.element.key) { i, k in
                    let m = slice.model(k.key)
                    RowBar(label: "\(m.id)  ·  \(m.pricing.badge.lowercased())", value: Fmt.compact(k.totals.tokens), share: k.share, color: Theme.series(i),
                           detail: CostText.actualAndEquivalent(k.totals),
                           selected: store.filter.models.contains(k.key)) { store.toggleModel(k.key) }
                }
                if slice.byModel.isEmpty { EmptyHint() }
            }
        }
    }

    private func tokenSplit(_ t: UsageTotals) -> String {
        var parts: [String] = []
        if t.paidTokens > 0 { parts.append("\(Fmt.compact(t.paidTokens)) paid") }
        if t.freeTokens > 0 { parts.append("\(Fmt.compact(t.freeTokens)) free") }
        if t.unknownTokens > 0 { parts.append("\(Fmt.compact(t.unknownTokens)) unknown") }
        return parts.isEmpty ? "in+out+cache read" : parts.joined(separator: " · ")
    }

    private func equivalentValue(_ t: UsageTotals) -> String {
        guard t.hasFree else { return "—" }
        guard store.equivalentBasis != nil else { return "n/a" }
        return Fmt.usd(t.billedEquivalentUSD, complete: t.costComplete)
    }

    private func equivalentSub(_ t: UsageTotals) -> String {
        guard t.hasFree else { return "no free-tier usage in period" }
        guard let basis = store.equivalentBasis else { return "no paid SWE model in price snapshot" }
        return "+\(Fmt.usd(t.equivalentUSD)) for \(Fmt.compact(t.freeTokens)) free tokens \(basis) · simulation"
    }
}

struct AgentsSection: View {
    @EnvironmentObject var store: UsageStore
    let slice: UsageSlice

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Panel(title: "Buckets", subtitle: "click to filter") {
                ForEach(slice.byBucket, id: \.key) { k in
                    RowBar(label: k.key.label, value: Fmt.compact(k.totals.tokens), share: k.share, color: Theme.color(for: k.key),
                           detail: "\(k.totals.turns) turns · \(Fmt.duration(ms: k.totals.modelMs))",
                           selected: store.filter.buckets.contains(k.key)) { store.toggleBucket(k.key) }
                }
            }
            .frame(maxWidth: 380)
            Panel(title: "Tokens by agent") {
                Chart(slice.byAgent.prefix(12), id: \.key) { k in
                    BarMark(x: .value("Tokens", k.totals.tokens), y: .value("Agent", slice.agent(k.key).label))
                        .foregroundStyle(Theme.color(for: slice.agent(k.key).bucket))
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks { v in AxisValueLabel { if let n = v.as(Int.self) { Text(Fmt.compact(n)) } }; AxisGridLine().foregroundStyle(Theme.line) } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.text) } }
                .frame(height: max(160, CGFloat(min(12, slice.byAgent.count)) * 26))
            }
        }
        Panel(title: "All agents", subtitle: "\(slice.byAgent.count) agents with turns") {
            UsageTable(rows: slice.byAgent.map { k in
                let a = slice.agent(k.key)
                return UsageTableRow(id: a.id, label: a.label, sub: a.bucket.label, color: Theme.color(for: a.bucket), totals: k.totals, share: k.share,
                                     selected: store.filter.agents.contains(a.id)) { store.toggleAgent(a.id) }
            })
        }
        if !slice.cube.pinDrift.isEmpty {
            Panel(title: "Pin drift", subtitle: "Otter roles running on a model other than the pinned one") {
                ForEach(slice.cube.pinDrift) { d in
                    HStack {
                        Text(d.role).font(.callout.weight(.medium))
                        Text("pinned \(d.pinned)").font(Theme.mono).foregroundStyle(Theme.muted)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Theme.muted)
                        Text(d.model).font(Theme.mono).foregroundStyle(Theme.amber)
                        Spacer()
                        Text("\(d.turns) turns").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }
}

struct ModelsSection: View {
    @EnvironmentObject var store: UsageStore
    let slice: UsageSlice

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Panel(title: "Token share") {
                Chart(Array(slice.byModel.enumerated()), id: \.element.key) { i, k in
                    SectorMark(angle: .value("Tokens", k.totals.tokens), innerRadius: .ratio(0.6), angularInset: 1.5)
                        .foregroundStyle(Theme.series(i))
                        .cornerRadius(3)
                }
                .frame(height: 220)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(slice.byModel.prefix(8).enumerated()), id: \.element.key) { i, k in
                        HStack(spacing: 6) {
                            Circle().fill(Theme.series(i)).frame(width: 7, height: 7)
                            Text(slice.model(k.key).id).font(.caption).lineLimit(1)
                            Spacer()
                            Text(Fmt.percent(k.share)).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .frame(maxWidth: 360)
            Panel(title: "Cost by model", subtitle: "solid = actual estimated cost · faded green = equivalent if free tier were billed (simulation)") {
                Chart(Array(slice.byModel.enumerated()), id: \.element.key) { i, k in
                    BarMark(x: .value("USD", k.totals.costUSD), y: .value("Model", slice.model(k.key).id))
                        .foregroundStyle(Theme.series(i)).cornerRadius(3)
                    if k.totals.equivalentUSD > 0 {
                        BarMark(x: .value("USD", k.totals.equivalentUSD), y: .value("Model", slice.model(k.key).id))
                            .foregroundStyle(Theme.ok.opacity(0.35)).cornerRadius(3)
                    }
                }
                .chartXAxis { AxisMarks { v in AxisValueLabel { if let n = v.as(Double.self) { Text(Fmt.usd(n)) } }; AxisGridLine().foregroundStyle(Theme.line) } }
                .frame(height: max(160, CGFloat(slice.byModel.count) * 26))
            }
        }
        Panel(title: "All models", subtitle: store.equivalentBasis.map { "equivalent = \($0) · simulation, not a charge" } ?? "equivalent cost unavailable: no paid SWE model in the price snapshot") {
            UsageTable(rows: slice.byModel.enumerated().map { i, k in
                let m = slice.model(k.key)
                let price = m.price.map { p in p.free ? "free tier · actual $0" : "$\(Fmt.trim(p.input * 1e6)) in · $\(Fmt.trim(p.output * 1e6)) out /1M" } ?? "run devin models list to price"
                return UsageTableRow(id: m.id, label: m.id, sub: price, tag: m.pricing, color: Theme.series(i), totals: k.totals, share: k.share,
                                     selected: store.filter.models.contains(k.key)) { store.toggleModel(k.key) }
            }, showEquivalent: true)
        }
    }
}

struct TimelineSection: View {
    let slice: UsageSlice
    @State private var metric = 0

    var body: some View {
        Panel(title: "Daily usage", subtitle: "stacked by bucket") {
            Picker("Metric", selection: $metric) {
                Text("Tokens").tag(0); Text("Turns").tag(1); Text("Cost").tag(2); Text("Model time").tag(3)
            }.pickerStyle(.segmented).frame(width: 360)
            TimelineChart(points: slice.filledTimeline(), height: 300, metric: metric, showAxes: true)
        }
        Panel(title: "Days", subtitle: "\(slice.timeline.count) days with activity") {
            LazyVStack(alignment: .leading, spacing: 6) {
                DayRow(cells: ["Day", "Turns", "Tokens", "Output", "Model time", "Est. cost"])
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                ForEach(slice.timeline.reversed()) { p in
                    DayRow(cells: [p.day, Fmt.int(p.totals.turns), Fmt.compact(p.totals.tokens), Fmt.compact(p.totals.output),
                                   Fmt.duration(ms: p.totals.modelMs), Fmt.usd(p.totals.costUSD, complete: p.totals.costComplete)])
                        .font(.callout.monospacedDigit())
                }
            }
        }
    }
}

private struct DayRow: View {
    let cells: [String]

    var body: some View {
        HStack(spacing: 18) {
            Text(cells[0]).font(Theme.mono).frame(width: 110, alignment: .leading)
            ForEach(1..<cells.count, id: \.self) { i in
                Text(cells[i]).frame(width: 90, alignment: .trailing)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ProjectsSection: View {
    @EnvironmentObject var store: UsageStore
    let slice: UsageSlice

    var body: some View {
        Panel(title: "Projects", subtitle: "by working directory · click to filter") {
            UsageTable(rows: slice.byProject.enumerated().map { i, k in
                let p = slice.project(k.key)
                return UsageTableRow(id: p.path, label: p.name, sub: p.path, color: Theme.series(i), totals: k.totals, share: k.share,
                                     selected: store.filter.projects.contains(k.key)) { store.toggleProject(k.key) }
            })
            if slice.byProject.isEmpty { EmptyHint() }
        }
    }
}

struct SessionsSection: View {
    @EnvironmentObject var store: UsageStore
    let slice: UsageSlice
    @State private var shown = SessionsSection.pageSize
    static let pageSize = 100

    var body: some View {
        Panel(title: "Sessions", subtitle: "\(slice.sessions.count) with turns in period · click to filter") {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(slice.sessions.prefix(shown)) { s in
                    SessionRow(slice: slice, s: s, selected: store.filter.sessions.contains(s.index)) { store.toggleSession(s.index) }
                }
            }
            if slice.sessions.count > shown {
                Button("Show \(min(Self.pageSize, slice.sessions.count - shown)) more of \(slice.sessions.count - shown) remaining") {
                    shown += Self.pageSize
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            if slice.sessions.isEmpty { EmptyHint() }
        }
        .onChange(of: slice.sessions.map(\.id)) { _, _ in shown = Self.pageSize }
    }
}

private struct SessionRow: View {
    let slice: UsageSlice
    let s: SessionSummary
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.gradient).frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.session.title.isEmpty ? s.session.id : s.session.title).font(.callout.weight(.medium)).lineLimit(1)
                    HStack(spacing: 8) {
                        Text(s.project.name).foregroundStyle(Theme.cyan)
                        Text(s.session.leadModel).font(Theme.mono)
                        Text(Fmt.relative(s.session.last))
                        Text(String(s.session.id.prefix(8))).font(Theme.mono)
                    }.font(.caption).foregroundStyle(Theme.muted)
                    HStack(spacing: 4) {
                        ForEach(s.agents.prefix(5), id: \.key) { a in
                            let ag = slice.agent(a.key)
                            Text("\(ag.label) \(Fmt.percent(a.share))")
                                .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                .foregroundStyle(Theme.color(for: ag.bucket))
                                .background(Theme.color(for: ag.bucket).opacity(0.12), in: Capsule())
                        }
                    }
                }
                Spacer()
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 2) {
                    GridRow { Text("turns"); Text("prompts"); Text("tokens"); Text("time"); Text("cost") }
                        .font(.caption2).foregroundStyle(Theme.muted)
                    GridRow {
                        Text(Fmt.int(s.totals.turns)); Text(Fmt.int(s.prompts)); Text(Fmt.compact(s.totals.tokens))
                        Text(Fmt.duration(ms: s.totals.modelMs)); Text(Fmt.usd(s.totals.costUSD, complete: s.totals.costComplete))
                    }.font(.callout.monospacedDigit())
                }
            }
            .padding(10)
            .background(selected ? Theme.cyan.opacity(0.1) : Theme.glass, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ToolsSection: View {
    let slice: UsageSlice

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Panel(title: "Tool calls", subtitle: "\(Fmt.int(slice.efficiency.toolCalls)) calls") {
                let top = slice.tools.prefix(15)
                let maxCalls = Double(top.first?.calls ?? 1)
                ForEach(top) { t in
                    RowBar(label: t.tool, value: Fmt.int(t.calls), share: Double(t.calls) / maxCalls, color: Theme.teal)
                }
                if slice.tools.isEmpty { EmptyHint() }
            }
            Panel(title: "Tool calls by agent") {
                let maxCalls = Double(slice.toolsByAgent.first?.totals.turns ?? 1)
                ForEach(slice.toolsByAgent, id: \.key) { k in
                    let a = slice.agent(k.key)
                    RowBar(label: a.label, value: Fmt.int(k.totals.turns), share: Double(k.totals.turns) / maxCalls, color: Theme.color(for: a.bucket))
                }
                if slice.toolsByAgent.isEmpty { EmptyHint() }
            }
        }
    }
}

struct EfficiencySection: View {
    let slice: UsageSlice

    var body: some View {
        let e = slice.efficiency
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            KPI(label: "Turns / prompt", value: e.turnsPerPrompt.map { Fmt.trim(($0 * 10).rounded() / 10) } ?? "—", sub: "\(Fmt.int(e.prompts)) prompts", accent: Theme.teal)
            KPI(label: "Tokens / prompt", value: e.tokensPerPrompt.map { Fmt.compact($0) } ?? "—", accent: Theme.cyan)
            KPI(label: "Output / turn", value: Fmt.compact(e.outputPerTurn), sub: "tokens", accent: Theme.violet)
            KPI(label: "Cache hit ratio", value: Fmt.percent(e.cacheHitRatio), sub: "cache read ÷ (input + cache read)", accent: Theme.pink)
            KPI(label: "Avg TTFT", value: Fmt.duration(ms: Int(e.avgTTFTMs)), accent: Theme.amber)
            KPI(label: "Avg turn", value: Fmt.duration(ms: Int(e.avgTurnMs)), accent: Theme.amber)
            KPI(label: "Model time", value: Fmt.duration(ms: e.modelTimeMs), accent: Theme.ok)
            KPI(label: "Tool calls", value: Fmt.int(e.toolCalls), sub: e.turns > 0 ? "\(Fmt.trim((Double(e.toolCalls) / Double(e.turns) * 10).rounded() / 10)) per turn" : nil, accent: Theme.teal)
        }
        Panel(title: "Token composition") {
            let t = slice.totals
            let total = Double(max(1, t.input + t.output + t.cacheRead + t.cacheCreation))
            ShareBar(segments: [(Theme.cyan, Double(t.input) / total), (Theme.teal, Double(t.output) / total),
                                (Theme.violet, Double(t.cacheRead) / total), (Theme.amber, Double(t.cacheCreation) / total)], height: 12)
            HStack(spacing: 18) {
                legend("Input", t.input, Theme.cyan); legend("Output", t.output, Theme.teal)
                legend("Cache read", t.cacheRead, Theme.violet); legend("Cache write", t.cacheCreation, Theme.amber)
            }
        }
    }

    private func legend(_ l: String, _ v: Int, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text("\(l) \(Fmt.compact(v))").font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

struct QualitySection: View {
    @EnvironmentObject var store: UsageStore
    let slice: UsageSlice

    var body: some View {
        let q = slice.cube.quality
        Panel(title: "Data quality") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                qrow("Assistant turns embedded", Fmt.int(q.turns))
                qrow("Duplicate rows collapsed", Fmt.int(q.duplicates), warn: q.duplicates > 0)
                qrow("Turns missing metrics", Fmt.int(q.metricsMissing), warn: q.metricsMissing > 0)
                qrow("Unknown attribution", Fmt.int(q.unknownTurns), warn: q.unknownTurns > 0)
                qrow("Unpriced turns", Fmt.int(q.unpricedTurns), warn: q.unpricedTurns > 0)
                qrow("Unpriced models", slice.cube.unpricedModels.isEmpty ? "none" : slice.cube.unpricedModels.joined(separator: ", "), warn: !slice.cube.unpricedModels.isEmpty)
                qrow("Message nodes scanned", Fmt.int(q.totalNodes))
                qrow("Query truncated", q.truncated ? "yes — raise the cap" : "no", warn: q.truncated)
                qrow("Price snapshot", slice.cube.priceSnapshotAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "missing")
                qrow("Database", store.resolvedDBPath)
                qrow("Window", "\(isoDay(slice.cube.from)) → \(isoDay(slice.cube.to)) (cap \(slice.cube.capDays)d)")
            }
            HStack {
                Button("Refresh prices from `devin models list`") { store.refreshPrices() }.controlSize(.small)
                Text("Pricing is a local estimate; it never reflects your invoice.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        Panel(title: "Methodology") {
            VStack(alignment: .leading, spacing: 8) {
                bullet("The Devin CLI sessions database is opened read-only and never modified. Nothing leaves this Mac.")
                bullet("A turn is one assistant `chat_message` row with usage metrics. Duplicate rows for the same message are collapsed once.")
                bullet("Attribution is structural: each turn is walked up the message tree to its root. Lead profiles (normal/plan/ask) are the lead; Otter Swarm roles are otter workers; other `subagent_*` profiles are other subagents; summarizer/compactor are housekeeping.")
                bullet("Tokens = input + output + cache read. Cache writes are shown separately and priced at the cache-write rate when present.")
                bullet("Cost multiplies each turn's tokens by the Otter Swarm price snapshot (~/.config/devin/otter/prices.json). Turns on models without a price stay unpriced and cost is marked with ≥.")
                bullet("Pin drift compares Otter role turns to the model pinned in ~/.config/devin/agents/<role>.md.")
            }
        }
    }

    private func qrow(_ l: String, _ v: String, warn: Bool = false) -> some View {
        GridRow {
            Text(l).foregroundStyle(Theme.muted)
            Text(v).font(Theme.mono).foregroundStyle(warn ? Theme.amber : Theme.text).lineLimit(2)
        }.font(.callout)
    }

    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.gradient).frame(width: 6, height: 6).padding(.top, 6)
            Text(t).font(.callout).foregroundStyle(Theme.text.opacity(0.9))
        }
    }
}

// MARK: - Shared pieces

struct TimelineChart: View {
    let points: [DayPoint]
    var height: CGFloat = 220
    var metric = 0
    var showAxes = true

    private func value(_ t: UsageTotals) -> Double {
        switch metric {
        case 1: return Double(t.turns)
        case 2: return t.costUSD
        case 3: return Double(t.modelMs) / 60_000
        default: return Double(t.tokens)
        }
    }

    private func label(_ v: Double) -> String {
        switch metric {
        case 1: return Fmt.int(Int(v))
        case 2: return Fmt.usd(v)
        case 3: return "\(Fmt.trim(v))m"
        default: return Fmt.compact(v)
        }
    }

    var body: some View {
        if points.allSatisfy({ $0.totals.turns == 0 }) {
            EmptyHint().frame(height: height)
        } else {
            Chart {
                ForEach(points) { p in
                    ForEach(AgentBucket.allCases) { b in
                        if let t = p.byBucket[b] {
                            BarMark(x: .value("Day", p.date, unit: .day), y: .value("Value", value(t)))
                                .foregroundStyle(by: .value("Bucket", b.label))
                        }
                    }
                }
            }
            .chartForegroundStyleScale(domain: AgentBucket.allCases.map(\.label), range: AgentBucket.allCases.map(Theme.color(for:)))
            .chartLegend(showAxes ? .visible : .hidden)
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: max(1, points.count / 7))) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Theme.muted); AxisGridLine().foregroundStyle(Theme.line) } }
            .chartYAxis { AxisMarks { v in AxisValueLabel { if let n = v.as(Double.self) { Text(label(n)) } }.foregroundStyle(Theme.muted); AxisGridLine().foregroundStyle(Theme.line) } }
            .frame(height: height)
        }
    }
}

struct UsageTableRow: Identifiable {
    let id: String
    let label: String
    let sub: String
    var tag: PricingClass? = nil
    let color: Color
    let totals: UsageTotals
    let share: Double
    let selected: Bool
    let onTap: () -> Void
}

struct UsageTable: View {
    let rows: [UsageTableRow]
    var showEquivalent = false

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text("Name").gridColumnAlignment(.leading)
                Text("Share"); Text("Turns"); Text("Input"); Text("Output"); Text("Cache"); Text("Model time"); Text("Actual cost")
                if showEquivalent { Text("Equivalent") }
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            ForEach(rows) { r in
                GridRow {
                    Button(action: r.onTap) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(r.color).frame(width: 4, height: 24)
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 6) {
                                    Text(r.label).font(.callout).lineLimit(1)
                                    if let tag = r.tag { Tag(text: tag.badge, color: tag.color) }
                                }
                                Text(r.sub).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            if r.selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.cyan).font(.caption) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .gridColumnAlignment(.leading)
                    Text(Fmt.percent(r.share)); Text(Fmt.int(r.totals.turns)); Text(Fmt.compact(r.totals.input))
                    Text(Fmt.compact(r.totals.output)); Text(Fmt.compact(r.totals.cacheRead))
                    Text(Fmt.duration(ms: r.totals.modelMs)); Text(Fmt.usd(r.totals.costUSD, complete: r.totals.costComplete))
                    if showEquivalent {
                        Text(r.totals.equivalentUSD > 0 ? "≈" + Fmt.usd(r.totals.equivalentUSD) : "—").foregroundStyle(Theme.ok)
                    }
                }
                .font(.callout.monospacedDigit())
                .padding(.vertical, 2)
            }
        }
    }
}

struct EmptyHint: View {
    var body: some View {
        VStack(spacing: 6) {
            OtterLogo(size: 40).opacity(0.5)
            Text("Nothing in this period").font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
