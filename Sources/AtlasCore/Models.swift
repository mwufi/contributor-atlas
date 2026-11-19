import Foundation

public enum WorkArea: String, CaseIterable, Codable, Identifiable, Sendable {
    case backend = "Backend & data"
    case web = "Web & design"
    case mobile = "Mobile"
    case quality = "Tests & quality"
    case infrastructure = "Infrastructure"
    case tooling = "Tools & agents"
    case documentation = "Documentation"
    case maintenance = "Dependencies & generated"
    case other = "Other"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .backend: "externaldrive"
        case .web: "rectangle.3.group"
        case .mobile: "iphone"
        case .quality: "checkmark.seal"
        case .infrastructure: "server.rack"
        case .tooling: "terminal"
        case .documentation: "doc.text"
        case .maintenance: "shippingbox"
        case .other: "folder"
        }
    }
    public static func classify(_ path: String) -> WorkArea {
        let p = path.lowercased()
        let file = p.split(separator: "/").last.map(String.init) ?? p
        if p.contains("/_generated/") || p.contains("/generated/") || ["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "package.resolved", "skills-lock.json"].contains(file) { return .maintenance }
        if p.contains(".test.") || p.contains(".spec.") || p.contains(".stories.") || p.hasPrefix("tests/") || p.contains("/__tests__/") || p.contains("/test/") || p.contains("/tests/") || p.hasPrefix("e2e/") || file.hasPrefix("vitest") || file.hasPrefix("playwright") { return .quality }
        if p.hasPrefix(".agents/") || p.hasPrefix(".claude/") || p.hasPrefix(".cursor/") || p.hasPrefix("skills/") || p.hasPrefix("scripts/") || p.hasPrefix("tools/") { return .tooling }
        if p.hasPrefix("docs/") || file.hasSuffix(".md") || file.hasSuffix(".mdx") { return .documentation }
        if p.hasPrefix(".github/") || p.hasPrefix("infra/") || file.contains("dockerfile") || file.hasPrefix("apphosting") || file.hasPrefix("firebase") || file.hasPrefix("vercel") { return .infrastructure }
        if p.hasPrefix("convex/") || p.hasPrefix("services/") || p.hasPrefix("apps/job-search") { return .backend }
        if p.hasPrefix("apps/cosign-mobile/") || p.hasPrefix("packages/ui/src/native/") { return .mobile }
        if p.hasPrefix("apps/cosign-main/") || p.hasPrefix("app/") || p.hasPrefix("components/") || p.hasPrefix("packages/ui/") || p.hasPrefix("assets/") || p.hasPrefix("public/") || p.hasPrefix("lib/") || p.hasPrefix("hooks/") { return .web }
        if file == "package.json" || file.contains("tsconfig") { return .maintenance }
        return .other
    }
}

public struct Commit: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var email: String
    public var date: Date
    public var offset: Int
    public var parents: [String]
    public var subject: String
    public var files: [String]
    public var areas: [WorkArea: Int]
    public var filesByArea: [WorkArea: [String]]
    public var isMerge: Bool { parents.count > 1 }
    public var isBot: Bool {
        let s = (name + " " + email).lowercased()
        return s.contains("[bot]") || s.contains("cursoragent") || s.contains("cursor agent") || s.contains("dependabot") || s.contains("github-actions") || s.contains("renovate")
    }
    public init(id: String, name: String, email: String, date: Date, offset: Int = 0, parents: [String] = [], subject: String, files: [String]) {
        self.id = id; self.name = name; self.email = email.lowercased(); self.date = date
        self.offset = offset; self.parents = parents; self.subject = subject; self.files = files
        self.filesByArea = Dictionary(grouping: files, by: WorkArea.classify)
        self.areas = filesByArea.mapValues(\.count)
    }
}

public struct RepositorySnapshot: Sendable {
    public var path: String
    public var branch: String
    public var head: String
    public var shallow: Bool
    public let commits: [Commit]
    public let timing: [ClockMode: [CommitTime]]
    public var loadedAt: Date
    public init(path: String, branch: String, head: String, shallow: Bool, commits: [Commit], loadedAt: Date = Date()) {
        self.path = path; self.branch = branch; self.head = head; self.shallow = shallow; self.commits = commits; self.loadedAt = loadedAt
        self.timing = Dictionary(uniqueKeysWithValues: ClockMode.allCases.map { clock in
            let fixed = clock.calendar()
            let calendars = Dictionary(uniqueKeysWithValues: Set(commits.map(\.offset)).map { ($0, clock.calendar(offset: $0)) })
            return (clock, commits.map { commit in
                let calendar = clock == .author ? calendars[commit.offset]! : fixed
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: commit.date)
                return CommitTime(day: Day(year: parts.year!, month: parts.month!, day: parts.day!), hour: parts.hour!, weekday: (parts.weekday! + 5) % 7)
            })
        })
    }
}

public struct CommitTime: Sendable {
    public let day: Day
    public let hour: Int
    public let weekday: Int
}

public enum ClockMode: String, CaseIterable, Identifiable, Sendable {
    case pacific = "Los Angeles", utc = "UTC", author = "Author’s timezone"
    public var id: String { rawValue }
    public func calendar(offset: Int = 0) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = switch self {
        case .pacific: TimeZone(identifier: "America/Los_Angeles")!
        case .utc: TimeZone(secondsFromGMT: 0)!
        case .author: TimeZone(secondsFromGMT: offset) ?? TimeZone(secondsFromGMT: 0)!
        }
        return c
    }
}

public struct Day: Hashable, Comparable, Identifiable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public var id: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public init(_ date: Date, calendar: Calendar) {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        year = p.year!; month = p.month!; day = p.day!
    }
    public init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }
    public var date: Date { ClockMode.utc.calendar().date(from: DateComponents(year: year, month: month, day: day))! }
    public static func < (lhs: Day, rhs: Day) -> Bool { (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day) }
    public func adding(_ n: Int) -> Day { Day(ClockMode.utc.calendar().date(byAdding: .day, value: n, to: date)!, calendar: ClockMode.utc.calendar()) }
    public var weekday: Int { (ClockMode.utc.calendar().component(.weekday, from: date) + 5) % 7 }
}

public enum AccountFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Everyone", people = "People", bots = "Automated accounts"
    public var id: String { rawValue }
}
public struct Filters: Hashable, Sendable {
    public var start: Day?
    public var end: Day?
    public var contributor: String?
    public var area: WorkArea?
    public var query = ""
    public var includeMerges = false
    public var accounts: AccountFilter = .all
    public var combineAliases = true
    public var clock: ClockMode = .pacific
    public var selectedDay: Day?
    public var hour: Int?
    public var weekday: Int?
    public init() {}
}

public struct Contributor: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var emails: [String]
    public var names: [String]
    public var isBot: Bool
}

/// Exact normalized names and exact emails form connected components. This is
/// an inspectable heuristic; disable it to group exclusively by mailmapped email.
public struct IdentityIndex: Sendable {
    public var contributors: [String: Contributor] = [:]
    public var byEmail: [String: String] = [:]
    public init(commits: [Commit], combineAliases: Bool) {
        var parent: [String: String] = [:]
        func root(_ x: String) -> String {
            var current = x
            while let p = parent[current], p != current { current = p }
            return current
        }
        var nameOwner: [String: String] = [:]
        for c in commits {
            if parent[c.email] == nil { parent[c.email] = c.email }
            if combineAliases {
                let name = c.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !name.isEmpty, let previous = nameOwner[name] {
                    let a = root(c.email), b = root(previous)
                    parent[max(a, b)] = min(a, b)
                } else if !name.isEmpty { nameOwner[name] = c.email }
            }
        }
        var groups: [String: [Commit]] = [:]
        for c in commits {
            let key = root(c.email)
            byEmail[c.email] = key
            groups[key, default: []].append(c)
        }
        for (key, values) in groups {
            let names = Set(values.map(\.name)).sorted()
            // Prefer a full display name over a handle, then the most-used name.
            let counts = Dictionary(grouping: values, by: \.name).mapValues(\.count)
            let name = names.sorted {
                if $0.contains(" ") != $1.contains(" ") { return $0.contains(" ") }
                if counts[$0] != counts[$1] { return counts[$0, default: 0] > counts[$1, default: 0] }
                return $0 < $1
            }.first ?? key
            contributors[key] = Contributor(id: key, name: name, emails: Set(values.map(\.email)).sorted(), names: names, isBot: values.allSatisfy(\.isBot))
        }
    }
}

public struct ContributorStats: Identifiable, Sendable {
    public var person: Contributor
    public var commits: Int = 0
    public var days: Set<Day> = []
    public var daily: [Day: Int] = [:]
    public var hours: [Int] = Array(repeating: 0, count: 24)
    public var areas: [WorkArea: Int] = [:]
    public var files: [String: Int] = [:]
    public var id: String { person.id }
    public var primaryArea: WorkArea { rankedAreas.first?.0 ?? .other }
    public var rankedAreas: [(WorkArea, Int)] { areas.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value } }
    public var peakHour: Int { hours.indices.max(by: { hours[$0] < hours[$1] }) ?? 0 }
    mutating func record(day: Day, hour: Int, paths: [String], work: [WorkArea: Int]) {
        commits += 1; days.insert(day); daily[day, default: 0] += 1; hours[hour] += 1
        for (area, count) in work { areas[area, default: 0] += count }
        for path in paths { files[path, default: 0] += 1 }
    }
}

public struct Analytics: Sendable {
    public var commits: [Commit] = []
    public var people: [ContributorStats] = []
    public var daily: [Day: Int] = [:]
    public var hours: [Int] = Array(repeating: 0, count: 24)
    public var weekHours: [Int] = Array(repeating: 0, count: 168)
    public var areas: [WorkArea: Int] = [:]
    public var areaCommits: [WorkArea: Int] = [:]
    public var files: [String: Int] = [:]
    public var start: Day
    public var end: Day
    public var calendarDays: Int { max(1, ClockMode.utc.calendar().dateComponents([.day], from: start.date, to: end.date).day! + 1) }
    public var dailyAverage: Double { Double(commits.count) / Double(calendarDays) }
    public var hourlyAverage: Double { Double(commits.count) / Double(calendarDays * 24) }
    public var peakHour: Int { hours.indices.max(by: { hours[$0] < hours[$1] }) ?? 0 }
    public var fileTouches: Int { files.values.reduce(0, +) }
    public init(snapshot: RepositorySnapshot, filters: Filters, identities: IdentityIndex) {
        let clock = filters.clock
        let times = snapshot.timing[clock]!
        let dates = times.map(\.day)
        let fallback = Day(snapshot.loadedAt, calendar: clock.calendar())
        start = filters.start ?? dates.min() ?? fallback
        end = filters.end ?? dates.max() ?? fallback
        var stats: [String: ContributorStats] = [:]
        let query = filters.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (position, c) in snapshot.commits.enumerated() {
            let key = identities.byEmail[c.email] ?? c.email
            guard let person = identities.contributors[key] else { continue }
            let time = times[position]
            let day = time.day, hour = time.hour
            guard day >= start, day <= end,
                filters.includeMerges || !c.isMerge,
                filters.contributor == nil || filters.contributor == key,
                filters.area == nil || c.areas[filters.area!] != nil,
                filters.accounts != .people || !person.isBot,
                filters.accounts != .bots || person.isBot,
                filters.selectedDay == nil || filters.selectedDay == day,
                filters.hour == nil || filters.hour == hour,
                filters.weekday == nil || filters.weekday == time.weekday
            else { continue }
            if !query.isEmpty && !(c.subject + " " + c.id + " " + c.name + " " + c.email + " " + c.files.joined(separator: " ")).lowercased().contains(query) { continue }
            commits.append(c)
            daily[day, default: 0] += 1; hours[hour] += 1; weekHours[time.weekday * 24 + hour] += 1
            // Mutate in place: copying a contributor's growing file dictionary on
            // every commit made aggregation quadratic for prolific contributors.
            let paths = filters.area.map { c.filesByArea[$0] ?? [] } ?? c.files
            let work = filters.area.map { area in c.areas.filter { $0.key == area } } ?? c.areas
            stats[key, default: ContributorStats(person: person)].record(day: day, hour: hour, paths: paths, work: work)
            for path in paths { files[path, default: 0] += 1 }
            for (area, count) in work {
                areas[area, default: 0] += count
                areaCommits[area, default: 0] += 1
            }
        }
        commits.sort { $0.date > $1.date }
        people = stats.values.sorted { $0.commits == $1.commits ? $0.person.name < $1.person.name : $0.commits > $1.commits }
    }
}
