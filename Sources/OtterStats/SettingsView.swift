import SwiftUI
import ServiceManagement
import OtterStatsCore

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var updates: UpdateChecker
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Show in menu bar", selection: $store.menuBarMetricRaw) {
                    ForEach(MenuBarMetric.allCases) { m in Text(m.label).tag(m.rawValue) }
                }
                Picker("Menu bar period", selection: $store.menuBarPeriodRaw) {
                    Text("Today").tag(Period.today.rawValue)
                    Text("Last 7 days").tag(Period.week.rawValue)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(Theme.fail) }
            }
            Section("Data") {
                Stepper("Refresh every \(store.refreshMinutes) min", value: $store.refreshMinutes, in: 1...120)
                    .onChange(of: store.refreshMinutes) { _, _ in store.scheduleTimer() }
                TextField("Sessions database", text: $store.dbPathOverride, prompt: Text(DevinPaths.defaultSessionsDB.path))
                    .onSubmit { store.settingsChanged() }
                TextField("Price snapshot", text: $store.pricesPathOverride, prompt: Text(DevinPaths.defaultPrices.path))
                    .onSubmit { store.settingsChanged() }
                Toggle("Demo mode (synthetic data)", isOn: $store.demoMode)
                    .onChange(of: store.demoMode) { _, _ in store.settingsChanged() }
                HStack {
                    Button("Refresh prices from Devin CLI") { store.refreshPrices() }
                    Button("Reload now") { store.settingsChanged() }
                }
                Text("Otter Stats only reads the local Devin CLI database (read-only) and the Otter Swarm price snapshot. Nothing is sent anywhere.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Section("Updates") {
                HStack {
                    if let release = updates.pending {
                        Label("Version \(release.version.description) is available", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(Theme.cyan)
                    } else if updates.checking {
                        Text("Checking…").foregroundStyle(Theme.muted)
                    } else if let err = updates.lastError {
                        Text("Check failed: \(err)").foregroundStyle(Theme.fail)
                    } else if let skipped = updates.available, skipped.version > updates.current {
                        Text("Version \(skipped.version.description) is available (skipped)").foregroundStyle(Theme.muted)
                    } else {
                        Text("You're up to date (\(updates.current.description))").foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("Check now") { updates.check() }.disabled(updates.checking)
                }
                if let release = updates.pending {
                    HStack {
                        Button("Open release") { updates.openRelease() }
                        Button("Copy brew command") { updates.copyBrewCommand() }
                        Button("Skip \(release.version.description)") { updates.skip(release) }
                    }
                } else if !updates.skippedVersion.isEmpty {
                    HStack {
                        Text("Skipping \(updates.skippedVersion)").font(.caption).foregroundStyle(Theme.muted)
                        Button("Unskip") { updates.skippedVersion = "" }.controlSize(.small)
                    }
                }
                Text("Checks GitHub Releases once a day. Upgrade with `\(UpdateChecker.brewCommand)` or download from the release page.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Section("About") {
                HStack(spacing: 12) {
                    OtterLogo(size: 40)
                    VStack(alignment: .leading) {
                        Text("Otter Stats \(updates.current.description)").font(.headline)
                        Text("Devin usage in your menu bar. Companion to Otter Swarm.").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                Link("otter-swarm on GitHub", destination: URL(string: "https://github.com/chris-wozniczek/otter-swarm")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .preferredColorScheme(.dark)
        .tint(Theme.cyan)
    }
}
