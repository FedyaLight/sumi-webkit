import Combine
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class BrowserNativeSurfaceRoutingOwnerTests: XCTestCase {
    func testNativeSurfacesAreConfiguredBeforeSidebarPublication() throws {
        let cases: [(
            kind: SumiNativeBrowserSurfaceKind,
            url: URL,
            name: String,
            symbol: String
        )] = [
            (
                .history,
                SumiSurface.historySurfaceURL(rangeQuery: "all"),
                "History",
                SumiSurface.historyTabFaviconSystemImageName
            ),
            (
                .bookmarks,
                SumiSurface.bookmarksSurfaceURL(),
                "Bookmarks",
                SumiSurface.bookmarksTabFaviconSystemImageName
            ),
        ]

        for testCase in cases {
            let harness = NativeSurfaceRoutingHarness()
            harness.windowState.isShowingEmptyState = true
            harness.windowState.commandPalettePresentationReason = .emptySpace
            harness.windowState.presentationState.isCommandPaletteVisible = true
            var publishedTab: Tab?
            let publication = harness.browser.tabStructureEventBus
                .scopedStructureChangesPublisher
                .filter { $0.affectsPage(
                    windowID: harness.windowState.id,
                    spaceID: harness.primarySpace.id,
                    profileID: harness.primarySpace.profileId
                ) }
                .sink { _ in
                    publishedTab = harness.browser.regularTabCollectionOwner
                        .tabs(in: harness.primarySpace)
                        .first(where: testCase.kind.matches)
                }

            harness.owner.openNativeBrowserSurface(
                testCase.kind,
                url: testCase.url,
                in: harness.windowState
            )

            let tab = try XCTUnwrap(publishedTab)
            XCTAssertEqual(tab.url, testCase.url)
            XCTAssertEqual(tab.name, testCase.name)
            XCTAssertEqual(
                tab.faviconPresentation,
                .systemSymbol(testCase.symbol)
            )
            XCTAssertEqual(tab.spaceId, harness.primarySpace.id)
            XCTAssertIdentical(harness.selectedTab, tab)
            XCTAssertFalse(harness.windowState.isShowingEmptyState)
            XCTAssertFalse(
                harness.windowState.presentationState.isCommandPaletteVisible
            )
            publication.cancel()
        }
    }

    func testNativeSurfaceReusesWindowSpaceSurfaceBeforeGlobalCurrentSpaceSurface() {
        let harness = NativeSurfaceRoutingHarness()
        harness.browser.spaceStateOwner.replaceCurrentSpace(harness.secondarySpace)
        let primarySurface = harness.makeSurfaceTab(in: harness.primarySpace)
        let secondarySurface = harness.makeSurfaceTab(in: harness.secondarySpace)

        harness.owner.openNativeBrowserSurface(
            .history,
            url: SumiSurface.historySurfaceURL(rangeQuery: "all"),
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
            .history,
            url: SumiSurface.historySurfaceURL(rangeQuery: "all"),
            in: harness.windowState
        )

        let openedTab = try XCTUnwrap(harness.selectedTab)
        XCTAssertNotIdentical(openedTab, secondarySurface)
        XCTAssertEqual(openedTab.spaceId, harness.primarySpace.id)
        XCTAssertEqual(harness.browser.regularTabCollectionOwner.tabs(in: harness.secondarySpace).count, initialSecondaryCount)
    }

    func testClosingLastNativeSurfaceSettlesWindowToEmptyState() throws {
        let harness = NativeSurfaceRoutingHarness()
        harness.owner.openNativeBrowserSurface(
            .bookmarks,
            url: SumiSurface.bookmarksSurfaceURL(),
            in: harness.windowState
        )
        let tab = try XCTUnwrap(harness.selectedTab)

        harness.browser.tabCloseOrchestration.closeTab(
            tab,
            in: harness.windowState
        )

        XCTAssertNil(harness.browser.regularTabCollectionOwner.tab(for: tab.id))
        XCTAssertNil(harness.windowState.currentTabId)
        XCTAssertTrue(harness.windowState.isShowingEmptyState)
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
            url: SumiSurface.historySurfaceURL(rangeQuery: "all").absoluteString,
            in: space,
            activate: false
        )
        SumiNativeBrowserSurfaceKind.history.configure(
            tab,
            url: SumiSurface.historySurfaceURL(rangeQuery: "all")
        )
        return tab
    }
}
