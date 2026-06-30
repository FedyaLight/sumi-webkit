import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabCloseLifecycleOwnerTests: XCTestCase {
    func testCloseRunsTabLocalTeardownInOrder() {
        let tabId = UUID()
        let webView = WKWebView(frame: .zero)
        let spy = Spy()
        let owner = TabCloseLifecycleOwner()

        owner.close(context: context(
            tabId: tabId,
            currentWebView: { webView },
            spy: spy
        ))

        XCTAssertEqual(
            spy.events,
            [
                .cleanupPermission("normal-tab-close"),
                .comprehensiveWebViewCleanup,
                .resetPlayback,
                .applyAudioState(.unmuted(isPlayingAudio: false)),
                .setLoadingIdle,
                .cleanupZoom(tabId),
                .updateTabVisibility,
                .currentWebView,
                .removeNavigationStateObservers,
                .removeTab(tabId),
                .cancelProfileAwait,
                .cancelPendingMainFrameNavigation,
            ]
        )
    }

    func testCloseSkipsObserverRemovalWhenCurrentWebViewWasAlreadyCleared() {
        let tabId = UUID()
        let spy = Spy()
        let owner = TabCloseLifecycleOwner()

        owner.close(context: context(
            tabId: tabId,
            currentWebView: { nil },
            spy: spy
        ))

        XCTAssertFalse(spy.events.contains(.removeNavigationStateObservers))
        XCTAssertEqual(spy.events.last, .cancelPendingMainFrameNavigation)
    }

    private func context(
        tabId: UUID,
        currentWebView: @escaping () -> WKWebView?,
        spy: Spy
    ) -> TabCloseLifecycleOwner.Context {
        TabCloseLifecycleOwner.Context(
            tabId: tabId,
            tabName: { "Example" },
            cleanupNormalTabPermissionRuntime: { reason in
                spy.events.append(.cleanupPermission(reason))
            },
            performComprehensiveWebViewCleanup: {
                spy.events.append(.comprehensiveWebViewCleanup)
            },
            resetPlaybackActivity: {
                spy.events.append(.resetPlayback)
            },
            applyAudioState: { state in
                spy.events.append(.applyAudioState(state))
            },
            setLoadingIdle: {
                spy.events.append(.setLoadingIdle)
            },
            cleanupZoomForTab: { closedTabId in
                spy.events.append(.cleanupZoom(closedTabId))
            },
            updateTabVisibility: {
                spy.events.append(.updateTabVisibility)
            },
            currentWebView: {
                spy.events.append(.currentWebView)
                return currentWebView()
            },
            removeNavigationStateObservers: { _ in
                spy.events.append(.removeNavigationStateObservers)
            },
            removeTab: { closedTabId in
                spy.events.append(.removeTab(closedTabId))
            },
            cancelProfileAwait: {
                spy.events.append(.cancelProfileAwait)
            },
            cancelPendingMainFrameNavigation: {
                spy.events.append(.cancelPendingMainFrameNavigation)
            }
        )
    }
}

private final class Spy {
    var events: [Event] = []
}

private enum Event: Equatable {
    case cleanupPermission(String)
    case comprehensiveWebViewCleanup
    case resetPlayback
    case applyAudioState(SumiWebViewAudioState)
    case setLoadingIdle
    case cleanupZoom(UUID)
    case updateTabVisibility
    case currentWebView
    case removeNavigationStateObservers
    case removeTab(UUID)
    case cancelProfileAwait
    case cancelPendingMainFrameNavigation
}
