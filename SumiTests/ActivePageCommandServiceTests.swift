import AppKit
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ActivePageCommandServiceTests: XCTestCase {
    func testSelectedAndGlanceReloadUseDifferentPhysicalPaths() {
        let window = BrowserWindowState()
        let selectedTab = makeTab("https://selected.example")
        let previewTab = makeTab("https://preview.example")
        let recorder = ActivePageCommandRecorder()
        let service = makeService(
            window: window,
            selectedTab: selectedTab,
            glance: { recorder.glance },
            reloadSelected: { tab, window, _ in
                recorder.selectedReloads.append((tab.id, window.id))
                return Self.acceptedOutcome(for: tab)
            },
            reloadPreview: { tab in
                recorder.previewReloads.append(tab.id)
                return Self.acceptedOutcome(for: tab)
            }
        )

        XCTAssertTrue(service.reloadActivePage().ownsFutureOrSubmittedNavigation)
        recorder.glance = .init(tab: previewTab, url: previewTab.url, webView: WKWebView())
        XCTAssertTrue(service.reloadActivePage().ownsFutureOrSubmittedNavigation)

        XCTAssertEqual(recorder.selectedReloads.map(\.0), [selectedTab.id])
        XCTAssertEqual(recorder.selectedReloads.map(\.1), [window.id])
        XCTAssertEqual(recorder.previewReloads, [previewTab.id])
    }

    func testNativeSurfaceRejectsPageCommands() {
        let window = BrowserWindowState()
        let historyTab = makeTab("sumi://history?range=all")
        let recorder = ActivePageCommandRecorder()
        let nativeWebView = WKWebView()
        let service = makeService(
            window: window,
            selectedTab: historyTab,
            webView: nativeWebView,
            reloadSelected: { _, _, _ in
                recorder.selectedReloadCount += 1
                return Self.acceptedOutcome(for: historyTab)
            },
            reloadPreview: { _ in
                recorder.previewReloadCount += 1
                return Self.acceptedOutcome(for: historyTab)
            }
        )

        XCTAssertFalse(service.reloadActivePage().ownsFutureOrSubmittedNavigation)
        service.toggleMuteForActivePage()
        XCTAssertFalse(service.copyActivePageURL())
        XCTAssertFalse(service.inspectActivePage())

        XCTAssertFalse(historyTab.audioState.isMuted)
        XCTAssertEqual(recorder.selectedReloadCount, 0)
        XCTAssertEqual(recorder.previewReloadCount, 0)
        XCTAssertFalse(nativeWebView.isInspectable)
    }

    func testCopyUsesGlanceSessionHTTPURLAndExactWindowNotification() throws {
        let window = BrowserWindowState()
        let selectedTab = makeTab("https://selected.example")
        let previewTab = makeTab("https://preview.example/original")
        let sessionURL = try XCTUnwrap(URL(string: "https://preview.example/current"))
        let notifications = NotificationPresentingSpy()
        let service = makeService(
            window: window,
            selectedTab: selectedTab,
            glance: {
                .init(tab: previewTab, url: sessionURL, webView: WKWebView())
            },
            notifications: notifications
        )
        NSPasteboard.general.clearContents()

        XCTAssertTrue(service.copyActivePageURL())

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), sessionURL.absoluteString)
        XCTAssertEqual(notifications.presentNotificationCalls.map { $0.1?.id }, [window.id])
    }

    func testCopyRejectsNonWebScheme() {
        let window = BrowserWindowState()
        let fileTab = makeTab("file:///tmp/document.html")
        let notifications = NotificationPresentingSpy()
        let service = makeService(
            window: window,
            selectedTab: fileTab,
            notifications: notifications
        )

        XCTAssertFalse(service.copyActivePageURL())
        XCTAssertTrue(notifications.presentNotificationCalls.isEmpty)
    }

    func testInspectorUsesResolvedGlancePreviewWebView() {
        let window = BrowserWindowState()
        let selectedTab = makeTab("https://selected.example")
        let previewTab = makeTab("https://preview.example")
        let previewWebView = WKWebView()
        var inspectedWebView: WKWebView?
        let service = makeService(
            window: window,
            selectedTab: selectedTab,
            glance: {
                .init(tab: previewTab, url: previewTab.url, webView: previewWebView)
            },
            openInspector: {
                inspectedWebView = $0
                return true
            }
        )

        XCTAssertTrue(service.inspectActivePage())
        XCTAssertTrue(previewWebView.isInspectable)
        XCTAssertIdentical(inspectedWebView, previewWebView)
    }

    private func makeService(
        window: BrowserWindowState,
        selectedTab: Tab,
        glance: @escaping @MainActor @Sendable () -> ActivePageResolver.GlanceSnapshot? = { nil },
        webView: WKWebView? = nil,
        reloadSelected: @escaping @MainActor @Sendable (
            Tab,
            BrowserWindowState,
            String
        ) -> PageReloadCommandOutcome = { tab, _, _ in
            ActivePageCommandServiceTests.acceptedOutcome(for: tab)
        },
        reloadPreview: @escaping @MainActor @Sendable (
            Tab
        ) -> PageReloadCommandOutcome = { tab in
            ActivePageCommandServiceTests.acceptedOutcome(for: tab)
        },
        notifications: NotificationPresentingSpy = NotificationPresentingSpy(),
        openInspector: @escaping @MainActor (WKWebView) -> Bool = { _ in true }
    ) -> ActivePageCommandService {
        let resolver = ActivePageResolver(
            activeWindow: { window },
            selectedTab: { _ in selectedTab },
            glanceSnapshot: { _ in glance() },
            windowOwnedWebView: { _, _ in webView }
        )
        return ActivePageCommandService(
            resolver: resolver,
            reloadSelectedPage: reloadSelected,
            reloadPreviewPage: reloadPreview,
            clipboard: BrowserURLClipboardService(notifications: { notifications }),
            inspector: WebInspectorService(
                isEnabled: { true },
                openInspector: openInspector
            )
        )
    }

    private func makeTab(_ url: String) -> Tab {
        Tab(
            url: URL(string: url)!,
            name: url,
            loadsCachedFaviconOnInit: false
        )
    }

    private static func acceptedOutcome(for tab: Tab) -> PageReloadCommandOutcome {
        let intent = tab.mainFrameLoads.currentIntent
        return PageReloadCommandOutcome(.waiting(
            TabMainFramePendingAttemptOwner(
                intent: intent,
                documentGeneration: 0,
                participantID: UUID(),
                webViewID: ObjectIdentifier(tab),
                phase: .deferred
            )
        ))
    }
}

@MainActor
private final class ActivePageCommandRecorder {
    var glance: ActivePageResolver.GlanceSnapshot?
    var selectedReloads: [(UUID, UUID)] = []
    var previewReloads: [UUID] = []
    var selectedReloadCount = 0
    var previewReloadCount = 0
}
