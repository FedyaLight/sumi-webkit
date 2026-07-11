import WebKit
import XCTest
import SumiWebRuntime

@testable import Sumi

@MainActor
final class BrowserWebViewRoutingServiceTests: XCTestCase {
    func testMissingTabDoesNotInvokeCommandsForTabBackedOperations() {
        let commandRecorder = RecordingWebViewRoutingCommands()
        let service = BrowserWebViewRoutingService(
            tabLookup: { _ in nil },
            webViewSessions: commandRecorder.webViewSessions,
            ownershipQuery: WebViewOwnershipQuery(
                webViewSessions: commandRecorder.webViewSessions
            ),
            commands: commandRecorder.commands
        )
        let tabId = UUID()
        let intent = TabMainFrameNavigationIntent(
            revision: 1,
            targetURL: URL(string: "https://example.com/missing")!
        )

        service.syncTabAcrossWindows(tabId)
        service.reloadTabAcrossWindows(
            tabId,
            intent: intent,
            policy: .standard
        )
        service.reloadTab(
            tabId,
            in: UUID(),
            intent: intent,
            policy: .standard
        )

        XCTAssertTrue(commandRecorder.syncCalls.isEmpty)
        XCTAssertTrue(commandRecorder.reloadCalls.isEmpty)
        XCTAssertTrue(commandRecorder.windowReloadCalls.isEmpty)
    }

    func testRoutingCallsDelegateToInjectedCommands() throws {
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/page")),
            loadsCachedFaviconOnInit: false
        )
        let commandRecorder = RecordingWebViewRoutingCommands()
        let expectedWebView = WKWebView()
        let originatingWebView = WKWebView()
        let windowId = UUID()
        let reloadWindowId = UUID()
        let reloadIntent = tab.beginMainFrameNavigationIntent(to: tab.url)
        registerTrackedWebView(
            expectedWebView,
            for: tab.id,
            in: windowId,
            repository: commandRecorder.webViewSessions
        )
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabId in tabId == tab.id ? tab : nil },
            webViewSessions: commandRecorder.webViewSessions,
            ownershipQuery: WebViewOwnershipQuery(
                webViewSessions: commandRecorder.webViewSessions
            ),
            commands: commandRecorder.commands
        )

        let webView = service.webView(for: tab.id, in: windowId)
        service.syncTabAcrossWindows(tab.id, originatingWebView: originatingWebView)
        service.reloadTabAcrossWindows(
            tab.id,
            intent: reloadIntent,
            policy: .standard
        )
        service.reloadTab(
            tab.id,
            in: reloadWindowId,
            intent: reloadIntent,
            policy: .standard
        )
        service.setMuteState(true, for: tab.id)

        XCTAssertIdentical(webView, expectedWebView)

        let syncCall = try XCTUnwrap(commandRecorder.syncCalls.first)
        XCTAssertIdentical(syncCall.tab, tab)
        XCTAssertEqual(syncCall.url, tab.url)
        XCTAssertIdentical(syncCall.originatingWebView, originatingWebView)

        XCTAssertEqual(commandRecorder.reloadCalls.count, 1)
        XCTAssertIdentical(commandRecorder.reloadCalls.first, tab)
        let windowReload = try XCTUnwrap(commandRecorder.windowReloadCalls.first)
        XCTAssertIdentical(windowReload.tab, tab)
        XCTAssertEqual(windowReload.windowId, reloadWindowId)
        XCTAssertEqual(commandRecorder.muteCalls.count, 1)
        XCTAssertEqual(commandRecorder.muteCalls.first?.muted, true)
        XCTAssertEqual(commandRecorder.muteCalls.first?.tabId, tab.id)
    }

    func testWindowOwnedWebViewUsesCanonicalTrackedWebView() throws {
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/page")),
            loadsCachedFaviconOnInit: false
        )
        let tabWebView = WKWebView()
        let trackedWebView = WKWebView()
        tab.replaceUntrackedWebView(tabWebView)
        let commandRecorder = RecordingWebViewRoutingCommands()
        let windowID = UUID()
        registerTrackedWebView(
            trackedWebView,
            for: tab.id,
            in: windowID,
            repository: commandRecorder.webViewSessions
        )
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabId in tabId == tab.id ? tab : nil },
            webViewSessions: commandRecorder.webViewSessions,
            ownershipQuery: WebViewOwnershipQuery(
                webViewSessions: commandRecorder.webViewSessions
            ),
            commands: commandRecorder.commands
        )

        XCTAssertIdentical(
            service.windowOwnedWebView(for: tab, in: windowID),
            trackedWebView
        )
    }

    func testWindowOwnedWebViewDoesNotReturnUntrackedCurrentWebView() throws {
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/page")),
            loadsCachedFaviconOnInit: false
        )
        let tabWebView = WKWebView()
        tab.replaceUntrackedWebView(tabWebView)
        let commandRecorder = RecordingWebViewRoutingCommands()
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabId in tabId == tab.id ? tab : nil },
            webViewSessions: commandRecorder.webViewSessions,
            ownershipQuery: WebViewOwnershipQuery(
                webViewSessions: commandRecorder.webViewSessions
            ),
            commands: commandRecorder.commands
        )

        XCTAssertNil(service.windowOwnedWebView(for: tab, in: UUID()))
    }

    func testWindowOwnedWebViewDoesNotReturnAssignedWebViewForDifferentWindow() throws {
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/page")),
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(WKWebView())
        let commandRecorder = RecordingWebViewRoutingCommands()
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabId in tabId == tab.id ? tab : nil },
            webViewSessions: commandRecorder.webViewSessions,
            ownershipQuery: WebViewOwnershipQuery(
                webViewSessions: commandRecorder.webViewSessions
            ),
            commands: commandRecorder.commands
        )

        XCTAssertNil(service.windowOwnedWebView(for: tab, in: UUID()))
    }

    func testWindowRefreshUsesTrackedViewAndRoutesExactIntentAndPolicy() throws {
        let commandRecorder = RecordingWebViewRoutingCommands()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/tracked")),
            webViewSessions: commandRecorder.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let windowState = BrowserWindowState()
        registerTrackedWebView(
            WKWebView(),
            for: tab.id,
            in: windowState.id,
            repository: commandRecorder.webViewSessions
        )
        commandRecorder.materializedWebView = WKWebView()
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabID in tabID == tab.id ? tab : nil },
            webViewSessions: commandRecorder.webViewSessions,
            ownershipQuery: WebViewOwnershipQuery(
                webViewSessions: commandRecorder.webViewSessions
            ),
            commands: commandRecorder.commands
        )

        let outcome = service.refreshPage(
            for: tab,
            in: windowState,
            reason: "test",
            policy: .fromOrigin
        )

        XCTAssertEqual(outcome, .accepted)
        XCTAssertTrue(commandRecorder.materializeCalls.isEmpty)
        let reload = try XCTUnwrap(commandRecorder.windowReloadCalls.first)
        XCTAssertIdentical(reload.tab, tab)
        XCTAssertEqual(reload.windowId, windowState.id)
        XCTAssertEqual(reload.intent.targetURL, tab.url)
        XCTAssertEqual(reload.policy, .fromOrigin)
    }

    func testWindowRefreshMaterializesOnlyTheRequestedWindowWhenUntracked() throws {
        let commandRecorder = RecordingWebViewRoutingCommands()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/materialized")),
            webViewSessions: commandRecorder.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let materializedWebView = WKWebView()
        commandRecorder.materializedWebView = materializedWebView
        let windowState = BrowserWindowState()
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabID in tabID == tab.id ? tab : nil },
            webViewSessions: commandRecorder.webViewSessions,
            ownershipQuery: WebViewOwnershipQuery(
                webViewSessions: commandRecorder.webViewSessions
            ),
            commands: commandRecorder.commands
        )

        XCTAssertEqual(
            service.refreshPage(
                for: tab,
                in: windowState,
                reason: "test"
            ),
            .accepted
        )
        XCTAssertFalse(commandRecorder.materializeCalls.isEmpty)
        XCTAssertTrue(commandRecorder.materializeCalls.allSatisfy {
            $0.tab === tab && $0.windowId == windowState.id
        })
        XCTAssertEqual(
            commandRecorder.windowReloadCalls.first?.windowId,
            windowState.id
        )
    }

    func testAnyLiveWebViewFallsBackToUntrackedOwnedWebViewViaOwnershipQuery() throws {
        let commandRecorder = RecordingWebViewRoutingCommands()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/page")),
            webViewSessions: commandRecorder.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let untracked = FocusableWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        untracked.owningTab = tab
        tab.replaceUntrackedWebView(untracked)
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabId in tabId == tab.id ? tab : nil },
            webViewSessions: commandRecorder.webViewSessions,
            ownershipQuery: WebViewOwnershipQuery(
                webViewSessions: commandRecorder.webViewSessions
            ),
            commands: commandRecorder.commands
        )

        XCTAssertIdentical(service.anyLiveWebView(for: tab), untracked)
        XCTAssertTrue(service.hasLiveWebView(for: tab))
        XCTAssertTrue(service.ownsLiveWebView(untracked, for: tab))
    }

    func testProcessRecoveryServiceRetainsFailedSubmissionUntilConcreteBind() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/recovery"))
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        let originalIntent = tab.mainFrameLoads.currentIntent
        _ = tab.webContentRecovery.beginRecovery(on: webView)

        var shouldBind = false
        var submissionCount = 0
        var boundNavigation: NSObject?
        let recoveryService = WebContentProcessRecoveryService(
            isProtected: { _ in false },
            submit: { submittedTab, submittedWebView, intent in
                submissionCount += 1
                XCTAssertIdentical(submittedTab, tab)
                XCTAssertIdentical(submittedWebView, webView)
                XCTAssertEqual(intent, originalIntent)
                guard shouldBind else { return .failed }
                let navigation = NSObject()
                boundNavigation = navigation
                XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: webView))
                XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
                    on: webView,
                    navigationID: ObjectIdentifier(navigation),
                    navigationLifetime: navigation,
                    matching: nil
                ))
                return TabMainFrameReloadCommandOutcome.accepted
            }
        )

        XCTAssertEqual(recoveryService.recover(webView, for: tab), .scheduled)
        XCTAssertEqual(submissionCount, 1)
        XCTAssertTrue(tab.webContentRecovery.isRecoveryRequired(on: webView))
        XCTAssertTrue(recoveryService.hasPendingRecovery(for: webView))
        XCTAssertEqual(tab.mainFrameLoads.currentIntent, originalIntent)

        shouldBind = true
        recoveryService.retryPendingImmediately(for: ObjectIdentifier(webView))

        XCTAssertNotNil(boundNavigation)
        XCTAssertEqual(submissionCount, 2)
        XCTAssertFalse(tab.webContentRecovery.isRecoveryRequired(on: webView))
        XCTAssertFalse(recoveryService.hasPendingRecovery(for: webView))
        XCTAssertEqual(tab.mainFrameLoads.currentIntent, originalIntent)
    }

    func testProcessRecoveryServiceCanRetainBeforeFirstSubmission() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/retained-recovery"))
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        _ = tab.webContentRecovery.beginRecovery(on: webView)
        var submissionCount = 0
        let recoveryService = WebContentProcessRecoveryService(
            isProtected: { _ in false },
            submit: { _, _, _ in
                submissionCount += 1
                return .failed
            }
        )

        XCTAssertTrue(recoveryService.retain(webView, for: tab))
        XCTAssertEqual(submissionCount, 0)
        XCTAssertTrue(recoveryService.hasPendingRecovery(for: webView))

        recoveryService.retryPendingImmediately(for: ObjectIdentifier(webView))

        XCTAssertEqual(submissionCount, 1)
        XCTAssertTrue(recoveryService.hasPendingRecovery(for: webView))
        XCTAssertTrue(tab.webContentRecovery.isRecoveryRequired(on: webView))
        recoveryService.cancel(webView)
    }

    func testRoutingServiceDelegatesExactOwnedProcessRecovery() throws {
        let commandRecorder = RecordingWebViewRoutingCommands()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/routed-recovery")),
            webViewSessions: commandRecorder.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        _ = tab.webContentRecovery.beginRecovery(on: webView)
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabID in tabID == tab.id ? tab : nil },
            webViewSessions: commandRecorder.webViewSessions,
            ownershipQuery: WebViewOwnershipQuery(
                webViewSessions: commandRecorder.webViewSessions
            ),
            commands: commandRecorder.commands
        )

        XCTAssertEqual(
            service.recoverWebContentProcess(tab.id, on: webView),
            .scheduled
        )
        XCTAssertEqual(commandRecorder.processRecoveryCalls.count, 1)
        XCTAssertIdentical(commandRecorder.processRecoveryCalls.first?.tab, tab)
        XCTAssertIdentical(commandRecorder.processRecoveryCalls.first?.webView, webView)
        XCTAssertTrue(tab.webContentRecovery.isRecoveryRequired(on: webView))
    }

    func testRoutingServiceRejectsRecoveryMarkerForUnownedWebView() throws {
        let commandRecorder = RecordingWebViewRoutingCommands()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/foreign-recovery")),
            webViewSessions: commandRecorder.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let foreignWebView = WKWebView()
        _ = tab.webContentRecovery.beginRecovery(on: foreignWebView)
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabID in tabID == tab.id ? tab : nil },
            webViewSessions: commandRecorder.webViewSessions,
            ownershipQuery: WebViewOwnershipQuery(
                webViewSessions: commandRecorder.webViewSessions
            ),
            commands: commandRecorder.commands
        )

        XCTAssertFalse(
            service.retainWebContentProcessRecovery(
                tab.id,
                on: foreignWebView
            )
        )
        XCTAssertEqual(
            service.recoverWebContentProcess(tab.id, on: foreignWebView),
            .failed
        )
        XCTAssertTrue(commandRecorder.processRecoveryCalls.isEmpty)
    }

    func testRoutingServiceRejectsOwnedWebViewWithoutRecoveryMarker() throws {
        let commandRecorder = RecordingWebViewRoutingCommands()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/no-marker")),
            webViewSessions: commandRecorder.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        let service = BrowserWebViewRoutingService(
            tabLookup: { tabID in tabID == tab.id ? tab : nil },
            webViewSessions: commandRecorder.webViewSessions,
            ownershipQuery: WebViewOwnershipQuery(
                webViewSessions: commandRecorder.webViewSessions
            ),
            commands: commandRecorder.commands
        )

        XCTAssertFalse(
            service.retainWebContentProcessRecovery(tab.id, on: webView)
        )
        XCTAssertEqual(
            service.recoverWebContentProcess(tab.id, on: webView),
            .failed
        )
        XCTAssertTrue(commandRecorder.processRecoveryCalls.isEmpty)
    }

    func testProcessRecoveryServiceNeverSubmitsWhileCompositorProtected() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/protected"))
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        _ = tab.webContentRecovery.beginRecovery(on: webView)

        var isProtected = true
        var submissionCount = 0
        var boundNavigation: NSObject?
        let recoveryService = WebContentProcessRecoveryService(
            isProtected: { _ in isProtected },
            submit: { _, _, _ in
                submissionCount += 1
                let navigation = NSObject()
                boundNavigation = navigation
                XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: webView))
                XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
                    on: webView,
                    navigationID: ObjectIdentifier(navigation),
                    navigationLifetime: navigation,
                    matching: nil
                ))
                return .accepted
            }
        )

        XCTAssertEqual(recoveryService.recover(webView, for: tab), .scheduled)
        XCTAssertEqual(submissionCount, 0)
        XCTAssertTrue(tab.webContentRecovery.isRecoveryRequired(on: webView))

        isProtected = false
        recoveryService.retryPendingImmediately(for: ObjectIdentifier(webView))

        XCTAssertNotNil(boundNavigation)
        XCTAssertEqual(submissionCount, 1)
        XCTAssertFalse(tab.webContentRecovery.isRecoveryRequired(on: webView))
        XCTAssertFalse(recoveryService.hasPendingRecovery(for: webView))
    }

    func testProcessRecoveryServiceRetriesLatestSemanticIntentWithoutCreatingRevision() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/initial"))
        let latestURL = try XCTUnwrap(URL(string: "https://example.com/latest"))
        let tab = Tab(url: initialURL, loadsCachedFaviconOnInit: false)
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        _ = tab.webContentRecovery.beginRecovery(on: webView)

        var submittedIntents: [TabMainFrameNavigationIntent] = []
        let recoveryService = WebContentProcessRecoveryService(
            isProtected: { _ in false },
            submit: { _, _, intent in
                submittedIntents.append(intent)
                return .failed
            }
        )

        let initialIntent = tab.mainFrameLoads.currentIntent
        XCTAssertEqual(recoveryService.recover(webView, for: tab), .scheduled)
        XCTAssertEqual(tab.mainFrameLoads.currentIntent, initialIntent)

        let latestIntent = tab.beginMainFrameNavigationIntent(to: latestURL)
        recoveryService.retryPendingImmediately(for: ObjectIdentifier(webView))

        XCTAssertEqual(submittedIntents, [initialIntent, latestIntent])
        XCTAssertEqual(tab.mainFrameLoads.currentIntent, latestIntent)
        XCTAssertTrue(tab.webContentRecovery.isRecoveryRequired(on: webView))

        recoveryService.cancel(webView)

        XCTAssertFalse(recoveryService.hasPendingRecovery(for: webView))
        XCTAssertTrue(tab.webContentRecovery.isRecoveryRequired(on: webView))
    }

    private func registerTrackedWebView(
        _ webView: WKWebView,
        for tabID: UUID,
        in windowID: UUID,
        repository: WebViewSessionRepository
    ) {
        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: TrackedWebViewOwner(tabID: tabID, windowID: windowID),
            in: repository,
            removeFromContainers: { _ in },
            installRuntimeObservations: { _ in },
            uninstallRuntimeObservationsIfUntracked: { _ in },
            pruneInvalidDeferredCommands: { _ in },
            canDisplaceWebView: { _ in true },
            removeRecentVisibility: { _ in },
            cleanupDisplacedWebView: { _, _ in }
        )
    }
}

@MainActor
private final class RecordingWebViewRoutingCommands {
    struct SyncCall {
        let tab: Tab
        let url: URL
        let originatingWebView: WKWebView?
    }

    struct MuteCall {
        let muted: Bool
        let tabId: UUID
    }

    struct WindowReloadCall {
        let tab: Tab
        let windowId: UUID
        let intent: TabMainFrameNavigationIntent
        let policy: WebRuntimeMainFrameReloadPolicy
    }

    struct MaterializeCall {
        let tab: Tab
        let windowId: UUID
    }

    struct ProcessRecoveryCall {
        let tab: Tab
        let webView: WKWebView
    }

    private(set) var syncCalls: [SyncCall] = []
    private(set) var reloadCalls: [Tab] = []
    private(set) var windowReloadCalls: [WindowReloadCall] = []
    private(set) var processRecoveryCalls: [ProcessRecoveryCall] = []
    private(set) var muteCalls: [MuteCall] = []
    private(set) var materializeCalls: [MaterializeCall] = []
    var materializedWebView: WKWebView?
    let webViewSessions = WebViewSessionRepository()

    var commands: BrowserWebViewRoutingService.Commands {
        BrowserWebViewRoutingService.Commands(
            sync: { [weak self] tab, url, originatingWebView in
                self?.syncCalls.append(
                    SyncCall(
                        tab: tab,
                        url: url,
                        originatingWebView: originatingWebView
                    )
                )
            },
            reloadAll: { [weak self] tab, _, _ in
                self?.reloadCalls.append(tab)
            },
            reloadWindow: { [weak self] tab, windowID, intent, policy in
                self?.windowReloadCalls.append(
                    WindowReloadCall(
                        tab: tab,
                        windowId: windowID,
                        intent: intent,
                        policy: policy
                    )
                )
                return .accepted
            },
            retainRecovery: { _, _ in true },
            recover: { [weak self] tab, webView in
                self?.processRecoveryCalls.append(
                    ProcessRecoveryCall(tab: tab, webView: webView)
                )
                return TabMainFrameReloadCommandOutcome.scheduled
            },
            cancelRecovery: { _ in },
            setMute: { [weak self] muted, tabID in
                self?.muteCalls.append(MuteCall(muted: muted, tabId: tabID))
            },
            materialize: { [weak self] tab, windowID in
                self?.materializeCalls.append(
                    MaterializeCall(tab: tab, windowId: windowID)
                )
                return self?.materializedWebView
            },
            rebuildWindowConfiguration: { _, _, _, _ in .notNeeded }
        )
    }
}
