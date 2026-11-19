import XCTest
@testable import AtlasCore

final class NavigationTests: XCTestCase {
    func testBackAndForwardRestoreFullContributorContext() {
        let overview = AtlasLocation()
        var detail = overview
        detail.section = "Contributors"
        detail.filters.contributor = "person@example.test"
        detail.filters.area = .backend
        detail.filters.clock = .utc
        detail.filters.selectedDay = Day(year: 2026, month: 11, day: 2)
        detail.range = "90 days"; detail.year = 2025
        var history = NavigationHistory(overview)
        history.record(detail)
        XCTAssertEqual(history.back(), overview)
        XCTAssertTrue(history.canGoForward)
        XCTAssertEqual(history.forward(), detail)
        XCTAssertEqual(history.current.filters.contributor, "person@example.test")
        XCTAssertFalse(history.canGoForward)
    }
    func testDivergingAfterBackClearsForwardBranch() {
        var history = NavigationHistory("Overview")
        history.record("Contributors"); history.record("Anna")
        XCTAssertEqual(history.back(), "Contributors")
        history.record("Rory")
        XCTAssertFalse(history.canGoForward)
        XCTAssertNil(history.forward())
        XCTAssertEqual(history.back(), "Contributors")
    }
    func testSearchReplacementKeepsPreSearchDestination() {
        let initial = AtlasLocation(section: "Contributors")
        var typed = initial; typed.filters.query = "A"
        var complete = typed; complete.filters.query = "Anna"
        var history = NavigationHistory(initial)
        history.record(typed)
        XCTAssertTrue(complete.differsOnlyInQuery(from: typed))
        history.record(complete, replacingCurrent: true)
        XCTAssertEqual(history.previous.count, 1)
        XCTAssertEqual(history.back(), initial)
        XCTAssertEqual(history.forward(), complete)
        var other = complete; other.filters.area = .web
        XCTAssertFalse(other.differsOnlyInQuery(from: complete))
    }
    func testDuplicateLocationsAndBoundedHistory() {
        var history = NavigationHistory(0, limit: 2)
        history.record(0)
        XCTAssertFalse(history.canGoBack)
        history.record(1); history.record(2); history.record(3)
        XCTAssertEqual(history.previous, [1, 2])
        XCTAssertEqual(history.back(), 2)
        XCTAssertEqual(history.back(), 1)
        XCTAssertNil(history.back())
    }
    func testRecentAnalysisCacheRespectsRecencyAndCapacity() {
        var cache = RecentCache<String, Int>(capacity: 2)
        cache.insert(1, for: "overview"); cache.insert(2, for: "person")
        XCTAssertEqual(cache.value(for: "overview"), 1)
        cache.insert(3, for: "search")
        XCTAssertNil(cache.value(for: "person"))
        XCTAssertEqual(cache.value(for: "overview"), 1)
        XCTAssertEqual(cache.value(for: "search"), 3)
        cache = RecentCache(capacity: 2)
        XCTAssertNil(cache.value(for: "overview"))
    }
    func testFilterCacheKeyIncludesEveryDrilldownDimension() {
        let original = Filters()
        var changed = original; changed.hour = 4
        var cache = RecentCache<Filters, String>()
        cache.insert("overview", for: original)
        XCTAssertNil(cache.value(for: changed))
        changed = original; changed.combineAliases = false
        XCTAssertNil(cache.value(for: changed))
        changed = original; changed.clock = .author
        XCTAssertNil(cache.value(for: changed))
    }
}
