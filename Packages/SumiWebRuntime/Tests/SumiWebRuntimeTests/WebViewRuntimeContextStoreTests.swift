import Foundation
import WebKit
import XCTest

@testable import SumiWebRuntime

@MainActor
final class WebViewRuntimeContextStoreTests: XCTestCase {
    func testEnvironmentAttachesAndDetachesAsOneUnit() {
        let store = WebViewRuntimeContextStore()
        let marker = UUID()
        let environment = makeEnvironment(marker: marker)

        XCTAssertNil(store.environment)
        XCTAssertNil(store.browser)

        store.attach(environment)

        XCTAssertNotNil(store.environment)
        XCTAssertEqual(store.requireBrowser().globallyVisibleTabIDs(), [marker])
        XCTAssertEqual(store.requireVisible().globallyVisibleTabIDs(), [marker])
        XCTAssertFalse(store.requireInitialDocument().needsInitialDocumentExtensionContextLoad(marker))

        store.detach()

        XCTAssertNil(store.environment)
        XCTAssertNil(store.browser)
    }

    private func makeEnvironment(marker: UUID) -> WebViewRuntimeEnvironment {
        WebViewRuntimeEnvironment(
            visible: .init(
                windowState: { _ in nil },
                currentTabId: { _ in nil },
                splitVisibleTabIds: { _ in [] },
                resolveTab: { _, _ in nil },
                canMaterializeWebViewDuringStartup: { _ in false },
                markTabAccessed: { _ in },
                globallyVisibleTabIDs: { [marker] },
                scheduleTabSuspensionReconcile: { _ in },
                scheduleBackgroundMediaReconcile: { _ in },
                refreshCompositor: { _ in }
            ),
            browser: .init(
                tab: { _ in nil },
                regularTabs: { [] },
                pinnedTabs: { [] },
                allWindows: { [] },
                window: { _ in nil },
                windowContaining: { _ in nil },
                currentTab: { _ in nil },
                selectTab: { _, _ in },
                handleUnprotectedWebViewDidClose: { _ in false },
                refreshCompositor: { _ in },
                notifyTabActivatedIfLoaded: { _ in },
                globallyVisibleTabIDs: { [marker] }
            ),
            initialDocument: .init(
                needsInitialDocumentExtensionContextLoad: { _ in false },
                ensureInitialExtensionContextsLoaded: { _ in },
                refreshCompositorForWindow: { _ in }
            ),
            shutdown: .init(cleanupUserScripts: { _, _ in })
        )
    }
}
