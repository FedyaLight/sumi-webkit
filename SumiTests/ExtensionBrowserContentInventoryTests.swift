import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionBrowserContentInventoryTests: XCTestCase {
    func testTabsPreserveRuntimeThenWindowEphemeralOrder() {
        let first = Tab()
        let second = Tab()
        let firstEphemeral = Tab()
        let secondEphemeral = Tab()
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        firstWindow.ephemeralTabs = [firstEphemeral]
        secondWindow.ephemeralTabs = [secondEphemeral]
        let runtime = makeRuntime(
            tabs: [first, second],
            windows: [firstWindow, secondWindow]
        )

        let tabs = ExtensionBrowserContentInventory().tabs(in: runtime)

        XCTAssertEqual(
            tabs.map(ObjectIdentifier.init),
            [first, second, firstEphemeral, secondEphemeral]
                .map(ObjectIdentifier.init)
        )
    }

    func testLiveWebViewsOrderPrimaryThenUntrackedThenRemainingTracked() {
        let tab = Tab()
        let primaryWindowID = UUID()
        let primary = WKWebView()
        let untracked = WKWebView()
        let firstRemaining = WKWebView()
        let secondRemaining = WKWebView()
        let runtime = makeRuntime(
            primaryTrackedWindowID: { tabID in
                tabID == tab.id ? primaryWindowID : nil
            },
            windowOwnedWebView: { candidate, windowID in
                candidate === tab && windowID == primaryWindowID
                    ? primary
                    : nil
            },
            untrackedOwnedWebView: { candidate in
                candidate === tab ? untracked : nil
            },
            trackedWebViews: { tabID in
                guard tabID == tab.id else { return [] }
                return [
                    primary,
                    firstRemaining,
                    untracked,
                    firstRemaining,
                    secondRemaining,
                ]
            }
        )

        let webViews = ExtensionBrowserContentInventory().liveWebViews(
            for: tab,
            in: runtime
        )

        XCTAssertEqual(
            webViews.map(ObjectIdentifier.init),
            [primary, untracked, firstRemaining, secondRemaining]
                .map(ObjectIdentifier.init)
        )
    }

    func testTrackedOrderRemainsStableWithoutPrimaryResidence() {
        let tab = Tab()
        let untracked = WKWebView()
        let firstTracked = WKWebView()
        let secondTracked = WKWebView()
        let runtime = makeRuntime(
            untrackedOwnedWebView: { candidate in
                candidate === tab ? untracked : nil
            },
            trackedWebViews: { tabID in
                tabID == tab.id
                    ? [firstTracked, secondTracked]
                    : []
            }
        )

        let webViews = ExtensionBrowserContentInventory().liveWebViews(
            for: tab,
            in: runtime
        )

        XCTAssertEqual(
            webViews.map(ObjectIdentifier.init),
            [untracked, firstTracked, secondTracked]
                .map(ObjectIdentifier.init)
        )
    }

    func testUnavailableRuntimeDoesNotReadWebViewProviders() {
        let tab = Tab()
        var providerCallCount = 0
        let runtime = makeRuntime(
            primaryTrackedWindowID: { _ in
                providerCallCount += 1
                return UUID()
            },
            windowOwnedWebView: { _, _ in
                providerCallCount += 1
                return WKWebView()
            },
            untrackedOwnedWebView: { _ in
                providerCallCount += 1
                return WKWebView()
            },
            trackedWebViews: { _ in
                providerCallCount += 1
                return [WKWebView()]
            },
            browserRuntimeAvailable: { false }
        )

        XCTAssertTrue(
            ExtensionBrowserContentInventory().liveWebViews(
                for: tab,
                in: runtime
            ).isEmpty
        )
        XCTAssertEqual(providerCallCount, 0)
    }

    private func makeRuntime(
        tabs: [Tab] = [],
        windows: [BrowserWindowState] = [],
        primaryTrackedWindowID: @escaping @MainActor (UUID) -> UUID? = {
            _ in nil
        },
        windowOwnedWebView: @escaping @MainActor (
            Tab,
            UUID
        ) -> WKWebView? = { _, _ in nil },
        untrackedOwnedWebView: @escaping @MainActor (
            Tab
        ) -> WKWebView? = { _ in nil },
        trackedWebViews: @escaping @MainActor (
            UUID
        ) -> [WKWebView] = { _ in [] },
        browserRuntimeAvailable: @escaping @MainActor () -> Bool = { true }
    ) -> ExtensionManagerRuntime {
        ExtensionManagerRuntime(
            currentProfile: { nil },
            profile: { _ in nil },
            ephemeralProfile: { _ in nil },
            windowState: { _ in nil },
            activeWindowState: { nil },
            allTabs: { tabs },
            allWindowStates: { windows },
            windowStateContainingTab: { _ in nil },
            windowOwnedWebView: windowOwnedWebView,
            primaryTrackedWindowId: primaryTrackedWindowID,
            untrackedOwnedWebView: untrackedOwnedWebView,
            trackedWebViews: trackedWebViews,
            rebuildLiveWebViews: { _ in .noLiveWindows },
            websiteDataMutationAdmissionIsBlocked: { _ in false },
            waitForWebsiteDataMutationAdmission: { _ in true },
            browserRuntimeAvailable: browserRuntimeAvailable,
            extensionsModuleEnabled: { .enabled(true) }
        )
    }
}
