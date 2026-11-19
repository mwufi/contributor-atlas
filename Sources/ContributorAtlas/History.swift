import SwiftUI
import AppKit
import AtlasCore

struct CommitHistoryView: View {
    let data: Analytics
    @State private var page = 0
    private let pageSize = 60
    var body: some View {
        Panel(title: "Commit history", detail: "\(compact(data.commits.count)) matching commits") {
            CommitRows(commits: Array(data.commits.dropFirst(page * pageSize).prefix(pageSize)))
            HStack {
                Text("Page \(page + 1) of \(max(1, (data.commits.count + pageSize - 1) / pageSize))").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Previous") { page -= 1 }.disabled(page == 0)
                Button("Next") { page += 1 }.disabled((page + 1) * pageSize >= data.commits.count)
            }
        }.onChange(of: data.commits.map(\.id)) { _, _ in page = 0 }
    }
}

struct CommitRows: View {
    @EnvironmentObject var store: AtlasStore
    let commits: [Commit]
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(commits) { c in
                Button { store.selectedCommit = c } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: c.isMerge ? "arrow.triangle.merge" : "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(.tertiary).frame(width: 18).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(c.subject).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                            HStack(spacing: 8) {
                                Text(store.identities.byEmail[c.email].flatMap { store.identities.contributors[$0]?.name } ?? c.name)
                                Text("·"); Text(Day(c.date, calendar: store.filters.clock.calendar(offset: c.offset)).id)
                                Text("·"); Text("\(c.files.count) files")
                            }.font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Text(String(c.id.prefix(7))).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    }.padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider().opacity(0.5)
            }
        }
    }
}

struct CommitDetail: View {
    @EnvironmentObject var store: AtlasStore
    @Environment(\.dismiss) var dismiss
    let commit: Commit
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full; formatter.timeStyle = .short
        formatter.timeZone = store.filters.clock.calendar(offset: commit.offset).timeZone
        return formatter.string(from: commit.date) + " · " + store.filters.clock.rawValue
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Commit details").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(commit.subject).font(.title2).textSelection(.enabled)
            VStack(alignment: .leading, spacing: 8) {
                Text(commit.name + " <" + commit.email + ">").textSelection(.enabled)
                Text(formattedDate).foregroundStyle(.secondary)
                HStack {
                    Text(commit.id).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(commit.id, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("Copy commit SHA")
                }
            }.font(.system(size: 12))
            Divider()
            HStack {
                Text("Changed files").font(.headline)
                Spacer()
                Text("\(commit.files.count)").foregroundStyle(.secondary)
            }
            if commit.isMerge { Text("Merge diffs are not expanded. Inspect the constituent commits for file-level work.").font(.callout).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(commit.files.enumerated()), id: \.offset) { _, path in
                        HStack(alignment: .top) {
                            Image(systemName: WorkArea.classify(path).symbol).foregroundStyle(.secondary).frame(width: 20)
                            Text(path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            Spacer()
                            Text(WorkArea.classify(path).rawValue).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.padding(28).frame(width: 780, height: 600)
            .environment(\.timeZone, store.filters.clock.calendar(offset: commit.offset).timeZone)
    }
}

struct MethodologyView: View {
    @EnvironmentObject var store: AtlasStore
    var body: some View {
        Panel(title: "What the numbers mean") {
            VStack(alignment: .leading, spacing: 22) {
                note("Scope", "The app reads all commits reachable from the selected checkout’s HEAD, pinned to one SHA at refresh. It does not fetch, change branches, or read GitHub reviews, PR comments, issues, or uncommitted files. Refresh after pulling new history. Shallow clones are explicitly marked.")
                note("Attribution", "Commits belong to their Git author, using repository mailmap normalization. Matching names (case insensitive) and matching emails are combined by default; this is a heuristic, not verified identity. Disable “Combine matching author names” in Filters to separate email identities. Co-authored-by trailers and committers are not counted as separate contributors.")
                note("Frequency", "Commits / day = matching commits ÷ all calendar days in the selected range, including zero days. Commits / hour divides that denominator by 24; it is a calendar-normalized rate, not hours worked. Active-day averages exclude zero days. The hourly chart counts commits by hour of day, and the weekly grid by weekday and hour.")
                note("Dates & timezones", "Activity uses author timestamps. All history spans the earliest to latest authored date. Preset periods end on the latest authored date in the repository, not today. Choose Los Angeles, UTC, or each commit’s author timezone in Filters. Author-local charts compare local clock times, not simultaneous moments. The calendar displays one year at a time while totals retain the full filtered range.")
                note("Work groups", "A changed-file touch is one path in one non-merge commit. Each path is classified by the rules below. A contributor’s primary group is the area with the most file touches in the current filters. The matrix counts commits touching each area, so columns can overlap. These groups describe recorded work; they are not job titles, ownership assignments, quality scores, or productivity rankings. Large imports and formatting changes can dominate touches.")
                note("Merges & automation", "Merges are excluded by default to avoid counting integration activity as implementation work. If included, they contribute to frequency but merge diffs are not expanded. Automated accounts are detected from explicit bot/agent naming patterns; human-authored AI-assisted commits remain attributed to the human author.")
                note("Filtering & export", "All filters apply together. Work-area filters select commits touching that area and restrict file evidence to the selected area. Search matches author, email, SHA, subject, or changed path. Calendar and hour clicks add filters; remove their chips to return to the broader view. CSV exports every matching commit and its full file list, with spreadsheet formula protection.")
            }
        }
        Panel(title: "File classification", detail: "First matching rule wins") {
            VStack(alignment: .leading, spacing: 13) {
                rule(.maintenance, "Generated folders and lockfiles; remaining package manifests and TypeScript configuration.")
                rule(.quality, "Tests, specs, Storybook stories, test folders, Vitest and Playwright configuration.")
                rule(.tooling, "scripts/, tools/, skills/, .agents/, .claude/, .cursor/.")
                rule(.documentation, "docs/ and Markdown files not already classified as tools or tests.")
                rule(.infrastructure, ".github/, infra/, Docker, App Hosting, Firebase and Vercel configuration.")
                rule(.backend, "convex/, services/ and job-search services.")
                rule(.mobile, "apps/cosign-mobile/ and packages/ui/src/native/.")
                rule(.web, "Web app, shared UI, components, assets, public files, hooks and client libraries.")
                rule(.other, "Unmatched paths. Renames count as old/new paths, because rename detection is disabled.")
            }
        }
        if let snapshot = store.snapshot {
            Panel(title: "Current snapshot") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(snapshot.path).textSelection(.enabled)
                    Text("HEAD: \(snapshot.head)").textSelection(.enabled)
                    Text("Indexed \(snapshot.loadedAt.formatted()) · \(snapshot.commits.count) commits · \(snapshot.shallow ? "partial" : "full reachable") history")
                }.font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    func note(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 13, weight: .semibold)); Text(text).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true) }
    }
    func rule(_ area: WorkArea, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 18) { Label(area.rawValue, systemImage: area.symbol).frame(width: 190, alignment: .leading); Text(text).foregroundStyle(.secondary) }.font(.system(size: 12))
    }
}
