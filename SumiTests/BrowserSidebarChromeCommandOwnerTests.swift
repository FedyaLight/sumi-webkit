import XCTest
@testable import Sumi

@MainActor
final class BrowserSidebarChromeCommandOwnerTests: XCTestCase {
    func testChromeCommandsRouteToDependencies() {
        let spy = Spy()
        let owner = makeOwner(spy: spy)
        let windowState = BrowserWindowState()

        owner.showGradientEditor(source: makePresentationSource(windowState: windowState))
        owner.toggleSidebar(in: windowState)
        owner.openAppearanceSettings(in: windowState)
        owner.closeDownloadsPopover(in: windowState)
        owner.toggleDownloadsPopover(in: windowState)

        XCTAssertEqual(
            spy.events,
            [
                .showGradientEditor,
                .toggleSidebar(windowState.id),
                .openAppearanceSettings(windowState.id),
                .closeDownloadsPopover(windowState.id),
                .toggleDownloadsPopover(windowState.id),
            ]
        )
    }

    private func makeOwner(spy: Spy) -> BrowserSidebarChromeCommandOwner {
        BrowserSidebarChromeCommandOwner(
            dependencies: BrowserSidebarChromeCommandOwner.Dependencies(
                showGradientEditor: { _ in
                    spy.events.append(.showGradientEditor)
                },
                toggleSidebar: { windowState in
                    spy.events.append(.toggleSidebar(windowState.id))
                },
                openAppearanceSettings: { windowState in
                    spy.events.append(.openAppearanceSettings(windowState.id))
                },
                closeDownloadsPopover: { windowState in
                    spy.events.append(.closeDownloadsPopover(windowState.id))
                },
                toggleDownloadsPopover: { windowState in
                    spy.events.append(.toggleDownloadsPopover(windowState.id))
                }
            )
        )
    }

    private func makePresentationSource(
        windowState: BrowserWindowState
    ) -> SidebarTransientPresentationSource {
        SidebarTransientPresentationSource(
            windowID: windowState.id,
            window: nil,
            originOwnerView: nil,
            previousFirstResponder: nil,
            wasKeyWindow: false,
            coordinator: nil
        )
    }
}

private final class Spy {
    var events: [BrowserSidebarChromeCommandOwnerTests.Event] = []
}

extension BrowserSidebarChromeCommandOwnerTests {
    enum Event: Equatable {
        case showGradientEditor
        case toggleSidebar(UUID)
        case openAppearanceSettings(UUID)
        case closeDownloadsPopover(UUID)
        case toggleDownloadsPopover(UUID)
    }
}
