import AppKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowShellServiceTests: XCTestCase {
    func testCreateIncognitoWindowShowsFloatingBarEmptyStateWithoutCreatingEmptyTab() throws {
        let harness = makeHarness()
        let service = BrowserWindowShellService()
        var emptyStateWindowIds: [UUID] = []

        let context = makeContext(harness: harness) { windowState in
            emptyStateWindowIds.append(windowState.id)
            windowState.currentTabId = nil
            windowState.ephemeralTabs.removeAll()
            windowState.isShowingEmptyState = true
            windowState.floatingBarDraftText = ""
            windowState.floatingBarDraftNavigatesCurrentTab = false
            windowState.floatingBarPresentationReason = .emptySpace
            windowState.isFloatingBarVisible = true
        }

        service.createIncognitoWindow(using: context)

        guard let windowState = harness.windowRegistry.allWindows.first else {
            return XCTFail("Expected an incognito window to be registered.")
        }
        defer {
            windowState.window?.close()
            harness.windowRegistry.unregister(windowState.id)
        }

        XCTAssertTrue(windowState.isIncognito)
        XCTAssertEqual(emptyStateWindowIds, [windowState.id])
        XCTAssertTrue(windowState.ephemeralTabs.isEmpty)
        XCTAssertNil(windowState.currentTabId)
        XCTAssertTrue(windowState.isShowingEmptyState)
        XCTAssertTrue(windowState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .emptySpace)
        XCTAssertEqual(windowState.floatingBarDraftText, "")
        XCTAssertFalse(windowState.floatingBarDraftNavigatesCurrentTab)

        let ephemeralProfile = try XCTUnwrap(windowState.ephemeralProfile)
        XCTAssertTrue(ephemeralProfile.isEphemeral)
        XCTAssertFalse(ephemeralProfile.dataStore.isPersistent)
        XCTAssertFalse(harness.profileManager.profiles.contains { $0.id == ephemeralProfile.id })
    }

    func testEphemeralTabsUseMonotonicIndexesAndIncognitoCleanupIsIdempotent() async throws {
        let harness = makeHarness()
        let service = BrowserWindowShellService()
        let context = makeContext(harness: harness) { windowState in
            windowState.currentTabId = nil
            windowState.isShowingEmptyState = true
            windowState.floatingBarPresentationReason = .emptySpace
            windowState.isFloatingBarVisible = true
        }

        service.createIncognitoWindow(using: context)

        let windowState = try XCTUnwrap(harness.windowRegistry.allWindows.first)
        defer {
            windowState.window?.close()
            harness.windowRegistry.unregister(windowState.id)
        }

        let profile = try XCTUnwrap(windowState.ephemeralProfile)
        let firstTab = harness.tabManager.createEphemeralTab(
            url: try XCTUnwrap(URL(string: "https://example.com/one")),
            in: windowState,
            profile: profile
        )
        let secondTab = harness.tabManager.createEphemeralTab(
            url: try XCTUnwrap(URL(string: "https://example.com/two")),
            in: windowState,
            profile: profile
        )

        XCTAssertEqual(firstTab.index, 0)
        XCTAssertEqual(secondTab.index, 1)
        XCTAssertEqual(windowState.currentTabId, secondTab.id)
        XCTAssertFalse(profile.dataStore.isPersistent)

        await service.closeIncognitoWindow(windowState, using: context)
        await service.closeIncognitoWindow(windowState, using: context)

        XCTAssertTrue(windowState.ephemeralTabs.isEmpty)
        XCTAssertTrue(windowState.ephemeralSpaces.isEmpty)
        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentSpaceId)
        XCTAssertNil(windowState.ephemeralProfile)
    }

    private struct Harness {
        let windowRegistry: WindowRegistry
        let webViewCoordinator: WebViewCoordinator
        let profileManager: ProfileManager
        let tabManager: TabManager
    }

    private func makeHarness() -> Harness {
        let context = SumiStartupPersistence.shared.container.mainContext
        let profileManager = ProfileManager(context: context)
        let tabManager = TabManager(browserManager: nil, context: context)
        return Harness(
            windowRegistry: WindowRegistry(),
            webViewCoordinator: WebViewCoordinator(),
            profileManager: profileManager,
            tabManager: tabManager
        )
    }

    private func makeContext(
        harness: Harness,
        showEmptyState: @escaping @MainActor (BrowserWindowState) -> Void
    ) -> BrowserWindowShellService.Context {
        BrowserWindowShellService.Context(
            windowRegistry: harness.windowRegistry,
            webViewCoordinator: harness.webViewCoordinator,
            permissionLifecycleController: nil,
            profileManager: harness.profileManager,
            tabManager: harness.tabManager,
            makeContentView: { _, _, _ in NSView() },
            showEmptyState: showEmptyState
        )
    }
}
