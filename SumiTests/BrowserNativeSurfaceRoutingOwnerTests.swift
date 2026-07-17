import XCTest

@testable import Sumi

@MainActor
final class BrowserNativeSurfaceRoutingOwnerTests: XCTestCase {
    func testNativeSurfaceReusesWindowSpaceSurfaceBeforeGlobalCurrentSpaceSurface() {
        let harness = NativeSurfaceRoutingHarness()
        harness.browser.spaceStateOwner.replaceCurrentSpace(harness.secondarySpace)
        let primarySurface = harness.makeSurfaceTab(in: harness.primarySpace)
        let secondarySurface = harness.makeSurfaceTab(in: harness.secondarySpace)

        harness.owner.openNativeBrowserSurface(
            .settings,
            url: SettingsTabs.general.settingsSurfaceURL,
            in: harness.windowState
        )

        XCTAssertIdentical(harness.selectedTab, primarySurface)
        XCTAssertNotIdentical(harness.selectedTab, secondarySurface)
    }

    func testNativeSurfaceMissingWindowSpaceDoesNotUseGlobalCurrentSpace() throws {
        let harness = NativeSurfaceRoutingHarness()
        harness.windowState.currentSpaceId = UUID()
        harness.windowState.currentProfileId = nil
        harness.browser.spaceStateOwner.replaceCurrentSpace(harness.secondarySpace)
        let secondarySurface = harness.makeSurfaceTab(in: harness.secondarySpace)
        let initialSecondaryCount = harness.browser.regularTabCollectionOwner.tabs(in: harness.secondarySpace).count

        harness.owner.openNativeBrowserSurface(
            .settings,
            url: SettingsTabs.general.settingsSurfaceURL,
            in: harness.windowState
        )

        let openedTab = try XCTUnwrap(harness.selectedTab)
        XCTAssertNotIdentical(openedTab, secondarySurface)
        XCTAssertEqual(openedTab.spaceId, harness.primarySpace.id)
        XCTAssertEqual(harness.browser.regularTabCollectionOwner.tabs(in: harness.secondarySpace).count, initialSecondaryCount)
    }
}

@MainActor
private final class NativeSurfaceRoutingHarness {
    let browser: BrowserManager
    let primaryProfile = Profile(name: "Primary")
    let secondaryProfile = Profile(name: "Secondary")
    let primarySpace: Space
    let secondarySpace: Space
    let windowState = BrowserWindowState()
    var selectedTab: Tab? {
        guard let selectedTabID = windowState.currentTabId else { return nil }
        return browser.regularTabCollectionOwner.tab(for: selectedTabID)
    }

    lazy var owner = browser.chromeBundle.nativeSurfaceRoutingOwner

    init() {
        browser = BrowserManager()
        primarySpace = Space(name: "Primary", profileId: primaryProfile.id)
        secondarySpace = Space(name: "Secondary", profileId: secondaryProfile.id)

        browser.spaceStateOwner.replaceSpaces([primarySpace, secondarySpace])
        browser.spaceStateOwner.replaceCurrentSpace(primarySpace)
        browser.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = primarySpace.id
        windowState.currentProfileId = primaryProfile.id
        browser.windowRegistry.register(windowState)
        browser.windowRegistry.setActive(windowState)
    }

    func makeSurfaceTab(in space: Space) -> Tab {
        let tab = browser.regularTabLifecycleOwner.createNewTab(
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
