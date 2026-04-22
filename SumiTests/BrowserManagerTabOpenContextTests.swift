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

    func testRegularDropToEssentialsUsesTargetSpaceProfileInsteadOfGlobalCurrentProfile() {
        let browserManager = BrowserManager()

        let globalProfile = Profile(name: "Global")
        let targetProfile = Profile(name: "Target")
        browserManager.profileManager.profiles = [globalProfile, targetProfile]
        browserManager.currentProfile = globalProfile

        let sourceSpace = Space(name: "Source", profileId: globalProfile.id)
        let targetSpace = Space(name: "Target", profileId: targetProfile.id)
        browserManager.tabManager.spaces = [sourceSpace, targetSpace]

        let tab = browserManager.tabManager.createNewTab(
            url: "https://drag.example",
            in: sourceSpace,
            activate: false
        )

        browserManager.tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                fromContainer: .spaceRegular(sourceSpace.id),
                toContainer: .essentials,
                toIndex: 0,
                toSpaceId: targetSpace.id
            )
        )

        XCTAssertEqual(browserManager.tabManager.essentialPins(for: targetProfile.id).count, 1)
        XCTAssertTrue(browserManager.tabManager.essentialPins(for: globalProfile.id).isEmpty)
    }

    func testPinnedDropToEssentialsUsesExplicitTargetProfileForSecondarySpace() {
        let browserManager = BrowserManager()

        let globalProfile = Profile(name: "Global")
        let targetProfile = Profile(name: "Target")
        browserManager.profileManager.profiles = [globalProfile, targetProfile]
        browserManager.currentProfile = globalProfile

        let sourceSpace = Space(name: "Source", profileId: globalProfile.id)
        let hoveredSpace = Space(name: "Hovered", profileId: targetProfile.id)
        browserManager.tabManager.spaces = [sourceSpace, hoveredSpace]

        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: sourceSpace.id,
            index: 0,
            launchURL: URL(string: "https://launcher.example")!,
            title: "Launcher"
        )
        browserManager.tabManager.setSpacePinnedShortcuts([pin], for: sourceSpace.id)

        browserManager.tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                fromContainer: .spacePinned(sourceSpace.id),
                toContainer: .essentials,
                toIndex: 0,
                toSpaceId: sourceSpace.id,
                toProfileId: targetProfile.id
            )
        )

        XCTAssertTrue(browserManager.tabManager.spacePinnedPins(for: sourceSpace.id).isEmpty)
        XCTAssertEqual(browserManager.tabManager.essentialPins(for: targetProfile.id).count, 1)
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
        await drainMainQueue()

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
        await drainMainQueue()

        XCTAssertGreaterThan(firstWindow.compositorVersion, firstInitialVersion)
        XCTAssertEqual(secondWindow.compositorVersion, secondInitialVersion)
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
