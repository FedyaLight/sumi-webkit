import SumiDomain
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ActivePageBrowserManagerIntegrationTests: XCTestCase {
    func testPinnedSplitPhysicalPageFocusChangesURLBarContextToClickedPin() throws {
        let registry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(
                database: try makeInMemoryStartupDatabase()
            )
        )
        let profile = try XCTUnwrap(browserManager.currentProfile)
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Pinned split focus",
            profileID: profile.id
        )
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        registry.register(windowState)
        registry.setActive(windowState)
        let folder = TabFolder(
            name: "Pinned split folder",
            spaceId: space.id,
            index: 0
        )
        browserManager.folderCollectionStateOwner.replaceFoldersBySpace([
            space.id: [folder],
        ])

        let firstPin = try XCTUnwrap(
            browserManager.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .spacePinned,
                    executionProfileId: nil,
                    spaceId: space.id,
                    index: 0,
                    folderId: folder.id,
                    launchURL: URL(string: "https://first-pinned.example")!,
                    title: "First pinned"
                ),
                at: 0
            )
        )
        let secondPin = try XCTUnwrap(
            browserManager.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .spacePinned,
                    executionProfileId: nil,
                    spaceId: space.id,
                    index: 1,
                    folderId: folder.id,
                    launchURL: URL(string: "https://second-pinned.example")!,
                    title: "Second pinned"
                ),
                at: 1
            )
        )
        let first = try XCTUnwrap(
            browserManager.shortcutTabMaterializer.materialize(
                firstPin,
                in: windowState.id,
                currentSpaceId: space.id
            )
        )
        let second = try XCTUnwrap(
            browserManager.shortcutTabMaterializer.materialize(
                secondPin,
                in: windowState.id,
                currentSpaceId: space.id
            )
        )
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .shortcutPin(firstPin.id),
                    .shortcutPin(secondPin.id),
                ],
                layoutKind: .vertical,
                container: .shortcutSidebar(
                    spaceId: space.id,
                    profileId: nil,
                    folderId: folder.id,
                    index: 0
                )
            )
        )
        XCTAssertTrue(browserManager.splitGroupMutations.insert(group, persist: false))
        windowState.currentTabId = first.id
        windowState.currentShortcutPinRole = .spacePinned
        windowState.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .shortcutPin(firstPin.id)
        )

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profile.dataStore
        let secondWebView = FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
        secondWebView.owningTab = second
        XCTAssertTrue(
            browserManager.testWebViewRuntime().trackedWebViewAdmission
                .registerAuxiliaryTrackedWebView(
                    secondWebView,
                    for: second,
                    in: windowState.id
                )
                .isAccepted
        )
        XCTAssertNil(second.profileId)
        XCTAssertTrue(
            second.linkPresentationCommands.activateSource(of: secondWebView)
        )

        let page = try XCTUnwrap(
            browserManager.urlBarBundle.contextOwner.urlBarContext
                .activePage(windowState)
        )
        XCTAssertIdentical(page.tab, second)
        XCTAssertEqual(windowState.currentTabId, second.id)
        XCTAssertEqual(
            windowState.splitSelection?.activeMemberID,
            .shortcutPin(secondPin.id)
        )
    }

    func testResolverUsesSelectedIncognitoTabAndExactWindowWebView() throws {
        let registry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupDatabase()
            )
        )
        let webViewRuntime = browserManager.testWebViewRuntime()
        let window = BrowserWindowState()
        window.isIncognito = true
        browserManager.tabResidenceAuthority.establishResidenceSession(on: window)
        let tab = Tab(
            url: URL(string: "https://private.example")!,
            webViewSessions: browserManager.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        window.replaceEphemeralTabs([tab])
        window.currentTabId = tab.id
        registry.register(window)
        registry.setActive(window)
        webViewRuntime.trackedWebViewAdmission.attemptAssignment(
            webView,
            to: tab,
            in: window.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )

        let page = try XCTUnwrap(
            browserManager.shellRuntime.activePageResolver.resolveActiveWindow()
        )

        XCTAssertIdentical(page.windowState, window)
        XCTAssertIdentical(page.tab, tab)
        XCTAssertIdentical(page.canonicalWebView, webView)
    }

    func testResolverUsesActiveSplitMemberInsteadOfFirstGroupMember() throws {
        let registry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupDatabase()
            )
        )
        let firstSpace = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "First",
            profileID: UUID()
        )
        let secondSpace = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Second",
            profileID: UUID()
        )
        let first = browserManager.regularTabLifecycleOwner
            .createNewTab(url: "https://first.example", in: firstSpace)
        let active = browserManager.regularTabLifecycleOwner
            .createNewTab(url: "https://active.example", in: secondSpace)
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(first.id), .regularTab(active.id)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: firstSpace.id)
            )
        )
        XCTAssertTrue(
            browserManager.splitGroupMutations.insert(
                group,
                persist: false
            )
        )
        let window = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: window)
        window.currentSpaceId = firstSpace.id
        window.currentTabId = active.id
        window.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .regularTab(active.id)
        )
        registry.register(window)
        registry.setActive(window)

        let page = try XCTUnwrap(
            browserManager.shellRuntime.activePageResolver.resolveActiveWindow()
        )

        XCTAssertEqual(
            browserManager.splitWindowContext.query.visibleTabIDs(in: window.id),
            [first.id, active.id]
        )
        XCTAssertIdentical(page.tab, active)
    }
}
