import XCTest

@testable import Sumi

@MainActor
final class BrowserNativeSurfaceRoutingOwnerTests: XCTestCase {
    func testNativeSurfaceReusesWindowSpaceSurfaceBeforeGlobalCurrentSpaceSurface() {
        let harness = NativeSurfaceRoutingHarness()
        harness.tabManager.currentSpace = harness.secondarySpace
        let primarySurface = harness.makeSurfaceTab(in: harness.primarySpace)
        let secondarySurface = harness.makeSurfaceTab(in: harness.secondarySpace)

        harness.owner.openNativeBrowserSurface(
            .settings,
            url: SettingsTabs.general.settingsSurfaceURL,
            in: harness.windowState
        )

        XCTAssertIdentical(harness.selectedTab, primarySurface)
        XCTAssertNotIdentical(harness.selectedTab, secondarySurface)
        XCTAssertTrue(harness.openedContexts.isEmpty)
        XCTAssertEqual(harness.focusCount, 1)
    }

    func testNativeSurfaceMissingWindowSpaceDoesNotUseGlobalCurrentSpace() throws {
        let harness = NativeSurfaceRoutingHarness()
        harness.windowState.currentSpaceId = UUID()
        harness.windowState.currentProfileId = nil
        harness.tabManager.currentSpace = harness.secondarySpace
        let secondarySurface = harness.makeSurfaceTab(in: harness.secondarySpace)
        let initialSecondaryCount = harness.tabManager.tabs(in: harness.secondarySpace).count

        harness.owner.openNativeBrowserSurface(
            .settings,
            url: SettingsTabs.general.settingsSurfaceURL,
            in: harness.windowState
        )

        let openedTab = try XCTUnwrap(harness.selectedTab)
        XCTAssertNotIdentical(openedTab, secondarySurface)
        XCTAssertEqual(openedTab.spaceId, harness.primarySpace.id)
        XCTAssertEqual(harness.openedContexts.map(\.preferredSpaceId), [harness.primarySpace.id])
        XCTAssertEqual(harness.tabManager.tabs(in: harness.secondarySpace).count, initialSecondaryCount)
        XCTAssertEqual(harness.focusCount, 1)
    }
}

@MainActor
private final class NativeSurfaceRoutingHarness {
    let browserManager: BrowserManager
    let tabManager: TabManager
    let primaryProfile = Profile(name: "Primary")
    let secondaryProfile = Profile(name: "Secondary")
    let primarySpace: Space
    let secondarySpace: Space
    let windowState = BrowserWindowState()
    var selectedTab: Tab?
    var openedContexts: [BrowserTabOpenContext] = []
    var focusCount = 0

    lazy var owner = BrowserNativeSurfaceRoutingOwner(
        dependencies: BrowserNativeSurfaceRoutingOwner.Dependencies(
            tabManager: { [tabManager] in tabManager },
            settings: { nil },
            openNewTab: { [self] url, context in
                openedContexts.append(context)
                let targetSpace = context.preferredSpaceId.flatMap { preferredSpaceId in
                    tabManager.spaces.first { $0.id == preferredSpaceId }
                }
                let tab = tabManager.createNewTab(
                    url: url,
                    in: targetSpace,
                    activate: false
                )
                selectedTab = tab
                windowState.currentTabId = tab.id
                windowState.currentSpaceId = tab.spaceId
                return tab
            },
            selectTab: { [self] tab, windowState in
                selectedTab = tab
                windowState.currentTabId = tab.id
                windowState.currentSpaceId = tab.spaceId
            },
            focusWindow: { [self] _ in
                focusCount += 1
            }
        )
    )

    init() {
        browserManager = BrowserManager()
        tabManager = browserManager.tabManager
        primarySpace = Space(name: "Primary", profileId: primaryProfile.id)
        secondarySpace = Space(name: "Secondary", profileId: secondaryProfile.id)

        tabManager.spaces = [primarySpace, secondarySpace]
        tabManager.currentSpace = primarySpace
        windowState.tabManager = tabManager
        windowState.currentSpaceId = primarySpace.id
        windowState.currentProfileId = primaryProfile.id
    }

    func makeSurfaceTab(in space: Space) -> Tab {
        let tab = tabManager.createNewTab(
            url: SettingsTabs.general.settingsSurfaceURL.absoluteString,
            in: space,
            activate: false
        )
        SumiNativeBrowserSurfaceKind.settings.configure(
            tab,
            url: SettingsTabs.general.settingsSurfaceURL
        )
        return tab
    }
}
