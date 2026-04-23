import XCTest

@testable import Sumi

final class HistoryRangeTests: XCTestCase {
    func testDisplayedRangesStartTodayAndEndWithOlder() {
        let referenceDate = ISO8601DateFormatter().date(from: "2026-04-23T12:00:00Z")!

        let ranges = DataModel.HistoryRange.displayedRanges(
            for: referenceDate,
            calendar: makeUTCCalendar()
        )

        XCTAssertEqual(ranges.first, .today)
        XCTAssertEqual(ranges.last, .older)
        XCTAssertTrue(ranges.contains(.yesterday))
    }

    func testHistorySurfaceURLRoundTripsRange() {
        let url = SumiSurface.historySurfaceURL(
            rangeQuery: DataModel.HistoryRange.older.paneQueryValue
        )

        XCTAssertTrue(SumiSurface.isHistorySurfaceURL(url))
        XCTAssertEqual(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "range" })?
                .value,
            DataModel.HistoryRange.older.paneQueryValue
        )
    }
    private func makeUTCCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
