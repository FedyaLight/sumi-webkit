import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewCleanupOwnerTests: XCTestCase {
    func testCleanupWebViewUsesScopedRuntimeInOrder() {
        let tabId = UUID()
        let webView = WKWebView(frame: .zero)
        var events: [Event] = []
        var handledEvent: SumiPermissionLifecycleEvent?
        var deferredWebView: WKWebView?
        var deferredTabId: UUID?
        var deferredReason: String?

        let context = makeContext(
            tabId: tabId,
            handlePermissionLifecycleEvent: { event in
                handledEvent = event
                events.append(.permissionEvent)
            },
            deferProtectedWebViewCleanup: { candidateWebView, candidateTabId, reason in
                deferredWebView = candidateWebView
                deferredTabId = candidateTabId
                deferredReason = reason
                events.append(.protectedCleanupCheck)
                return false
            },
            shutdownRuntime: SumiWebViewShutdown.NormalTabRuntime(
                cleanupUserScripts: { controller, webViewId in
                    XCTAssertIdentical(controller, webView.configuration.userContentController)
                    events.append(.cleanupUserScripts(webViewId))
                },
                removeWebViewFromContainers: { candidateWebView in
                    XCTAssertIdentical(candidateWebView, webView)
                    events.append(.removeFromContainers)
                }
            ),
            currentPermissionPageId: { "page-1" },
            profilePartitionId: { "profile-1" },
            unbindAudioState: { candidateWebView in
                XCTAssertIdentical(candidateWebView, webView)
                events.append(.unbindAudio)
            },
            removeNavigationStateObservers: { candidateWebView in
                XCTAssertIdentical(candidateWebView, webView)
                events.append(.removeNavigationStateObservers)
            },
            removeNavigationDelegateBundle: { candidateWebView in
                XCTAssertIdentical(candidateWebView, webView)
                events.append(.removeNavigationDelegateBundle)
            }
        )

        TabWebViewCleanupOwner.cleanupWebView(webView, context: context)

        XCTAssertEqual(
            handledEvent,
            .webViewDeallocated(
                pageId: "page-1",
                tabId: tabId.uuidString.lowercased(),
                profilePartitionId: "profile-1",
                reason: "normal-tab-webview-cleanup"
            )
        )
        XCTAssertIdentical(deferredWebView, webView)
        XCTAssertEqual(deferredTabId, tabId)
        XCTAssertEqual(deferredReason, "Tab.cleanupCloneWebView")
        XCTAssertEqual(
            events,
            [
                .permissionEvent,
                .protectedCleanupCheck,
                .cleanupUserScripts(tabId),
                .unbindAudio,
                .removeNavigationStateObservers,
                .removeNavigationDelegateBundle,
                .removeFromContainers,
            ]
        )
    }

    func testCleanupWebViewDeferralSkipsShutdownAndTabLocalCleanup() {
        let tabId = UUID()
        let webView = WKWebView(frame: .zero)
        var events: [Event] = []

        let context = makeContext(
            tabId: tabId,
            handlePermissionLifecycleEvent: { _ in
                events.append(.permissionEvent)
            },
            deferProtectedWebViewCleanup: { _, _, _ in
                events.append(.protectedCleanupCheck)
                return true
            },
            shutdownRuntime: SumiWebViewShutdown.NormalTabRuntime(
                cleanupUserScripts: { _, _ in
                    XCTFail("Deferred cleanup must not run shutdown user-script cleanup")
                },
                removeWebViewFromContainers: { _ in
                    XCTFail("Deferred cleanup must not remove containers")
                }
            ),
            unbindAudioState: { _ in
                XCTFail("Deferred cleanup must not unbind audio state")
            },
            removeNavigationStateObservers: { _ in
                XCTFail("Deferred cleanup must not remove navigation observers")
            },
            removeNavigationDelegateBundle: { _ in
                XCTFail("Deferred cleanup must not remove delegate bundle")
            }
        )

        TabWebViewCleanupOwner.cleanupWebView(webView, context: context)

        XCTAssertEqual(events, [.permissionEvent, .protectedCleanupCheck])
    }

    private func makeContext(
        tabId: UUID,
        handlePermissionLifecycleEvent: @escaping TabWebViewCleanupOwner.PermissionLifecycleEventHandler = { _ in /* No-op. */ },
        deferProtectedWebViewCleanup: @escaping TabWebViewCleanupOwner.ProtectedWebViewCleanupDeferrer = { _, _, _ in false },
        shutdownRuntime: SumiWebViewShutdown.NormalTabRuntime = SumiWebViewShutdown.NormalTabRuntime(
            cleanupUserScripts: { _, _ in /* No-op. */ },
            removeWebViewFromContainers: { _ in /* No-op. */ }
        ),
        currentPermissionPageId: @escaping () -> String = { "page" },
        profilePartitionId: @escaping () -> String? = { nil },
        unbindAudioState: @escaping (WKWebView) -> Void = { _ in /* No-op. */ },
        removeNavigationStateObservers: @escaping (WKWebView) -> Void = { _ in /* No-op. */ },
        removeNavigationDelegateBundle: @escaping (WKWebView) -> Void = { _ in /* No-op. */ }
    ) -> TabWebViewCleanupOwner.Context {
        TabWebViewCleanupOwner.Context(
            tabId: tabId,
            tabName: { "Example" },
            handlePermissionLifecycleEvent: handlePermissionLifecycleEvent,
            deferProtectedWebViewCleanup: deferProtectedWebViewCleanup,
            shutdownRuntime: shutdownRuntime,
            notifyNowPlayingTabUnloaded: { _ in /* No-op. */ },
            currentWebView: { nil },
            clearCurrentWebView: { /* No-op. */ },
            removeAllWebViews: { _ in false },
            currentPermissionPageId: currentPermissionPageId,
            profilePartitionId: profilePartitionId,
            invalidatePermissionPageForReplacement: { _ in /* No-op. */ },
            unbindAudioState: unbindAudioState,
            removeNavigationStateObservers: removeNavigationStateObservers,
            removeNavigationDelegateBundle: removeNavigationDelegateBundle,
            resetPlaybackActivity: { /* No-op. */ },
            setLoadingIdle: { /* No-op. */ }
        )
    }
}

private enum Event: Equatable {
    case permissionEvent
    case protectedCleanupCheck
    case cleanupUserScripts(UUID)
    case unbindAudio
    case removeNavigationStateObservers
    case removeNavigationDelegateBundle
    case removeFromContainers
}
