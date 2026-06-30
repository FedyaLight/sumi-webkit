import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserActivePageRoutingOwnerTests: XCTestCase {
    func testActivePageTabPrefersGlancePreviewBeforeCurrentTab() {
        let windowState = BrowserWindowState()
        let currentTab = makeTab("https://current.example")
        let previewTab = makeTab("https://preview.example")
        let harness = BrowserActivePageRoutingOwnerHarness(activeWindow: windowState)
        harness.currentTabsByWindowId[windowState.id] = currentTab
        harness.previewTabsByWindowId[windowState.id] = previewTab
        let owner = harness.makeOwner()

        XCTAssertIdentical(owner.activePageTab(for: windowState), previewTab)
        XCTAssertIdentical(owner.activePageTabForActiveWindow(), previewTab)
    }

    func testCurrentTabForActiveWindowDoesNotUseGlancePreview() {
        let windowState = BrowserWindowState()
        let currentTab = makeTab("https://current.example")
        let previewTab = makeTab("https://preview.example")
        let harness = BrowserActivePageRoutingOwnerHarness(activeWindow: windowState)
        harness.currentTabsByWindowId[windowState.id] = currentTab
        harness.previewTabsByWindowId[windowState.id] = previewTab
        let owner = harness.makeOwner()

        XCTAssertIdentical(owner.currentTabForActiveWindow(), currentTab)
    }

    func testActivePageURLPrefersGlanceSessionURLBeforeTabURL() throws {
        let windowState = BrowserWindowState()
        let tab = makeTab("https://tab.example")
        let sessionURL = try XCTUnwrap(URL(string: "https://session.example/path"))
        let harness = BrowserActivePageRoutingOwnerHarness(activeWindow: windowState)
        harness.currentTabsByWindowId[windowState.id] = tab
        harness.sessionURLsByWindowId[windowState.id] = sessionURL
        let owner = harness.makeOwner()

        XCTAssertEqual(owner.activePageURL(for: windowState), sessionURL)
        XCTAssertEqual(owner.activePageURLForActiveWindow(), sessionURL)
    }

    func testActivePageRoutingReturnsNilWhenNoActiveWindowExists() {
        let harness = BrowserActivePageRoutingOwnerHarness()
        let owner = harness.makeOwner()

        XCTAssertNil(owner.currentTabForActiveWindow())
        XCTAssertNil(owner.activePageTabForActiveWindow())
        XCTAssertNil(owner.activePageURLForActiveWindow())
    }

    func testActivePageWebViewPrefersWindowOwnedLookupBeforeTabCurrentWebView() throws {
        let windowState = BrowserWindowState()
        let tabWebView = WKWebView(frame: .zero)
        let coordinatorWebView = WKWebView(frame: .zero)
        let tab = makeTab("https://tab.example")
        tab.replaceUntrackedWebView(tabWebView)
        let harness = BrowserActivePageRoutingOwnerHarness(activeWindow: windowState)
        harness.currentTabsByWindowId[windowState.id] = tab
        harness.webViewsByKey[harness.webViewKey(tabId: tab.id, windowId: windowState.id)] = coordinatorWebView
        let owner = harness.makeOwner()

        XCTAssertIdentical(try XCTUnwrap(owner.activePageWebView(for: windowState)), coordinatorWebView)
    }

    func testActivePageWebViewDoesNotUseUntrackedTabCurrentWebView() throws {
        let windowState = BrowserWindowState()
        let tabWebView = WKWebView(frame: .zero)
        let tab = makeTab("https://tab.example")
        tab.replaceUntrackedWebView(tabWebView)
        let harness = BrowserActivePageRoutingOwnerHarness(activeWindow: windowState)
        harness.currentTabsByWindowId[windowState.id] = tab
        let owner = harness.makeOwner()

        XCTAssertNil(owner.activePageWebView(for: windowState))
    }

    func testActivePageWebViewUsesActivePreviewCurrentWebView() throws {
        let windowState = BrowserWindowState()
        let currentTab = makeTab("https://current.example")
        let previewWebView = WKWebView(frame: .zero)
        let previewTab = makeTab("https://preview.example")
        previewTab.replaceUntrackedWebView(previewWebView)
        let harness = BrowserActivePageRoutingOwnerHarness(activeWindow: windowState)
        harness.currentTabsByWindowId[windowState.id] = currentTab
        harness.previewTabsByWindowId[windowState.id] = previewTab
        let owner = harness.makeOwner()

        XCTAssertIdentical(try XCTUnwrap(owner.activePageWebView(for: windowState)), previewWebView)
    }

    func testActivePageWebViewDoesNotUseTabAssignedWebViewForAnotherWindow() {
        let requestedWindow = BrowserWindowState()
        let owningWindowId = UUID()
        let tab = makeTab("https://tab.example")
        tab.replaceUntrackedWebView(WKWebView(frame: .zero))
        tab.primaryWindowId = owningWindowId
        let harness = BrowserActivePageRoutingOwnerHarness(activeWindow: requestedWindow)
        harness.currentTabsByWindowId[requestedWindow.id] = tab
        let owner = harness.makeOwner()

        XCTAssertNil(owner.activePageWebView(for: requestedWindow))
    }

    func testActivePageWebViewDoesNotUseWindowAssignedTabWebViewWithoutCoordinatorTracking() throws {
        let windowState = BrowserWindowState()
        let tabWebView = WKWebView(frame: .zero)
        let tab = makeTab("https://tab.example")
        tab.replaceUntrackedWebView(tabWebView)
        tab.primaryWindowId = windowState.id
        let harness = BrowserActivePageRoutingOwnerHarness(activeWindow: windowState)
        harness.currentTabsByWindowId[windowState.id] = tab
        let owner = harness.makeOwner()

        XCTAssertNil(owner.activePageWebView(for: windowState))
    }

    func testRefreshCurrentTabInActiveWindowRoutesThroughWindowScopedDependency() {
        let windowState = BrowserWindowState()
        let tab = makeTab("https://refresh.example")
        let harness = BrowserActivePageRoutingOwnerHarness(activeWindow: windowState)
        harness.currentTabsByWindowId[windowState.id] = tab
        let owner = harness.makeOwner()

        owner.refreshCurrentTabInActiveWindow()

        XCTAssertEqual(
            harness.refreshedPages,
            [.init(tabId: tab.id, windowId: windowState.id)]
        )
    }

    func testPresentExternalURLCreatesTabInActiveWindow() throws {
        let windowState = BrowserWindowState()
        let url = try XCTUnwrap(URL(string: "https://external.example"))
        let harness = BrowserActivePageRoutingOwnerHarness(activeWindow: windowState)
        let owner = harness.makeOwner()

        owner.presentExternalURL(url)

        XCTAssertEqual(
            harness.createdTabs,
            [.init(windowId: windowState.id, url: "https://external.example")]
        )
    }

    func testOpenDroppedRegularURLRoutesToRequestedSpaceAndInsertionIndex() throws {
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        let url = try XCTUnwrap(URL(string: "https://drop.example"))
        let harness = BrowserActivePageRoutingOwnerHarness()
        harness.spaces.insert(spaceId)
        let owner = harness.makeOwner()

        let opened = owner.openDroppedURL(
            url,
            in: windowState,
            at: .spaceRegular(spaceId: spaceId, slot: 3)
        )

        XCTAssertTrue(opened)
        let event = try XCTUnwrap(harness.openedTabs.first)
        XCTAssertEqual(event.url, "https://drop.example")
        XCTAssertEqual(event.context.preferredSpaceId, spaceId)
        XCTAssertEqual(event.context.regularInsertionIndex, 3)
        assertForeground(event.context, windowState: windowState)
    }

    func testOpenDroppedPinnedURLConvertsOpenedTabToSpacePinnedShortcut() throws {
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        let url = try XCTUnwrap(URL(string: "https://pinned.example"))
        let harness = BrowserActivePageRoutingOwnerHarness()
        harness.spaces.insert(spaceId)
        let owner = harness.makeOwner()

        let opened = owner.openDroppedURL(
            url,
            in: windowState,
            at: .spacePinned(spaceId: spaceId, slot: 2)
        )

        XCTAssertTrue(opened)
        let openedTab = try XCTUnwrap(harness.openedTabs.first)
        let conversion = try XCTUnwrap(harness.convertedPins.first)
        XCTAssertEqual(openedTab.url, "https://pinned.example")
        XCTAssertEqual(openedTab.context.preferredSpaceId, spaceId)
        XCTAssertEqual(conversion.tabId, openedTab.returnedTab.id)
        XCTAssertEqual(conversion.role, .spacePinned)
        XCTAssertEqual(conversion.spaceId, spaceId)
        XCTAssertEqual(conversion.index, 2)
        XCTAssertTrue(conversion.openTargetFolder)
        assertForeground(openedTab.context, windowState: windowState)
    }

    func testOpenDroppedURLRejectsMissingTargetSpaceBeforeOpeningTab() throws {
        let windowState = BrowserWindowState()
        let url = try XCTUnwrap(URL(string: "https://missing-space.example"))
        let harness = BrowserActivePageRoutingOwnerHarness()
        let owner = harness.makeOwner()

        let opened = owner.openDroppedURL(
            url,
            in: windowState,
            at: .spaceRegular(spaceId: UUID(), slot: 0)
        )

        XCTAssertFalse(opened)
    }

    private func assertForeground(
        _ context: BrowserTabOpenContext,
        windowState: BrowserWindowState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch context.activationPolicy {
        case .foreground(let routedWindowState, _):
            XCTAssertIdentical(routedWindowState, windowState, file: file, line: line)
        case .background:
            XCTFail("Expected foreground tab open context", file: file, line: line)
        }
    }

    private func makeTab(_ urlString: String) -> Tab {
        Tab(
            url: URL(string: urlString)!,
            name: urlString,
            loadsCachedFaviconOnInit: false
        )
    }
}

@MainActor
private final class BrowserActivePageRoutingOwnerHarness {
    struct CreatedTab: Equatable {
        let windowId: UUID
        let url: String
    }

    struct OpenedTab {
        let url: String
        let context: BrowserTabOpenContext
        let returnedTab: Tab
    }

    struct ConvertedPin {
        let tabId: UUID
        let role: ShortcutPinRole
        let profileId: UUID?
        let spaceId: UUID?
        let folderId: UUID?
        let index: Int
        let openTargetFolder: Bool
    }

    struct RefreshedPage: Equatable {
        let tabId: UUID
        let windowId: UUID
    }

    var activeWindow: BrowserWindowState?
    var currentTabsByWindowId: [UUID: Tab] = [:]
    var previewTabsByWindowId: [UUID: Tab] = [:]
    var sessionURLsByWindowId: [UUID: URL] = [:]
    var webViewsByKey: [String: WKWebView] = [:]
    var spaces: Set<UUID> = []
    var folderSpaceIds: [UUID: UUID] = [:]
    var essentialsInsertion: TabManager.EssentialsInsertionPlan?
    var createdTabs: [CreatedTab] = []
    var openedTabs: [OpenedTab] = []
    var convertedPins: [ConvertedPin] = []
    var refreshedPages: [RefreshedPage] = []
    var copyToastWindowIds: [UUID] = []
    var pasteboardWrites: [String] = []

    init(activeWindow: BrowserWindowState? = nil) {
        self.activeWindow = activeWindow
    }

    func makeOwner() -> BrowserActivePageRoutingOwner {
        BrowserActivePageRoutingOwner(
            dependencies: BrowserActivePageRoutingOwner.Dependencies(
                activeWindow: { [weak self] in self?.activeWindow },
                currentTab: { [weak self] windowState in
                    self?.currentTabsByWindowId[windowState.id]
                },
                activePreviewTab: { [weak self] windowState in
                    self?.previewTabsByWindowId[windowState.id]
                },
                activeSessionURL: { [weak self] windowState in
                    self?.sessionURLsByWindowId[windowState.id]
                },
                windowOwnedWebView: { [weak self] tab, windowId in
                    guard let self else { return nil }
                    return webViewsByKey[webViewKey(tabId: tab.id, windowId: windowId)]
                },
                refreshActivePage: { [weak self] tab, windowState in
                    self?.refreshedPages.append(
                        .init(tabId: tab.id, windowId: windowState.id)
                    )
                },
                createNewTab: { [weak self] windowState, url in
                    self?.createdTabs.append(.init(windowId: windowState.id, url: url))
                },
                openNewTab: { [weak self] url, context in
                    guard let self, let tabURL = URL(string: url) else { return nil }
                    let tab = Tab(
                        url: tabURL,
                        name: url,
                        loadsCachedFaviconOnInit: false
                    )
                    openedTabs.append(.init(url: url, context: context, returnedTab: tab))
                    return tab
                },
                containsSpace: { [weak self] spaceId in
                    self?.spaces.contains(spaceId) == true
                },
                folderSpaceId: { [weak self] folderId in
                    self?.folderSpaceIds[folderId]
                },
                resolveEssentialsInsertion: { [weak self] _, _ in
                    self?.essentialsInsertion
                },
                convertTabToShortcutPin: { [weak self] tab, role, profileId, spaceId, folderId, index, openTargetFolder in
                    self?.convertedPins.append(
                        .init(
                            tabId: tab.id,
                            role: role,
                            profileId: profileId,
                            spaceId: spaceId,
                            folderId: folderId,
                            index: index,
                            openTargetFolder: openTargetFolder
                        )
                    )
                    return ShortcutPin(
                        id: UUID(),
                        role: role,
                        profileId: profileId,
                        spaceId: spaceId,
                        index: index,
                        folderId: folderId,
                        launchURL: tab.url,
                        title: tab.name
                    )
                },
                presentCopyToast: { [weak self] windowState in
                    self?.copyToastWindowIds.append(windowState.id)
                },
                writeURLToPasteboard: { [weak self] url in
                    self?.pasteboardWrites.append(url)
                    return true
                }
            )
        )
    }

    func webViewKey(tabId: UUID, windowId: UUID) -> String {
        "\(tabId.uuidString)|\(windowId.uuidString)"
    }
}
