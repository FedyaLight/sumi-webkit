import WebKit
import XCTest
import SumiWebRuntime

@testable import Sumi

@MainActor
final class DeferredProtectedCommandTests: XCTestCase {
    func testMatchingTrackedOwnerFlushesDeferredRemoveTrackedWebView() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let tabID = UUID()
        let windowID = UUID()
        let trackedOwner = TrackedWebViewOwner(tabID: tabID, windowID: windowID)
        let webViewID = ObjectIdentifier(webView)
        var executedCommands: [DeferredWebViewCommand] = []

        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: { trackedOwner },
            executeCommand: { command in
                executedCommands.append(command)
                return true
            }
        )

        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            .removeTrackedWebView(webViewID: webViewID, tabID: tabID, windowID: windowID),
            for: webView,
            reason: "test",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))
        XCTAssertTrue(mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID))

        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: webViewID,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()

        XCTAssertEqual(executedCommands.count, 1)
        assertRemoveTrackedCommand(
            executedCommands[0],
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID
        )
        XCTAssertFalse(mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID))
    }

    func testStaleTrackedOwnerPrunesDeferredRemoveTrackedWebViewBeforeFlush() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let tabID = UUID()
        let originalWindowID = UUID()
        let reassignedWindowID = UUID()
        let originalOwner = TrackedWebViewOwner(tabID: tabID, windowID: originalWindowID)
        let reassignedOwner = TrackedWebViewOwner(tabID: tabID, windowID: reassignedWindowID)
        let webViewID = ObjectIdentifier(webView)
        var currentOwner = originalOwner
        var executedCommands: [DeferredWebViewCommand] = []

        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: { currentOwner },
            executeCommand: { command in
                executedCommands.append(command)
                return true
            }
        )

        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            .removeTrackedWebView(
                webViewID: webViewID,
                tabID: tabID,
                windowID: originalWindowID
            ),
            for: webView,
            reason: "test",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))
        XCTAssertTrue(mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID))

        currentOwner = reassignedOwner
        owner.pruneInvalidCommands(
            reason: "test.reassigned",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )

        XCTAssertFalse(mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID))

        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: webViewID,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()

        XCTAssertTrue(executedCommands.isEmpty)
    }

    func testStaleTabScopedOwnerPrunesDeferredCleanupTabWebViewBeforeFlush() async {
        let webView = WKWebView()
        let tabID = UUID()
        let webViewID = ObjectIdentifier(webView)

        await assertStaleTabScopedCommandIsPruned(
            .cleanupTabWebView(webViewID: webViewID, tabID: tabID),
            webView: webView,
            tabID: tabID
        )
    }

    func testStaleTabScopedOwnerPrunesDeferredFallbackCleanupBeforeFlush() async {
        let webView = WKWebView()
        let tabID = UUID()
        let webViewID = ObjectIdentifier(webView)
        let lease = WebViewPendingCleanupLease(id: UUID(), tabID: tabID)

        await assertStaleTabScopedCommandIsPruned(
            .performFallbackWebViewCleanup(webViewID: webViewID, lease: lease),
            webView: webView,
            tabID: tabID,
            fallbackLease: lease
        )
    }

    func testTrackedTabScopedOwnerPrunesDeferredCleanupTabWebViewBeforeFlush() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let tabID = UUID()
        let webViewID = ObjectIdentifier(webView)
        var isTrackedForTab = false
        var executedCommands: [DeferredWebViewCommand] = []

        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: {
                isTrackedForTab ? TrackedWebViewOwner(tabID: tabID, windowID: UUID()) : nil
            },
            canCleanUpDetachedWebView: { candidateWebViewID, candidateTabID in
                candidateWebViewID == webViewID
                    && candidateTabID == tabID
                    && isTrackedForTab == false
            },
            executeCommand: { command in
                executedCommands.append(command)
                return true
            }
        )

        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            .cleanupTabWebView(webViewID: webViewID, tabID: tabID),
            for: webView,
            reason: "test",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))
        XCTAssertTrue(mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID))

        isTrackedForTab = true
        owner.pruneInvalidCommands(
            reason: "test.tracked",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )

        XCTAssertFalse(mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID))

        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: webViewID,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()

        XCTAssertTrue(executedCommands.isEmpty)
    }

    func testDeferredNavigationRebuildIsPrunedWhenNewerRebuildIntentBegins() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let originalURL = URL(string: "safari-web-extension://extension/a.html")!
        let newerURL = URL(string: "https://example.com/b")!
        let tab = Tab(url: originalURL)
        var executedCommands: [DeferredWebViewCommand] = []
        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: { nil },
            resolveTab: { tabID in tabID == tab.id ? tab : nil },
            executeCommand: { command in
                executedCommands.append(command)
                return true
            }
        )

        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            .rebuildLiveWebViews(
                tabID: tab.id,
                preferredPrimaryWindowID: nil,
                intent: .init(
                    revision: 0,
                    targetURL: originalURL,
                    configuration: .currentExtensionPage,
                    kind: .semanticNavigation
                )
            ),
            for: webView,
            reason: "test.navigation-a",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))

        _ = tab.beginMainFrameNavigationIntent(to: newerURL)
        _ = tab.webViewRebuildEpoch.advance()
        tab.url = newerURL
        owner.pruneInvalidCommands(
            reason: "test.navigation-b",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )

        XCTAssertFalse(
            mediaProtectionOwner.hasDeferredProtectedCommands(for: ObjectIdentifier(webView))
        )
        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: ObjectIdentifier(webView),
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()
        XCTAssertTrue(executedCommands.isEmpty)
    }

    func testStaleOldWebViewLifecycleCannotInvalidateDeferredSemanticNavigation() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let oldURL = URL(string: "https://example.com/old")!
        let targetURL = URL(string: "https://example.com/new")!
        let oldWebView = SumiNavigationURLReportingWebView()
        oldWebView.reportedURL = oldURL
        let tab = Tab(url: oldURL)
        let navigationIntent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let rebuildRevision = tab.webViewRebuildEpoch.advance()
        tab.url = targetURL
        var executedCommands: [DeferredWebViewCommand] = []
        let runtime = makeRuntime(
            webView: oldWebView,
            trackedOwner: { nil },
            resolveTab: { tabID in tabID == tab.id ? tab : nil },
            executeCommand: { command in
                executedCommands.append(command)
                return true
            }
        )
        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(
            for: oldWebView
        )
        XCTAssertTrue(owner.enqueue(
            .rebuildLiveWebViews(
                tabID: tab.id,
                preferredPrimaryWindowID: nil,
                intent: .init(
                    revision: rebuildRevision,
                    targetURL: targetURL,
                    configuration: .normal,
                    kind: .semanticNavigation
                )
            ),
            for: oldWebView,
            reason: "test.stale-old-lifecycle",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))

        let staleNavigation = NSObject()
        tab.makeMainFrameLifecycleResponder().navigationDidStart(
            SumiNavigationContext(
                navigationID: ObjectIdentifier(staleNavigation),
                navigationLifetime: staleNavigation,
                action: nil,
                url: oldURL,
                isCurrent: true,
                isMainFrame: true,
                webView: oldWebView
            )
        )

        XCTAssertEqual(tab.url, targetURL)
        XCTAssertEqual(tab.mainFrameLoads.currentIntent(matching: targetURL), navigationIntent)
        XCTAssertTrue(mediaProtectionOwner.hasDeferredProtectedCommands(
            for: ObjectIdentifier(oldWebView)
        ))

        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: ObjectIdentifier(oldWebView),
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()

        XCTAssertEqual(executedCommands.count, 1)
        guard case .rebuildLiveWebViews(_, _, let intent) = executedCommands[0] else {
            return XCTFail("Expected deferred semantic rebuild")
        }
        XCTAssertEqual(intent.targetURL, targetURL)
        XCTAssertEqual(intent.revision, rebuildRevision)
    }

    func testNewerRebuildIntentWinsBeforeScheduledFlushExecution() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let targetURL = URL(string: "https://example.com/same-target")!
        let tab = Tab(url: targetURL)
        let oldRevision = tab.webViewRebuildEpoch.advance()
        var executedCommands: [DeferredWebViewCommand] = []
        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: { nil },
            resolveTab: { tabID in tabID == tab.id ? tab : nil },
            executeCommand: { command in
                executedCommands.append(command)
                return true
            }
        )

        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            .rebuildLiveWebViews(
                tabID: tab.id,
                preferredPrimaryWindowID: nil,
                intent: .init(
                    revision: oldRevision,
                    targetURL: targetURL,
                    configuration: .normal,
                    kind: .semanticNavigation
                )
            ),
            for: webView,
            reason: "test.old-intent",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))

        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: ObjectIdentifier(webView),
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        _ = tab.webViewRebuildEpoch.advance()
        await drainMainQueue()

        XCTAssertTrue(executedCommands.isEmpty)
    }

    func testMaintenanceRebuildCannotDisplaceProtectedSemanticNavigation() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let semanticURL = URL(string: "https://example.com/user-destination")!
        let tab = Tab(url: semanticURL)
        let revision = tab.webViewRebuildEpoch.advance()
        var executedCommands: [DeferredWebViewCommand] = []
        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: { nil },
            resolveTab: { tabID in tabID == tab.id ? tab : nil },
            executeCommand: { command in
                executedCommands.append(command)
                return true
            }
        )

        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            .rebuildLiveWebViews(
                tabID: tab.id,
                preferredPrimaryWindowID: UUID(),
                intent: .init(
                    revision: revision,
                    targetURL: semanticURL,
                    configuration: .currentExtensionPage,
                    kind: .semanticNavigation
                )
            ),
            for: webView,
            reason: "test.semantic",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))
        XCTAssertTrue(owner.enqueue(
            .rebuildLiveWebViews(
                tabID: tab.id,
                preferredPrimaryWindowID: nil,
                intent: .init(
                    revision: revision,
                    targetURL: semanticURL,
                    configuration: .normal,
                    kind: .maintenance
                )
            ),
            for: webView,
            reason: "test.maintenance",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))

        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: ObjectIdentifier(webView),
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()

        XCTAssertEqual(executedCommands.count, 1)
        guard case .rebuildLiveWebViews(_, let preferredWindowID, let intent) = executedCommands[0] else {
            return XCTFail("Expected semantic rebuild execution")
        }
        XCTAssertNotNil(preferredWindowID)
        XCTAssertEqual(intent.targetURL, semanticURL)
        XCTAssertEqual(intent.configuration, .currentExtensionPage)
        XCTAssertEqual(intent.kind, .semanticNavigation)
    }

    func testProtectedTrackedNavigationReplaysForExactOwnerAndIntent() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let initialURL = URL(string: "https://example.com/initial")!
        let targetURL = URL(string: "https://example.com/target")!
        let tab = Tab(url: initialURL)
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        tab.url = targetURL
        let trackedOwner = TrackedWebViewOwner(tabID: tab.id, windowID: UUID())
        var executedCommands: [DeferredWebViewCommand] = []
        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: { trackedOwner },
            resolveTab: { $0 == tab.id ? tab : nil },
            executeCommand: {
                executedCommands.append($0)
                return true
            }
        )
        let command = DeferredWebViewCommand.synchronizeTrackedNavigation(
            webViewID: ObjectIdentifier(webView),
            tabID: tab.id,
            windowID: trackedOwner.windowID,
            intent: .init(revision: intent.revision, targetURL: targetURL)
        )

        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            command,
            for: webView,
            reason: "test.protected-navigation",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))

        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: ObjectIdentifier(webView),
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()

        XCTAssertEqual(executedCommands.count, 1)
        guard case .synchronizeTrackedNavigation(
            let executedWebViewID,
            let executedTabID,
            let executedWindowID,
            let executedIntent
        ) = executedCommands[0] else {
            return XCTFail("Expected protected navigation replay")
        }
        XCTAssertEqual(executedWebViewID, ObjectIdentifier(webView))
        XCTAssertEqual(executedTabID, tab.id)
        XCTAssertEqual(executedWindowID, trackedOwner.windowID)
        XCTAssertEqual(executedIntent.revision, intent.revision)
        XCTAssertEqual(executedIntent.targetURL, targetURL)
    }

    func testNewerNavigationIntentPrunesProtectedTrackedNavigation() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let initialURL = URL(string: "https://example.com/initial")!
        let deferredURL = URL(string: "https://example.com/deferred")!
        let newerURL = URL(string: "https://example.com/newer")!
        let tab = Tab(url: initialURL)
        let deferredIntent = tab.beginMainFrameNavigationIntent(to: deferredURL)
        tab.url = deferredURL
        let trackedOwner = TrackedWebViewOwner(tabID: tab.id, windowID: UUID())
        var executedCommands: [DeferredWebViewCommand] = []
        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: { trackedOwner },
            resolveTab: { $0 == tab.id ? tab : nil },
            executeCommand: {
                executedCommands.append($0)
                return true
            }
        )
        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            .synchronizeTrackedNavigation(
                webViewID: ObjectIdentifier(webView),
                tabID: tab.id,
                windowID: trackedOwner.windowID,
                intent: .init(
                    revision: deferredIntent.revision,
                    targetURL: deferredURL
                )
            ),
            for: webView,
            reason: "test.stale-protected-navigation",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))

        _ = tab.beginMainFrameNavigationIntent(to: newerURL)
        tab.url = newerURL
        owner.pruneInvalidCommands(
            reason: "test.newer-navigation",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )

        XCTAssertFalse(mediaProtectionOwner.hasDeferredProtectedCommands(
            for: ObjectIdentifier(webView)
        ))
        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: ObjectIdentifier(webView),
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()
        XCTAssertTrue(executedCommands.isEmpty)
    }

    func testProtectedTrackedReloadReplaysForExactSemanticRevision() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let targetURL = URL(string: "https://example.com/reload")!
        let tab = Tab(url: targetURL)
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let trackedOwner = TrackedWebViewOwner(tabID: tab.id, windowID: UUID())
        var executedCommands: [DeferredWebViewCommand] = []
        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: { trackedOwner },
            resolveTab: { $0 == tab.id ? tab : nil },
            executeCommand: {
                executedCommands.append($0)
                return true
            }
        )
        let command = DeferredWebViewCommand.reloadTrackedNavigation(
            webViewID: ObjectIdentifier(webView),
            tabID: tab.id,
            windowID: trackedOwner.windowID,
            intent: .init(
                revision: intent.revision,
                targetURL: targetURL,
                policy: .fromOrigin
            )
        )

        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            command,
            for: webView,
            reason: "test.protected-reload",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))
        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: ObjectIdentifier(webView),
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()

        XCTAssertEqual(executedCommands.count, 1)
        guard case .reloadTrackedNavigation(
            let executedWebViewID,
            let executedTabID,
            let executedWindowID,
            let executedIntent
        ) = executedCommands[0] else {
            return XCTFail("Expected protected reload replay")
        }
        XCTAssertEqual(executedWebViewID, ObjectIdentifier(webView))
        XCTAssertEqual(executedTabID, tab.id)
        XCTAssertEqual(executedWindowID, trackedOwner.windowID)
        XCTAssertEqual(executedIntent.revision, intent.revision)
        XCTAssertEqual(executedIntent.targetURL, targetURL)
        XCTAssertEqual(executedIntent.policy, .fromOrigin)
    }

    func testNewerSemanticRevisionPrunesProtectedTrackedReload() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let targetURL = URL(string: "https://example.com/reload")!
        let newerURL = URL(string: "https://example.com/newer")!
        let tab = Tab(url: targetURL)
        let deferredIntent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let trackedOwner = TrackedWebViewOwner(tabID: tab.id, windowID: UUID())
        var executedCommands: [DeferredWebViewCommand] = []
        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: { trackedOwner },
            resolveTab: { $0 == tab.id ? tab : nil },
            executeCommand: {
                executedCommands.append($0)
                return true
            }
        )
        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            .reloadTrackedNavigation(
                webViewID: ObjectIdentifier(webView),
                tabID: tab.id,
                windowID: trackedOwner.windowID,
                intent: .init(
                    revision: deferredIntent.revision,
                    targetURL: targetURL,
                    policy: .standard
                )
            ),
            for: webView,
            reason: "test.stale-protected-reload",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))

        _ = tab.beginMainFrameNavigationIntent(to: newerURL)
        tab.url = newerURL
        owner.pruneInvalidCommands(
            reason: "test.newer-navigation-after-reload",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )

        XCTAssertFalse(mediaProtectionOwner.hasDeferredProtectedCommands(
            for: ObjectIdentifier(webView)
        ))
        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: ObjectIdentifier(webView),
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()
        XCTAssertTrue(executedCommands.isEmpty)
    }

    func testReprotectionBeforeScheduledFlushKeepsCommandUntilNextRelease() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let tabID = UUID()
        let windowID = UUID()
        let webViewID = ObjectIdentifier(webView)
        let trackedOwner = TrackedWebViewOwner(tabID: tabID, windowID: windowID)
        var executedCommands: [DeferredWebViewCommand] = []
        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: { trackedOwner },
            executeCommand: { command in
                executedCommands.append(command)
                return true
            }
        )

        let firstProtectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            .removeTrackedWebView(
                webViewID: webViewID,
                tabID: tabID,
                windowID: windowID
            ),
            for: webView,
            reason: "test.reprotected",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))

        _ = mediaProtectionOwner.finishVisualHandoffProtection(firstProtectionLease)
        owner.flushCommandsIfUnprotected(
            for: webViewID,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        let secondProtectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        await drainMainQueue()

        XCTAssertTrue(executedCommands.isEmpty)
        XCTAssertTrue(mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID))

        _ = mediaProtectionOwner.finishVisualHandoffProtection(secondProtectionLease)
        owner.flushCommandsIfUnprotected(
            for: webViewID,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()

        XCTAssertEqual(executedCommands.count, 1)
        XCTAssertFalse(mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID))
    }

    func testGuaranteedCommandKeepsRetryingPastFormerBudgetUntilSuccess() async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let tabID = UUID()
        let windowID = UUID()
        let webViewID = ObjectIdentifier(webView)
        let trackedOwner = TrackedWebViewOwner(tabID: tabID, windowID: windowID)
        var executionAttemptCount = 0
        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: { trackedOwner },
            executeCommand: { _ in
                executionAttemptCount += 1
                return executionAttemptCount >= 5
            }
        )

        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(
            for: webView
        )
        XCTAssertTrue(owner.enqueue(
            .removeTrackedWebView(
                webViewID: webViewID,
                tabID: tabID,
                windowID: windowID
            ),
            for: webView,
            reason: "test.durable-retry",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))
        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: webViewID,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )

        for _ in 0..<100 where executionAttemptCount < 5 {
            do {
                try await Task.sleep(nanoseconds: 10_000_000)
            } catch {
                XCTFail("Retry wait was cancelled: \(error)")
                return
            }
        }

        XCTAssertEqual(executionAttemptCount, 5)
        XCTAssertFalse(mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID))
    }

    private func makeRuntime(
        webView: WKWebView,
        trackedOwner: @escaping () -> TrackedWebViewOwner?,
        canCleanUpDetachedWebView: @escaping (ObjectIdentifier, UUID) -> Bool = { _, _ in true },
        canPerformFallbackWebViewCleanup: @escaping (
            ObjectIdentifier,
            WebViewPendingCleanupLease
        ) -> Bool = { _, _ in true },
        resolveTab: @escaping (UUID) -> Tab? = { _ in nil },
        executeCommand: @escaping (DeferredWebViewCommand) -> Bool
    ) -> WebViewDeferredProtectedCommandExecutionOwner.Runtime {
        let webViewID = ObjectIdentifier(webView)
        let validationContext = WebViewDeferredProtectedCommandExecutionOwner.ValidationContext(
            resolveWebView: { candidateID in
                candidateID == webViewID ? webView : nil
            },
            resolveTrackedOwner: { candidateID in
                candidateID == webViewID ? trackedOwner() : nil
            },
            canCleanUpDetachedWebView: canCleanUpDetachedWebView,
            canPerformFallbackWebViewCleanup: canPerformFallbackWebViewCleanup,
            resolveTab: resolveTab,
            isSpaceProfileAssignmentValid: { _ in false },
            hasTabManager: { true },
            hasCleanupWindowTarget: { _ in true },
            hasTrackedWebViews: { true },
            hasWindow: { _ in true }
        )

        return WebViewDeferredProtectedCommandExecutionOwner.Runtime(
            validationContext: validationContext,
            executeCommand: executeCommand,
            finishCleanupSuppression: { _ in /* No-op. */ }
        )
    }

    private func assertStaleTabScopedCommandIsPruned(
        _ command: DeferredWebViewCommand,
        webView: WKWebView,
        tabID: UUID,
        fallbackLease: WebViewPendingCleanupLease? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let owner = WebViewDeferredProtectedCommandExecutionOwner()
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let webViewID = ObjectIdentifier(webView)
        var canCleanUpTabWebView = true
        var executedCommands: [DeferredWebViewCommand] = []

        let runtime = makeRuntime(
            webView: webView,
            trackedOwner: { nil },
            canCleanUpDetachedWebView: { candidateWebViewID, candidateTabID in
                candidateWebViewID == webViewID
                    && candidateTabID == tabID
                    && canCleanUpTabWebView
            },
            canPerformFallbackWebViewCleanup: { candidateWebViewID, candidateLease in
                candidateWebViewID == webViewID
                    && candidateLease == fallbackLease
                    && canCleanUpTabWebView
            },
            executeCommand: { command in
                executedCommands.append(command)
                return true
            }
        )

        let protectionLease = mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            command,
            for: webView,
            reason: "test",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ), file: file, line: line)
        XCTAssertTrue(
            mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID),
            file: file,
            line: line
        )

        canCleanUpTabWebView = false
        owner.pruneInvalidCommands(
            reason: "test.reassigned",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )

        XCTAssertFalse(
            mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID),
            file: file,
            line: line
        )

        _ = mediaProtectionOwner.finishVisualHandoffProtection(protectionLease)
        owner.flushCommandsIfUnprotected(
            for: webViewID,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()

        XCTAssertTrue(executedCommands.isEmpty, file: file, line: line)
    }

    private func assertRemoveTrackedCommand(
        _ command: DeferredWebViewCommand,
        webViewID: ObjectIdentifier,
        tabID: UUID,
        windowID: UUID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .removeTrackedWebView(
            commandWebViewID,
            commandTabID,
            commandWindowID
        ) = command else {
            return XCTFail("Expected removeTrackedWebView command", file: file, line: line)
        }

        XCTAssertEqual(commandWebViewID, webViewID, file: file, line: line)
        XCTAssertEqual(commandTabID, tabID, file: file, line: line)
        XCTAssertEqual(commandWindowID, windowID, file: file, line: line)
    }
}

private func drainMainQueue() async {
    await Task.yield()
    await Task.yield()
}
