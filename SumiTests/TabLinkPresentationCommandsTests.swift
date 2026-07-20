import AppKit
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabLinkPresentationCommandsTests: XCTestCase {
    func testSameTabTwoWindowLinkCommandsUseExactPhysicalSourceWindow() throws {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        let firstWebView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        let secondWebView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        firstWebView.owningTab = tab
        secondWebView.owningTab = tab

        var tabRequests: [(URL, UUID, UUID, Bool)] = []
        var windowRequests: [(URL, UUID, UUID, Bool)] = []
        let commands = makeCommands(
            tab: tab,
            physicalWindows: [
                firstWebView: firstWindow,
                secondWebView: secondWindow,
            ],
            openTab: { url, source, selected in
                tabRequests.append((
                    url,
                    source.tab.id,
                    source.window.id,
                    selected
                ))
                return true
            },
            openWindow: { url, source, selected in
                windowRequests.append((
                    url,
                    source.tab.id,
                    source.window.id,
                    selected
                ))
                return true
            }
        )
        let foregroundURL = try XCTUnwrap(
            URL(string: "https://target.example/foreground")
        )
        let backgroundURL = try XCTUnwrap(
            URL(string: "https://target.example/background")
        )
        let inactiveWindowURL = try XCTUnwrap(
            URL(string: "https://target.example/inactive-window")
        )
        let activeWindowURL = try XCTUnwrap(
            URL(string: "https://target.example/active-window")
        )

        XCTAssertTrue(commands.open(
            foregroundURL,
            from: secondWebView,
            disposition: .newTab(selected: true)
        ))
        XCTAssertTrue(commands.open(
            backgroundURL,
            from: secondWebView,
            disposition: .newTab(selected: false)
        ))
        XCTAssertTrue(commands.open(
            inactiveWindowURL,
            from: secondWebView,
            disposition: .newWindow(selected: false)
        ))
        XCTAssertTrue(commands.open(
            activeWindowURL,
            from: secondWebView,
            disposition: .newWindow(selected: true)
        ))

        XCTAssertEqual(tabRequests.map(\.0), [foregroundURL, backgroundURL])
        XCTAssertEqual(tabRequests.map(\.1), [tab.id, tab.id])
        XCTAssertEqual(tabRequests.map(\.2), [secondWindow.id, secondWindow.id])
        XCTAssertEqual(tabRequests.map(\.3), [true, false])
        XCTAssertEqual(
            windowRequests.map(\.0),
            [inactiveWindowURL, activeWindowURL]
        )
        XCTAssertEqual(windowRequests.map(\.1), [tab.id, tab.id])
        XCTAssertEqual(
            windowRequests.map(\.2),
            [secondWindow.id, secondWindow.id]
        )
        XCTAssertEqual(windowRequests.map(\.3), [false, true])
        XCTAssertFalse(
            tabRequests.contains { $0.2 == firstWindow.id }
                || windowRequests.contains { $0.2 == firstWindow.id }
        )
    }

    func testSameTabTwoWindowGlanceUsesExactPhysicalSourceWindow() throws {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        let firstWebView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        let secondWebView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        firstWebView.owningTab = tab
        secondWebView.owningTab = tab
        let targetURL = try XCTUnwrap(
            URL(string: "https://target.example/glance")
        )
        let origin = CGRect(x: 11, y: 22, width: 33, height: 44)
        var activatedWindowIDs: [UUID] = []
        var requests: [(URL, UUID, UUID, CGRect?)] = []
        let commands = makeCommands(
            tab: tab,
            physicalWindows: [
                firstWebView: firstWindow,
                secondWebView: secondWindow,
            ],
            activateSource: { source in
                XCTAssertIdentical(source.tab, tab)
                activatedWindowIDs.append(source.window.id)
                return true
            },
            presentGlance: { url, source, originRect in
                requests.append((
                    url,
                    source.tab.id,
                    source.window.id,
                    originRect
                ))
                return true
            }
        )

        XCTAssertTrue(commands.presentInGlance(
            targetURL,
            from: secondWebView,
            originRectInWindow: origin
        ))

        XCTAssertEqual(activatedWindowIDs, [secondWindow.id])
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.0, targetURL)
        XCTAssertEqual(requests.first?.1, tab.id)
        XCTAssertEqual(requests.first?.2, secondWindow.id)
        XCTAssertEqual(requests.first?.3, origin)
        XCTAssertNotEqual(requests.first?.2, firstWindow.id)
    }

    func testUntrackedOrMismatchedPhysicalSourceFailsClosed() throws {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let untracked = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        let mismatched = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        untracked.owningTab = tab
        mismatched.owningTab = tab
        var requestCount = 0
        let commands = TabLinkPresentationCommands(
            resolveSource: { _ in nil },
            openTab: { _, _, _ in
                requestCount += 1
                return true
            },
            openWindow: { _, _, _ in
                requestCount += 1
                return true
            },
            openSplit: { _, _ in
                requestCount += 1
                return true
            },
            activateSource: { _ in
                requestCount += 1
                return true
            },
            presentGlance: { _, _, _ in
                requestCount += 1
                return true
            }
        )
        let targetURL = try XCTUnwrap(URL(string: "https://target.example"))

        XCTAssertFalse(commands.open(
            targetURL,
            from: untracked,
            disposition: .newTab(selected: true)
        ))
        XCTAssertFalse(commands.open(
            targetURL,
            from: mismatched,
            disposition: .newWindow(selected: true)
        ))
        XCTAssertFalse(
            commands.presentInGlance(targetURL, from: mismatched)
        )

        XCTAssertEqual(requestCount, 0)
    }

    func testRejectedExactWindowActivationDoesNotPresentGlance() throws {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let sourceWindow = BrowserWindowState()
        let sourceWebView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        sourceWebView.owningTab = tab
        let targetURL = try XCTUnwrap(
            URL(string: "https://target.example/glance")
        )
        var presentationCount = 0
        let commands = makeCommands(
            tab: tab,
            physicalWindows: [sourceWebView: sourceWindow],
            activateSource: { _ in false },
            presentGlance: { _, _, _ in
                presentationCount += 1
                return true
            }
        )

        XCTAssertFalse(
            commands.presentInGlance(targetURL, from: sourceWebView)
        )
        XCTAssertEqual(presentationCount, 0)
    }

    private func makeCommands(
        tab: Tab,
        physicalWindows: [FocusableWKWebView: BrowserWindowState],
        openTab: @escaping TabLinkPresentationCommands.OpenTab = {
            _, _, _ in true
        },
        openWindow: @escaping TabLinkPresentationCommands.OpenWindow = {
            _, _, _ in true
        },
        openSplit: @escaping TabLinkPresentationCommands.OpenSplit = {
            _, _ in true
        },
        activateSource: @escaping TabLinkPresentationCommands.ActivateSource = {
            _ in true
        },
        presentGlance: @escaping TabLinkPresentationCommands.PresentGlance = {
            _, _, _ in true
        }
    ) -> TabLinkPresentationCommands {
        let receipts = Dictionary(
            uniqueKeysWithValues: physicalWindows.map { webView, window in
                (ObjectIdentifier(webView), makeReceipt(
                    tab: tab,
                    window: window,
                    webView: webView
                ))
            }
        )
        return TabLinkPresentationCommands(
            resolveSource: { receipts[ObjectIdentifier($0)] },
            openTab: openTab,
            openWindow: openWindow,
            openSplit: openSplit,
            activateSource: activateSource,
            presentGlance: presentGlance
        )
    }

    private func makeReceipt(
        tab: Tab,
        window: BrowserWindowState,
        webView: FocusableWKWebView
    ) -> PhysicalWebViewSourceReceipt {
        let profile = Profile(
            name: "Unit",
            dataStore: webView.configuration.websiteDataStore
        )
        let space = Space(name: "Unit", profileId: profile.id)
        return PhysicalWebViewSourceReceipt(
            webView: webView,
            trackedWebView: TrackedWebViewOwner(
                tabID: tab.id,
                windowID: window.id
            ),
            tab: tab,
            window: window,
            residence: .regularSpaceMember,
            presentationSpace: space,
            presentationProfile: profile,
            executionProfile: profile,
            dataStore: profile.dataStore,
            appKitWindow: nil
        )
    }
}
