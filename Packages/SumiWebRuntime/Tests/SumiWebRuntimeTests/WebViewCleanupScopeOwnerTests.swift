import WebKit
import XCTest

@testable import SumiWebRuntime

@MainActor
final class WebViewCleanupScopeOwnerTests: XCTestCase {
    func testCleanupContinuesWhenProtectionEndsBeforeDeferralCommit() {
        let owner = WebViewCleanupScopeOwner()
        let trackedOwner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let webView = WKWebView()
        var protectionChecks = 0
        var cleaned: [(ObjectIdentifier, TrackedWebViewOwner)] = []

        owner.cleanupWindow(
            trackedOwner.windowID,
            entries: [(trackedOwner, webView)],
            runtime: .init(
                tabForID: { _ in nil },
                isWebViewProtectedFromCompositorMutation: { _ in
                    protectionChecks += 1
                    return protectionChecks == 1
                },
                enqueueDeferredProtectedCommand: { _, _, _ in false },
                cleanupUnprotectedTrackedWebView: { webView, owner, _ in
                    cleaned.append((ObjectIdentifier(webView), owner))
                    return true
                },
                refreshPrimaryTrackedWebView: { _ in }
            )
        )

        XCTAssertEqual(protectionChecks, 2)
        XCTAssertEqual(cleaned.count, 1)
        XCTAssertEqual(cleaned.first?.0, ObjectIdentifier(webView))
        XCTAssertEqual(cleaned.first?.1, trackedOwner)
    }

    func testCleanupDoesNotMutateWebViewThatRemainsProtectedWithoutDeferral() {
        let owner = WebViewCleanupScopeOwner()
        let trackedOwner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let webView = WKWebView()
        var cleanupCount = 0

        owner.cleanupWindow(
            trackedOwner.windowID,
            entries: [(trackedOwner, webView)],
            runtime: .init(
                tabForID: { _ in nil },
                isWebViewProtectedFromCompositorMutation: { _ in true },
                enqueueDeferredProtectedCommand: { _, _, _ in false },
                cleanupUnprotectedTrackedWebView: { _, _, _ in
                    cleanupCount += 1
                    return true
                },
                refreshPrimaryTrackedWebView: { _ in }
            )
        )

        XCTAssertEqual(cleanupCount, 0)
    }

    func testRejectedCleanupDoesNotRefreshPrimaryWebView() {
        let owner = WebViewCleanupScopeOwner()
        let tab = StubTabHandle()
        let trackedOwner = TrackedWebViewOwner(
            tabID: tab.id,
            windowID: UUID()
        )
        var refreshCount = 0

        owner.cleanupWindow(
            trackedOwner.windowID,
            entries: [(trackedOwner, WKWebView())],
            runtime: .init(
                tabForID: { _ in tab },
                isWebViewProtectedFromCompositorMutation: { _ in false },
                enqueueDeferredProtectedCommand: { _, _, _ in false },
                cleanupUnprotectedTrackedWebView: { _, _, _ in false },
                refreshPrimaryTrackedWebView: { _ in refreshCount += 1 }
            )
        )

        XCTAssertEqual(refreshCount, 0)
    }
}

@MainActor
private final class StubTabHandle: WebRuntimeTabHandle {
    let id = UUID()
    let webViewSession: WebViewSessionHandle
    let requiresPrimaryWebView = true
    var url = URL(string: "about:blank")!
    let isEphemeral = false
    let resolvedProfileId: UUID? = nil

    init() {
        webViewSession = WebViewSessionHandle(
            tabID: id,
            repository: WebViewSessionRepository()
        )
    }
}
