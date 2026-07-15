import Foundation
import XCTest

/// Hermetic end-to-end oracle for the native sidebar reorder gesture. It
/// observes the rendered row order directly and does not depend on test-only
/// drag markers or repeated SQLite reads.
@MainActor
final class SumiSidebarDragReorderOracleUITests: SumiLaunchSmokeUITestCase {
    func testRegularTabDragReordersVisibleSidebarRows() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5), "The browser window did not appear")

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)

        let source = element(withIdentifier: "tab-row-\(fixture.regularTabID)", in: app)
        let target = element(withIdentifier: "tab-row-\(fixture.secondaryRegularTabID)", in: app)
        XCTAssertTrue(source.waitForExistence(timeout: 5), "The source regular tab row is missing")
        XCTAssertTrue(target.waitForExistence(timeout: 5), "The target regular tab row is missing")
        XCTAssertLessThan(source.frame.midY, target.frame.midY, "The fixture regular-tab order is invalid")

        let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.6, thenDragTo: end)

        let rows = [source, target]
        let reordered = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let elements = object as? [XCUIElement], elements.count == 2 else {
                    return false
                }
                return elements[0].exists
                    && elements[1].exists
                    && elements[0].frame.midY > elements[1].frame.midY
            },
            object: rows
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [reordered], timeout: 5),
            .completed,
            "Dragging the first regular tab below its sibling did not reorder the rendered rows"
        )
    }
}
