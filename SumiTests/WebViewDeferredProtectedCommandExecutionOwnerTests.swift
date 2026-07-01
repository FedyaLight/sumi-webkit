import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewDeferredProtectedCommandExecutionOwnerTests: XCTestCase {
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

        mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(owner.enqueue(
            .removeTrackedWebView(webViewID: webViewID, tabID: tabID, windowID: windowID),
            for: webView,
            reason: "test",
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ))
        XCTAssertTrue(mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID))

        _ = mediaProtectionOwner.finishVisualHandoffProtection(for: webView)
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

        mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
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

        _ = mediaProtectionOwner.finishVisualHandoffProtection(for: webView)
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

        await assertStaleTabScopedCommandIsPruned(
            .performFallbackWebViewCleanup(webViewID: webViewID, tabID: tabID),
            webView: webView,
            tabID: tabID
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
            canCleanUpTabWebView: { candidateWebViewID, candidateTabID in
                candidateWebViewID == webViewID
                    && candidateTabID == tabID
                    && isTrackedForTab == false
            },
            executeCommand: { command in
                executedCommands.append(command)
                return true
            }
        )

        mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
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

        _ = mediaProtectionOwner.finishVisualHandoffProtection(for: webView)
        owner.flushCommandsIfUnprotected(
            for: webViewID,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        )
        await drainMainQueue()

        XCTAssertTrue(executedCommands.isEmpty)
    }

    private func makeRuntime(
        webView: WKWebView,
        trackedOwner: @escaping () -> TrackedWebViewOwner?,
        canCleanUpTabWebView: @escaping (ObjectIdentifier, UUID) -> Bool = { _, _ in true },
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
            canCleanUpTabWebView: canCleanUpTabWebView,
            resolveTab: { _ in nil },
            hasTabManager: { true },
            hasCleanupWindowTarget: { _ in true },
            hasTrackedWebViews: { true },
            hasWindow: { _ in true }
        )

        return WebViewDeferredProtectedCommandExecutionOwner.Runtime(
            validationContext: validationContext,
            executeCommand: executeCommand,
            finishCleanupSuppression: { _ in }
        )
    }

    private func assertStaleTabScopedCommandIsPruned(
        _ command: DeferredWebViewCommand,
        webView: WKWebView,
        tabID: UUID,
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
            canCleanUpTabWebView: { candidateWebViewID, candidateTabID in
                candidateWebViewID == webViewID
                    && candidateTabID == tabID
                    && canCleanUpTabWebView
            },
            executeCommand: { command in
                executedCommands.append(command)
                return true
            }
        )

        mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
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

        _ = mediaProtectionOwner.finishVisualHandoffProtection(for: webView)
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
