import SwiftUI
import Charts
import AtlasCore

struct MetricsView: View {
    let data: Analytics
    var body: some View {
        HStack(spacing: 0) {
            metric("Commits", compact(data.commits.count), "\(data.people.count) contributors")
            Divider().frame(height: 54)
            metric("Commits / day", decimal(data.dailyAverage), "Across \(data.calendarDays) calendar days")
            Divider().frame(height: 54)
            metric("Active days", compact(data.daily.count), "\(decimal(Double(data.commits.count) / Double(max(1, data.daily.count)))) commits / active day")
            Divider().frame(height: 54)
            metric("Busiest hour", hourLabel(data.peakHour), "\(compact(data.hours[data.peakHour])) commits in this hour")
        }.padding(.vertical, 20).atlasContentSurface()
    }
    func metric(_ title: String, _ value: String, _ foot: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(foot).font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.horizontal, 24).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OverviewView: View {
    @EnvironmentObject var store: AtlasStore
    let data: Analytics
    var years: [Int] { store.availableYears }
    var body: some View {
        MetricsView(data: data)
        CalendarHeatmap(data: data, year: $store.year, years: years, selected: store.filters.selectedDay) { day in store.filters.selectedDay = store.filters.selectedDay == day ? nil : day }
        HStack(alignment: .top, spacing: 18) {
            Panel(title: data.calendarDays > 730 ? "Commits by week" : "Commits by day", detail: "\(decimal(data.dailyAverage)) / calendar day") { DailyChart(data: data) }
            Panel(title: "Commits by hour", detail: "\(frequency(data.hourlyAverage)) / calendar hour") {
                HourChart(hours: data.hours, selected: store.filters.hour) { h in store.filters.hour = store.filters.hour == h ? nil : h }
            }
        }
        Panel(title: "Contributors", detail: "Grouped by primary work area · click a person to explore") { ContributorTable(data: data, grouped: true) }
        Panel(title: "Weekly rhythm", detail: store.filters.clock.rawValue + " · click a cell to filter") {
            WeekHourHeatmap(values: data.weekHours) { day, hour in var f = store.filters; f.weekday = day; f.hour = hour; store.filters = f }
        }
    }
}

struct ContributorsView: View {
    @EnvironmentObject var store: AtlasStore
    let data: Analytics
    @State private var grouped = true
    var selected: ContributorStats? { data.people.first { $0.id == store.filters.contributor } }
    var body: some View {
        if let person = selected {
            HStack(spacing: 14) {
                PersonIcon(bot: person.person.isBot, size: 46)
                VStack(alignment: .leading, spacing: 5) {
                    Text(person.person.emails.joined(separator: "  ·  ")).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack { AreaBadge(area: person.primaryArea); Text("Primary area by changed-file touches").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Spacer()
                if person.person.emails.count > 1 { Text("\(person.person.emails.count) email aliases").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            MetricsView(data: data)
            CalendarHeatmap(data: data, year: $store.year, years: store.availableYears, selected: store.filters.selectedDay) { store.filters.selectedDay = store.filters.selectedDay == $0 ? nil : $0 }
            HStack(alignment: .top, spacing: 18) {
                Panel(title: "Commits by hour", detail: "\(frequency(data.hourlyAverage)) / calendar hour") { HourChart(hours: data.hours, selected: store.filters.hour) { store.filters.hour = store.filters.hour == $0 ? nil : $0 } }
                Panel(title: "Work profile", detail: "Changed-file touches") { AreaBreakdown(areas: person.areas) { store.filters.area = $0 } }
            }
            Panel(title: "Weekly rhythm", detail: store.filters.clock.rawValue) { WeekHourHeatmap(values: data.weekHours) { day, hour in var f = store.filters; f.weekday = day; f.hour = hour; store.filters = f } }
            HStack(alignment: .top, spacing: 18) {
                Panel(title: "Most-touched files") { FileList(files: person.files) }
                Panel(title: "Recent commits", detail: "Latest 8 in current filters") { CommitRows(commits: Array(data.commits.prefix(8))) }
            }
        } else {
            HStack {
                Text("\(data.people.count) contributors").font(.system(size: 15, weight: .medium))
                Spacer()
                Picker("Layout", selection: $grouped) { Text("Work groups").tag(true); Text("Most commits").tag(false) }.pickerStyle(.segmented).labelsHidden().frame(width: 230)
            }
            Panel(title: "Contributor activity", detail: "Averages use the same \(data.calendarDays)-day window for everyone") { ContributorTable(data: data, grouped: grouped) }
            Panel(title: "Work-area matrix", detail: "Commits touching each area · a commit may appear in multiple columns") { WorkMatrix(data: data) }
        }
    }
}

struct ContributorTable: View {
    @EnvironmentObject var store: AtlasStore
    let data: Analytics
    var grouped: Bool
    private var groups: [(String, [ContributorStats])] {
        if !grouped { return [("", data.people)] }
        return Dictionary(grouping: data.people, by: \.primaryArea).map { ($0.key.rawValue, $0.value) }
            .sorted { $0.1.reduce(0) { $0 + $1.commits } > $1.1.reduce(0) { $0 + $1.commits } }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Contributor").frame(maxWidth: .infinity, alignment: .leading)
                Text("Activity").frame(width: 130, alignment: .leading)
                Text("Commits").frame(width: 65, alignment: .trailing)
                Text("/ day").frame(width: 52, alignment: .trailing)
                Text("/ hour").frame(width: 52, alignment: .trailing)
                Text("Active days").frame(width: 72, alignment: .trailing)
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).padding(.bottom, 12)
            ForEach(groups, id: \.0) { group in
                if !group.0.isEmpty {
                    HStack(spacing: 8) {
                        Text(group.0).font(.system(size: 11, weight: .semibold))
                        Text("\(group.1.count)").font(.system(size: 10)).foregroundStyle(.secondary)
                        Rectangle().fill(Color.atlasLine).frame(height: 1)
                    }.padding(.top, 15).padding(.bottom, 7)
                }
                ForEach(group.1) { p in
                    Button { store.inspect(p) } label: {
                        HStack(spacing: 16) {
                            HStack(spacing: 10) {
                                PersonIcon(bot: p.person.isBot)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.person.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                                    Text(p.rankedAreas.prefix(2).map { $0.0.rawValue }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Sparkline(daily: p.daily, start: data.start, end: data.end)
                            Text(compact(p.commits)).fontWeight(.medium).frame(width: 65, alignment: .trailing)
                            Text(decimal(Double(p.commits) / Double(data.calendarDays))).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                            Text(frequency(Double(p.commits) / Double(data.calendarDays * 24))).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                            Text(compact(p.days.count)).foregroundStyle(.secondary).frame(width: 72, alignment: .trailing)
                        }.font(.system(size: 12)).monospacedDigit().padding(.vertical, 11).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider().opacity(0.45)
                }
            }
        }
    }
}

struct WorkAreasView: View {
    @EnvironmentObject var store: AtlasStore
    let data: Analytics
    var body: some View {
        Panel(title: "Who works on what", detail: "Commit counts · click a cell to filter contributor + area") { WorkMatrix(data: data) }
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
            ForEach(WorkArea.allCases.filter { data.areas[$0] != nil }) { area in
                Panel(title: area.rawValue, detail: "\(compact(data.areaCommits[area, default: 0])) commits") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("\(compact(data.areas[area, default: 0])) file touches", systemImage: area.symbol).font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            Button("Explore") { store.filters.area = area; store.section = "Commit history" }.buttonStyle(.link).font(.system(size: 11))
                        }
                        ForEach(data.people.filter { $0.areas[area] != nil }.sorted { $0.areas[area, default: 0] > $1.areas[area, default: 0] }.prefix(5)) { person in
                            Button {
                                var f = store.filters; f.contributor = person.id; f.area = area; store.filters = f; store.section = "Contributors"
                            } label: {
                                HStack {
                                    Text(person.person.name).font(.system(size: 12))
                                    Spacer()
                                    Text("\(Int(Double(person.areas[area, default: 0]) / Double(max(1, data.areas[area, default: 0])) * 100))% of touches").font(.system(size: 11)).foregroundStyle(.secondary)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct WorkMatrix: View {
    @EnvironmentObject var store: AtlasStore
    let data: Analytics
    var areas: [WorkArea] { WorkArea.allCases.filter { data.areas[$0] != nil } }
    var counts: [String: [WorkArea: Int]] {
        var result: [String: [WorkArea: Int]] = [:]
        for c in data.commits {
            let id = store.identities.byEmail[c.email] ?? c.email
            for area in c.areas.keys { result[id, default: [:]][area, default: 0] += 1 }
        }
        return result
    }
    var body: some View {
        let values = counts
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Text("Contributor").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 155, alignment: .leading)
                ForEach(areas) { area in
                    VStack(spacing: 6) { Image(systemName: area.symbol); Text(area.rawValue).font(.system(size: 9)).multilineTextAlignment(.center).lineLimit(2) }
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 44)
                }
            }
            ForEach(data.people) { person in
                let row = values[person.id] ?? [:]
                let maxCount = max(1, row.values.max() ?? 1)
                HStack(spacing: 5) {
                    Button { store.inspect(person) } label: { Text(person.person.name).font(.system(size: 11)).lineLimit(1).frame(width: 155, alignment: .leading) }.buttonStyle(.plain)
                    ForEach(areas) { area in
                        let n = row[area, default: 0]
                        Button {
                            var f = store.filters; f.contributor = person.id; f.area = area; store.filters = f; store.section = "Contributors"
                        } label: {
                            Text(n == 0 ? "–" : compact(n)).font(.system(size: 11, weight: n > 0 ? .medium : .regular)).monospacedDigit()
                                .foregroundStyle(n > maxCount / 2 ? Color.white : Color.primary.opacity(n == 0 ? 0.25 : 0.8))
                                .frame(maxWidth: .infinity).frame(height: 34)
                                .background(n == 0 ? Color.primary.opacity(0.025) : Color.atlasAccent.opacity(0.12 + 0.88 * Double(n) / Double(maxCount)), in: RoundedRectangle(cornerRadius: 4))
                        }.buttonStyle(.plain).disabled(n == 0).help("\(person.person.name): \(n) commits touching \(area.rawValue)")
                    }
                }
            }
            Text("Color intensity is relative to each contributor’s busiest area.").font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }
    }
}

struct AreaBreakdown: View {
    let areas: [WorkArea: Int]
    var select: (WorkArea) -> Void
    var body: some View {
        VStack(spacing: 12) {
            let total = max(1, areas.values.reduce(0, +))
            ForEach(areas.sorted { $0.value > $1.value }.prefix(6), id: \.key) { area, count in
                Button { select(area) } label: {
                    VStack(spacing: 5) {
                        HStack { Text(area.rawValue); Spacer(); Text("\(Int(Double(count) / Double(total) * 100))%").foregroundStyle(.secondary) }.font(.system(size: 11))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.04))
                                Capsule().fill(Color.atlasAccent.opacity(0.65)).frame(width: max(2, geo.size.width * Double(count) / Double(total)))
                            }
                        }.frame(height: 5)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
}

struct FileList: View {
    let files: [String: Int]
    var body: some View {
        VStack(spacing: 12) {
            ForEach(files.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(10), id: \.key) { path, count in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "doc").foregroundStyle(.tertiary)
                    Text(path).lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(path)
                    Spacer(minLength: 0)
                    Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                }.font(.system(size: 11))
            }
        }
    }
}
