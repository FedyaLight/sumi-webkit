import WebKit
import XCTest
import SumiWebRuntime

@testable import Sumi

@MainActor
final class TabCloseLifecycleOwnerTests: XCTestCase {
    func testCloseRunsTabLocalTeardownInOrder() {
        let tabId = UUID()
        let spy = Spy()
        let owner = TabCloseLifecycleOwner()

        owner.close(context: context(
            tabId: tabId,
            spy: spy
        ))

        XCTAssertEqual(
            spy.events,
            [
                .cleanupPermission("normal-tab-close"),
                .cancelProfileAwait,
                .cancelPendingMainFrameNavigation,
                .comprehensiveWebViewCleanup,
                .resetPlayback,
                .applyAudioState(.unmuted(isPlayingAudio: false)),
                .setLoadingIdle,
                .cleanupZoom(tabId),
                .updateTabVisibility,
                .removeTab(tabId),
            ]
        )
    }

    func testCloseLeavesCallbackDetachmentToSealedRetirement() {
        let tabId = UUID()
        let spy = Spy()
        let owner = TabCloseLifecycleOwner()

        owner.close(context: context(
            tabId: tabId,
            spy: spy
        ))

        XCTAssertFalse(spy.events.contains(.currentWebView))
        XCTAssertFalse(spy.events.contains(.removeNavigationStateObservers))
        XCTAssertEqual(spy.events.last, .removeTab(tabId))
    }

    private func context(
        tabId: UUID,
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
