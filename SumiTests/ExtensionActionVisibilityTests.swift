import XCTest
@testable import Sumi

final class ExtensionActionVisibilityTests: XCTestCase {
    func testNoActionsAreHidden() {
        XCTAssertEqual(
            ExtensionActionPlacement.resolve(totalActions: 0),
            .hidden
        )
    }

    func testOneActionStaysInURLBar() {
        XCTAssertEqual(
            ExtensionActionPlacement.resolve(totalActions: 1),
            .urlBar
        )
    }

    func testTwoActionsStayInURLBar() {
        XCTAssertEqual(
            ExtensionActionPlacement.resolve(totalActions: 2),
            .urlBar
        )
    }

    func testThreeActionsMoveToSidebarGrid() {
        XCTAssertEqual(
            ExtensionActionPlacement.resolve(totalActions: 3),
            .sidebarGrid
        )
    }

    func testMoreThanThreeActionsMoveToSidebarGrid() {
        XCTAssertEqual(
            ExtensionActionPlacement.resolve(totalActions: 5),
            .sidebarGrid
        )
    }

    func testNoActionsFitWhenWidthIsZero() {
        XCTAssertEqual(
            ExtensionActionVisibility.visibleCount(totalActions: 3, availableWidth: 0),
            0
        )
    }

    func testOneActionFitsAtExactButtonWidth() {
        XCTAssertEqual(
            ExtensionActionVisibility.visibleCount(totalActions: 3, availableWidth: 28),
            1
        )
    }

    func testPartialOverflowKeepsLeadingActionsOnly() {
        XCTAssertEqual(
            ExtensionActionVisibility.visibleCount(totalActions: 5, availableWidth: 92),
            3
        )
    }

    func testWideContainerShowsAllActions() {
        XCTAssertEqual(
            ExtensionActionVisibility.visibleCount(totalActions: 4, availableWidth: 200),
            4
        )
    }

    func testSidebarHeaderHostsGridSurfaceBelowURLBar() throws {
        let header = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")
        let spacesSidebar = try Self.source(named: "Navigation/Sidebar/SpacesSideBarView.swift")

        XCTAssertTrue(header.contains("sidebarURLBar"))
        XCTAssertFalse(header.contains("sidebarExtensionGrid"))
        XCTAssertTrue(spacesSidebar.contains("makeSidebarExtensionGrid"))
        XCTAssertTrue(spacesSidebar.contains("layout: .sidebarGrid"))
        XCTAssertTrue(spacesSidebar.contains("ExtensionActionPlacement.resolve"))
        XCTAssertTrue(spacesSidebar.contains("ExtensionActionSnapshotGrid"))
    }

    func testURLBarHostsOnlyCompactExtensionActions() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/URLBarTrailingActions.swift")

        XCTAssertTrue(source.contains("urlBarExtensionActions"))
        XCTAssertTrue(source.contains("layout: .compactStrip"))
        XCTAssertFalse(source.contains("layout: .sidebarGrid"))
    }

    func testURLBarExtensionActionsPrecedeBrowserActions() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/URLBarTrailingActions.swift")

        let extensionsIndex = try XCTUnwrap(source.range(of: "urlBarExtensionActions")?.lowerBound)
        let copyIndex = try XCTUnwrap(source.range(of: "copyLinkButton(for: currentTab)")?.lowerBound)
        let hubIndex = try XCTUnwrap(source.range(of: "hubButton")?.lowerBound)

        XCTAssertLessThan(extensionsIndex, copyIndex)
        XCTAssertLessThan(extensionsIndex, hubIndex)
    }

    func testEmptyPinnedListDoesNotPinEveryExtensionByDefault() throws {
        let store = try Self.source(named: "Sumi/Managers/ExtensionManager/ExtensionManager+Store.swift")
        let module = try Self.source(named: "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift")

        XCTAssertFalse(store.contains("if normalizedPinnedIDs.isEmpty"))
        XCTAssertTrue(module.contains("?? []"))
        XCTAssertTrue(module.contains("managerIfLoadedAndEnabled()?.isPinnedToToolbar(extensionId) ?? false"))
    }

    func testURLHubShowsOnlyUnpinnedExtensionActions() throws {
        let popover = try Self.source(named: "Sumi/Components/Sidebar/URLBarHubPopover.swift")
        let extensionActions = try Self.source(named: "Sumi/Components/Extensions/ExtensionActionView.swift")

        XCTAssertTrue(popover.contains("unpinnedEnabledExtensionActions"))
        XCTAssertTrue(extensionActions.contains("hubExtensions"))
        XCTAssertTrue(extensionActions.contains("isPinnedToToolbar($0.id) == false"))
    }

    func testExtensionsModuleLoadsActionSurfaceMetadataOnAttach() throws {
        let source = try Self.source(named: "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift")
        let attachRange = try XCTUnwrap(source.range(of: "func attach(browserManager: BrowserManager)"))
        let managerFactoryRange = try XCTUnwrap(source.range(of: "func managerIfEnabled()"))
        let attachBody = String(source[attachRange.lowerBound..<managerFactoryRange.lowerBound])

        XCTAssertTrue(attachBody.contains("ensureActionSurfaceMetadataLoadedIfNeeded()"))
    }

    func testExtensionContextMenusExposePinAndUnpinActions() throws {
        let source = try Self.source(named: "Sumi/Components/Extensions/ExtensionActionView.swift")

        XCTAssertTrue(source.contains("title: \"Pin to Toolbar\""))
        XCTAssertTrue(source.contains("actionPresentationContext.pinToToolbar(extensionId: ext.id)"))
        XCTAssertTrue(source.contains("title: \"Unpin from Toolbar\""))
        XCTAssertTrue(source.contains("actionPresentationContext.unpinFromToolbar(extensionId: ext.id)"))
        XCTAssertTrue(source.contains("if ext.hasOptionsPage"))
        XCTAssertTrue(source.contains("title: \"Options\""))
        XCTAssertTrue(source.contains("actionPresentationContext.openOptionsPage(for: ext)"))
        XCTAssertFalse(source.contains("title: \"Open Extension Action\""))
    }

    func testSidebarGridUsesSidebarPinnedChromeAndNonInteractiveAnchor() throws {
        let source = try Self.source(named: "Sumi/Components/Extensions/ExtensionActionView.swift")

        XCTAssertTrue(source.contains("tokens.pinnedHoverBackground"))
        XCTAssertTrue(source.contains("tokens.pinnedIdleBackground"))
        XCTAssertTrue(source.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(source.contains("minHeight: 26, maxHeight: 26"))
    }

    func testSidebarExtensionGridUsesSpaceProfileDuringTransitions() throws {
        let extensionActions = try Self.source(named: "Sumi/Components/Extensions/ExtensionActionView.swift")
        let spacesSidebar = try Self.source(named: "Navigation/Sidebar/SpacesSideBarView.swift")
        let store = try Self.source(named: "Sumi/Managers/ExtensionManager/ExtensionManager+Store.swift")

        XCTAssertTrue(extensionActions.contains("var profileId: UUID?"))
        XCTAssertTrue(spacesSidebar.contains("profileId: pageProfileId"))
        XCTAssertTrue(spacesSidebar.contains("transitionSnapshot?.source.extensionActions"))
        XCTAssertTrue(store.contains("pinnedToolbarProfileKey(for: profileId)"))
    }

    func testExtensionActionColdStartClickUsesWindowSelectionFallbackAndLiveAnchorRegistration() throws {
        let actionViewSource = try Self.source(named: "Sumi/Components/Extensions/ExtensionActionView.swift")
        let contextSource = try Self.source(
            named: "Sumi/Components/Extensions/ExtensionActionPresentationContext.swift"
        )

        XCTAssertTrue(actionViewSource.contains("actionPresentationContext.presentActionPopup(for: ext)"))
        XCTAssertTrue(contextSource.contains("currentActionTab"))
        XCTAssertTrue(contextSource.contains("currentActionTabForClick"))
        XCTAssertTrue(contextSource.contains("windowState.currentTabId.flatMap"))
        XCTAssertTrue(contextSource.contains("browserManager.shellSelectionService.currentTab"))
        XCTAssertTrue(contextSource.contains("browserManager.tabManager.hasLoadedInitialData"))
        XCTAssertTrue(actionViewSource.contains("ActionAnchorHostView"))
        XCTAssertTrue(actionViewSource.contains("override func viewDidMoveToWindow()"))
        XCTAssertTrue(actionViewSource.contains("registerAnchor()"))
    }

    func testExtensionActionClickSupportsDefaultActionWhenNoTabIsAvailable() throws {
        let source = try Self.source(named: "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift")

        XCTAssertFalse(source.contains("No active eligible tab is available for the extension action."))
        XCTAssertTrue(source.contains("registerTabWithExtensionRuntime("))
        XCTAssertTrue(source.contains("reason: \"ExtensionManager.openActionPopupFromURLHub\""))
        XCTAssertTrue(source.contains("let adapter: ExtensionTabAdapter?"))
        XCTAssertTrue(source.contains("adapter = nil"))
        XCTAssertTrue(source.contains("extensionContext.action(for: adapter)"))
        XCTAssertTrue(source.contains("extensionContext.performAction(for: adapter)"))
        XCTAssertFalse(source.contains("notifyTabActivated(newTab: currentTab, previous: nil)"))
    }

    func testWebExtensionBridgeAdaptersUseBrowserContextBoundary() throws {
        let bridgeSource = try Self.source(named: "Sumi/Managers/ExtensionManager/ExtensionBridge.swift")
        let managerSource = try Self.source(named: "Sumi/Managers/ExtensionManager/ExtensionManager.swift")
        let profilesSource = try Self.source(named: "Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift")

        XCTAssertTrue(bridgeSource.contains("protocol ExtensionBrowserBridgeContext"))
        XCTAssertTrue(bridgeSource.contains("extension BrowserManager: ExtensionBrowserBridgeContext"))
        XCTAssertTrue(managerSource.contains("weak var browserBridgeContext"))
        XCTAssertTrue(profilesSource.contains("browserBridgeContext = browserManager"))

        XCTAssertFalse(
            bridgeSource.contains("private weak var browserManager: BrowserManager?"),
            "WebExtension adapters should depend on the bridge context, not BrowserManager as a service locator"
        )
        XCTAssertFalse(
            bridgeSource.contains("browserManager: BrowserManager,"),
            "WebExtension adapter initializers should accept ExtensionBrowserBridgeContext"
        )
    }

    func testURLBarDoesNotHostASeparateAdBlockerAction() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/URLBarTrailingActions.swift")

        XCTAssertFalse(source.contains("urlbar-adblocker-action-button"))
        XCTAssertFalse(source.contains("AdBlockerActionAnchorView"))
    }

    private static func source(named relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
