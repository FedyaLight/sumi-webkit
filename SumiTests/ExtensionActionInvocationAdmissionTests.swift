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
    static let clickedPageURL = URL(string: "https://clicked.example/path")!
    static let clickedHostPattern = "https://clicked.example/*"

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

    func makePresentationQuery(
        harness: ExtensionActionInvocationHarness
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

    func makePublishedPresentationTab(
        url: URL,
        profileID: UUID,
        harness: ExtensionActionInvocationHarness,
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

    func clearHooks(_ harness: ExtensionActionInvocationHarness) {
        harness.manager.testHooks.permissionPromptDecision = nil
        harness.manager.testHooks.didDispatchExtensionAction = nil
    }

    func makeAdmission(
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

    func makeInvocationService(
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

    func exactInvocation(
        in harness: ExtensionActionInvocationHarness
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

    func makeHarness(name: String) async throws -> ExtensionActionInvocationHarness {
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
        return ExtensionActionInvocationHarness(
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
    func installPromptingExtension(
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

    func makeTestContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }

    /// Gives any stray continuation of the settled invocation a chance to
    /// run, so a late effect would be observed by the assertions.
    func drainMainActorTurns() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    static func copyRecord(
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

    static func makeSyntheticRecord(id: String) -> InstalledExtension {
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

final class ExtensionActionInvocationTestClock: @unchecked Sendable {
    let lock = NSLock()
    var value: TimeInterval

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
final class RecoveringActionDispatch: ExtensionActionDispatching {
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
final class SuccessfulBindingRecovery:
    ExtensionActionPopupBindingRecovering {
    private(set) var receipts: [ExtensionContextBindingReceipt] = []

    func recover(_ stalled: ExtensionContextBindingReceipt) async -> Bool {
        receipts.append(stalled)
        return true
    }
}

/// Fires a main-actor mutation exactly once from a synchronous observer;
/// the attempt closure reports whether its firing condition was met.
final class ReentrantMutationTrigger: @unchecked Sendable {
    private(set) var didFire = false
    let attempt: @MainActor () -> Bool

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
