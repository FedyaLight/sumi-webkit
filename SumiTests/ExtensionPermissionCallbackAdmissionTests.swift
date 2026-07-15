import Combine
import SwiftData
import WebKit
import XCTest

@testable import Sumi

/// Integration tests for typed callback-evidence admission on the three
/// WebKit permission prompt callbacks, driven through the real
/// `ExtensionControllerDelegateBridge` against a live `ExtensionManager`.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPermissionCallbackAdmissionTests: XCTestCase {
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

    // MARK: - Exact current pair admits the callback

    func testExactCurrentControllerAndContextAdmitsPermissionPrompt() async throws {
        let harness = try await makeHarness(name: "ExactAdmission")
        let permission = WKWebExtension.Permission(rawValue: "cookies")
        var promptCount = 0
        harness.manager.testHooks.permissionPromptDecision = { _, _, _ in
            promptCount += 1
            return .allow(expirationDate: nil)
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        let result = await drivePermissionsPrompt([permission], harness: harness)

        XCTAssertEqual(promptCount, 1)
        XCTAssertTrue(result.granted.contains(permission))
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertEqual(
            harness.context.permissionStatus(for: permission),
            .grantedExplicitly
        )
        let stored = try XCTUnwrap(
            harness.inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .permission,
                target: permission.rawValue
            )
        )
        XCTAssertEqual(stored.state, .allowed)
    }

    // MARK: - Wrong controller fails closed before prompt and mutations

    func testWrongControllerFailsClosedBeforePromptAndMutations() async throws {
        let harness = try await makeHarness(name: "WrongController")
        let permission = WKWebExtension.Permission(rawValue: "cookies")
        let foreignController = WKWebExtensionController(
            configuration: .nonPersistent()
        )
        var promptCount = 0
        harness.manager.testHooks.permissionPromptDecision = { _, _, _ in
            promptCount += 1
            return .allow(expirationDate: nil)
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        let result = await drivePermissionsPrompt(
            [permission],
            harness: harness,
            controller: foreignController
        )

        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(result.granted, [])
        XCTAssertNil(result.expiration)
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertEqual(
            harness.context.permissionStatus(for: permission),
            .unknown
        )
        XCTAssertNil(
            harness.inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .permission,
                target: permission.rawValue
            )
        )
    }

    // MARK: - Binding can change before the scheduled prompt task starts

    func testRebindBeforePromptTaskRunsFailsClosedBeforePresentation() async throws {
        let harness = try await makeHarness(name: "PrePromptTaskRebind")
        let permission = WKWebExtension.Permission(rawValue: "cookies")
        let completed = expectation(description: "callback completed")
        var completionCalls = 0
        var granted = Set<WKWebExtension.Permission>()
        var promptCount = 0
        harness.manager.testHooks.permissionPromptDecision = { _, _, _ in
            promptCount += 1
            return .allow(expirationDate: nil)
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        harness.inspection.controller.delegateBridge.webExtensionController(
            harness.controller,
            promptForPermissions: [permission],
            in: nil,
            for: harness.context
        ) { result, _ in
            completionCalls += 1
            granted = result
            completed.fulfill()
        }

        // The bridge has captured evidence, but its Task cannot start until
        // this main-actor turn yields. Rebinding now must prevent presentation.
        _ = harness.inspection.contextState.profiles.setContext(
            harness.context,
            extensionId: harness.extensionID,
            profileId: harness.profileID
        )
        await fulfillment(of: [completed], timeout: 2)
        await drainMainActorTurns()

        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(completionCalls, 1)
        XCTAssertEqual(granted, [])
        XCTAssertEqual(harness.context.permissionStatus(for: permission), .unknown)
    }

    // MARK: - Context replacement during the prompt await

    func testContextReplacementDuringPromptFailsClosedWithoutMutations() async throws {
        let harness = try await makeHarness(name: "ContextReplacement")
        let permission = WKWebExtension.Permission(rawValue: "cookies")
        let replacement = WKWebExtensionContext(
            for: harness.context.webExtension
        )
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            _ = inspection.contextState.profiles.setContext(
                replacement,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return .allow(expirationDate: nil)
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        let result = await drivePermissionsPrompt([permission], harness: harness)

        XCTAssertEqual(result.granted, [])
        XCTAssertNil(result.expiration)
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertEqual(
            harness.context.permissionStatus(for: permission),
            .unknown
        )
        XCTAssertEqual(
            replacement.permissionStatus(for: permission),
            .unknown
        )
        XCTAssertNil(
            harness.inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .permission,
                target: permission.rawValue
            )
        )
    }

    // MARK: - Same-context rebind during the prompt await

    func testSameContextRebindDuringPromptInvalidatesCallback() async throws {
        let harness = try await makeHarness(name: "SameContextRebind")
        let permission = WKWebExtension.Permission(rawValue: "cookies")
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            _ = inspection.contextState.profiles.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return .allow(expirationDate: nil)
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        let result = await drivePermissionsPrompt([permission], harness: harness)

        XCTAssertEqual(result.granted, [])
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertEqual(
            harness.context.permissionStatus(for: permission),
            .unknown
        )
        XCTAssertNil(
            harness.inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .permission,
                target: permission.rawValue
            )
        )
    }

    // MARK: - Controller A→B→A during the prompt await

    func testControllerABADuringPromptCannotReviveEvidenceButAdmitsNewCallback() async throws {
        let harness = try await makeHarness(name: "ControllerABA")
        let permission = WKWebExtension.Permission(rawValue: "cookies")
        let replacementController = WKWebExtensionController(
            configuration: .nonPersistent()
        )
        var staleDrive = true
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            if staleDrive {
                inspection.contextState.profiles.setController(
                    replacementController,
                    for: harness.profileID
                )
                inspection.contextState.profiles.setController(
                    harness.controller,
                    for: harness.profileID
                )
            }
            return .allow(expirationDate: nil)
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        let staleResult = await drivePermissionsPrompt([permission], harness: harness)

        XCTAssertEqual(staleResult.granted, [])
        XCTAssertEqual(staleResult.completionCalls, 1)
        XCTAssertEqual(
            harness.context.permissionStatus(for: permission),
            .unknown
        )
        XCTAssertNil(
            harness.inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .permission,
                target: permission.rawValue
            )
        )

        // A fresh callback against the settled A binding must be admitted.
        staleDrive = false
        let freshResult = await drivePermissionsPrompt([permission], harness: harness)
        XCTAssertTrue(freshResult.granted.contains(permission))
        XCTAssertEqual(freshResult.completionCalls, 1)
        XCTAssertEqual(
            harness.context.permissionStatus(for: permission),
            .grantedExplicitly
        )
    }

    // MARK: - Extension load generation change during the prompt await

    func testExtensionLoadGenerationChangeDuringPromptInvalidatesCallback() async throws {
        let harness = try await makeHarness(name: "LoadGeneration")
        let permission = WKWebExtension.Permission(rawValue: "cookies")
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            inspection.runtimeAuthorities.loadRevisions.advance()
            return .allow(expirationDate: nil)
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        let result = await drivePermissionsPrompt([permission], harness: harness)

        XCTAssertEqual(result.granted, [])
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertEqual(
            harness.context.permissionStatus(for: permission),
            .unknown
        )
        XCTAssertNil(
            harness.inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .permission,
                target: permission.rawValue
            )
        )
    }

    // MARK: - Unrelated extension rebind must not invalidate the callback

    func testUnrelatedExtensionRebindDuringPromptDoesNotInvalidateCallback() async throws {
        let harness = try await makeHarness(name: "UnrelatedRebind")
        let permission = WKWebExtension.Permission(rawValue: "cookies")
        let unrelatedContext = try await makeUnrelatedExtensionContext()
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            _ = inspection.contextState.profiles.setContext(
                unrelatedContext,
                extensionId: "unrelated-extension",
                profileId: harness.profileID
            )
            return .allow(expirationDate: nil)
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        let result = await drivePermissionsPrompt([permission], harness: harness)

        XCTAssertTrue(result.granted.contains(permission))
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertEqual(
            harness.context.permissionStatus(for: permission),
            .grantedExplicitly
        )
        let stored = try XCTUnwrap(
            harness.inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .permission,
                target: permission.rawValue
            )
        )
        XCTAssertEqual(stored.state, .allowed)
    }

    // MARK: - Reentrant replacement after the first observable effect

    func testReentrantReplacementAfterFirstSiteAccessEffectStopsRemainingTail() async throws {
        let harness = try await makeHarness(name: "ReentrantTail")
        let patternA = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.proton.me/*")
        )
        let patternB = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://pass.proton.me/*")
        )
        harness.manager.testHooks.permissionPromptDecision = { _, _, _ in
            .allow(expirationDate: nil)
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        // The first setConfiguredSiteAccess posts the site-access change
        // notification synchronously; rebinding there is a reentrant
        // replacement caused by the callback's own first observable effect.
        // Fire only once a configured rule for one of the prompt patterns
        // exists, so unrelated policy-store persistence cannot trip it early.
        let rebindTrigger = ReentrantRebindTrigger {
            [inspection = harness.inspection] in
            let ruleWritten = [patternA, patternB].contains { pattern in
                inspection.actionPolicy.siteAccess.configuredSiteAccessLevel(
                    for: pattern,
                    extensionId: harness.extensionID,
                    profileId: harness.profileID
                ) != .ask
            }
            guard ruleWritten else { return false }
            _ = inspection.contextState.profiles.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return true
        }
        let observer = harness.inspection.actionSurfaces.publication.siteAccessPolicyChangePublisher.sink {
            MainActor.assumeIsolated {
                rebindTrigger.fireIfArmed()
            }
        }
        defer { observer.cancel() }

        let result = await driveMatchPatternsPrompt(
            [patternA, patternB],
            harness: harness
        )

        XCTAssertTrue(rebindTrigger.didFire)
        XCTAssertEqual(result.granted, [])
        XCTAssertNil(result.expiration)
        XCTAssertEqual(result.completionCalls, 1)

        let persistedStates = [patternA, patternB].map { pattern in
            harness.inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .matchPattern,
                target: pattern.string
            )
        }
        XCTAssertEqual(
            persistedStates.compactMap { $0 }.count,
            1,
            "exactly the first pattern settles; the stale tail must stop"
        )
        let configuredLevels = [patternA, patternB].map { pattern in
            harness.inspection.actionPolicy.siteAccess.configuredSiteAccessLevel(
                for: pattern,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
        }
        XCTAssertEqual(configuredLevels.filter { $0 == .allow }.count, 1)
        XCTAssertEqual(configuredLevels.filter { $0 == .ask }.count, 1)
    }

    // MARK: - Match pattern family: stale after await applies nothing

    func testMatchPatternPromptStaleAfterAwaitAppliesNothing() async throws {
        let harness = try await makeHarness(name: "MatchPatternStale")
        let pattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.proton.me/*")
        )
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            _ = inspection.contextState.profiles.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return .allow(expirationDate: nil)
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        let result = await driveMatchPatternsPrompt([pattern], harness: harness)

        XCTAssertEqual(result.granted, [])
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertEqual(
            harness.context.permissionStatus(for: pattern),
            .unknown
        )
        XCTAssertNil(
            harness.inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .matchPattern,
                target: pattern.string
            )
        )
        XCTAssertEqual(
            harness.inspection.actionPolicy.siteAccess.configuredSiteAccessLevel(
                for: pattern,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            ),
            .ask
        )
    }

    // MARK: - URL family: stale callback leaves site access and diagnostics

    func testURLPromptStaleAfterAwaitLeavesSiteAccessAndDiagnosticsUntouched() async throws {
        let harness = try await makeHarness(name: "URLStale")
        let url = try XCTUnwrap(URL(string: "https://account.proton.me/u/0"))
        let diagnosticsBefore = SafariExtensionAutofillFillDiagnostics
            .snapshot().bucketCounts
        harness.manager.testHooks.permissionPromptDecision = {
            [inspection = harness.inspection] _, _, _ in
            _ = inspection.contextState.profiles.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
            return .allow(expirationDate: nil)
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        let result = await driveURLsPrompt([url], harness: harness)

        XCTAssertEqual(result.granted, [])
        XCTAssertNil(result.expiration)
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertFalse(harness.context.hasAccess(to: url))
        XCTAssertEqual(
            harness.inspection.actionPolicy.siteAccess.configuredSiteAccessLevel(
                for: url,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            ),
            .ask
        )
        XCTAssertNil(
            harness.inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .matchPattern,
                target: "https://account.proton.me/*"
            )
        )
        XCTAssertEqual(
            SafariExtensionAutofillFillDiagnostics.snapshot().bucketCounts,
            diagnosticsBefore
        )
    }

    // MARK: - URL family: exact current pair settles the prompt

    func testURLPromptWithCurrentEvidenceGrantsAndPersists() async throws {
        let harness = try await makeHarness(name: "URLGrant")
        let url = try XCTUnwrap(URL(string: "https://account.proton.me/u/0"))
        harness.manager.testHooks.permissionPromptDecision = { _, _, _ in
            .allow(expirationDate: nil)
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        let result = await driveURLsPrompt([url], harness: harness)

        XCTAssertEqual(result.granted, [url])
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertTrue(harness.context.hasAccess(to: url))
        XCTAssertEqual(
            harness.inspection.actionPolicy.siteAccess.configuredSiteAccessLevel(
                for: url,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            ),
            .allow
        )
        let stored = try XCTUnwrap(
            harness.inspection.actionPolicy.permissionDecisions.storedExtensionPermissionDecision(
                extensionId: harness.extensionID,
                profileId: harness.profileID,
                targetKind: .matchPattern,
                target: "https://account.proton.me/*"
            )
        )
        XCTAssertEqual(stored.state, .allowed)
    }

    // MARK: - Stored-decision fast path requires exact current evidence

    func testStoredDecisionFastPathRequiresExactCurrentEvidence() async throws {
        let harness = try await makeHarness(name: "StoredFastPath")
        let permission = WKWebExtension.Permission(rawValue: "cookies")
        harness.inspection.actionPolicy.permissionDecisions.persistExtensionPermissionDecision(
            extensionId: harness.extensionID,
            profileId: harness.profileID,
            targetKind: .permission,
            target: permission.rawValue,
            state: .allowed,
            expiresAt: nil
        )
        var promptCount = 0
        harness.manager.testHooks.permissionPromptDecision = { _, _, _ in
            promptCount += 1
            return .deny
        }
        defer { harness.manager.testHooks.permissionPromptDecision = nil }

        let foreignController = WKWebExtensionController(
            configuration: .nonPersistent()
        )
        let rejected = await drivePermissionsPrompt(
            [permission],
            harness: harness,
            controller: foreignController
        )

        XCTAssertEqual(rejected.granted, [])
        XCTAssertEqual(rejected.completionCalls, 1)
        XCTAssertEqual(
            harness.context.permissionStatus(for: permission),
            .unknown,
            "capture failure must not replay stored decisions"
        )

        let admitted = await drivePermissionsPrompt([permission], harness: harness)

        XCTAssertEqual(promptCount, 0, "stored decision must settle without a prompt")
        XCTAssertTrue(admitted.granted.contains(permission))
        XCTAssertEqual(admitted.completionCalls, 1)
        XCTAssertEqual(
            harness.context.permissionStatus(for: permission),
            .grantedExplicitly
        )
    }

    // MARK: - Harness

    private struct Harness {
        let manager: ExtensionManager
        let inspection: ExtensionManagerTestInspection
        let profileID: UUID
        let extensionID: String
        let context: WKWebExtensionContext
        let controller: WKWebExtensionController
    }

    private func makeHarness(name: String) async throws -> Harness {
        let container = try makeTestContainer()
        let profile = Profile(name: name)
        let inspection = ExtensionManagerInspectionCapture()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            testInspectionDidAssemble: inspection.install
        )
        let installed = try await installExtension(
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
        let controller = inspection.inspection.controller.provisioning
            .ensureExtensionController(for: profile.id)
        XCTAssertNotNil(
            inspection.inspection.controller.callbackAdmission.capture(
                context: context,
                controller: controller
            ),
            "harness must start from an admissible current binding"
        )
        return Harness(
            manager: manager,
            inspection: inspection.inspection,
            profileID: profile.id,
            extensionID: installed.id,
            context: context,
            controller: controller
        )
    }

    private func drivePermissionsPrompt(
        _ permissions: Set<WKWebExtension.Permission>,
        harness: Harness,
        controller: WKWebExtensionController? = nil
    ) async -> (
        granted: Set<WKWebExtension.Permission>,
        expiration: Date?,
        completionCalls: Int
    ) {
        var completionCalls = 0
        let settled: (Set<WKWebExtension.Permission>, Date?) =
            await withCheckedContinuation { continuation in
                harness.inspection.controller.delegateBridge.webExtensionController(
                    controller ?? harness.controller,
                    promptForPermissions: permissions,
                    in: nil,
                    for: harness.context
                ) { granted, expiration in
                    completionCalls += 1
                    if completionCalls == 1 {
                        continuation.resume(returning: (granted, expiration))
                    }
                }
            }
        await drainMainActorTurns()
        return (settled.0, settled.1, completionCalls)
    }

    private func driveMatchPatternsPrompt(
        _ matchPatterns: Set<WKWebExtension.MatchPattern>,
        harness: Harness,
        controller: WKWebExtensionController? = nil
    ) async -> (
        granted: Set<WKWebExtension.MatchPattern>,
        expiration: Date?,
        completionCalls: Int
    ) {
        var completionCalls = 0
        let settled: (Set<WKWebExtension.MatchPattern>, Date?) =
            await withCheckedContinuation { continuation in
                harness.inspection.controller.delegateBridge.webExtensionController(
                    controller ?? harness.controller,
                    promptForPermissionMatchPatterns: matchPatterns,
                    in: nil,
                    for: harness.context
                ) { granted, expiration in
                    completionCalls += 1
                    if completionCalls == 1 {
                        continuation.resume(returning: (granted, expiration))
                    }
                }
            }
        await drainMainActorTurns()
        return (settled.0, settled.1, completionCalls)
    }

    private func driveURLsPrompt(
        _ urls: Set<URL>,
        harness: Harness,
        controller: WKWebExtensionController? = nil
    ) async -> (
        granted: Set<URL>,
        expiration: Date?,
        completionCalls: Int
    ) {
        var completionCalls = 0
        let settled: (Set<URL>, Date?) =
            await withCheckedContinuation { continuation in
                harness.inspection.controller.delegateBridge.webExtensionController(
                    controller ?? harness.controller,
                    promptForPermissionToAccess: urls,
                    in: nil,
                    for: harness.context
                ) { granted, expiration in
                    completionCalls += 1
                    if completionCalls == 1 {
                        continuation.resume(returning: (granted, expiration))
                    }
                }
            }
        await drainMainActorTurns()
        return (settled.0, settled.1, completionCalls)
    }

    /// Gives any stray continuation of the settled callback a chance to run,
    /// so a double completion would be observed by the call counters.
    private func drainMainActorTurns() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func installExtension(
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
            "permissions": ["storage"],
            "optional_permissions": ["cookies"],
            "optional_host_permissions": [
                "https://account.proton.me/*",
                "https://pass.proton.me/*",
            ],
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

    private func makeUnrelatedExtensionContext() async throws
        -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Unrelated",
            "version": "1.0",
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        return WKWebExtensionContext(for: webExtension)
    }
}

/// Fires a main-actor rebind exactly once from a synchronous notification
/// observer; boxed so the `@Sendable` observer closure captures one value.
/// The attempt closure returns whether its firing condition was met.
private final class ReentrantRebindTrigger: @unchecked Sendable {
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
