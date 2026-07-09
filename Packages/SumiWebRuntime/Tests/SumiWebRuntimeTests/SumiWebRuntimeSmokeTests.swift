import XCTest
import SumiWebRuntime

final class SumiWebRuntimeSmokeTests: XCTestCase {
    @MainActor
    func testRegistryStartsEmpty() {
        let registry = WindowWebViewRegistry()
        XCTAssertTrue(registry.isEmpty)
        XCTAssertEqual(registry.totalTrackedWebViewCount, 0)
    }

    func testVisibleTabPreparationPlanOrdersSplitTabs() {
        let tabA = UUID()
        let tabB = UUID()
        let ordered = VisibleTabPreparationPlan.visibleTabIDs(
            currentTabId: tabA,
            splitTabIds: [tabB, tabA]
        )
        XCTAssertEqual(ordered, [tabB, tabA])
    }
}
