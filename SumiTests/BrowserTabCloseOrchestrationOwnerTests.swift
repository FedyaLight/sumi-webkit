import XCTest

@testable import Sumi

@MainActor
final class BrowserTabCloseOrchestrationOwnerTests: XCTestCase {
    func testCloseCurrentTabInExplicitWindowIgnoresDifferentActiveWindow() {
        let explicitWindow = BrowserWindowState()
        let activeWindow = BrowserWindowState()
        let glanceManager = GlanceManager()
        var currentTabWindowIds: [UUID] = []
        var emptyStateWindowIds: [UUID] = []
        let owner = BrowserTabCloseOrchestrationOwner(
            dependencies: BrowserTabCloseOrchestrationOwner.Dependencies(
                activeWindow: { activeWindow },
                currentTab: { windowState in
                    currentTabWindowIds.append(windowState.id)
                    return nil
                },
                glanceManager: glanceManager,
                tabManager: { fatalError("tabManager should not be used") },
                fallbackPlanner: { fatalError("fallbackPlanner should not be used") },
                shortcutLiveTabCloseOwner: {
                    fatalError("shortcutLiveTabCloseOwner should not be used")
                },
                selectTab: { _, _ in fatalError("selectTab should not be used") },
                performImmediateVisualHandoffIfPossible: { _ in
                    fatalError("visual handoff should not be used")
                },
                showEmptyState: { windowState in
                    emptyStateWindowIds.append(windowState.id)
                },
                persistWindowSession: { _ in
                    fatalError("persistWindowSession should not be used")
                }
            )
        )

        owner.closeCurrentTab(in: explicitWindow)

        XCTAssertEqual(currentTabWindowIds, [explicitWindow.id])
        XCTAssertEqual(emptyStateWindowIds, [explicitWindow.id])
    }
}
