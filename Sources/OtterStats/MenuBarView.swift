import SwiftUI
import Charts
import OtterStatsCore

struct MenuBarView: View {
    @EnvironmentObject var store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKeys.popoverPeriod) private var periodRaw: String = Period.today.rawValue

    private var period: Period { Period(rawValue: periodRaw) ?? .today }
    private var slice: UsageSlice { period == .today ? store.todaySlice : store.weekSlice }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            ScrollView(.vertical) {
                if let error = store.error, store.cube.isEmpty {
                    errorState(error)
                } else {
                    VStack(spacing: 12) {
                        kpis
                        burnBar
                        sparkline
                        topLists
                        recentSessions
                        quality
                    }
                    .padding(14)
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity, alignment: .top)
            Divider().overlay(Theme.line)
            footer
        }
        .frame(width: 360, height: 720)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .tint(Theme.cyan)
    }

    private var header: some View {
        HStack(spacing: 10) {
            OtterLogo(size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("Otter Stats").font(.system(size: 14, weight: .bold, design: .rounded))
                Text(store.loading ? "Refreshing…" : "Devin usage · \(Fmt.relative(store.lastRefresh.map { Int($0.timeIntervalSince1970) }))")
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
            Spacer()
            PillToggle(selection: $periodRaw, options: [(Period.today.rawValue, "Today"), (Period.week.rawValue, "7 days")])
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var kpis: some View {
        let t = slice.totals
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            KPI(label: "Est. cost", value: Fmt.usd(t.costUSD, complete: t.costComplete),
                sub: t.costComplete ? "\(t.pricedTurns) priced turns" : "\(t.unpricedTurns) unpriced turns", accent: Theme.amber)
            KPI(label: "Tokens", value: Fmt.compact(t.tokens),
                sub: "in \(Fmt.compact(t.input)) · out \(Fmt.compact(t.output))\ncache \(Fmt.compact(t.cacheRead))", accent: Theme.cyan)
            KPI(label: "Turns", value: Fmt.int(t.turns), sub: "\(Fmt.int(slice.prompts)) prompts", accent: Theme.teal)
            KPI(label: "Model time", value: Fmt.duration(ms: t.modelMs), sub: "\(slice.sessionsWithTurns) sessions", accent: Theme.violet)
        }
    }

    @ViewBuilder private var burnBar: some View {
        if !slice.byBucket.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who burned it").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                ShareBar(segments: slice.byBucket.map { (Theme.color(for: $0.key), $0.share) })
                HStack(spacing: 10) {
                    ForEach(slice.byBucket, id: \.key) { k in
                        HStack(spacing: 4) {
                            Circle().fill(Theme.color(for: k.key)).frame(width: 6, height: 6)
                            Text("\(k.key.label) \(Fmt.percent(k.share))").font(.caption2).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var sparkline: some View {
        let points = store.fortnightSlice.filledTimeline().suffix(14)
        if points.contains(where: { $0.totals.turns > 0 }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Last 14 days · tokens").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                Chart(Array(points)) { p in
                    BarMark(x: .value("Day", p.date, unit: .day), y: .value("Tokens", p.totals.tokens))
                        .foregroundStyle(Theme.gradient)
                        .cornerRadius(2)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 44)
            }
        }
    }

    private var topLists: some View {
        HStack(alignment: .top, spacing: 10) {
            miniList(title: "Agents", rows: slice.byAgent.prefix(4).map { (slice.agent($0.key).label, $0.share, Theme.color(for: slice.agent($0.key).bucket)) })
            miniList(title: "Models", rows: slice.byModel.prefix(4).enumerated().map { (slice.model($0.element.key).id, $0.element.share, Theme.series($0.offset)) })
        }
    }

    private func miniList(title: String, rows: [(String, Double, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            if rows.isEmpty {
                Text("No turns").font(.caption2).foregroundStyle(Theme.muted)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(r.0).font(.caption).lineLimit(1)
                        Spacer()
                        Text(Fmt.percent(r.1)).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                    }
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 1.5).fill(r.2).frame(width: max(2, g.size.width * r.1))
                    }.frame(height: 3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.glass, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var recentSessions: some View {
        let sessions = slice.sessions.prefix(3)
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Top sessions").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                ForEach(sessions) { s in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.gradient).frame(width: 3, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.session.title.isEmpty ? String(s.session.id.prefix(12)) : s.session.title).font(.caption).lineLimit(1)
                            Text("\(s.project.name) · \(Fmt.relative(s.session.last))").font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Fmt.usd(s.totals.costUSD, complete: s.totals.costComplete)).font(.caption.monospacedDigit())
                            Text(Fmt.compact(s.totals.tokens) + " tok").font(.caption2).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var quality: some View {
        let q = store.cube.quality
        if q.duplicates > 0 || q.unknownTurns > 0 || !store.cube.unpricedModels.isEmpty || store.error != nil {
            VStack(alignment: .leading, spacing: 3) {
                if let e = store.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.fail)
                }
                if q.duplicates > 0 { Text("\(q.duplicates) duplicate assistant rows collapsed") }
                if q.unknownTurns > 0 { Text("\(q.unknownTurns) turns with unknown attribution") }
                if !store.cube.unpricedModels.isEmpty { Text("Unpriced: \(store.cube.unpricedModels.joined(separator: ", "))") }
            }
            .font(.caption2).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            OtterLogo(size: 56).opacity(0.8)
            Text("No usage data yet").font(.headline)
            Text(message).font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            HStack {
                Button("Retry") { store.refresh() }
                Button("Try demo data") { store.demoMode = true; store.settingsChanged() }
            }
            .controlSize(.small)
        }
        .padding(24)
    }

    private func dismissPopover() {
        for w in NSApp.windows where w.className.contains("MenuBarExtra") || w.className.contains("StatusBar") {
            w.orderOut(nil)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                dismissPopover()
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Dashboard", systemImage: "rectangle.3.group")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .controlSize(.small).help("Refresh")
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }.controlSize(.small).help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .controlSize(.small).help("Quit Otter Stats")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
