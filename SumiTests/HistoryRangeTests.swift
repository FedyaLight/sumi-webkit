import XCTest

@testable import Sumi

final class HistoryRangeTests: XCTestCase {
    func testDisplayedRangesStartTodayAndEndWithOlder() {
        let referenceDate = ISO8601DateFormatter().date(from: "2026-04-23T12:00:00Z")!

        let ranges = HistoryRange.displayedRanges(
            for: referenceDate,
            calendar: makeUTCCalendar()
        )

        XCTAssertEqual(ranges.first, .today)
        XCTAssertEqual(ranges.last, .older)
        XCTAssertTrue(ranges.contains(.yesterday))
    }

    func testHistorySurfaceURLRoundTripsRange() {
        let url = SumiSurface.historySurfaceURL(
            rangeQuery: HistoryRange.older.paneQueryValue
        )

        XCTAssertTrue(SumiSurface.isHistorySurfaceURL(url))
        XCTAssertEqual(SumiSurface.historyRange(from: url), .older)
    }

    func testOlderRangeStartsBeforeDisplayedWeekOnly() throws {
        let calendar = makeUTCCalendar()
        let referenceDate = ISO8601DateFormatter().date(from: "2026-04-23T12:00:00Z")!
        let range = try XCTUnwrap(HistoryRange.older.dateRange(for: referenceDate, calendar: calendar))

        let sixDaysAgo = ISO8601DateFormatter().date(from: "2026-04-17T00:00:00Z")!
        let sevenDaysAgo = ISO8601DateFormatter().date(from: "2026-04-16T23:59:59Z")!

        XCTAssertFalse(range.contains(sixDaysAgo))
        XCTAssertTrue(range.contains(sevenDaysAgo))
    }

    private func makeUTCCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
