import Foundation
import AppKit
import OtterStatsCore

struct ReleaseInfo: Equatable {
    let version: SemanticVersion
    let url: URL
    let notes: String
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let repo = "chris-wozniczek/otter-stats"
    static let brewCommand = "brew update && brew upgrade --cask otter-stats"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!
    static let interval: TimeInterval = 24 * 60 * 60

    @Published private(set) var available: ReleaseInfo?
    @Published private(set) var checking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?
    @Published var skippedVersion: String {
        didSet { UserDefaults.standard.set(skippedVersion, forKey: SettingsKeys.skippedUpdate) }
    }

    let current: SemanticVersion
    private var timer: Timer?

    init() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        current = SemanticVersion(raw) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
        skippedVersion = UserDefaults.standard.string(forKey: SettingsKeys.skippedUpdate) ?? ""
        if let t = UserDefaults.standard.object(forKey: SettingsKeys.lastUpdateCheck) as? Date { lastChecked = t }
    }

    /// Update the user should see: newer than the running build and not explicitly skipped.
    var pending: ReleaseInfo? {
        guard let available, available.version > current, available.version.description != skippedVersion else { return nil }
        return available
    }

    func start() {
        check()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let last = self.lastChecked else { self?.check(); return }
                if Date().timeIntervalSince(last) >= Self.interval { self.check() }
            }
        }
    }

    func check() {
        guard !checking else { return }
        checking = true
        lastError = nil
        Task {
            defer { checking = false }
            do {
                available = try await Self.fetchLatest()
                lastChecked = Date()
                UserDefaults.standard.set(lastChecked, forKey: SettingsKeys.lastUpdateCheck)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func skip(_ release: ReleaseInfo) { skippedVersion = release.version.description }

    func openRelease() {
        NSWorkspace.shared.open(available?.url ?? Self.releasesPage)
    }

    func copyBrewCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.brewCommand, forType: .string)
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: URL
        let body: String?
        let draft: Bool
        let prerelease: Bool
    }

    private static func fetchLatest() async throws -> ReleaseInfo? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("otter-stats", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "UpdateChecker", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "GitHub returned HTTP \(http.statusCode)"])
        }
        let rel = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !rel.draft, !rel.prerelease, let v = SemanticVersion(rel.tag_name) else { return nil }
        return ReleaseInfo(version: v, url: rel.html_url, notes: rel.body ?? "")
    }
}
