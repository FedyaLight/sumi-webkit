import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserTabWebKitCloseServiceTests: XCTestCase {
    func testDedicatedTrackedChildUsesWindowTransaction() {
        let fixture = makeTrackedFixture()
        let targets = CloseTargetStub(.tracked(fixture.target))
        let childWindows = ChildCloseStub(closes: true)
        let commands = CloseCommandsSpy()

        XCTAssertTrue(BrowserTabWebKitCloseService(
            targets: targets,
            childWindows: childWindows,
            commands: commands
        ).handleWebViewDidClose(fixture.webView))

        XCTAssertIdentical(childWindows.received?.tab, fixture.tab)
        XCTAssertTrue(commands.actions.isEmpty)
    }

    func testAdoptedTrackedChildUsesNormalTabClose() {
        let fixture = makeTrackedFixture()
        let targets = CloseTargetStub(.tracked(fixture.target))
        let childWindows = ChildCloseStub(closes: false)
        let commands = CloseCommandsSpy()

        _ = BrowserTabWebKitCloseService(
            targets: targets,
            childWindows: childWindows,
            commands: commands
        ).handleWebViewDidClose(fixture.webView)

        XCTAssertEqual(commands.actions, [.tracked])
    }

    func testUntrackedTargetUsesUntrackedCommand() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let webView = WKWebView()
        let targets = CloseTargetStub(.untracked(UntrackedWebKitCloseTarget(
            webView: webView,
            tab: tab,
            window: nil
        )))
        let childWindows = ChildCloseStub(closes: false)
        let commands = CloseCommandsSpy()

        _ = BrowserTabWebKitCloseService(
            targets: targets,
            childWindows: childWindows,
            commands: commands
        ).handleWebViewDidClose(webView)

        XCTAssertEqual(commands.actions, [.untracked])
        XCTAssertNil(childWindows.received)
    }

    func testStaleTrackedSlotIsCleanedWithoutLogicalTabClose() {
        let webView = WKWebView()
        let owner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let targets = CloseTargetStub(.staleTracked(owner))
        let childWindows = ChildCloseStub(closes: false)
        let commands = CloseCommandsSpy()

        _ = BrowserTabWebKitCloseService(
            targets: targets,
            childWindows: childWindows,
            commands: commands
        ).handleWebViewDidClose(webView)

        XCTAssertEqual(commands.actions, [.stale])
        XCTAssertEqual(commands.staleOwner, owner)
    }

    func testOrphanWebViewUsesPhysicalShutdown() {
        let webView = WKWebView()
        let targets = CloseTargetStub(.orphan)
        let commands = CloseCommandsSpy()

        _ = BrowserTabWebKitCloseService(
            targets: targets,
            childWindows: ChildCloseStub(closes: false),
            commands: commands
        ).handleWebViewDidClose(webView)

        XCTAssertEqual(commands.actions, [.orphan])
    }

    private func makeTrackedFixture() -> (
        tab: Tab,
        webView: WKWebView,
        target: TrackedWebKitCloseTarget
    ) {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let webView = WKWebView()
        let window = BrowserWindowState()
        let owner = TrackedWebViewOwner(
            tabID: tab.id,
            windowID: window.id
        )
        return (
            tab,
            webView,
            TrackedWebKitCloseTarget(
                webView: webView,
                owner: owner,
                tab: tab,
                window: window
            )
        )
    }
}

@MainActor
private final class CloseTargetStub: WebKitCloseTargetResolving {
    private let target: WebKitCloseTarget

    init(_ target: WebKitCloseTarget) {
        self.target = target
    }

    func resolve(_ webView: WKWebView) -> WebKitCloseTarget {
        target
    }
}

@MainActor
private final class ChildCloseStub: WebKitChildWindowClosing {
    private let closes: Bool
    private(set) var received: TrackedWebKitCloseTarget?

    init(closes: Bool) {
        self.closes = closes
    }

    func closeIfDedicatedChild(
        _ target: TrackedWebKitCloseTarget
    ) -> Bool {
        received = target
        return closes
    }
}

@MainActor
private final class CloseCommandsSpy: BrowserWebKitCloseCommanding {
    enum Action: Equatable {
        case tracked
        case untracked
        case stale
        case orphan
    }

    private(set) var actions: [Action] = []
    private(set) var staleOwner: TrackedWebViewOwner?

    func closeTrackedTab(_ target: TrackedWebKitCloseTarget) {
        actions.append(.tracked)
    }

    func closeUntrackedTab(_ target: UntrackedWebKitCloseTarget) {
        actions.append(.untracked)
    }

    func discardStaleTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) {
        staleOwner = owner
        actions.append(.stale)
    }

    func discardOrphanWebView(_ webView: WKWebView) {
        actions.append(.orphan)
    }
}
