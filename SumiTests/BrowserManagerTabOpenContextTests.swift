import AppKit
import XCTest
@testable import Sumi

@MainActor
final class BrowserManagerTabOpenContextTests: XCTestCase {
    func testBackgroundOpenUsesSourceTabSpaceInsteadOfGlobalCurrentSpace() {
        let browserManager = BrowserManager()
        let sourceSpace = Space(name: "Source")
        let fallbackSpace = Space(name: "Fallback")
        browserManager.tabManager.spaces = [sourceSpace, fallbackSpace]
        browserManager.tabManager.currentSpace = fallbackSpace

        let sourceTab = browserManager.tabManager.createNewTab(
            url: "https://source.example",
            in: sourceSpace,
            activate: false
        )

        let openedTab = browserManager.openNewTab(
            url: "https://opened.example",
            context: .background(sourceTab: sourceTab)
        )

        XCTAssertEqual(openedTab.spaceId, sourceSpace.id)
        XCTAssertTrue(
            browserManager.tabManager.tabs(in: sourceSpace).contains(where: { $0.id == openedTab.id })
        )
    }

    func testForegroundOpenSelectsTabBeforeWebViewIsLoaded() {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let profileId = UUID()
        let space = Space(name: "Primary", profileId: profileId)
        browserManager.tabManager.spaces = [space]

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profileId

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let newTab = browserManager.openNewTab(
            url: "https://example.com",
            context: .foreground(windowState: windowState)
        )

        XCTAssertEqual(windowState.currentTabId, newTab.id)
        XCTAssertEqual(newTab.spaceId, space.id)
        XCTAssertNil(newTab.existingWebView)
        XCTAssertTrue(
            browserManager.tabManager.tabs(in: space).contains(where: { $0.id == newTab.id })
        )
    }

    /// Explicit `.deferred` matches default foreground policy: selection is synchronous, WKWebView load is async.
    /// (Avoid spinning until `isUnloaded == false` in XCTest — materializing WKWebView can trap in the test host.)
    func testExplicitDeferredForegroundOpenSelectsTabBeforeWebViewIsLoaded() {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let profileId = UUID()
        let space = Space(name: "Primary", profileId: profileId)
        browserManager.tabManager.spaces = [space]

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profileId

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let newTab = browserManager.openNewTab(
            url: "https://explicit-deferred.example",
            context: .foreground(windowState: windowState, loadPolicy: .deferred)
        )

        XCTAssertEqual(windowState.currentTabId, newTab.id)
        XCTAssertTrue(newTab.isUnloaded)
    }

    func testBackgroundOpenKeepsCurrentSelectionAndDefersWebViewMaterialization() {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let coordinator = WebViewCoordinator()
        browserManager.windowRegistry = windowRegistry
        browserManager.webViewCoordinator = coordinator

        let profileId = UUID()
        let space = Space(name: "Primary", profileId: profileId)
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profileId
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let currentTab = browserManager.tabManager.createNewTab(
            url: "https://current.example",
            in: space,
            activate: false
        )
        windowState.currentTabId = currentTab.id

        let newTab = browserManager.openNewTab(
            url: "https://background.example",
            context: .background(
                windowState: windowState,
                sourceTab: currentTab,
                preferredSpaceId: space.id
            )
        )

        XCTAssertEqual(windowState.currentTabId, currentTab.id)
        XCTAssertEqual(newTab.spaceId, space.id)
        XCTAssertTrue(newTab.isUnloaded)
        XCTAssertNil(newTab.existingWebView)
        XCTAssertNil(coordinator.getWebView(for: newTab.id, in: windowState.id))
    }

    func testBackgroundIncognitoOpenKeepsCurrentSelectionAndDefersWebViewMaterialization() {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let coordinator = WebViewCoordinator()
        browserManager.windowRegistry = windowRegistry
        browserManager.webViewCoordinator = coordinator

        let profile = Profile(name: "Private")
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.isIncognito = true
        windowState.ephemeralProfile = profile
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let currentTab = browserManager.tabManager.createEphemeralTab(
            url: URL(string: "https://current-private.example")!,
            in: windowState,
            profile: profile
        )
        windowState.currentTabId = currentTab.id

        let newTab = browserManager.openNewTab(
            url: "https://background-private.example",
            context: .background(
                windowState: windowState,
                sourceTab: currentTab
            )
        )

        XCTAssertEqual(windowState.currentTabId, currentTab.id)
        XCTAssertTrue(windowState.ephemeralTabs.contains(where: { $0.id == newTab.id }))
        XCTAssertTrue(newTab.isUnloaded)
        XCTAssertNil(newTab.existingWebView)
        XCTAssertNil(coordinator.getWebView(for: newTab.id, in: windowState.id))
    }

    func testPinTabUsesVisibleWindowProfileInsteadOfGlobalCurrentProfile() {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let globalProfile = Profile(name: "Global")
        let visibleProfile = Profile(name: "Visible")
        browserManager.profileManager.profiles = [globalProfile, visibleProfile]
        browserManager.currentProfile = globalProfile

        let space = Space(name: "Visible Space", profileId: visibleProfile.id)
        browserManager.tabManager.spaces = [space]

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = visibleProfile.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let urls = [
            "https://one.example",
            "https://two.example",
            "https://three.example",
        ]

        for url in urls {
            let tab = browserManager.tabManager.createNewTab(
                url: url,
                in: space,
                activate: false
            )
            browserManager.tabManager.pinTab(
                tab,
                context: .init(windowState: windowState, spaceId: space.id)
            )
        }

        XCTAssertEqual(browserManager.tabManager.essentialPins(for: visibleProfile.id).count, 3)
        XCTAssertTrue(browserManager.tabManager.essentialPins(for: globalProfile.id).isEmpty)
    }

    func testRegularDropToEssentialsUsesCurrentSidebarProfile() {
        let browserManager = BrowserManager()

        let globalProfile = Profile(name: "Global")
        let targetProfile = Profile(name: "Target")
        browserManager.profileManager.profiles = [globalProfile, targetProfile]
        browserManager.currentProfile = globalProfile

        let sourceSpace = Space(name: "Source", profileId: globalProfile.id)
        browserManager.tabManager.spaces = [sourceSpace]

        let tab = browserManager.tabManager.createNewTab(
            url: "https://drag.example",
            in: sourceSpace,
            activate: false
        )

        browserManager.tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: SidebarDragScope(
                    spaceId: sourceSpace.id,
                    profileId: globalProfile.id,
                    sourceContainer: .spaceRegular(sourceSpace.id),
                    sourceItemId: tab.id,
                    sourceItemKind: .tab
                ),
                fromContainer: .spaceRegular(sourceSpace.id),
                toContainer: .essentials,
                toIndex: 0
            )
        )

        XCTAssertEqual(browserManager.tabManager.essentialPins(for: globalProfile.id).count, 1)
        XCTAssertTrue(browserManager.tabManager.essentialPins(for: targetProfile.id).isEmpty)
    }

    func testPinnedDropToEssentialsRejectsMismatchedScopeProfile() {
        let browserManager = BrowserManager()

        let globalProfile = Profile(name: "Global")
        let targetProfile = Profile(name: "Target")
        browserManager.profileManager.profiles = [globalProfile, targetProfile]
        browserManager.currentProfile = globalProfile

        let sourceSpace = Space(name: "Source", profileId: globalProfile.id)
        browserManager.tabManager.spaces = [sourceSpace]

        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: sourceSpace.id,
            index: 0,
            launchURL: URL(string: "https://launcher.example")!,
            title: "Launcher"
        )
        browserManager.tabManager.setSpacePinnedShortcuts([pin], for: sourceSpace.id)

        let accepted = browserManager.tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: SidebarDragScope(
                    spaceId: sourceSpace.id,
                    profileId: targetProfile.id,
                    sourceContainer: .spacePinned(sourceSpace.id),
                    sourceItemId: pin.id,
                    sourceItemKind: .tab
                ),
                fromContainer: .spacePinned(sourceSpace.id),
                toContainer: .essentials,
                toIndex: 0
            )
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(browserManager.tabManager.spacePinnedPins(for: sourceSpace.id).map(\.id), [pin.id])
        XCTAssertTrue(browserManager.tabManager.essentialPins(for: targetProfile.id).isEmpty)
        XCTAssertTrue(browserManager.tabManager.essentialPins(for: globalProfile.id).isEmpty)
    }

    func testPinTabStopsAfterTwelfthEssentialPin() {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let globalProfile = Profile(name: "Global")
        let visibleProfile = Profile(name: "Visible")
        browserManager.profileManager.profiles = [globalProfile, visibleProfile]
        browserManager.currentProfile = globalProfile

        let space = Space(name: "Visible Space", profileId: visibleProfile.id)
        browserManager.tabManager.spaces = [space]

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = visibleProfile.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        for index in 0..<13 {
            let tab = browserManager.tabManager.createNewTab(
                url: "https://\(index).example",
                in: space,
                activate: false
            )
            browserManager.tabManager.pinTab(
                tab,
                context: .init(windowState: windowState, spaceId: space.id)
            )
        }

        XCTAssertEqual(
            browserManager.tabManager.essentialPins(for: visibleProfile.id).count,
            TabManager.EssentialsCapacityPolicy.maxItems
        )
    }

    func testTabSelectionPolicyKeepsCurrentSpaceForEssential() {
        let currentSpaceId = UUID()
        let essentialSpaceId = UUID()
        let pinId = UUID()

        let target = WindowTabSelectionPolicy.targetState(
            tabId: UUID(),
            tabSpaceId: essentialSpaceId,
            isShortcutLiveInstance: true,
            shortcutPinId: pinId,
            shortcutPinRole: .essential,
            currentSpaceId: currentSpaceId,
            updateSpaceFromTab: true,
            rememberSelection: true
        )

        XCTAssertEqual(target.currentSpaceId, currentSpaceId)
        XCTAssertEqual(target.currentShortcutPinId, pinId)
        XCTAssertEqual(target.currentShortcutPinRole, .essential)
        XCTAssertEqual(target.shortcutMemoryUpdate, .none)
        XCTAssertEqual(target.regularTabMemoryUpdate, .none)
    }

    func testTabSelectionPolicyStoresSpaceLauncherSelection() {
        let currentSpaceId = UUID()
        let launcherSpaceId = UUID()
        let pinId = UUID()

        let target = WindowTabSelectionPolicy.targetState(
            tabId: UUID(),
            tabSpaceId: launcherSpaceId,
            isShortcutLiveInstance: true,
            shortcutPinId: pinId,
            shortcutPinRole: .spacePinned,
            currentSpaceId: currentSpaceId,
            updateSpaceFromTab: true,
            rememberSelection: true
        )

        XCTAssertEqual(target.currentSpaceId, launcherSpaceId)
        XCTAssertEqual(target.currentShortcutPinId, pinId)
        XCTAssertEqual(target.currentShortcutPinRole, .spacePinned)
        XCTAssertEqual(target.shortcutMemoryUpdate, .set(spaceId: launcherSpaceId, pinId: pinId))
        XCTAssertEqual(target.regularTabMemoryUpdate, .none)
    }

    func testTabSelectionPolicyClearsShortcutSelectionForRegularTab() {
        let spaceId = UUID()
        let tabId = UUID()

        let target = WindowTabSelectionPolicy.targetState(
            tabId: tabId,
            tabSpaceId: spaceId,
            isShortcutLiveInstance: false,
            shortcutPinId: nil,
            shortcutPinRole: nil,
            currentSpaceId: spaceId,
            updateSpaceFromTab: true,
            rememberSelection: true
        )

        XCTAssertEqual(target.currentTabId, tabId)
        XCTAssertNil(target.currentShortcutPinId)
        XCTAssertNil(target.currentShortcutPinRole)
        XCTAssertEqual(target.shortcutMemoryUpdate, .clear(spaceId: spaceId))
        XCTAssertEqual(target.regularTabMemoryUpdate, .set(spaceId: spaceId, tabId: tabId))
    }

    func testUserTabActivationCoalescesToLastRequestForWindow() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let space = Space(name: "Primary")
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let firstTab = browserManager.tabManager.createNewTab(
            url: "https://first.example",
            in: space,
            activate: false
        )
        let secondTab = browserManager.tabManager.createNewTab(
            url: "https://second.example",
            in: space,
            activate: false
        )

        browserManager.requestUserTabActivation(
            firstTab,
            in: windowState,
            loadPolicy: .deferred
        )
        browserManager.requestUserTabActivation(
            secondTab,
            in: windowState,
            loadPolicy: .deferred
        )

        XCTAssertNil(windowState.currentTabId)

        await drainMainQueue()

        XCTAssertEqual(windowState.currentTabId, secondTab.id)
        XCTAssertNotEqual(windowState.currentTabId, firstTab.id)
    }

    func testSelectingTabDoesNotRefreshUnrelatedWindowCompositor() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let coordinator = WebViewCoordinator()
        let sharedSpace = Space(name: "Primary")
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()

        browserManager.webViewCoordinator = coordinator
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [sharedSpace]
        browserManager.tabManager.currentSpace = sharedSpace
        browserManager.tabManager.setTabs([], for: sharedSpace.id)

        firstWindow.tabManager = browserManager.tabManager
        firstWindow.currentSpaceId = sharedSpace.id
        secondWindow.tabManager = browserManager.tabManager
        secondWindow.currentSpaceId = sharedSpace.id

        windowRegistry.register(firstWindow)
        windowRegistry.register(secondWindow)
        windowRegistry.setActive(firstWindow)

        coordinator.setCompositorContainerView(NSView(), for: firstWindow.id)
        coordinator.setCompositorContainerView(NSView(), for: secondWindow.id)

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/selected",
            in: sharedSpace,
            activate: false
        )
        await waitForCondition { browserManager.tabManager.hasLoadedInitialData }
        await settleCompositorVersions(for: [firstWindow, secondWindow])

        let firstInitialVersion = firstWindow.compositorVersion
        let secondInitialVersion = secondWindow.compositorVersion

        browserManager.applyTabSelection(
            tab,
            in: firstWindow,
            updateSpaceFromTab: true,
            updateTheme: false,
            rememberSelection: false,
            persistSelection: false
        )
        await settleCompositorVersions(for: [firstWindow, secondWindow])

        XCTAssertGreaterThan(firstWindow.compositorVersion, firstInitialVersion)
        XCTAssertEqual(secondWindow.compositorVersion, secondInitialVersion)
    }

    private func settleCompositorVersions(for windows: [BrowserWindowState]) async {
        var previousSnapshot: [UUID: Int]? = nil

        for _ in 0..<8 {
            await drainMainQueue()

            let snapshot = Dictionary(
                uniqueKeysWithValues: windows.map { windowState in
                    (windowState.id, windowState.compositorVersion)
                }
            )

            if snapshot == previousSnapshot {
                return
            }

            previousSnapshot = snapshot
        }
    }

    private func waitForCondition(
        iterations: Int = 64,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<iterations {
            if condition() {
                return
            }
            await drainMainQueue()
        }
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        await Task.yield()
    }
}
