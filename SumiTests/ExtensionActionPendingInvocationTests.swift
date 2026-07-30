import Combine
import Foundation
import WebKit
import XCTest

@testable import Sumi

/// Integration tests for the exact fail-closed action-invocation transaction,
/// driven through the real `ExtensionManager` composition. Mid-flight
/// mutations ride the permission-prompt await (the only await inside the
/// invocation after runtime resolution) and the transaction's own reentrant
/// observable effects (site-access change notification, action-surface
/// publication).
@available(macOS 15.5, *)

@MainActor
extension ExtensionActionInvocationAdmissionTests {
    func testPendingPopupInvocationRequiresRecoveryOnlyAfterDeadline()
        async throws {
        let harness = try await makeHarness(name: "PopupDeadline")
        let (evidence, action) = try exactInvocation(
            in: harness
        )
        let clock = ExtensionActionInvocationTestClock(now: 10)
        let ledger = ExtensionActionPopupInvocationLedger(
            recoveryInterval: 5,
            now: { clock.now() }
        )
        let target = ExtensionActionPopupInvocationTarget(
            anchorSessionToken: UUID(),
            windowID: UUID()
        )

        guard case .registered = ledger.register(
            evidence: evidence,
            action: action,
            target: target
        ) else {
            return XCTFail("first exact invocation must register")
        }
        clock.set(14.9)
        guard case .awaitingSettlement = ledger.register(
            evidence: evidence,
            action: action,
            target: target
        ) else {
            return XCTFail("a live request inside the deadline must stay single-flight")
        }
        clock.set(15)
        guard case .recoveryRequired(let receipt) = ledger.register(
            evidence: evidence,
            action: action,
            target: target
        ) else {
            return XCTFail("a user retry after the deadline must request exact binding recovery")
        }

        XCTAssertEqual(
            receipt,
            harness.inspection.contextState.profiles.contextBindingReceipt(
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
        )
    }

    func testCanceledInvocationIsQuarantinedAndLateCallbackIsRejected()
        async throws {
        let harness = try await makeHarness(name: "PopupQuarantine")
        let (evidence, action) = try exactInvocation(in: harness)
        let ledger = ExtensionActionPopupInvocationLedger(
            recoveryInterval: 60,
            now: { 0 }
        )
        let target = ExtensionActionPopupInvocationTarget(
            anchorSessionToken: UUID(),
            windowID: UUID()
        )
        guard case .registered(let registration) = ledger.register(
            evidence: evidence,
            action: action,
            target: target
        ) else {
            return XCTFail("first exact invocation must register")
        }
        ledger.cancel(registration)
        guard case .recoveryRequired = ledger.register(
            evidence: evidence,
            action: action,
            target: target
        ) else {
            return XCTFail("canceled dispatch must require a fresh binding")
        }
        let callbackEvidence = try XCTUnwrap(
            harness.inspection.popups.callbackAdmission.capture(
                context: harness.context,
                controller: evidence.runtimeBinding.controller
            )
        )

        guard case .staleBrowserInvocation = ledger.claim(
            action: action,
            evidence: callbackEvidence
        ) else {
            return XCTFail("late callback from a quarantined dispatch must fail closed")
        }
    }

    func testCoalescedPopupInvocationAdoptsNewestExactClickTarget()
        async throws {
        let harness = try await makeHarness(name: "PopupRetarget")
        let (evidence, action) = try exactInvocation(in: harness)
        let ledger = ExtensionActionPopupInvocationLedger(
            recoveryInterval: 60,
            now: { 0 }
        )
        let firstTarget = ExtensionActionPopupInvocationTarget(
            anchorSessionToken: UUID(),
            windowID: UUID()
        )
        let newestTarget = ExtensionActionPopupInvocationTarget(
            anchorSessionToken: UUID(),
            windowID: UUID()
        )
        guard case .registered = ledger.register(
            evidence: evidence,
            action: action,
            target: firstTarget
        ) else {
            return XCTFail("first exact invocation must register")
        }
        guard case .awaitingSettlement = ledger.register(
            evidence: evidence,
            action: action,
            target: newestTarget
        ) else {
            return XCTFail("a coalesced click must keep one WebKit invocation")
        }
        let callbackEvidence = try XCTUnwrap(
            harness.inspection.popups.callbackAdmission.capture(
                context: harness.context,
                controller: evidence.runtimeBinding.controller
            )
        )

        guard case .claimed(let receipt) = ledger.claim(
            action: action,
            evidence: callbackEvidence
        ) else {
            return XCTFail("the current callback must claim the coalesced invocation")
        }
        XCTAssertEqual(receipt.target, newestTarget)
    }

    func testCatalogRevisionChangeReplacesUnclaimablePendingInvocation()
        async throws {
        let harness = try await makeHarness(name: "PopupCatalogRevision")
        let (firstEvidence, firstAction) = try exactInvocation(in: harness)
        let ledger = ExtensionActionPopupInvocationLedger(
            recoveryInterval: 60,
            now: { 0 }
        )
        guard case .registered = ledger.register(
            evidence: firstEvidence,
            action: firstAction,
            target: .init(anchorSessionToken: UUID(), windowID: UUID())
        ) else {
            return XCTFail("first catalog revision must register")
        }

        let installed = try XCTUnwrap(
            harness.inspection.actionSurfaces.installedExtensions.records.first {
                $0.id == harness.extensionID
            }
        )
        harness.inspection.actionSurfaces.installedExtensions.upsert(
            Self.copyRecord(
                installed,
                isEnabled: true,
                manifestRootFingerprint: "replacement-\(installed.manifestRootFingerprint)"
            )
        )
        let (currentEvidence, currentAction) = try exactInvocation(in: harness)
        XCTAssertIdentical(firstAction, currentAction)
        let currentTarget = ExtensionActionPopupInvocationTarget(
            anchorSessionToken: UUID(),
            windowID: UUID()
        )
        guard case .registered = ledger.register(
            evidence: currentEvidence,
            action: currentAction,
            target: currentTarget
        ) else {
            return XCTFail("new catalog authority must replace the stale entry")
        }
        let callbackEvidence = try XCTUnwrap(
            harness.inspection.popups.callbackAdmission.capture(
                context: harness.context,
                controller: currentEvidence.runtimeBinding.controller
            )
        )

        guard case .claimed(let receipt) = ledger.claim(
            action: currentAction,
            evidence: callbackEvidence
        ) else {
            return XCTFail("callback must claim current catalog authority")
        }
        XCTAssertEqual(receipt.target, currentTarget)
    }

    func testContextRetirementQuarantinesBeforeUnloadAndPreservesFailure()
        async throws {
        let harness = try await makeHarness(name: "PopupRetirementOrdering")
        let (evidence, action) = try exactInvocation(in: harness)
        let target = ExtensionActionPopupInvocationTarget(
            anchorSessionToken: UUID(),
            windowID: UUID()
        )
        guard case .registered = harness.inspection.popups.invocations
            .register(evidence: evidence, action: action, target: target)
        else {
            return XCTFail("popup invocation must register before retirement")
        }
        let receipt = try XCTUnwrap(
            harness.inspection.contextState.profiles.contextBindingReceipt(
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
        )
        var observedQuarantineInsideUnload = false
        let retirement = ExtensionContextRetirement(
            profileRuntime: harness.inspection.contextState.profiles,
            backgroundRuntimeState: harness.inspection.contextState.background,
            runtimeResidency: harness.inspection.runtimeAuthorities.residency,
            errorObservation: harness.inspection.contextState.errors,
            diagnostics: harness.inspection.contextCoordination.diagnostics,
            actionPopups: harness.inspection.popups.runtimeRetirement,
            unloadContext: { _, _ in
                guard case .recoveryRequired(let observed) = harness.inspection
                    .popups.invocations.register(
                        evidence: evidence,
                        action: action,
                        target: target
                    )
                else {
                    return XCTFail(
                        "invocation must be quarantined before WebKit unload"
                    )
                }
                XCTAssertEqual(observed, receipt)
                observedQuarantineInsideUnload = true
                throw NSError(
                    domain: "ExtensionActionInvocationAdmissionTests",
                    code: 1
                )
            }
        )

        XCTAssertEqual(retirement.retire(receipt), .unloadFailed)
        XCTAssertTrue(observedQuarantineInsideUnload)
        guard case .recoveryRequired(let preserved) = harness.inspection
            .popups.invocations.register(
                evidence: evidence,
                action: action,
                target: target
            )
        else {
            return XCTFail("failed unload must preserve the quarantine")
        }
        XCTAssertEqual(preserved, receipt)
    }

    func testSuccessfulBindingRecoveryRetriesInvocationServiceOnce()
        async throws {
        let harness = try await makeHarness(name: "PopupServiceRecovery")
        let receipt = try XCTUnwrap(
            harness.inspection.contextState.profiles.contextBindingReceipt(
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
        )
        let dispatch = RecoveringActionDispatch(stalledBinding: receipt)
        let recovery = SuccessfulBindingRecovery()
        var dispatches = 0
        harness.manager.testHooks.permissionPromptDecision = { _, _, _ in
            .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let service = makeInvocationService(
            inspection: harness.inspection,
            attachedRuntime: harness.attachedRuntime,
            actionDispatch: dispatch,
            bindingRecovery: recovery,
            actionDispatchProbe: { _ in dispatches += 1 }
        )
        let result = await service.openPopup(
            extensionID: harness.extensionID,
            currentTab: harness.tab
        )
        XCTAssertTrue(
            result.opened,
            "unexpected blocker: \(result.blocker?.rawValue ?? "nil") \(result.message)"
        )
        XCTAssertEqual(recovery.receipts, [receipt])
        XCTAssertEqual(dispatch.contexts.count, 2)
        XCTAssertIdentical(dispatch.contexts.first, harness.context)
        XCTAssertIdentical(dispatch.contexts.last, harness.context)
        XCTAssertEqual(dispatches, 1)
        XCTAssertEqual(harness.actionPopupMetricCount(), 1)
    }

    // MARK: - ExtensionActionInvocationHarness

    struct ExtensionActionInvocationHarness {
        let manager: ExtensionManager
        let inspection: ExtensionManagerTestInspection
        let attachedRuntime: ExtensionAttachedBrowserRuntimeInspection
        let browserManager: BrowserManager
        let profileID: UUID
        let extensionID: String
        let tab: Tab
        let context: WKWebExtensionContext
        let windowRegistry: WindowRegistry
        let windowState: BrowserWindowState

        @MainActor
        func openPopup() async -> BrowserExtensionActionPopupRequestResult {
            let anchor = ExtensionActionPopupAnchor(
                extensionID: extensionID,
                profileID: profileID,
                windowID: UUID(),
                tabID: tab.id,
                sessionToken: UUID(),
                capturedAt: Date(),
                buttonView: nil
            )
            inspection.popups.anchors.store(anchor)
            return await inspection.actionSurfaces.invocation.openPopup(
                extensionID: extensionID,
                currentTab: tab,
                popupTargetRequest: .explicitAnchor(anchor.sessionToken)
            )
        }

        @MainActor
        func storedDecision() -> ExtensionManager.ExtensionStoredPermissionDecision? {
            inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: extensionID,
                profileId: profileID,
                targetKind: .matchPattern,
                target: ExtensionActionInvocationAdmissionTests.clickedHostPattern
            )
        }

        @MainActor
        func configuredLevel() -> SafariExtensionSiteAccessLevel {
            inspection.actionPolicy.siteAccess.configuredSiteAccessLevel(
                for: ExtensionActionInvocationAdmissionTests.clickedPageURL,
                extensionId: extensionID,
                profileId: profileID
            )
        }

        @MainActor
        func pageURLStatus() -> WKWebExtensionContext.PermissionStatus {
            context.permissionStatus(
                for: ExtensionActionInvocationAdmissionTests.clickedPageURL
            )
        }

        @MainActor
        func actionPopupMetricCount() -> Int {
            let metrics = inspection.runtimeAuthorities.metrics.metrics(
                for: extensionID
            )
            guard let metrics, metrics.lastBackgroundWakeReason == .actionPopup
            else {
                return 0
            }
            return metrics.backgroundWakeCount
        }
    }

    func testPresentationQueryIsolatesSameExtensionAcrossTwoPublishedPages()
        async throws {
        let harness = try await makeHarness(name: "PresentationTwoPages")
        let secondWindow = BrowserWindowState()
        harness.browserManager.tabResidenceAuthority.establishResidenceSession(on: secondWindow)
        XCTAssertEqual(
            harness.windowRegistry.register(secondWindow),
            .registered
        )
        addTeardownBlock { @MainActor in
            harness.windowRegistry.unregister(secondWindow.id)
        }
        let firstTab = makePublishedPresentationTab(
            url: Self.clickedPageURL,
            profileID: harness.profileID,
            harness: harness,
            windowState: harness.windowState
        )
        let secondTab = makePublishedPresentationTab(
            url: URL(string: "https://second.example/")!,
            profileID: harness.profileID,
            harness: harness,
            windowState: secondWindow
        )
        let query = makePresentationQuery(harness: harness)
        let firstTarget = try XCTUnwrap(query.target(
            extensionID: harness.extensionID,
            tab: firstTab,
            window: harness.windowState
        ))
        let secondTarget = try XCTUnwrap(query.target(
            extensionID: harness.extensionID,
            tab: secondTab,
            window: secondWindow
        ))
        let firstAdapter = try XCTUnwrap(
            harness.attachedRuntime.adapters.stableAdapter(for: firstTab)
        )
        let secondAdapter = try XCTUnwrap(
            harness.attachedRuntime.adapters.stableAdapter(for: secondTab)
        )
        let firstAction = try XCTUnwrap(
            harness.context.action(for: firstAdapter)
        )
        let secondAction = try XCTUnwrap(
            harness.context.action(for: secondAdapter)
        )
        XCTAssertNotEqual(firstTarget.tabIdentifier, secondTarget.tabIdentifier)
        XCTAssertEqual(
            firstTarget.adapterIdentifier,
            ObjectIdentifier(firstAdapter)
        )
        XCTAssertEqual(
            secondTarget.adapterIdentifier,
            ObjectIdentifier(secondAdapter)
        )
        XCTAssertNotEqual(firstTarget.adapterIdentifier, secondTarget.adapterIdentifier)
        XCTAssertIdentical(
            firstAction.associatedTab as? ExtensionTabAdapter,
            firstAdapter
        )
        XCTAssertIdentical(
            secondAction.associatedTab as? ExtensionTabAdapter,
            secondAdapter
        )
        XCTAssertNotNil(query.snapshot(for: firstTarget))
        XCTAssertNotNil(query.snapshot(for: secondTarget))
    }

    func testPresentationQueryUsesAccountForkExecutionContextNotPresentationProfile()
        async throws {
        let harness = try await makeHarness(name: "PresentationAccountFork")
        let executionProfile = Profile(name: "Presentation Execution")
        harness.browserManager.profileManager.profiles.append(executionProfile)
        let executionProfileID = executionProfile.id
        let executionContext = WKWebExtensionContext(
            for: harness.context.webExtension
        )
        harness.inspection.contextState.profiles.setContext(
            executionContext,
            extensionId: harness.extensionID,
            profileId: executionProfileID
        )
        let executionController = harness.inspection.controller.provisioning
            .ensureExtensionController(
            for: executionProfileID
        )
        try executionController.load(executionContext)
        addTeardownBlock {
            try? executionController.unload(executionContext)
        }
        let forkedTab = makePublishedPresentationTab(
            url: URL(string: "https://account-fork.example/")!,
            profileID: executionProfileID,
            harness: harness
        )
        let query = makePresentationQuery(harness: harness)

        let target = try XCTUnwrap(query.target(
            extensionID: harness.extensionID,
            tab: forkedTab,
            window: harness.windowState
        ))

        XCTAssertNotEqual(executionProfileID, harness.profileID)
        XCTAssertEqual(
            harness.inspection.contextState.profiles.currentProfileId,
            harness.profileID
        )
        XCTAssertFalse(executionContext === harness.context)
        XCTAssertEqual(target.profileID, executionProfileID)
        XCTAssertEqual(
            target.contextReceipt.key.profileId,
            executionProfileID
        )
        XCTAssertNotNil(query.snapshot(for: target))
    }

    func testPresentationQueryRejectsAmbiguousContextBinding() async throws {
        let harness = try await makeHarness(name: "PresentationAmbiguous")
        let publishedTab = makePublishedPresentationTab(
            url: Self.clickedPageURL,
            profileID: harness.profileID,
            harness: harness
        )
        let query = makePresentationQuery(harness: harness)
        XCTAssertNotNil(query.target(
            extensionID: harness.extensionID,
            tab: publishedTab,
            window: harness.windowState
        ))

        _ = harness.inspection.contextState.profiles.setContext(
            harness.context,
            extensionId: harness.extensionID,
            profileId: UUID()
        )

        XCTAssertNil(query.target(
            extensionID: harness.extensionID,
            tab: publishedTab,
            window: harness.windowState
        ))
    }

    func testPresentationQueryRejectsSameIDWindowReplacement() async throws {
        let harness = try await makeHarness(name: "PresentationWindowABA")
        let tab = makePublishedPresentationTab(
            url: Self.clickedPageURL,
            profileID: harness.profileID,
            harness: harness
        )
        let query = makePresentationQuery(harness: harness)
        let staleTarget = try XCTUnwrap(query.target(
            extensionID: harness.extensionID,
            tab: tab,
            window: harness.windowState
        ))
        XCTAssertNotNil(query.snapshot(for: staleTarget))

        harness.windowRegistry.unregister(harness.windowState.id)
        let replacement = BrowserWindowState(id: harness.windowState.id)
        harness.browserManager.tabResidenceAuthority.establishResidenceSession(on: replacement)
        replacement.currentProfileId = harness.profileID
        replacement.currentSpaceId = tab.spaceId
        replacement.currentTabId = tab.id
        XCTAssertEqual(
            harness.windowRegistry.register(replacement),
            .registered
        )

        XCTAssertNil(query.snapshot(for: staleTarget))
        XCTAssertNil(query.target(
            extensionID: harness.extensionID,
            tab: tab,
            window: harness.windowState
        ))
        XCTAssertNil(query.target(
            extensionID: harness.extensionID,
            tab: tab,
            window: replacement
        ))
    }

    func testPresentationQueryRejectsSameRegularTabClaimedByTwoWindows()
        async throws {
        let harness = try await makeHarness(name: "PresentationTwoWindows")
        let tab = makePublishedPresentationTab(
            url: Self.clickedPageURL,
            profileID: harness.profileID,
            harness: harness
        )
        let secondWindow = BrowserWindowState()
        harness.browserManager.tabResidenceAuthority.establishResidenceSession(on: secondWindow)
        secondWindow.currentProfileId = harness.profileID
        secondWindow.currentSpaceId = tab.spaceId
        secondWindow.currentTabId = tab.id
        XCTAssertEqual(
            harness.windowRegistry.register(secondWindow),
            .registered
        )
        addTeardownBlock { @MainActor in
            harness.windowRegistry.unregister(secondWindow.id)
        }
        let query = makePresentationQuery(harness: harness)

        XCTAssertNil(query.target(
            extensionID: harness.extensionID,
            tab: tab,
            window: harness.windowState
        ))
        XCTAssertNil(query.target(
            extensionID: harness.extensionID,
            tab: tab,
            window: secondWindow
        ))
    }

}
