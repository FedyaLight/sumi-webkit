import XCTest
@testable import Sumi

@MainActor
final class BrowserSidebarShortcutPromotionOwnerTests: XCTestCase {
    func testPinShortcutGloballyBuildsPromotionTabFromLiveShortcutState() throws {
        let spy = Spy()
        let owner = makeOwner(spy: spy)
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        let pin = try makeShortcutPin(title: "Saved Title")
        let liveTab = makeTab(name: "  Live Title  ")

        owner.pinShortcutGlobally(pin, in: windowState, spaceId: spaceId, liveTab: liveTab)

        XCTAssertEqual(
            spy.events,
            [
                .makePromotionTab(
                    pin.launchURL,
                    "Live Title",
                    SumiPersistentGlyph.launcherSystemImageFallback,
                    spaceId
                ),
                .pinTab(
                    spy.promotionTabs[0].id,
                    windowState.id,
                    spaceId
                ),
            ]
        )
        XCTAssertEqual(spy.promotionTabs[0].name, "Live Title")
        XCTAssertEqual(spy.promotionTabs[0].url, pin.launchURL)
        XCTAssertEqual(spy.promotionTabs[0].spaceId, spaceId)
        XCTAssertTrue(spy.promotionTabs[0].faviconIsTemplateGlobePlaceholder)
    }

    func testPinShortcutGloballyFallsBackToPinTitleWithoutLiveTitle() throws {
        let spy = Spy()
        let owner = makeOwner(spy: spy)
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        let pin = try makeShortcutPin(title: "Saved Title")

        owner.pinShortcutGlobally(pin, in: windowState, spaceId: spaceId, liveTab: nil)

        XCTAssertEqual(
            spy.events,
            [
                .makePromotionTab(
                    pin.launchURL,
                    "Saved Title",
                    SumiPersistentGlyph.launcherSystemImageFallback,
                    spaceId
                ),
                .pinTab(spy.promotionTabs[0].id, windowState.id, spaceId),
            ]
        )
    }

    func testPinShortcutGloballySkipsPinWhenPromotionTabCannotBeBuilt() throws {
        let spy = Spy()
        let owner = makeOwner(spy: spy, shouldBuildPromotionTab: false)
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        let pin = try makeShortcutPin(title: "Saved Title")

        owner.pinShortcutGlobally(pin, in: windowState, spaceId: spaceId, liveTab: nil)

        XCTAssertEqual(
            spy.events,
            [
                .makePromotionTab(
                    pin.launchURL,
                    "Saved Title",
                    SumiPersistentGlyph.launcherSystemImageFallback,
                    spaceId
                ),
            ]
        )
        XCTAssertTrue(spy.promotionTabs.isEmpty)
    }

    private func makeOwner(
        spy: Spy,
        shouldBuildPromotionTab: Bool = true
    ) -> BrowserSidebarShortcutPromotionOwner {
        BrowserSidebarShortcutPromotionOwner(
            dependencies: BrowserSidebarShortcutPromotionOwner.Dependencies(
                makePromotionTab: { url, title, favicon, spaceId in
                    spy.events.append(.makePromotionTab(url, title, favicon, spaceId))
                    guard shouldBuildPromotionTab else { return nil }

                    let tab = Tab(
                        url: url,
                        name: title,
                        favicon: favicon,
                        spaceId: spaceId,
                        index: 0
                    )
                    spy.promotionTabs.append(tab)
                    return tab
                },
                pinTab: { tab, context in
                    spy.events.append(
                        .pinTab(
                            tab.id,
                            context.windowState?.id,
                            context.spaceId
                        )
                    )
                }
            )
        )
    }

    private func makeShortcutPin(title: String) throws -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: UUID(),
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://example.com")),
            title: title
        )
    }

    private func makeTab(name: String) -> Tab {
        Tab(
            url: URL(string: "https://example.com/live")!,
            name: name,
            favicon: "star",
            index: 0
        )
    }
}

private final class Spy {
    var events: [BrowserSidebarShortcutPromotionOwnerTests.Event] = []
    var promotionTabs: [Tab] = []
}

extension BrowserSidebarShortcutPromotionOwnerTests {
    enum Event: Equatable {
        case makePromotionTab(URL, String, String, UUID)
        case pinTab(UUID, UUID?, UUID?)
    }
}
