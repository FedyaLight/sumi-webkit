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
final class ExtensionActionInvocationAdmissionTests: XCTestCase {
    private static let clickedPageURL = URL(string: "https://clicked.example/path")!
    private static let clickedHostPattern = "https://clicked.example/*"

    // MARK: - 1. Exact current invocation dispatches once

    func testExactCurrentInvocationReachesActionDispatchOnce() async throws {
        let harness = try await makeHarness(name: "ExactDispatch")
        var dispatches = [String]()
        harness.manager.testHooks.didDispatchExtensionAction = { dispatches.append($0) }
        harness.manager.testHooks.permissionPromptDecision = { _, _, _ in
            .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let result = await harness.openPopup()
        await drainMainActorTurns()

        XCTAssertTrue(
            result.opened,
            "unexpected blocker: \(result.blocker?.rawValue ?? "nil") \(result.message)"
        )
        XCTAssertEqual(dispatches, [harness.extensionID])
        XCTAssertEqual(
            harness.context.permissionStatus(for: Self.clickedPageURL),
            .grantedExplicitly
        )
        XCTAssertEqual(harness.storedDecision()?.state, .allowed)
        XCTAssertEqual(harness.configuredLevel(), .allow)
        XCTAssertEqual(harness.actionPopupMetricCount(), 1)
    }

    // MARK: - 2. Context replacement during authorization fails closed

    func testContextReplacementDuringAuthorizationFailsClosed() async throws {
        let harness = try await makeHarness(name: "ContextReplacement")
        let replacement = WKWebExtensionContext(for: harness.context.webExtension)
        let statusBefore = harness.pageURLStatus()
        let replacementStatusBefore = replacement.permissionStatus(
            for: Self.clickedPageURL
        )
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            _ = inspection.contextState.profiles.setContext(
                replacement,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let result = await harness.openPopup()
        await drainMainActorTurns()

        XCTAssertEqual(result.blocker, .staleInvocation)
        XCTAssertEqual(harness.pageURLStatus(), statusBefore)
        XCTAssertEqual(
            replacement.permissionStatus(for: Self.clickedPageURL),
            replacementStatusBefore
        )
        XCTAssertNil(harness.storedDecision())
        XCTAssertEqual(harness.configuredLevel(), .ask)
        XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(harness.actionPopupMetricCount(), 0)
    }

    // MARK: - 3. Same-object rebind invalidates old evidence

    func testSameContextRebindDuringAuthorizationInvalidatesInvocation() async throws {
        let harness = try await makeHarness(name: "SameContextRebind")
        let statusBefore = harness.pageURLStatus()
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            _ = inspection.contextState.profiles.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let result = await harness.openPopup()

        XCTAssertEqual(result.blocker, .staleInvocation)
        XCTAssertEqual(harness.pageURLStatus(), statusBefore)
        XCTAssertNil(harness.storedDecision())
        XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(harness.actionPopupMetricCount(), 0)
    }

    // MARK: - 4. Controller A→B→A cannot revive an old invocation

    func testControllerABADuringAuthorizationCannotReviveInvocation() async throws {
        let harness = try await makeHarness(name: "ControllerABA")
        let originalController = harness.inspection.controller.provisioning.ensureExtensionController(
            for: harness.profileID
        )
        let replacementController = WKWebExtensionController(
            configuration: .nonPersistent()
        )
        var dispatches = 0
        var staleDrive = true
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            if staleDrive {
                inspection.contextState.profiles.setController(
                    replacementController,
                    for: harness.profileID
                )
                inspection.contextState.profiles.setController(
                    originalController,
                    for: harness.profileID
                )
            }
            return .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let staleResult = await harness.openPopup()

        XCTAssertEqual(staleResult.blocker, .staleInvocation)
        XCTAssertNil(harness.storedDecision())
        XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(harness.actionPopupMetricCount(), 0)

        // A fresh click against the settled A binding must be admitted.
        staleDrive = false
        let freshResult = await harness.openPopup()
        XCTAssertTrue(
            freshResult.opened,
            "unexpected blocker: \(freshResult.blocker?.rawValue ?? "nil") \(freshResult.message)"
        )
        XCTAssertEqual(dispatches, 1)
        XCTAssertEqual(harness.storedDecision()?.state, .allowed)
    }

    // MARK: - 5. Load-generation change invalidates the invocation

    func testExtensionLoadGenerationChangeDuringAuthorizationInvalidatesInvocation() async throws {
        let harness = try await makeHarness(name: "LoadGeneration")
        let statusBefore = harness.pageURLStatus()
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            inspection.runtimeAuthorities.loadRevisions.advance()
            return .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let result = await harness.openPopup()

        XCTAssertEqual(result.blocker, .staleInvocation)
        XCTAssertEqual(harness.pageURLStatus(), statusBefore)
        XCTAssertNil(harness.storedDecision())
        XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(harness.actionPopupMetricCount(), 0)
    }

    // MARK: - 6. Catalog removal / disable invalidates captured authority

    func testInstalledRecordRemovalDuringAuthorizationInvalidatesInvocation() async throws {
        let harness = try await makeHarness(name: "RecordRemoval")
        let statusBefore = harness.pageURLStatus()
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            inspection.actionSurfaces.installedExtensions.remove(id: harness.extensionID)
            return .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let result = await harness.openPopup()

        XCTAssertEqual(result.blocker, .staleInvocation)
        XCTAssertEqual(harness.pageURLStatus(), statusBefore)
        XCTAssertNil(harness.storedDecision())
        XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(harness.actionPopupMetricCount(), 0)
    }

    func testInstalledRecordDisableDuringAuthorizationInvalidatesInvocation() async throws {
        let harness = try await makeHarness(name: "RecordDisable")
        let disabledRecord = try XCTUnwrap(
            harness.inspection.actionSurfaces.installedExtensions.records
                .first { $0.id == harness.extensionID }
                .map { Self.copyRecord($0, isEnabled: false) }
        )
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            inspection.actionSurfaces.installedExtensions.upsert(disabledRecord)
            return .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let result = await harness.openPopup()

        XCTAssertEqual(result.blocker, .staleInvocation)
        XCTAssertNil(harness.storedDecision())
        XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(harness.actionPopupMetricCount(), 0)
    }

    // MARK: - 7. Unrelated extension mutation does not invalidate

    func testUnrelatedExtensionMutationDoesNotInvalidateInvocation() async throws {
        let harness = try await makeHarness(name: "UnrelatedMutation")
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            inspection.actionSurfaces.installedExtensions.upsert(
                Self.makeSyntheticRecord(id: "unrelated-\(UUID().uuidString)")
            )
            return .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let result = await harness.openPopup()

        XCTAssertTrue(
            result.opened,
            "unexpected blocker: \(result.blocker?.rawValue ?? "nil") \(result.message)"
        )
        XCTAssertEqual(dispatches, 1)
        XCTAssertEqual(
            harness.context.permissionStatus(for: Self.clickedPageURL),
            .grantedExplicitly
        )
        XCTAssertEqual(harness.storedDecision()?.state, .allowed)
        XCTAssertEqual(harness.actionPopupMetricCount(), 1)
    }

    // MARK: - 8. Tab profile change while authorization awaits fails closed

    func testTabProfileChangeDuringAuthorizationFailsClosed() async throws {
        let harness = try await makeHarness(name: "TabProfileChange")
        let statusBefore = harness.pageURLStatus()
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [tab = harness.tab] _, _, _ in
            tab.profileId = UUID()
            return .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let result = await harness.openPopup()

        XCTAssertEqual(result.blocker, .staleInvocation)
        XCTAssertEqual(harness.pageURLStatus(), statusBefore)
        XCTAssertNil(harness.storedDecision())
        XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(harness.actionPopupMetricCount(), 0)
    }

    // MARK: - 9. Main-frame document replacement while awaiting fails closed

    func testMainFrameDocumentReplacementDuringAuthorizationFailsClosed() async throws {
        let harness = try await makeHarness(name: "DocumentReplacement")
        let statusBefore = harness.pageURLStatus()
        let replacementWebView = WKWebView()
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [tab = harness.tab] _, _, _ in
            // Production shape: a main-frame commit settles through one
            // semantic committed-document transition while the prompt is up.
            tab.committedDocumentRuntime.performTransition(
                reason: .documentCommit
            ) {
                tab.committedDocumentRuntime.recordCommit(
                    TabCommittedDocumentEvidence(
                        webView: replacementWebView,
                        revision: 1,
                        documentGeneration: 1,
                        participantID: UUID(),
                        committedURL: URL(string: "https://elsewhere.example/")!,
                        presentationURL: URL(string: "https://elsewhere.example/")!,
                        isPDF: false
                    ),
                    publishesCanonicalDocument: true
                )
            }
            return .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let result = await harness.openPopup()
        await drainMainActorTurns()

        XCTAssertEqual(result.blocker, .staleInvocation)
        XCTAssertEqual(harness.pageURLStatus(), statusBefore)
        XCTAssertNil(harness.storedDecision())
        XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(harness.actionPopupMetricCount(), 0)
    }

    // MARK: - 10. Stale prompt allow performs no effects at all

    func testStalePromptAllowPerformsNoMutationPersistenceActionOrMetric() async throws {
        let harness = try await makeHarness(name: "StaleAllow")
        let statusBefore = harness.pageURLStatus()
        let diagnosticsBefore = SafariExtensionAutofillFillDiagnostics
            .snapshot().bucketCounts
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            _ = inspection.contextState.profiles.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let result = await harness.openPopup()
        await drainMainActorTurns()

        XCTAssertEqual(result.blocker, .staleInvocation)
        XCTAssertEqual(
            harness.pageURLStatus(),
            statusBefore,
            "stale allow must not grant WebKit access"
        )
        XCTAssertEqual(
            harness.configuredLevel(),
            .ask,
            "stale allow must not mutate configured site access"
        )
        XCTAssertNil(
            harness.storedDecision(),
            "stale allow must not persist a durable decision"
        )
        XCTAssertEqual(dispatches, 0, "stale allow must not invoke the action")
        XCTAssertEqual(
            harness.actionPopupMetricCount(),
            0,
            "stale allow must not record a success metric"
        )
        XCTAssertEqual(
            SafariExtensionAutofillFillDiagnostics.snapshot().bucketCounts,
            diagnosticsBefore
        )
    }

    // MARK: - 11. Stale prompt deny performs no stale mutation either

    func testStalePromptDenyPerformsNoStaleMutationPersistenceOrAction() async throws {
        let harness = try await makeHarness(name: "StaleDeny")
        let statusBefore = harness.pageURLStatus()
        let diagnosticsBefore = SafariExtensionAutofillFillDiagnostics
            .snapshot().bucketCounts
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            _ = inspection.contextState.profiles.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return .deny
        }
        defer { clearHooks(harness) }

        let result = await harness.openPopup()
        await drainMainActorTurns()

        XCTAssertEqual(result.blocker, .staleInvocation)
        XCTAssertEqual(
            harness.pageURLStatus(),
            statusBefore,
            "stale deny must not write an explicit denial into WebKit"
        )
        XCTAssertEqual(harness.configuredLevel(), .ask)
        XCTAssertNil(harness.storedDecision())
        XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(harness.actionPopupMetricCount(), 0)
        XCTAssertEqual(
            SafariExtensionAutofillFillDiagnostics.snapshot().bucketCounts,
            diagnosticsBefore
        )
    }

    // MARK: - 12. Reentrant invalidation between grant and persistence

    func testReentrantInvalidationBetweenPermissionMutationAndPersistenceStopsTail() async throws {
        let harness = try await makeHarness(name: "ReentrantGrantTail")
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = { _, _, _ in
            .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        // The configured-site-access write posts the policy-change
        // notification synchronously between the WebKit grant and the durable
        // decision persistence; rebinding there is a reentrant replacement
        // caused by the invocation's own observable effect.
        let trigger = ReentrantMutationTrigger { [inspection = harness.inspection] in
            guard inspection.actionPolicy.siteAccess.configuredSiteAccessLevel(
                for: Self.clickedPageURL,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            ) == .allow else { return false }
            _ = inspection.contextState.profiles.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return true
        }
        let observer = harness.inspection.actionSurfaces.publication.siteAccessPolicyChangePublisher.sink {
            MainActor.assumeIsolated { trigger.fireIfArmed() }
        }
        defer { observer.cancel() }

        let result = await harness.openPopup()
        await drainMainActorTurns()

        XCTAssertTrue(trigger.didFire)
        XCTAssertEqual(result.blocker, .staleInvocation)
        XCTAssertEqual(
            harness.context.permissionStatus(for: Self.clickedPageURL),
            .grantedExplicitly,
            "the WebKit grant preceded the reentrant replacement and stands"
        )
        XCTAssertEqual(harness.configuredLevel(), .allow)
        XCTAssertNil(
            harness.storedDecision(),
            "durable decision persistence is the stale tail and must stop"
        )
        XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(harness.actionPopupMetricCount(), 0)
    }

    // MARK: - 13. Reentrant invalidation between publication and dispatch

    func testReentrantInvalidationBetweenActionPublicationAndDispatchPreventsPerformAction() async throws {
        let harness = try await makeHarness(name: "ReentrantPublication")
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = { _, _, _ in
            .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        // Fire on the action-surface publication that follows durable
        // persistence: the invocation's own publication effect reentrantly
        // replaces the binding before `performAction`.
        var cancellables = Set<AnyCancellable>()
        let trigger = ReentrantMutationTrigger { [inspection = harness.inspection] in
            guard inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .matchPattern,
                target: Self.clickedHostPattern
            ) != nil else { return false }
            _ = inspection.contextState.profiles.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return true
        }
        harness.inspection.actionSurfaces.publication.actionStatesPublisher
            .dropFirst()
            .sink { _ in trigger.fireIfArmed() }
            .store(in: &cancellables)

        let result = await harness.openPopup()
        await drainMainActorTurns()
        cancellables.removeAll()

        XCTAssertTrue(trigger.didFire)
        XCTAssertEqual(result.blocker, .staleInvocation)
        XCTAssertEqual(
            dispatches,
            0,
            "performAction must not run after reentrant invalidation at publication"
        )
        XCTAssertEqual(harness.storedDecision()?.state, .allowed)
        XCTAssertEqual(harness.actionPopupMetricCount(), 0)
    }

    // MARK: - 14. The result settles deterministically and only once

    func testStaleInvocationSettlesDeterministicallyOnceWithoutLateEffects() async throws {
        let harness = try await makeHarness(name: "SettlesOnce")
        var dispatches = 0
        var promptCount = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            promptCount += 1
            _ = inspection.contextState.profiles.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return .allow(expirationDate: nil)
        }
        defer { clearHooks(harness) }

        let result = await harness.openPopup()
        let settledBlocker = result.blocker
        await drainMainActorTurns()

        XCTAssertEqual(promptCount, 1)
        XCTAssertEqual(settledBlocker, .staleInvocation)
        XCTAssertFalse(result.opened)
        // No scheduled continuation may append effects after settlement.
        XCTAssertNil(harness.storedDecision())
        XCTAssertEqual(harness.configuredLevel(), .ask)
        XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(harness.actionPopupMetricCount(), 0)
    }

    // MARK: - 15. Pre-resolution profile drift cannot redirect a click

    func testUntrackedTabIsRejectedBeforeRuntimeResolution() async throws {
        let harness = try await makeHarness(name: "PreResolutionProfile")
        let detachedTab = Tab(url: Self.clickedPageURL)
        let boundary = makeAdmission(
            inspection: harness.inspection,
            attachedRuntime: harness.attachedRuntime
        )
        let request = boundary.request.capture(
            extensionID: harness.extensionID,
            currentTab: detachedTab
        )

        XCTAssertNil(request)
    }

    func testNoTabFallbackProfileChangeDuringRuntimeResolutionInvalidatesRequest() async throws {
        let harness = try await makeHarness(name: "PreResolutionNoTabProfile")
        let boundary = makeAdmission(
            inspection: harness.inspection,
            attachedRuntime: harness.attachedRuntime
        )
        let request = try XCTUnwrap(
            boundary.request.capture(
                extensionID: harness.extensionID,
                currentTab: nil
            )
        )

        _ = harness.inspection.contextState.profiles.activateProfile(
            UUID(),
            hasExtensionDemand: false,
            runtimeIsReadyOrLoading: false
        )

        let evidence = boundary.invocation.capture(
            request: request,
            profileID: harness.profileID,
            context: harness.context,
            controller: harness.inspection.contextState.profiles.controller(
                for: harness.profileID
            )
        )

        XCTAssertNil(evidence)
    }

    // MARK: - 16. A pre-existing runtime cannot be rebound during resolution

    func testExistingRuntimeRebindDuringRuntimeResolutionInvalidatesRequest() async throws {
        let harness = try await makeHarness(name: "PreResolutionRuntimeRebind")
        let boundary = makeAdmission(
            inspection: harness.inspection,
            attachedRuntime: harness.attachedRuntime
        )
        let request = try XCTUnwrap(
            boundary.request.capture(
                extensionID: harness.extensionID,
                currentTab: harness.tab
            )
        )

        _ = harness.inspection.contextState.profiles.setContext(
            harness.context,
            extensionId: harness.extensionID,
            profileId: harness.profileID
        )

        let evidence = boundary.invocation.capture(
            request: request,
            profileID: harness.profileID,
            context: harness.context,
            controller: harness.inspection.contextState.profiles.controller(
                for: harness.profileID
            )
        )

        XCTAssertNil(evidence)
    }

    // MARK: - 17. A pre-resolution document replacement stops the click

    func testDocumentReplacementDuringRuntimeResolutionInvalidatesRequest() async throws {
        let harness = try await makeHarness(name: "PreResolutionDocument")
        let boundary = makeAdmission(
            inspection: harness.inspection,
            attachedRuntime: harness.attachedRuntime
        )
        let request = try XCTUnwrap(
            boundary.request.capture(
                extensionID: harness.extensionID,
                currentTab: harness.tab
            )
        )
        harness.tab.committedDocumentRuntime.performTransition(
            reason: .documentCommit
        ) {
            harness.tab.committedDocumentRuntime.recordCommit(
                TabCommittedDocumentEvidence(
                    webView: WKWebView(),
                    revision: 1,
                    documentGeneration: 1,
                    participantID: UUID(),
                    committedURL: URL(string: "https://replacement.example/")!,
                    presentationURL: URL(string: "https://replacement.example/")!,
                    isPDF: false
                ),
                publishesCanonicalDocument: true
            )
        }

        let evidence = boundary.invocation.capture(
            request: request,
            profileID: harness.profileID,
            context: harness.context,
            controller: harness.inspection.contextState.profiles.controller(
                for: harness.profileID
            )
        )

        XCTAssertNil(evidence)
    }

    // MARK: - 18. Exact adapter absence is invalidated by later publication

    func testAdapterAbsenceIsExactAuthority() async throws {
        let harness = try await makeHarness(name: "ExactAdapterAbsence")
        harness.attachedRuntime.normalTabs.tabRegistration.register(
            harness.tab,
            reason: "ExtensionActionInvocationAdmissionTests"
        )
        let adapter = try XCTUnwrap(
            harness.attachedRuntime.adapters.stableAdapter(for: harness.tab)
        )
        harness.inspection.normalTabs.adapters.removeTabAdapter(for: harness.tab.id)

        let boundary = makeAdmission(
            inspection: harness.inspection,
            attachedRuntime: harness.attachedRuntime
        )
        let request = try XCTUnwrap(
            boundary.request.capture(
                extensionID: harness.extensionID,
                currentTab: harness.tab
            )
        )
        let captured = try XCTUnwrap(
            boundary.invocation.capture(
                request: request,
                profileID: harness.profileID,
                context: harness.context,
                controller: harness.inspection.contextState.profiles.controller(
                    for: harness.profileID
                )
            )
        )
        let admittedAbsence = try XCTUnwrap(
            boundary.invocation.admitAdapter(nil, for: captured)
        )
        XCTAssertTrue(boundary.invocation.isCurrent(admittedAbsence))

        harness.inspection.normalTabs.adapters.tabAdapters[harness.tab.id] = adapter

        XCTAssertFalse(boundary.invocation.isCurrent(admittedAbsence))
    }

    // MARK: - 19. Rejected invocation stays zero-cost

    func testResidenceDelegationFailsClosedBeforeAttachmentAndAfterRetirement()
        async throws {
        let harness = try await makeHarness(name: "ResidenceDelegation")
        let detached = ExtensionBrowserAttachmentAuthority()

        XCTAssertFalse(
            detached.containsExactResidence(
                harness.tab,
                in: harness.windowState
            )
        )

        let attachment = harness.inspection.browserPublication.attachment
        XCTAssertTrue(
            attachment.containsExactResidence(
                harness.tab,
                in: harness.windowState
            )
        )

        attachment.retireCurrentAttachment()

        XCTAssertFalse(
            attachment.containsExactResidence(
                harness.tab,
                in: harness.windowState
            )
        )
    }

    func testRejectedInvocationDoesNotMaterializeLazyRuntimeSystems() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "ZeroCost")
        let inspection = ExtensionManagerInspectionCapture()
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let manager = ExtensionManager(
            database: container,
            initialProfile: profile,
            attachedRuntimeDidInstall: attachedRuntime.install,
            testInspectionDidAssemble: inspection.install
        )

        let result = await inspection.inspection.actionSurfaces.invocation
            .openPopup(
            extensionID: "not-installed",
            currentTab: nil
        )

        XCTAssertEqual(result.blocker, .extensionNotInstalled)
        // The lazy runtime systems whose materialization carries background
        // cost (native messaging, background wakes, the browser runtime
        // bridge) must stay cold for a rejected invocation.
        XCTAssertNil(inspection.inspection.nativeMessaging.loadedRelay)
        XCTAssertFalse(
            inspection.inspection.nativeMessaging.hasLoadedWakeOwner
        )
        XCTAssertFalse(attachedRuntime.hasInstalledRuntime)
        withExtendedLifetime(manager) {}
    }

    // MARK: - 20. Popup invocation settlement and exact recovery

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

    // MARK: - Harness

    private struct Harness {
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

    private func makePresentationQuery(
        harness: Harness
    ) -> ExtensionActionPresentationQuery {
        let profiles = harness.inspection.contextState.profiles
        let adapters = harness.attachedRuntime.adapters
        let windows = harness.attachedRuntime.bridge.windows
        return ExtensionActionPresentationQuery(
            contextBindings: { extensionID in
                profiles.contextsByProfile.compactMap {
                    profileID, contexts in
                    guard let context = contexts[extensionID],
                          let identity = profiles.exactContextIdentity(
                              for: context
                          ),
                          identity.extensionId == extensionID,
                          identity.profileId == profileID,
                          let receipt = profiles.contextBindingReceipt(
                              extensionId: extensionID,
                              profileId: profileID
                          ),
                          profiles.context(ifCurrent: receipt) === context
                    else { return nil }
                    return ExtensionActionPresentationQuery.ContextBinding(
                        context: context,
                        receipt: receipt
                    )
                }
            },
            currentContext: profiles.context(ifCurrent:),
            stableAdapter: adapters.stableAdapter(for:),
            windowRegistrationReceipt: windows.registrationReceipt(for:),
            registeredWindow: windows.window(ifCurrent:),
            allWindows: { windows.allExtensionWindowStates },
            residences: harness.attachedRuntime.bridge.tabResidences
        )
    }

    private func makePublishedPresentationTab(
        url: URL,
        profileID: UUID,
        harness: Harness,
        windowState: BrowserWindowState? = nil
    ) -> Tab {
        let windowState = windowState ?? harness.windowState
        let configuration = harness.inspection.controller.browserConfiguration
            .auxiliaryWebViewConfiguration(surface: .extensionOptions)
        harness.inspection.normalTabs.configuration
            .prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profileID,
            reason: #function
        )
        let tab = harness.browserManager
            .regularTabLifecycleOwner.createNewTab(
                url: url.absoluteString,
                in: harness.browserManager.spaceStateOwner.currentSpace,
                activate: false,
                webViewConfigurationOverride: configuration,
                executionProfileID: profileID
            )
        tab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: harness.browserManager)
        )
        let webView = FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)
        windowState.currentProfileId = profileID
        windowState.currentSpaceId = tab.spaceId
        windowState.currentTabId = tab.id
        harness.attachedRuntime.normalTabs.tabRegistration.register(
            tab,
            reason: #function
        )
        XCTAssertTrue(
            harness.attachedRuntime.normalTabs.publishedTabs
                .containsPublishedTab(tab)
        )
        return tab
    }

    private func clearHooks(_ harness: Harness) {
        harness.manager.testHooks.permissionPromptDecision = nil
        harness.manager.testHooks.didDispatchExtensionAction = nil
    }

    private func makeAdmission(
        inspection: ExtensionManagerTestInspection,
        attachedRuntime: ExtensionAttachedBrowserRuntimeInspection
    ) -> (
        request: ExtensionActionRequestAdmission,
        invocation: ExtensionActionInvocationAdmission
    ) {
        let request = ExtensionActionRequestAdmission(
            runtimeBindingAdmission: inspection.controller.callbackAdmission,
            profileRuntime: inspection.contextState.profiles,
            allTabs: { [tabs = attachedRuntime.bridge.tabs] in
                tabs.allExtensionTabs
            },
            profileID: attachedRuntime.controller.profiles.profileID,
            currentProfileID: {
                [profiles = inspection.contextState.profiles] in
                profiles.currentProfileId
                    ?? profiles.currentRememberedProfile?.id
            },
            installedExtensions: inspection.actionSurfaces.installedExtensions
        )
        let invocation = ExtensionActionInvocationAdmission(
            runtimeBindingAdmission: inspection.controller.callbackAdmission,
            requestAdmission: request,
            installedExtensions: inspection.actionSurfaces.installedExtensions,
            adapterStore: inspection.normalTabs.adapters
        )
        return (request, invocation)
    }

    private func makeInvocationService(
        inspection: ExtensionManagerTestInspection,
        attachedRuntime: ExtensionAttachedBrowserRuntimeInspection,
        actionDispatch: any ExtensionActionDispatching,
        bindingRecovery: any ExtensionActionPopupBindingRecovering,
        actionDispatchProbe: @escaping @MainActor (String) -> Void
    ) -> ExtensionActionInvocationService {
        let boundary = makeAdmission(
            inspection: inspection,
            attachedRuntime: attachedRuntime
        )
        return ExtensionActionInvocationService(
            environment: .init(
                runtimeResolver: ExtensionActionRuntimeResolver(
                    environment: .init(
                        installedExtensions:
                            inspection.actionSurfaces.installedExtensions,
                        runtimeAccess:
                            inspection.contextCoordination.runtimeAccess,
                        runtimeLifecycle:
                            inspection.runtimeAuthorities.lifecycle,
                        runtimeCatalog:
                            inspection.runtimeAuthorities.catalog,
                        anchorStore: inspection.popups.anchors,
                        anchorResolution: inspection.popups.anchorResolver,
                        profileTransition:
                            inspection.contextCoordination.profileTransition,
                        contextResidency:
                            inspection.contextCoordination.residency,
                        failureDiagnostics:
                            inspection.actionPolicy.popupFailureDiagnostics,
                        resolvedProfileID:
                            attachedRuntime.controller.profiles.profileID,
                        primaryWindowID: {
                            [windows = attachedRuntime.bridge.windows] tab in
                            windows.preferredExtensionWindowState(
                                containing: tab
                            )?.id
                        },
                        activeWindowID: {
                            [windows = attachedRuntime.bridge.windows] in
                            windows.activeExtensionWindowState?.id
                        },
                        trace: { _ in }
                    )
                ),
                requestAdmission: boundary.request,
                pageAccess: ExtensionActionPageAccessAuthorizer(
                    environment: .init(
                        siteAccess: inspection.actionPolicy.siteAccess,
                        decisions:
                            inspection.actionPolicy.permissionDecisions,
                        prompt: {
                            [prompt = inspection.actionPolicy.permissionPrompt,
                             profiles = inspection.contextState.profiles]
                            context, targets, reason, dedupeKey in
                            await prompt.promptForDecision(
                                extensionContext: context,
                                targets: targets,
                                reason: reason,
                                dedupeKey: dedupeKey,
                                extensionIdentifier:
                                    profiles.extensionId(for: context)
                            )
                        }
                    ),
                    admission: boundary.invocation
                ),
                admission: boundary.invocation,
                actionPublication: inspection.actionSurfaces.publisher,
                runtimeMetrics: inspection.runtimeAuthorities.metrics,
                stableAdapter: { [adapters = attachedRuntime.adapters] in
                    adapters.stableAdapter(for: $0)
                },
                registerTab: {
                    [tabRegistration = attachedRuntime.normalTabs.tabRegistration]
                    tab,
                    reason in
                    tabRegistration.register(tab, reason: reason)
                },
                actionDispatchProbe: actionDispatchProbe,
                trace: { _ in }
            ),
            actionDispatch: actionDispatch,
            popupBindingRecovery: bindingRecovery
        )
    }

    private func exactInvocation(
        in harness: Harness
    ) throws -> (ExtensionActionInvocationEvidence, WKWebExtension.Action) {
        harness.attachedRuntime.normalTabs.tabRegistration.register(
            harness.tab,
            reason: "ExtensionActionInvocationAdmissionTests.exactInvocation"
        )
        let boundary = makeAdmission(
            inspection: harness.inspection,
            attachedRuntime: harness.attachedRuntime
        )
        let request = try XCTUnwrap(
            boundary.request.capture(
                extensionID: harness.extensionID,
                currentTab: harness.tab
            )
        )
        let captured = try XCTUnwrap(
            boundary.invocation.capture(
                request: request,
                profileID: harness.profileID,
                context: harness.context,
                controller: harness.context.webExtensionController
            )
        )
        let adapter = try XCTUnwrap(
            harness.attachedRuntime.adapters.stableAdapter(for: harness.tab)
        )
        let evidence = try XCTUnwrap(
            boundary.invocation.admitAdapter(adapter, for: captured)
        )
        let action = try XCTUnwrap(
            harness.context.action(for: evidence.adapter)
        )
        return (evidence, action)
    }

    private func makeHarness(name: String) async throws -> Harness {
        let container = try makeTestContainer()
        let profile = Profile(name: name)
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let inspection = ExtensionManagerInspectionCapture()
        let manager = makeSafariExtensionTestExtensionManager(
            database: container,
            initialProfile: profile,
            attachedRuntimeCapture: attachedRuntime,
            inspectionCapture: inspection
        )
        let windowRegistry = WindowRegistry()
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile,
            windowRegistry: windowRegistry
        )
        browserManager.startupRestoreLifecycle.markLoadFinished()
        manager.attach(browserManager: browserManager)
        let installed = try await installPromptingExtension(
            inspection: inspection.inspection,
            name: name
        )
        _ = try await inspection.inspection.installation.lifecycle.enable(
            installed.id
        )
        let context = try XCTUnwrap(
            inspection.inspection.contextState.profileState.context(
                for: installed.id,
                profileId: profile.id
            )
        )
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: Self.clickedPageURL.absoluteString,
            in: browserManager.spaceStateOwner.currentSpace,
            activate: false
        )
        tab.profileId = profile.id
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = tab.spaceId
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        addTeardownBlock { @MainActor in
            windowRegistry.unregister(windowState.id)
        }
        return Harness(
            manager: manager,
            inspection: inspection.inspection,
            attachedRuntime: attachedRuntime.runtime,
            browserManager: browserManager,
            profileID: profile.id,
            extensionID: installed.id,
            tab: tab,
            context: context,
            windowRegistry: windowRegistry,
            windowState: windowState
        )
    }

    /// Installs an extension whose page access must be resolved through the
    /// action-click permission prompt: a concrete host permission for the
    /// clicked page, no `activeTab`.
    private func installPromptingExtension(
        inspection: ExtensionManagerTestInspection,
        name: String
    ) async throws -> InstalledExtension {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let installRoot = directory.deletingLastPathComponent()
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: installRoot.path) {
                try FileManager.default.removeItem(at: installRoot)
            }
        }

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
            "host_permissions": [Self.clickedHostPattern],
            "action": ["default_popup": "popup.html"],
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(
                to: directory.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )
        try Data("<!doctype html><title>popup</title>".utf8)
            .write(
                to: directory.appendingPathComponent("popup.html"),
                options: [.atomic]
            )

        return try await inspection.installation.installer.install(
            from: directory,
            enableOnInstall: false
        )
    }

    private func makeTestContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }

    /// Gives any stray continuation of the settled invocation a chance to
    /// run, so a late effect would be observed by the assertions.
    private func drainMainActorTurns() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    private static func copyRecord(
        _ record: InstalledExtension,
        isEnabled: Bool,
        manifestRootFingerprint: String? = nil
    ) -> InstalledExtension {
        InstalledExtension(
            id: record.id,
            name: record.name,
            version: record.version,
            manifestVersion: record.manifestVersion,
            description: record.description,
            isEnabled: isEnabled,
            installDate: record.installDate,
            lastUpdateDate: record.lastUpdateDate,
            packagePath: record.packagePath,
            iconPath: record.iconPath,
            sourceKind: record.sourceKind,
            backgroundModel: record.backgroundModel,
            incognitoMode: record.incognitoMode,
            sourcePathFingerprint: record.sourcePathFingerprint,
            manifestRootFingerprint: manifestRootFingerprint
                ?? record.manifestRootFingerprint,
            sourceBundlePath: record.sourceBundlePath,
            optionsPagePath: record.optionsPagePath,
            defaultPopupPath: record.defaultPopupPath,
            hasBackground: record.hasBackground,
            hasAction: record.hasAction,
            hasOptionsPage: record.hasOptionsPage,
            hasContentScripts: record.hasContentScripts,
            hasExtensionPages: record.hasExtensionPages,
            activationSummary: record.activationSummary,
            manifest: record.manifest
        )
    }

    private static func makeSyntheticRecord(id: String) -> InstalledExtension {
        InstalledExtension(
            id: id,
            name: "Unrelated",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: false,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: "/tmp/unrelated-package",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "unrelated-source",
            manifestRootFingerprint: "unrelated-manifest",
            sourceBundlePath: "",
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: false,
            hasOptionsPage: false,
            hasContentScripts: false,
            hasExtensionPages: false,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: false,
                hasOptionsPage: false,
                hasExtensionPages: false
            ),
            manifest: ["manifest_version": 3, "name": "Unrelated", "version": "1.0"]
        )
    }
}

private final class ExtensionActionInvocationTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval

    init(now: TimeInterval) {
        value = now
    }

    func now() -> TimeInterval {
        lock.withLock { value }
    }

    func set(_ value: TimeInterval) {
        lock.withLock {
            self.value = value
        }
    }
}

@available(macOS 15.5, *)
@MainActor
private final class RecoveringActionDispatch: ExtensionActionDispatching {
    let stalledBinding: ExtensionContextBindingReceipt
    private(set) var contexts: [WKWebExtensionContext] = []

    init(stalledBinding: ExtensionContextBindingReceipt) {
        self.stalledBinding = stalledBinding
    }

    func perform(
        action _: WKWebExtension.Action,
        evidence: ExtensionActionInvocationEvidence,
        popupTarget _: ExtensionActionPopupInvocationTarget?
    ) -> ExtensionActionDispatchResult {
        contexts.append(evidence.context)
        if contexts.count == 1 {
            return .popupBindingRecoveryRequired(stalledBinding)
        }
        return .performed(nil)
    }

    func cancel(_: ExtensionActionPopupInvocationRegistration?) {}
}

@available(macOS 15.5, *)
@MainActor
private final class SuccessfulBindingRecovery:
    ExtensionActionPopupBindingRecovering {
    private(set) var receipts: [ExtensionContextBindingReceipt] = []

    func recover(_ stalled: ExtensionContextBindingReceipt) async -> Bool {
        receipts.append(stalled)
        return true
    }
}

/// Fires a main-actor mutation exactly once from a synchronous observer;
/// the attempt closure reports whether its firing condition was met.
private final class ReentrantMutationTrigger: @unchecked Sendable {
    private(set) var didFire = false
    private let attempt: @MainActor () -> Bool

    init(attempt: @escaping @MainActor () -> Bool) {
        self.attempt = attempt
    }

    @MainActor
    func fireIfArmed() {
        guard didFire == false else { return }
        if attempt() {
            didFire = true
        }
    }
}
