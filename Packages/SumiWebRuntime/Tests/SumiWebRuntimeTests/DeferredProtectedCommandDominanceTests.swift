import Foundation
import WebKit
import XCTest

@testable import SumiWebRuntime

@MainActor
final class DeferredProtectedCommandDominanceTests: XCTestCase {
    func testTrackedGlobalCleanupOnlySupersedesTrackedWork() {
        let firstWebView = NSObject()
        let tabID = UUID()
        let windowID = UUID()
        let unrelatedWindowID = UUID()
        var buffer = DeferredProtectedCommandBuffer()

        _ = buffer.enqueue(.removeTrackedWebView(
            webViewID: ObjectIdentifier(firstWebView),
            tabID: tabID,
            windowID: windowID
        ))
        _ = buffer.enqueue(rebuild(tabID: tabID))
        _ = buffer.enqueue(.cleanupWindow(windowID: unrelatedWindowID))
        _ = buffer.enqueue(.evictHiddenWebViews(windowID: windowID))

        let cleanupResult = buffer.enqueueReportingSupersededCommands(.cleanupAllWebViews)

        assertOutcome(cleanupResult.outcome, is: .enqueued)
        XCTAssertEqual(cleanupResult.supersededCommands.count, 2)
        XCTAssertEqual(buffer.count, 3)
        guard case .cleanupAllWebViews = buffer.commands[0],
              case .rebuildLiveWebViews(let retainedTabID, _, _) = buffer.commands[1],
              case .cleanupWindow(let retainedWindowID) = buffer.commands[2]
        else {
            return XCTFail("Expected tracked cleanup to preserve broader lifecycle work")
        }
        XCTAssertEqual(retainedTabID, tabID)
        XCTAssertEqual(retainedWindowID, unrelatedWindowID)

        let coveredNavigation = navigation(
            webViewID: ObjectIdentifier(firstWebView),
            tabID: tabID,
            windowID: windowID
        )
        let coveredResult = buffer.enqueueReportingSupersededCommands(coveredNavigation)

        assertOutcome(coveredResult.outcome, is: .collapsed)
        XCTAssertEqual(coveredResult.supersededCommands.count, 1)
        XCTAssertEqual(buffer.count, 3)
        guard case .synchronizeTrackedNavigation = coveredResult.supersededCommands[0] else {
            return XCTFail("Expected the later narrow command to be reported as superseded")
        }
    }

    func testTrackedGlobalCleanupDoesNotClaimBroaderOrNonTrackedEffects() {
        let closeWebView = NSObject()
        let pendingCleanupWebView = NSObject()
        let pendingCleanupTabID = UUID()
        var buffer = DeferredProtectedCommandBuffer()

        _ = buffer.enqueue(.cleanupWindow(windowID: UUID()))
        _ = buffer.enqueue(.closeWebViewFromWebKit(
            webViewID: ObjectIdentifier(closeWebView)
        ))
        _ = buffer.enqueue(.performFallbackWebViewCleanup(
            webViewID: ObjectIdentifier(pendingCleanupWebView),
            lease: WebViewPendingCleanupLease(
                id: UUID(),
                tabID: pendingCleanupTabID
            )
        ))

        let result = buffer.enqueueReportingSupersededCommands(.cleanupAllWebViews)

        assertOutcome(result.outcome, is: .enqueued)
        XCTAssertTrue(result.supersededCommands.isEmpty)
        XCTAssertEqual(buffer.count, 4)
    }

    func testWindowCleanupOnlySupersedesCommandsWithTheSameProvenWindow() {
        let firstWebView = NSObject()
        let secondWebView = NSObject()
        let tabID = UUID()
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        var buffer = DeferredProtectedCommandBuffer()

        _ = buffer.enqueue(navigation(
            webViewID: ObjectIdentifier(firstWebView),
            tabID: tabID,
            windowID: firstWindowID
        ))
        _ = buffer.enqueue(navigation(
            webViewID: ObjectIdentifier(secondWebView),
            tabID: tabID,
            windowID: secondWindowID
        ))
        _ = buffer.enqueue(rebuild(tabID: tabID))

        let result = buffer.enqueueReportingSupersededCommands(
            .cleanupWindow(windowID: firstWindowID)
        )

        assertOutcome(result.outcome, is: .enqueued)
        XCTAssertEqual(result.supersededCommands.count, 1)
        XCTAssertEqual(buffer.count, 3)
        guard case .cleanupWindow(let retainedWindowID) = buffer.commands[0],
              case .synchronizeTrackedNavigation(
                  _,
                  _,
                  let retainedNavigationWindowID,
                  _
              ) = buffer.commands[1],
              case .rebuildLiveWebViews(let retainedTabID, _, _) = buffer.commands[2]
        else {
            return XCTFail("Expected cleanup plus the unrelated window and tab-global work")
        }
        XCTAssertEqual(retainedWindowID, firstWindowID)
        XCTAssertEqual(retainedNavigationWindowID, secondWindowID)
        XCTAssertEqual(retainedTabID, tabID)

        let coveredResult = buffer.enqueueReportingSupersededCommands(navigation(
            webViewID: ObjectIdentifier(firstWebView),
            tabID: tabID,
            windowID: firstWindowID
        ))
        assertOutcome(coveredResult.outcome, is: .collapsed)
        XCTAssertEqual(coveredResult.supersededCommands.count, 1)
        XCTAssertEqual(buffer.count, 3)
    }

    func testWebKitCloseSupersedesNarrowMutationsForTheSameWebView() {
        let firstWebView = NSObject()
        let secondWebView = NSObject()
        let firstWebViewID = ObjectIdentifier(firstWebView)
        let secondWebViewID = ObjectIdentifier(secondWebView)
        let tabID = UUID()
        let windowID = UUID()
        var buffer = DeferredProtectedCommandBuffer()

        _ = buffer.enqueue(.removeWebViewFromContainers(webViewID: firstWebViewID))
        _ = buffer.enqueue(navigation(
            webViewID: firstWebViewID,
            tabID: tabID,
            windowID: windowID
        ))
        _ = buffer.enqueue(navigation(
            webViewID: secondWebViewID,
            tabID: tabID,
            windowID: windowID
        ))

        let result = buffer.enqueueReportingSupersededCommands(
            .closeWebViewFromWebKit(webViewID: firstWebViewID)
        )

        assertOutcome(result.outcome, is: .enqueued)
        XCTAssertEqual(result.supersededCommands.count, 2)
        XCTAssertEqual(buffer.count, 2)
        guard case .closeWebViewFromWebKit(let retainedTeardownWebViewID) = buffer.commands[0],
              case .synchronizeTrackedNavigation(
                  let retainedNavigationWebViewID,
                  _,
                  _,
                  _
              ) = buffer.commands[1]
        else {
            return XCTFail("Expected exact teardown and only the unrelated WebView mutation")
        }
        XCTAssertEqual(retainedTeardownWebViewID, firstWebViewID)
        XCTAssertEqual(retainedNavigationWebViewID, secondWebViewID)
    }

    func testNarrowCleanupNeverSupersedesWebKitCloseRouting() {
        let webView = NSObject()
        let webViewID = ObjectIdentifier(webView)
        let tabID = UUID()
        let windowID = UUID()
        let close = DeferredWebViewCommand.closeWebViewFromWebKit(
            webViewID: webViewID
        )
        let narrowCleanup = DeferredWebViewCommand.removeTrackedWebView(
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID
        )
        var closeFirstBuffer = DeferredProtectedCommandBuffer()
        _ = closeFirstBuffer.enqueue(close)

        let narrowResult = closeFirstBuffer.enqueueReportingSupersededCommands(
            narrowCleanup
        )

        assertOutcome(narrowResult.outcome, is: .collapsed)
        XCTAssertEqual(narrowResult.supersededCommands.count, 1)
        guard closeFirstBuffer.count == 1,
              case .closeWebViewFromWebKit = closeFirstBuffer.commands[0]
        else {
            return XCTFail("Expected WebKit close routing to survive later narrow cleanup")
        }

        var closeLastBuffer = DeferredProtectedCommandBuffer()
        _ = closeLastBuffer.enqueue(narrowCleanup)
        let closeResult = closeLastBuffer.enqueueReportingSupersededCommands(close)

        assertOutcome(closeResult.outcome, is: .enqueued)
        XCTAssertEqual(closeResult.supersededCommands.count, 1)
        guard closeLastBuffer.count == 1,
              case .closeWebViewFromWebKit = closeLastBuffer.commands[0]
        else {
            return XCTFail("Expected newer WebKit close routing to replace narrow cleanup")
        }
    }

    func testWebKitCloseAndDetachedCleanupNeverSupersedeEachOther() {
        let webView = NSObject()
        let webViewID = ObjectIdentifier(webView)
        let close = DeferredWebViewCommand.closeWebViewFromWebKit(
            webViewID: webViewID
        )
        let detachedCleanup = DeferredWebViewCommand.cleanupTabWebView(
            webViewID: webViewID,
            tabID: UUID()
        )
        var cleanupFirstBuffer = DeferredProtectedCommandBuffer()
        _ = cleanupFirstBuffer.enqueue(detachedCleanup)

        let laterClose = cleanupFirstBuffer.enqueueReportingSupersededCommands(close)

        assertOutcome(laterClose.outcome, is: .enqueued)
        XCTAssertTrue(laterClose.supersededCommands.isEmpty)
        XCTAssertEqual(cleanupFirstBuffer.count, 2)

        var closeFirstBuffer = DeferredProtectedCommandBuffer()
        _ = closeFirstBuffer.enqueue(close)
        let laterCleanup = closeFirstBuffer.enqueueReportingSupersededCommands(
            detachedCleanup
        )

        assertOutcome(laterCleanup.outcome, is: .enqueued)
        XCTAssertTrue(laterCleanup.supersededCommands.isEmpty)
        XCTAssertEqual(closeFirstBuffer.count, 2)
    }

    func testFailedNarrowCommandIsNotRestoredAheadOfQueuedDominator() throws {
        let webView = NSObject()
        let tabID = UUID()
        let windowID = UUID()
        let command = navigation(
            webViewID: ObjectIdentifier(webView),
            tabID: tabID,
            windowID: windowID
        )
        var buffer = DeferredProtectedCommandBuffer()

        _ = buffer.enqueue(command)
        let executingCommand = try XCTUnwrap(buffer.popFirst())
        _ = buffer.enqueue(.cleanupWindow(windowID: windowID))

        let supersededCommands = buffer.restoreFirstIfNoNewerCommandExists(
            executingCommand
        )

        XCTAssertEqual(supersededCommands.count, 1)
        guard case .synchronizeTrackedNavigation = supersededCommands[0],
              buffer.count == 1,
              case .cleanupWindow(let retainedWindowID) = buffer.commands[0]
        else {
            return XCTFail("Expected the queued window cleanup to prevent stale restoration")
        }
        XCTAssertEqual(retainedWindowID, windowID)
    }

    func testFailedSemanticRebuildRestoresOverQueuedMaintenance() throws {
        let tabID = UUID()
        let semantic = rebuild(
            tabID: tabID,
            revision: 7,
            kind: .semanticNavigation
        )
        let maintenance = rebuild(
            tabID: tabID,
            revision: 7,
            kind: .maintenance
        )
        var buffer = DeferredProtectedCommandBuffer()
        _ = buffer.enqueue(semantic)
        let executingSemantic = try XCTUnwrap(buffer.popFirst())
        _ = buffer.enqueue(maintenance)

        let supersededCommands = buffer.restoreFirstIfNoNewerCommandExists(
            executingSemantic
        )

        XCTAssertEqual(supersededCommands.count, 1)
        guard case .rebuildLiveWebViews(_, _, let droppedIntent)
                = supersededCommands[0],
              buffer.count == 1,
              case .rebuildLiveWebViews(_, _, let restoredIntent) = buffer.commands[0]
        else {
            return XCTFail("Expected failed semantic rebuild to replace maintenance")
        }
        XCTAssertEqual(droppedIntent.kind, .maintenance)
        XCTAssertEqual(restoredIntent.kind, .semanticNavigation)
        XCTAssertEqual(restoredIntent.revision, 7)
    }

    func testFailedSemanticRebuildDoesNotReplaceNewerSemantic() throws {
        let tabID = UUID()
        let staleSemantic = rebuild(tabID: tabID, revision: 7)
        let newerSemantic = rebuild(tabID: tabID, revision: 8)
        var buffer = DeferredProtectedCommandBuffer()
        _ = buffer.enqueue(staleSemantic)
        let executingStaleSemantic = try XCTUnwrap(buffer.popFirst())
        _ = buffer.enqueue(newerSemantic)

        let supersededCommands = buffer.restoreFirstIfNoNewerCommandExists(
            executingStaleSemantic
        )

        XCTAssertEqual(supersededCommands.count, 1)
        guard case .rebuildLiveWebViews(_, _, let droppedIntent)
                = supersededCommands[0],
              buffer.count == 1,
              case .rebuildLiveWebViews(_, _, let retainedIntent) = buffer.commands[0]
        else {
            return XCTFail("Expected newer semantic rebuild to survive failed stale restore")
        }
        XCTAssertEqual(droppedIntent.revision, 7)
        XCTAssertEqual(retainedIntent.revision, 8)
        XCTAssertEqual(retainedIntent.kind, .semanticNavigation)
    }

    func testFailedMaintenanceNeverReplacesQueuedSemantic() throws {
        let tabID = UUID()
        let maintenance = rebuild(
            tabID: tabID,
            revision: 8,
            kind: .maintenance
        )
        let semantic = rebuild(
            tabID: tabID,
            revision: 7,
            kind: .semanticNavigation
        )
        var buffer = DeferredProtectedCommandBuffer()
        _ = buffer.enqueue(maintenance)
        let executingMaintenance = try XCTUnwrap(buffer.popFirst())
        _ = buffer.enqueue(semantic)

        let supersededCommands = buffer.restoreFirstIfNoNewerCommandExists(
            executingMaintenance
        )

        XCTAssertEqual(supersededCommands.count, 1)
        guard buffer.count == 1,
              case .rebuildLiveWebViews(_, _, let retainedIntent) = buffer.commands[0]
        else {
            return XCTFail("Expected semantic rebuild to survive maintenance restore")
        }
        XCTAssertEqual(retainedIntent.kind, .semanticNavigation)
        XCTAssertEqual(retainedIntent.revision, 7)
    }

    func testCapacityDisplacementIsReportedSeparatelyFromSemanticSupersession() {
        var buffer = DeferredProtectedCommandBuffer()
        for _ in 0..<DeferredProtectedCommandBuffer.softCapacity {
            _ = buffer.enqueue(rebuild(tabID: UUID(), kind: .maintenance))
        }
        let webView = NSObject()

        let result = buffer.enqueueReportingSupersededCommands(
            .cleanupTabWebView(
                webViewID: ObjectIdentifier(webView),
                tabID: UUID()
            )
        )

        assertOutcome(result.outcome, is: .enqueued)
        XCTAssertTrue(result.supersededCommands.isEmpty)
        XCTAssertEqual(result.capacityDisplacedCommands.count, 1)
        guard case .rebuildLiveWebViews(_, _, let displacedIntent)
                = result.capacityDisplacedCommands[0]
        else {
            return XCTFail("Expected replaceable maintenance work to be displaced")
        }
        XCTAssertEqual(displacedIntent.kind, .maintenance)
    }

    func testOwnerReportsSupersededCommandAndExecutesOnlyDominator() {
        let owner = WebViewProtectedCommandOwner()
        let sourceWebView = WKWebView()
        let sourceWebViewID = ObjectIdentifier(sourceWebView)
        let tabID = UUID()
        let windowID = UUID()
        let protectionLease = owner.beginVisualHandoffProtection(for: sourceWebView)
        var droppedCommands: [(DeferredWebViewCommand, String)] = []

        func enqueue(_ command: DeferredWebViewCommand) {
            XCTAssertEqual(owner.enqueueDeferredCommandIfNeeded(
                command,
                for: sourceWebView,
                reason: "test.dominance",
                resolveWebView: { $0 == sourceWebViewID ? sourceWebView : nil },
                isCommandValid: { _ in true },
                dropCommand: { droppedCommands.append(($0, $2)) },
                didPruneStaleWebViewIDs: { _ in /* no-op */ }
            ), .scheduled)
        }

        enqueue(navigation(
            webViewID: sourceWebViewID,
            tabID: tabID,
            windowID: windowID
        ))
        enqueue(.cleanupWindow(windowID: windowID))

        XCTAssertEqual(droppedCommands.count, 1)
        XCTAssertTrue(droppedCommands[0].1.hasSuffix(".superseded"))
        guard case .synchronizeTrackedNavigation = droppedCommands[0].0 else {
            return XCTFail("Expected the superseded navigation to be reported")
        }

        _ = owner.finishVisualHandoffProtection(protectionLease)
        var executedCommands: [DeferredWebViewCommand] = []
        XCTAssertEqual(owner.executeDeferredCommandsIfUnprotected(
            for: sourceWebViewID,
            resolveWebView: { $0 == sourceWebViewID ? sourceWebView : nil },
            isCommandValid: { _ in true },
            dropCommand: { _, _, _ in /* no-op */ },
            didPruneStaleWebViewIDs: { _ in /* no-op */ },
            executeCommand: {
                executedCommands.append($0)
                return .executed
            }
        ), 1)
        guard case .cleanupWindow(let executedWindowID) = executedCommands.first else {
            return XCTFail("Expected only the dominant cleanup to execute")
        }
        XCTAssertEqual(executedWindowID, windowID)
    }

    func testProfileAssignmentCoalescesToLatestExactRevision() {
        let tabID = UUID()
        var buffer = DeferredProtectedCommandBuffer()

        _ = buffer.enqueue(profileAssignment(tabID: tabID, revision: 4))
        let result = buffer.enqueueReportingSupersededCommands(
            profileAssignment(tabID: tabID, revision: 5)
        )

        assertOutcome(result.outcome, is: .collapsed)
        XCTAssertEqual(result.supersededCommands.count, 1)
        guard buffer.count == 1,
              case .assignProfile(_, _, let retainedIntent) = buffer.commands[0]
        else {
            return XCTFail("Expected only the latest profile transaction")
        }
        XCTAssertEqual(retainedIntent.revision, 5)

        let staleResult = buffer.enqueueReportingSupersededCommands(
            profileAssignment(tabID: tabID, revision: 3)
        )
        assertOutcome(staleResult.outcome, is: .collapsed)
        guard case .assignProfile(_, _, let stillRetainedIntent) = buffer.commands[0]
        else {
            return XCTFail("Expected the newer profile transaction to survive")
        }
        XCTAssertEqual(stillRetainedIntent.revision, 5)
    }

    func testProfileAssignmentReplacesMaintenanceButComposesWithSemanticNavigation() {
        let tabID = UUID()
        var maintenanceBuffer = DeferredProtectedCommandBuffer()
        _ = maintenanceBuffer.enqueue(rebuild(
            tabID: tabID,
            revision: 8,
            kind: .maintenance
        ))

        let maintenanceResult = maintenanceBuffer.enqueueReportingSupersededCommands(
            profileAssignment(tabID: tabID, revision: 2)
        )

        XCTAssertEqual(maintenanceResult.supersededCommands.count, 1)
        guard maintenanceBuffer.count == 1,
              case .assignProfile = maintenanceBuffer.commands[0]
        else {
            return XCTFail("Profile assignment should absorb redundant maintenance")
        }

        var semanticBuffer = DeferredProtectedCommandBuffer()
        _ = semanticBuffer.enqueue(rebuild(
            tabID: tabID,
            revision: 9,
            kind: .semanticNavigation
        ))
        let semanticResult = semanticBuffer.enqueueReportingSupersededCommands(
            profileAssignment(tabID: tabID, revision: 2)
        )

        XCTAssertTrue(semanticResult.supersededCommands.isEmpty)
        XCTAssertEqual(semanticBuffer.count, 2)
        XCTAssertTrue(semanticBuffer.commands.contains {
            if case .rebuildLiveWebViews(_, _, let intent) = $0 {
                return intent.kind == .semanticNavigation
            }
            return false
        })
        XCTAssertTrue(semanticBuffer.commands.contains {
            if case .assignProfile = $0 { return true }
            return false
        })
    }

    func testSpaceProfileBatchCoalescesLatestRevisionAndCoversIncludedMaintenance() {
        let spaceID = UUID()
        let tabID = UUID()
        var buffer = DeferredProtectedCommandBuffer()
        _ = buffer.enqueue(rebuild(
            tabID: tabID,
            revision: 4,
            kind: .maintenance
        ))

        let first = spaceProfileAssignment(
            spaceID: spaceID,
            tabID: tabID,
            revision: 2
        )
        let firstResult = buffer.enqueueReportingSupersededCommands(first)

        XCTAssertEqual(firstResult.supersededCommands.count, 1)
        guard buffer.count == 1,
              case .assignSpaceProfile(let firstIntent) = buffer.commands[0]
        else {
            return XCTFail("Expected the space batch to absorb included maintenance")
        }
        XCTAssertEqual(firstIntent.revision, 2)

        let latestResult = buffer.enqueueReportingSupersededCommands(
            spaceProfileAssignment(
                spaceID: spaceID,
                tabID: tabID,
                revision: 3
            )
        )
        assertOutcome(latestResult.outcome, is: .collapsed)
        guard buffer.count == 1,
              case .assignSpaceProfile(let latestIntent) = buffer.commands[0]
        else {
            return XCTFail("Expected only the latest space batch")
        }
        XCTAssertEqual(latestIntent.revision, 3)

        _ = buffer.enqueue(rebuild(
            tabID: tabID,
            revision: 5,
            kind: .semanticNavigation
        ))
        XCTAssertEqual(buffer.count, 2)
    }

    private func navigation(
        webViewID: ObjectIdentifier,
        tabID: UUID,
        windowID: UUID
    ) -> DeferredWebViewCommand {
        .synchronizeTrackedNavigation(
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID,
            intent: DeferredWebViewNavigationIntent(
                revision: 1,
                targetURL: URL(string: "https://example.com")!
            )
        )
    }

    private func rebuild(
        tabID: UUID,
        revision: UInt64 = 1,
        kind: DeferredWebViewRebuildKind = .semanticNavigation
    ) -> DeferredWebViewCommand {
        .rebuildLiveWebViews(
            tabID: tabID,
            preferredPrimaryWindowID: nil,
            intent: DeferredWebViewRebuildIntent(
                revision: revision,
                targetURL: URL(string: "https://example.com")!,
                configuration: .normal,
                kind: kind
            )
        )
    }

    private func profileAssignment(
        tabID: UUID,
        revision: UInt64
    ) -> DeferredWebViewCommand {
        .assignProfile(
            tabID: tabID,
            preferredPrimaryWindowID: nil,
            intent: DeferredWebViewProfileAssignmentIntent(
                revision: revision,
                expectedProfileID: UUID(),
                desiredProfileID: UUID(),
                resolvedProfileID: UUID(),
                targetURL: URL(string: "https://example.com/profile")!
            )
        )
    }

    private func spaceProfileAssignment(
        spaceID: UUID,
        tabID: UUID,
        revision: UInt64
    ) -> DeferredWebViewCommand {
        let profileIntent = DeferredWebViewProfileAssignmentIntent(
            revision: revision,
            expectedProfileID: nil,
            desiredProfileID: nil,
            resolvedProfileID: UUID(),
            targetURL: URL(string: "https://example.com/space-profile")!
        )
        return .assignSpaceProfile(
            intent: DeferredWebViewSpaceProfileAssignmentIntent(
                revision: revision,
                spaceID: spaceID,
                expectedProfileID: UUID(),
                desiredProfileID: UUID(),
                tabIntents: [
                    DeferredWebViewSpaceProfileTabIntent(
                        tabID: tabID,
                        intent: profileIntent
                    ),
                ]
            )
        )
    }

    private func assertOutcome(
        _ actual: DeferredProtectedCommandEnqueueOutcome,
        is expected: DeferredProtectedCommandEnqueueOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (.enqueued, .enqueued),
             (.collapsed, .collapsed),
             (.droppedAtCapacity, .droppedAtCapacity):
            break
        default:
            XCTFail("Expected \(expected), got \(actual)", file: file, line: line)
        }
    }
}
