import Foundation
import XCTest

@testable import Sumi

@MainActor
final class BrowserStartupProtectionRuntimeTests: XCTestCase {
    func testMaterializationPolicyDefersOnlyPrimaryNormalTabsUntilRestoreFinishes() {
        var appliedLevel = SumiProtectionLevel.protection
        let runtime = makeRuntime(appliedLevel: { appliedLevel })
        let normalTab = Tab(
            url: URL(string: "https://example.com/article")!,
            loadsCachedFaviconOnInit: false
        )
        let emptyTab = Tab(
            url: SumiSurface.emptyTabURL,
            loadsCachedFaviconOnInit: false
        )
        let extensionTab = Tab(
            url: URL(string: "safari-web-extension://ext-74657374/index.html")!,
            loadsCachedFaviconOnInit: false
        )

        XCTAssertTrue(runtime.shouldDeferNormalTabMaterializationDuringStartup)
        XCTAssertFalse(runtime.canMaterializeNormalTabWebViewDuringStartup(normalTab))
        XCTAssertTrue(runtime.canMaterializeNormalTabWebViewDuringStartup(emptyTab))
        XCTAssertTrue(runtime.canMaterializeNormalTabWebViewDuringStartup(extensionTab))

        runtime.finishStartupProtectionRestore()

        XCTAssertTrue(runtime.hasFinishedProtectionRestore)
        XCTAssertFalse(runtime.shouldDeferNormalTabMaterializationDuringStartup)
        XCTAssertTrue(runtime.canMaterializeNormalTabWebViewDuringStartup(normalTab))

        appliedLevel = .off
        let offRuntime = makeRuntime(appliedLevel: { appliedLevel })

        XCTAssertFalse(offRuntime.shouldDeferNormalTabMaterializationDuringStartup)
        XCTAssertTrue(offRuntime.canMaterializeNormalTabWebViewDuringStartup(normalTab))
    }

    func testFinishDrainsDeferredBackgroundTabsAndVisibleWindowHooksOnce() {
        let deferredTab = Tab(
            url: URL(string: "https://example.com/deferred")!,
            loadsCachedFaviconOnInit: false
        )
        let missingTab = Tab(
            url: URL(string: "https://example.com/missing")!,
            loadsCachedFaviconOnInit: false
        )
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        var preparedTabIds: [UUID] = []
        var scheduledWindowIds: [UUID] = []
        var refreshedWindowIds: [UUID] = []
        let runtime = makeRuntime(
            tab: { tabId in
                tabId == deferredTab.id ? deferredTab : nil
            },
            allWindows: {
                [firstWindow, secondWindow]
            },
            prepareBackgroundTabIfNeeded: { tab in
                preparedTabIds.append(tab.id)
            },
            schedulePrepareVisibleWebViews: { windowState in
                scheduledWindowIds.append(windowState.id)
            },
            refreshCompositor: { windowState in
                refreshedWindowIds.append(windowState.id)
            }
        )

        runtime.deferBackgroundTabUntilStartupReady(deferredTab)
        runtime.deferBackgroundTabUntilStartupReady(missingTab)
        runtime.deferBackgroundTabUntilStartupReady(deferredTab)
        runtime.finishStartupProtectionRestore()
        runtime.finishStartupProtectionRestore()

        XCTAssertEqual(preparedTabIds, [deferredTab.id])
        XCTAssertEqual(Set(scheduledWindowIds), [firstWindow.id, secondWindow.id])
        XCTAssertEqual(Set(refreshedWindowIds), [firstWindow.id, secondWindow.id])
        XCTAssertEqual(scheduledWindowIds.count, 2)
        XCTAssertEqual(refreshedWindowIds.count, 2)
    }

    func testBeginInTestsFinishesWithoutStartingRestoreTask() {
        var restoreCallCount = 0
        let runtime = makeRuntime(
            restoreAppliedProtectionLevelForStartup: {
                restoreCallCount += 1
            }
        )

        runtime.beginProtectionRestoreForStartupIfNeeded()

        XCTAssertTrue(runtime.hasFinishedProtectionRestore)
        XCTAssertEqual(restoreCallCount, 0)
    }

    private func makeRuntime(
        appliedLevel: @escaping () -> SumiProtectionLevel = { .protection },
        restoreAppliedProtectionLevelForStartup: @escaping () async throws -> Void = {},
        tab: @escaping (UUID) -> Tab? = { _ in nil },
        allWindows: @escaping () -> [BrowserWindowState] = { [] },
        prepareBackgroundTabIfNeeded: @escaping (Tab) -> Void = { _ in },
        schedulePrepareVisibleWebViews: @escaping (BrowserWindowState) -> Void = { _ in },
        refreshCompositor: @escaping (BrowserWindowState) -> Void = { _ in }
    ) -> BrowserStartupProtectionRuntime {
        BrowserStartupProtectionRuntime(
            dependencies: BrowserStartupProtectionRuntime.Dependencies(
                appliedProtectionLevel: appliedLevel,
                restoreAppliedProtectionLevelForStartup: restoreAppliedProtectionLevelForStartup,
                tab: tab,
                allWindows: allWindows,
                prepareBackgroundTabIfNeeded: prepareBackgroundTabIfNeeded,
                schedulePrepareVisibleWebViews: schedulePrepareVisibleWebViews,
                refreshCompositor: refreshCompositor
            )
        )
    }
}
