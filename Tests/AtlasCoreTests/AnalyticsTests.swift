import XCTest
@testable import AtlasCore

final class AnalyticsTests: XCTestCase {
    let parser = ISO8601DateFormatter()
    func commit(_ id: String, _ date: String, name: String = "Alice Doe", email: String = "alice@work.test", files: [String] = ["convex/users.ts"], parents: [String] = [], offset: Int = 0) -> Commit {
        Commit(id: id, name: name, email: email, date: parser.date(from: date)!, offset: offset, parents: parents, subject: "Implement behavior", files: files)
    }
    func snapshot(_ commits: [Commit]) -> RepositorySnapshot { RepositorySnapshot(path: "/test", branch: "main", head: "abc", shallow: false, commits: commits) }
    func analyze(_ commits: [Commit], filters: Filters = Filters()) -> Analytics {
        Analytics(snapshot: snapshot(commits), filters: filters, identities: IdentityIndex(commits: commits, combineAliases: filters.combineAliases))
    }
    func testCalendarDenominatorIncludesZeroDaysAndMergesAreExcluded() {
        let commits = [commit("a", "2026-11-01T12:00:00Z"), commit("b", "2026-11-03T12:00:00Z"), commit("c", "2026-11-03T12:00:00Z", parents: ["a", "b"])]
        let data = analyze(commits)
        XCTAssertEqual(data.commits.count, 2); XCTAssertEqual(data.calendarDays, 3)
        XCTAssertEqual(data.dailyAverage, 2.0 / 3, accuracy: 0.00001)
        XCTAssertEqual(data.daily.count, 2)
        var filters = Filters(); filters.includeMerges = true
        XCTAssertEqual(analyze(commits, filters: filters).commits.count, 3)
    }
    func testTimezoneDayAndHourBoundariesAndDST() {
        let commits = [commit("a", "2026-11-02T01:00:00Z", offset: 19800)]
        var f = Filters(); f.clock = .pacific
        let pacific = analyze(commits, filters: f)
        XCTAssertEqual(pacific.start.id, "2026-11-01"); XCTAssertEqual(pacific.hours[17], 1)
        f.clock = .utc
        XCTAssertEqual(analyze(commits, filters: f).start.id, "2026-11-02")
        f.clock = .author
        XCTAssertEqual(analyze(commits, filters: f).hours[6], 1)
    }
    func testAliasesAreTransitiveAndCanBeSeparated() {
        let commits = [commit("a", "2026-11-01T12:00:00Z"), commit("b", "2026-11-01T12:00:00Z", email: "alice@home.test"), commit("c", "2026-11-01T12:00:00Z", name: "alice-handle", email: "alice@home.test")]
        let index = IdentityIndex(commits: commits, combineAliases: true)
        XCTAssertEqual(index.contributors.count, 1)
        XCTAssertEqual(index.contributors.values.first?.name, "Alice Doe")
        XCTAssertEqual(IdentityIndex(commits: commits, combineAliases: false).contributors.count, 2)
    }
    func testAreaCountsAndSearchUseIntersectedPopulation() {
        let commits = [commit("a", "2026-11-01T12:00:00Z", files: ["convex/users.ts", "convex/users.test.ts", "app/page.tsx"]), commit("b", "2026-11-02T12:00:00Z", name: "Bob", email: "bob@test", files: ["app/page.tsx"])]
        var f = Filters(); f.area = .backend
        let data = analyze(commits, filters: f)
        XCTAssertEqual(data.commits.count, 1); XCTAssertEqual(data.fileTouches, 1)
        XCTAssertNil(data.areas[.quality]); XCTAssertEqual(data.people[0].primaryArea, .backend)
        f.query = "bob"; XCTAssertTrue(analyze(commits, filters: f).commits.isEmpty)
        f.query = "users.test"; XCTAssertEqual(analyze(commits, filters: f).commits.count, 1)
    }
    func testDayHourWeekdayAndAccountFilters() {
        let commits = [commit("a", "2026-11-02T18:00:00Z"), commit("b", "2026-11-03T18:00:00Z", name: "cursor[bot]", email: "cursor[bot]@test")]
        var f = Filters(); f.clock = .utc; f.weekday = 0; f.hour = 18
        XCTAssertEqual(analyze(commits, filters: f).commits.map(\.id), ["a"])
        f.weekday = nil; f.accounts = .bots
        XCTAssertEqual(analyze(commits, filters: f).commits.map(\.id), ["b"])
        f.selectedDay = Day(year: 2026, month: 11, day: 2)
        XCTAssertTrue(analyze(commits, filters: f).commits.isEmpty)
    }
    func testClassificationPrecedence() {
        XCTAssertEqual(WorkArea.classify("convex/_generated/api.d.ts"), .maintenance)
        XCTAssertEqual(WorkArea.classify("convex/users.test.ts"), .quality)
        XCTAssertEqual(WorkArea.classify(".agents/skills/example/SKILL.md"), .tooling)
        XCTAssertEqual(WorkArea.classify("packages/ui/src/native/features/Profile.tsx"), .mobile)
        XCTAssertEqual(WorkArea.classify("packages/ui/src/web/Profile.tsx"), .web)
    }
    func testNulParsingHandlesSpacesTabsAndNewlinesInPaths() throws {
        let sha = String(repeating: "a", count: 40)
        let log = "\u{1e}\(sha)\0Alice Doe\0alice@test\02026-11-01T01:30:00-07:00\0\0Subject with spaces\0\npath with space.ts\0tab\tname.ts\0line\nbreak.ts\0"
        let commits = try GitRepository.parse(log)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].files, ["path with space.ts", "tab\tname.ts", "line\nbreak.ts"])
        XCTAssertEqual(commits[0].offset, -25200)
        XCTAssertEqual(commits[0].parents, [])
        XCTAssertThrowsError(try GitRepository.parse("\u{1e}bad input"))
    }
    func testGitReaderAgainstTemporaryRepository() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try GitRepository.run(["init", "-b", "main"], path: url.path)
        _ = try GitRepository.run(["config", "user.name", "Test Person"], path: url.path)
        _ = try GitRepository.run(["config", "user.email", "test@example.invalid"], path: url.path)
        try "content".write(to: url.appendingPathComponent("file with space.md"), atomically: true, encoding: .utf8)
        _ = try GitRepository.run(["add", "."], path: url.path)
        _ = try GitRepository.run(["-c", "commit.gpgsign=false", "commit", "-m", "Initial file"], path: url.path)
        let result = try GitRepository.load(path: url.path)
        XCTAssertEqual(result.commits.count, 1)
        XCTAssertEqual(result.commits[0].files, ["file with space.md"])
        XCTAssertEqual(result.branch, "main"); XCTAssertFalse(result.shallow)
    }
}
