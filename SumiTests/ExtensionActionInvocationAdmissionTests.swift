import Combine
import SwiftData
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

    override func setUp() {
        super.setUp()
        removePersistedPolicyState()
    }

    override func tearDown() {
        removePersistedPolicyState()
        super.tearDown()
    }

    nonisolated private func removePersistedPolicyState() {
        UserDefaults.standard.removeObject(
            forKey: SafariExtensionSiteAccessPolicyStore.siteAccessStorageKey
        )
        UserDefaults.standard.removeObject(
            forKey: SafariExtensionSiteAccessPolicyStore.legacyPermissionDecisionsStorageKey
        )
    }

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
            [manager = harness.manager] _, _, _ in
            _ = manager.profileRuntime.setContext(
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
            [manager = harness.manager] _, _, _ in
            _ = manager.profileRuntime.setContext(
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
        let originalController = harness.manager.ensureExtensionController(
            for: harness.profileID
        )
        let replacementController = WKWebExtensionController(
            configuration: .nonPersistent()
        )
        var dispatches = 0
        var staleDrive = true
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [manager = harness.manager] _, _, _ in
            if staleDrive {
                manager.profileRuntime.setController(
                    replacementController,
                    for: harness.profileID
                )
                manager.profileRuntime.setController(
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
            [manager = harness.manager] _, _, _ in
            manager.runtimeSession.extensionLoadGeneration += 1
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
            [manager = harness.manager] _, _, _ in
            manager.installedExtensionCollection.remove(id: harness.extensionID)
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
            harness.manager.installedExtensionCollection.records
                .first { $0.id == harness.extensionID }
                .map { Self.copyRecord($0, isEnabled: false) }
        )
        var dispatches = 0
        harness.manager.testHooks.didDispatchExtensionAction = { _ in dispatches += 1 }
        harness.manager.testHooks.permissionPromptDecision = {
            [manager = harness.manager] _, _, _ in
            manager.installedExtensionCollection.upsert(disabledRecord)
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
            [manager = harness.manager] _, _, _ in
            manager.installedExtensionCollection.upsert(
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
            [manager = harness.manager] _, _, _ in
            _ = manager.profileRuntime.setContext(
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
            [manager = harness.manager] _, _, _ in
            _ = manager.profileRuntime.setContext(
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
        let trigger = ReentrantMutationTrigger { [manager = harness.manager] in
            guard manager.configuredSiteAccessLevel(
                for: Self.clickedPageURL,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            ) == .allow else { return false }
            _ = manager.profileRuntime.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return true
        }
        let observer = NotificationCenter.default.addObserver(
            forName: .sumiExtensionSiteAccessPoliciesDidChange,
            object: harness.manager,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated { trigger.fireIfArmed() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

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
        let trigger = ReentrantMutationTrigger { [manager = harness.manager] in
            guard manager.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .matchPattern,
                target: Self.clickedHostPattern
            ) != nil else { return false }
            _ = manager.profileRuntime.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return true
        }
        harness.manager.$actionStatesByExtensionID
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
            [manager = harness.manager] _, _, _ in
            promptCount += 1
            _ = manager.profileRuntime.setContext(
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
        let boundary = makeAdmission(manager: harness.manager)
        let request = boundary.request.capture(
            extensionID: harness.extensionID,
            currentTab: detachedTab
        )

        XCTAssertNil(request)
    }

    func testNoTabFallbackProfileChangeDuringRuntimeResolutionInvalidatesRequest() async throws {
        let harness = try await makeHarness(name: "PreResolutionNoTabProfile")
        let boundary = makeAdmission(manager: harness.manager)
        let request = try XCTUnwrap(
            boundary.request.capture(
                extensionID: harness.extensionID,
                currentTab: nil
            )
        )

        _ = harness.manager.profileRuntime.activateProfile(
            UUID(),
            hasExtensionDemand: false,
            runtimeIsReadyOrLoading: false
        )

        let evidence = boundary.invocation.capture(
            request: request,
            profileID: harness.profileID,
            context: harness.context,
            controller: harness.manager.profileRuntime.controller(
                for: harness.profileID
            )
        )

        XCTAssertNil(evidence)
    }

    // MARK: - 16. A pre-existing runtime cannot be rebound during resolution

    func testExistingRuntimeRebindDuringRuntimeResolutionInvalidatesRequest() async throws {
        let harness = try await makeHarness(name: "PreResolutionRuntimeRebind")
        let boundary = makeAdmission(manager: harness.manager)
        let request = try XCTUnwrap(
            boundary.request.capture(
                extensionID: harness.extensionID,
                currentTab: harness.tab
            )
        )

        _ = harness.manager.profileRuntime.setContext(
            harness.context,
            extensionId: harness.extensionID,
            profileId: harness.profileID
        )

        let evidence = boundary.invocation.capture(
            request: request,
            profileID: harness.profileID,
            context: harness.context,
            controller: harness.manager.profileRuntime.controller(
                for: harness.profileID
            )
        )

        XCTAssertNil(evidence)
    }

    // MARK: - 17. A pre-resolution document replacement stops the click

    func testDocumentReplacementDuringRuntimeResolutionInvalidatesRequest() async throws {
        let harness = try await makeHarness(name: "PreResolutionDocument")
        let boundary = makeAdmission(manager: harness.manager)
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
            controller: harness.manager.profileRuntime.controller(
                for: harness.profileID
            )
        )

        XCTAssertNil(evidence)
    }

    // MARK: - 18. Exact adapter absence is invalidated by later publication

    func testAdapterAbsenceIsExactAuthority() async throws {
        let harness = try await makeHarness(name: "ExactAdapterAbsence")
        harness.manager.normalTabRegistration.register(
            harness.tab,
            reason: "ExtensionActionInvocationAdmissionTests"
        )
        let adapter = try XCTUnwrap(
            harness.manager.adapterCatalog.stableAdapter(for: harness.tab)
        )
        harness.manager.adapterStore.removeTabAdapter(for: harness.tab.id)

        let boundary = makeAdmission(manager: harness.manager)
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
                controller: harness.manager.profileRuntime.controller(
                    for: harness.profileID
                )
            )
        )
        let admittedAbsence = try XCTUnwrap(
            boundary.invocation.admitAdapter(nil, for: captured)
        )
        XCTAssertTrue(boundary.invocation.isCurrent(admittedAbsence))

        harness.manager.adapterStore.tabAdapters[harness.tab.id] = adapter

        XCTAssertFalse(boundary.invocation.isCurrent(admittedAbsence))
    }

    // MARK: - 19. Rejected invocation stays zero-cost

    func testRejectedInvocationDoesNotMaterializeLazyRuntimeSystems() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "ZeroCost")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let result = await manager.extensionActionInvocation.openPopup(
            extensionID: "not-installed",
            currentTab: nil
        )

        XCTAssertEqual(result.blocker, .extensionNotInstalled)
        // The lazy runtime systems whose materialization carries background
        // cost (native messaging, background wakes, the browser runtime
        // bridge) must stay cold for a rejected invocation.
        XCTAssertNil(manager.loadedNativeMessagingRelayOwner)
        XCTAssertNil(manager.loadedNativeMessagingBackgroundWakeOwner)
        XCTAssertNil(manager.loadedRuntimePublicationReconciler)
    }

    // MARK: - Harness

    private struct Harness {
        let manager: ExtensionManager
        let browserManager: BrowserManager
        let profileID: UUID
        let extensionID: String
        let tab: Tab
        let context: WKWebExtensionContext

        @MainActor
        func openPopup() async -> BrowserExtensionActionPopupRequestResult {
            await manager.extensionActionInvocation.openPopup(
                extensionID: extensionID,
                currentTab: tab
            )
        }

        @MainActor
        func storedDecision() -> ExtensionManager.ExtensionStoredPermissionDecision? {
            manager.storedExtensionPermissionDecision(
                extensionId: extensionID,
                profileId: profileID,
                targetKind: .matchPattern,
                target: ExtensionActionInvocationAdmissionTests.clickedHostPattern
            )
        }

        @MainActor
        func configuredLevel() -> SafariExtensionSiteAccessLevel {
            manager.configuredSiteAccessLevel(
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
            let metrics = manager.runtimeSession
                .runtimeMetricsByExtensionID[extensionID]
            guard let metrics, metrics.lastBackgroundWakeReason == .actionPopup
            else {
                return 0
            }
            return metrics.backgroundWakeCount
        }
    }

    private func clearHooks(_ harness: Harness) {
        harness.manager.testHooks.permissionPromptDecision = nil
        harness.manager.testHooks.didDispatchExtensionAction = nil
    }

    private func makeAdmission(
        manager: ExtensionManager
    ) -> (
        request: ExtensionActionRequestAdmission,
        invocation: ExtensionActionInvocationAdmission
    ) {
        let request = ExtensionActionRequestAdmission(
            runtimeBindingAdmission: manager.controllerCallbackAdmission,
            profileRuntime: manager.profileRuntime,
            runtime: { [weak manager] in manager?.runtime ?? .inactive },
            installedExtensions: manager.installedExtensionCollection
        )
        let invocation = ExtensionActionInvocationAdmission(
            runtimeBindingAdmission: manager.controllerCallbackAdmission,
            requestAdmission: request,
            installedExtensions: manager.installedExtensionCollection,
            adapterStore: manager.adapterStore
        )
        return (request, invocation)
    }

    private func makeHarness(name: String) async throws -> Harness {
        let container = try makeTestContainer()
        let profile = Profile(name: name)
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        let installed = try await installPromptingExtension(
            manager: manager,
            name: name
        )
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        manager.attach(browserManager: browserManager)
        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: Self.clickedPageURL.absoluteString,
            in: browserManager.tabManager.spaceStateOwner.currentSpace,
            activate: false
        )
        tab.profileId = profile.id
        return Harness(
            manager: manager,
            browserManager: browserManager,
            profileID: profile.id,
            extensionID: installed.id,
            tab: tab,
            context: context
        )
    }

    /// Installs an extension whose page access must be resolved through the
    /// action-click permission prompt: a concrete host permission for the
    /// clicked page, no `activeTab`.
    private func installPromptingExtension(
        manager: ExtensionManager,
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

        return try await manager.extensionInstaller.install(
            from: directory,
            enableOnInstall: false
        )
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
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
        isEnabled: Bool
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
            manifestRootFingerprint: record.manifestRootFingerprint,
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
