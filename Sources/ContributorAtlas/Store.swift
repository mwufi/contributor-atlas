import SwiftUI
import AppKit
import AtlasCore
import UniformTypeIdentifiers

@MainActor
final class AtlasStore: ObservableObject {
    @Published var snapshot: RepositorySnapshot?
    @Published var analytics: Analytics?
    @Published var identities = IdentityIndex(commits: [], combineAliases: true)
    @Published var filters = Filters() {
        didSet {
            guard filters != oldValue else { return }
            scheduleAnalysis(debounce: filters.query != oldValue.query)
            scheduleHistory()
        }
    }
    @Published var loading = false
    @Published var calculating = false
    @Published var error: String?
    @Published var section = "Overview" { didSet { scheduleHistory() } }
    @Published var range = "All history" { didSet { scheduleHistory() } }
    @Published var year = 2026 { didSet { scheduleHistory() } }
    @Published var selectedCommit: Commit?
    @Published private(set) var history = NavigationHistory(AtlasLocation())
    @Published private(set) var yearsByClock: [ClockMode: [Int]] = [:]
    var availableYears: [Int] { yearsByClock[filters.clock] ?? [year] }
    private var cache = RecentCache<Filters, Analytics>()
    private var historyTask: Task<Void, Never>?
    private var restoring = false
    private var lastSearchEdit: Date?
    private var analysisTask: Task<Void, Never>?
    private var generation = 0
    private var identityMode = true
    let initialPath: String

    init(path: String) { initialPath = path }
    func load(_ path: String? = nil) {
        guard !loading else { return }
        loading = true; error = nil
        let location = path ?? snapshot?.path ?? initialPath
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try GitRepository.load(path: location) }.value
                analysisTask?.cancel(); historyTask?.cancel()
                restoring = true
                cache = RecentCache()
                snapshot = result
                yearsByClock = Dictionary(uniqueKeysWithValues: ClockMode.allCases.map { clock in
                    (clock, Set((result.timing[clock] ?? []).map { $0.day.year }).sorted().reversed().map { $0 })
                })
                identities = IdentityIndex(commits: result.commits, combineAliases: filters.combineAliases)
                identityMode = filters.combineAliases
                var f = Filters(); f.clock = filters.clock; f.combineAliases = filters.combineAliases
                filters = f; range = "All history"
                year = yearsByClock[f.clock]?.max() ?? 2026
                history = NavigationHistory(self.location)
                lastSearchEdit = nil
                restoring = false
                UserDefaults.standard.set(result.path, forKey: "repositoryPath")
                loading = false
                scheduleAnalysis()
            } catch { self.error = error.localizedDescription; loading = false }
        }
    }
    private func scheduleAnalysis(debounce: Bool = false) {
        guard let snapshot else { return }
        analysisTask?.cancel(); generation += 1
        let version = generation, filter = filters
        if identityMode != filters.combineAliases {
            identities = IdentityIndex(commits: snapshot.commits, combineAliases: filters.combineAliases)
            identityMode = filters.combineAliases
        }
        if let cached = cache.value(for: filter) {
            analytics = cached; calculating = false
            return
        }
        let index = identities
        calculating = true
        analysisTask = Task {
            if debounce {
                do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) { Analytics(snapshot: snapshot, filters: filter, identities: index) }.value
            guard !Task.isCancelled, version == generation else { return }
            cache.insert(result, for: filter)
            analytics = result; calculating = false
        }
    }
    private var location: AtlasLocation { AtlasLocation(section: section, filters: filters, range: range, year: year) }
    private func scheduleHistory() {
        guard !restoring, snapshot != nil else { return }
        historyTask?.cancel()
        // Coalesce synchronous changes (person + area + section) into one visit.
        historyTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            recordLocation()
        }
    }
    private func recordLocation() {
        guard !restoring, location != history.current else { return }
        let searchOnly = location.differsOnlyInQuery(from: history.current)
        let coalesce = searchOnly && lastSearchEdit.map { Date().timeIntervalSince($0) < 1.0 } == true
        history.record(location, replacingCurrent: coalesce)
        lastSearchEdit = searchOnly ? Date() : nil
    }
    func goBack() {
        historyTask?.cancel(); recordLocation()
        if let destination = history.back() { restore(destination) }
    }
    func goForward() {
        historyTask?.cancel(); recordLocation()
        if let destination = history.forward() { restore(destination) }
    }
    private func restore(_ destination: AtlasLocation) {
        restoring = true; lastSearchEdit = nil; selectedCommit = nil
        section = destination.section; range = destination.range; year = destination.year
        filters = destination.filters
        restoring = false
    }
    func navigate(to destination: String) {
        selectedCommit = nil
        section = destination
    }
    func setRange(_ value: String) {
        range = value
        var f = filters; f.selectedDay = nil
        if value == "All history" { f.start = nil; f.end = nil }
        else if let latest = snapshot?.timing[f.clock]?.map(\.day).max() {
            let count = value == "30 days" ? 30 : value == "90 days" ? 90 : 365
            f.end = latest; f.start = latest.adding(1 - count)
        }
        filters = f
    }
    func reset() {
        var f = Filters(); f.clock = filters.clock; f.combineAliases = filters.combineAliases
        filters = f; range = "All history"
    }
    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Analyze repository"
        if panel.runModal() == .OK, let url = panel.url { load(url.path) }
    }
    func inspect(_ person: ContributorStats) {
        filters.contributor = person.id; section = "Contributors"
    }
    func exportCSV() {
        guard let analytics else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "contributor-atlas.csv"; panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func csv(_ s: String) -> String {
            // Neutralize spreadsheet formulas in untrusted Git names and subjects.
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: { s.hasPrefix($0) }) ? "'" + s : s
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let date = ISO8601DateFormatter()
        var rows = ["sha,author,email,authored_at,merge,subject,files"]
        rows += analytics.commits.map { c in
            [c.id, c.name, c.email, date.string(from: c.date), String(c.isMerge), c.subject, c.files.joined(separator: "\n")].map(csv).joined(separator: ",")
        }
        do { try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }
}
