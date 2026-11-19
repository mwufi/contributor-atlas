import SwiftUI
import AppKit
import AtlasCore

@main
struct ContributorAtlasApp: App {
    @StateObject private var store: AtlasStore
    init() {
        let args = CommandLine.arguments
        let pathIndex = args.firstIndex(of: "--repo")
        let path = pathIndex.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
            ?? UserDefaults.standard.string(forKey: "repositoryPath")
            ?? FileManager.default.currentDirectoryPath
        if args.contains("--benchmark") {
            do {
                let snapshot = try GitRepository.load(path: path)
                let identities = IdentityIndex(commits: snapshot.commits, combineAliases: true)
                let filters = Filters()
                let start = ContinuousClock.now
                let overview = Analytics(snapshot: snapshot, filters: filters, identities: identities)
                let cold = start.duration(to: .now)
                var personFilters = filters
                personFilters.contributor = overview.people.first?.id
                let personStart = ContinuousClock.now
                let person = Analytics(snapshot: snapshot, filters: personFilters, identities: identities)
                let personDuration = personStart.duration(to: .now)
                var cache = RecentCache<Filters, Analytics>()
                cache.insert(overview, for: filters); cache.insert(person, for: personFilters)
                let cacheStart = ContinuousClock.now
                var checksum = 0
                for _ in 0..<1000 { checksum += cache.value(for: filters)?.commits.count ?? 0 }
                let cached = cacheStart.duration(to: .now)
                func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
                let report: [String: Any] = ["commits": snapshot.commits.count, "overviewMilliseconds": ms(cold), "contributorMilliseconds": ms(personDuration), "cachedLookupMeanMilliseconds": ms(cached) / 1000, "checksum": checksum]
                FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]))
                exit(0)
            } catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); exit(1) }
        }
        if args.contains("--report") {
            do {
                let snapshot = try GitRepository.load(path: path)
                let index = IdentityIndex(commits: snapshot.commits, combineAliases: true)
                let data = Analytics(snapshot: snapshot, filters: Filters(), identities: index)
                let report: [String: Any] = [
                    "head": snapshot.head, "branch": snapshot.branch, "shallow": snapshot.shallow,
                    "totalCommits": snapshot.commits.count, "nonMergeCommits": data.commits.count,
                    "from": data.start.id, "through": data.end.id,
                    "contributors": data.people.map { p -> [String: Any] in
                        ["name": p.person.name, "emails": p.person.emails, "commits": p.commits, "activeDays": p.days.count,
                         "commitsPerCalendarDay": Double(p.commits) / Double(data.calendarDays),
                         "primaryArea": p.primaryArea.rawValue,
                         "areasByFileTouches": Dictionary(uniqueKeysWithValues: p.areas.map { ($0.key.rawValue, $0.value) })]
                    }
                ]
                let output = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                FileHandle.standardOutput.write(output); exit(0)
            } catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); exit(1) }
        }
        _store = StateObject(wrappedValue: AtlasStore(path: path))
    }
    var body: some Scene {
        WindowGroup("Contributor Atlas") {
            ContentView().environmentObject(store)
                .frame(minWidth: 1120, minHeight: 740)
                .task { if store.snapshot == nil { store.load() } }
                .onAppear { NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1460, height: 1000)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Open Repository…") { store.chooseRepository() }.keyboardShortcut("o") }
            CommandMenu("Navigate") {
                Button("Back") { store.goBack() }.keyboardShortcut("[").disabled(!store.history.canGoBack)
                Button("Forward") { store.goForward() }.keyboardShortcut("]").disabled(!store.history.canGoForward)
                Divider()
                ForEach(Array(["Overview", "Contributors", "Work areas", "Commit history", "Methodology"].enumerated()), id: \.offset) { index, name in
                    Button(name) { store.navigate(to: name) }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }
            CommandGroup(after: .newItem) {
                Button("Refresh History") { store.load() }.keyboardShortcut("r")
                Button("Export Filtered Commits…") { store.exportCSV() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: AtlasStore
    @State private var visibility: NavigationSplitViewVisibility = .all
    private let sections = ["Overview", "Contributors", "Work areas", "Commit history", "Methodology"]
    private let symbols = ["square.grid.2x2", "person.2", "square.grid.3x3", "clock.arrow.circlepath", "info.circle"]
    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            detail
                .navigationTitle("Contributor Atlas")
                .navigationSubtitle(repositoryName + " · " + (store.snapshot?.branch ?? "Repository"))
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button { store.goBack() } label: { Label("Back", systemImage: "chevron.backward") }
                            .disabled(!store.history.canGoBack || store.loading).help("Back (⌘[)")
                        Button { store.goForward() } label: { Label("Forward", systemImage: "chevron.forward") }
                            .disabled(!store.history.canGoForward || store.loading).help("Forward (⌘])")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if store.loading || store.calculating { ProgressView().controlSize(.small).accessibilityLabel("Updating analysis") }
                        Button { store.load() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(store.loading).help("Refresh local history (⌘R)")
                        Button { store.exportCSV() } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }.disabled(store.analytics == nil || store.calculating).help("Export filtered commits")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.accentColor)
        .sheet(item: $store.selectedCommit) { commit in CommitDetail(commit: commit).environmentObject(store) }
    }
    private var repositoryName: String { URL(fileURLWithPath: store.snapshot?.path ?? store.initialPath).lastPathComponent }
    var sidebar: some View {
        List(selection: Binding<String?>(get: { store.section }, set: { if let value = $0 { store.navigate(to: value) } })) {
            Section("Repository") {
                ForEach(0..<4) { index in
                    Label(sections[index], systemImage: symbols[index]).tag(sections[index])
                        .padding(.vertical, 5)
                }
            }
            Section {
                Label(sections[4], systemImage: symbols[4]).tag(sections[4]).padding(.vertical, 5)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 9) {
                Label(repositoryName, systemImage: "folder.fill").font(.system(size: 13, weight: .semibold))
                if let snapshot = store.snapshot {
                    Text("\(compact(snapshot.commits.count)) commits · \(String(snapshot.head.prefix(7)))").font(.caption).foregroundStyle(.secondary)
                }
                Button("Open repository…") { store.chooseRepository() }.buttonStyle(.borderless).font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
    }
    var detail: some View {
        VStack(spacing: 0) {
            if let error = store.error {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).textSelection(.enabled)
                    Spacer(); Button("Dismiss") { store.error = nil }
                }.padding(14).background(Color.orange.opacity(0.1))
            }
            if let data = store.analytics {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        heading
                        if store.section == "Methodology" { MethodologyView() }
                        else {
                            if store.snapshot?.shallow == true {
                                Label("Partial history: fetch full history in Terminal, then refresh.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            }
                            if data.commits.isEmpty { EmptyResults { store.reset() } }
                            else {
                                switch store.section {
                                case "Contributors": ContributorsView(data: data)
                                case "Work areas": WorkAreasView(data: data)
                                case "Commit history": CommitHistoryView(data: data)
                                default: OverviewView(data: data)
                                }
                            }
                        }
                    }.padding(28).frame(maxWidth: 1600, alignment: .leading).frame(maxWidth: .infinity)
                }
                .id(store.section + (store.filters.contributor ?? ""))
                .atlasFilterBar(visible: store.section != "Methodology") {
                    FilterBar().padding(14).atlasNavigationGlass().padding(.horizontal, 24).padding(.vertical, 10)
                }
            } else {
                VStack(spacing: 18) {
                    if store.loading || store.calculating { ProgressView(); Text("Reading repository history…").foregroundStyle(.secondary) }
                    else {
                        ContentUnavailableView {
                            Label("Choose a Git repository", systemImage: "folder.badge.person.crop")
                        } actions: {
                            Button("Open Repository…") { store.chooseRepository() }.buttonStyle(.borderedProminent)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.atlasCanvas)
    }
    var heading: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.section == "Methodology" ? store.section : store.filters.contributor.flatMap { store.identities.contributors[$0]?.name } ?? store.section)
                    .font(.system(size: 28, weight: .semibold))
                if let data = store.analytics, store.section != "Methodology" {
                    Text("\(data.start.id) – \(data.end.id)  ·  \(store.filters.clock.rawValue)  ·  \(store.filters.includeMerges ? "Including merges" : "Non-merge commits")")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.filters.contributor != nil && store.section != "Methodology" {
                Button("All contributors") { store.filters.contributor = nil }.buttonStyle(.bordered)
            }
        }
    }
}

struct FilterBar: View {
    @EnvironmentObject var store: AtlasStore
    @State private var customDates = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search names, commits, or paths", text: $store.filters.query).textFieldStyle(.plain)
                }.padding(8).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8)).frame(minWidth: 180)
                Picker("Date range", selection: Binding(get: { store.range }, set: { if $0 == "Custom…" { customDates = true } else { store.setRange($0) } })) {
                    ForEach(["All history", "30 days", "90 days", "365 days", "Custom…"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 125)
                Picker("Work area", selection: $store.filters.area) {
                    Text("All work areas").tag(WorkArea?.none)
                    ForEach(WorkArea.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }.labelsHidden().frame(width: 160)
                Menu {
                    Picker("Accounts", selection: $store.filters.accounts) { ForEach(AccountFilter.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Timezone", selection: $store.filters.clock) { ForEach(ClockMode.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Include merge commits", isOn: $store.filters.includeMerges)
                    Toggle("Combine matching author names", isOn: Binding(get: { store.filters.combineAliases }, set: { value in
                        var f = store.filters; f.contributor = nil; f.combineAliases = value; store.filters = f
                    }))
                    Divider()
                    Button("Reset all filters") { store.reset() }
                } label: { Label("Filters", systemImage: "slider.horizontal.3") }.fixedSize()
            }.font(.system(size: 12))
            if hasChips {
                HStack(spacing: 8) {
                    if let id = store.filters.contributor, let p = store.identities.contributors[id] { chip(p.name) { store.filters.contributor = nil } }
                    if let d = store.filters.selectedDay { chip(d.id) { store.filters.selectedDay = nil } }
                    if let h = store.filters.hour { chip(hourLabel(h)) { store.filters.hour = nil } }
                    if let w = store.filters.weekday { chip(weekdays[w]) { store.filters.weekday = nil } }
                    if store.filters.accounts != .all { chip(store.filters.accounts.rawValue) { store.filters.accounts = .all } }
                    if store.filters.includeMerges { chip("Merges included") { store.filters.includeMerges = false } }
                    if !store.filters.combineAliases { chip("Separate email identities") { store.filters.combineAliases = true } }
                    Spacer()
                    Button("Clear all") { store.reset() }.buttonStyle(.link).font(.system(size: 11))
                }
            }
        }.popover(isPresented: $customDates) { DateRangeEditor().environmentObject(store) }
    }
    var hasChips: Bool { store.filters.contributor != nil || store.filters.selectedDay != nil || store.filters.hour != nil || store.filters.weekday != nil || store.filters.accounts != .all || store.filters.includeMerges || !store.filters.combineAliases }
    func chip(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(spacing: 5) { Text(text); Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.font(.system(size: 11)).padding(.horizontal, 9).padding(.vertical, 5).background(Color.atlasAccent.opacity(0.08), in: Capsule()) }.buttonStyle(.plain).foregroundStyle(Color.atlasAccent)
    }
}

struct DateRangeEditor: View {
    @EnvironmentObject var store: AtlasStore
    @Environment(\.dismiss) var dismiss
    @State private var start = Date()
    @State private var end = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom date range").font(.headline)
            DatePicker("From", selection: $start, displayedComponents: .date)
            DatePicker("Through", selection: $end, in: start..., displayedComponents: .date)
            HStack { Spacer(); Button("Apply") {
                var f = store.filters
                f.start = Day(start, calendar: ClockMode.utc.calendar()); f.end = Day(max(start, end), calendar: ClockMode.utc.calendar()); f.selectedDay = nil
                store.filters = f; store.range = "Custom…"; dismiss()
            }.buttonStyle(.borderedProminent) }
        }.padding(20).frame(width: 300)
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .onAppear { start = store.analytics?.start.date ?? Date(); end = store.analytics?.end.date ?? Date() }
    }
}
