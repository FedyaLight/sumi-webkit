import SwiftData
import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class BrowserManagerStartupPersistenceTests: XCTestCase {
    func testProductionCompositionKeepsOneStartupPersistenceIdentity() {
        XCTAssertIdentical(
            BrowserManagerStartupPersistence.production,
            SumiStartupPersistenceComposition.browserManagerStartupPersistence
        )
        XCTAssertIdentical(
            BrowserConfiguration.shared.autoplayPolicyStore,
            BrowserManagerStartupPersistence.production.autoplayPolicyStore
        )
    }

    func testDefaultTestBrowserManagerWindowSessionPersistenceIsIsolatedFromProductionKey()
        throws {
        let productionData = UserDefaults.standard.data(
            forKey: BrowserManager.lastWindowSessionKey
        )
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let snapshot = WindowSessionSnapshotFactory(
            glanceManager: browserManager.glanceManager
        ).make(for: windowState)

        XCTAssertTrue(
            browserManager.windowSessionPersistence.snapshotStore
                .persist(snapshot)
        )

        XCTAssertEqual(
            UserDefaults.standard.data(
                forKey: BrowserManager.lastWindowSessionKey
            ),
            productionData
        )
        guard case .loaded = browserManager.windowSessionPersistence
            .snapshotStore.loadResult() else {
            return XCTFail("Isolated test window-session store did not persist")
        }
    }

    func testOwnedTestWindowSessionDefaultsCleanTheirSuiteOnRelease() throws {
        var userDefaults: TestOwnedWindowSessionUserDefaults? =
            TestOwnedWindowSessionUserDefaults()
        let suiteName = try XCTUnwrap(userDefaults).ownedSuiteName
        userDefaults?.set("fixture", forKey: "window-session")
        XCTAssertFalse(
            UserDefaults.standard.persistentDomain(forName: suiteName)?
                .isEmpty ?? true
        )

        userDefaults = nil

        XCTAssertTrue(
            UserDefaults.standard.persistentDomain(forName: suiteName)?
                .isEmpty ?? true
        )
    }

    func testInjectedStartupPersistenceSuppliesManagerContexts() throws {
        let container = try makeInMemoryStartupContainer()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(container: container)
        )

        XCTAssertIdentical(browserManager.modelContext.container, container)
        XCTAssertIdentical(browserManager.profileManager.context.container, container)
        XCTAssertIdentical(browserManager.modelContext.container, container)
        XCTAssertNotNil(browserManager.currentProfile)
    }

    func testInjectedStartupPersistenceSuppliesDefaultPermissionStore() async throws {
        let container = try makeInMemoryStartupContainer()
        let startupPersistence = BrowserManagerStartupPersistence(container: container)
        let browserManager = BrowserManager(
            startupPersistence: startupPersistence
        )
        let key = permissionKey(profilePartitionId: browserManager.currentProfile!.id.uuidString)

        try await browserManager.permissionRuntime.permissionCoordinator.setSiteDecision(
            for: key,
            state: .deny,
            source: .user,
            reason: "startup-persistence-test"
        )

        let records = try await SwiftDataPermissionStore(container: container)
            .listDecisions(profilePartitionId: key.profilePartitionId)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.key, key)
        XCTAssertEqual(records.first?.decision.state, .deny)
        XCTAssertEqual(records.first?.decision.reason, "startup-persistence-test")
    }

    func testInjectedStartupPersistenceSharesOnePermissionStoreWithBrowserConfiguration() throws {
        let container = try makeInMemoryStartupContainer()
        let startupPersistence = BrowserManagerStartupPersistence(container: container)
        let browserManager = BrowserManager(startupPersistence: startupPersistence)

        XCTAssertIdentical(
            browserManager.browserConfiguration.autoplayPolicyStore,
            browserManager.permissionRuntime.autoplayStore
        )
        XCTAssertIdentical(
            startupPersistence.autoplayPolicyStore,
            browserManager.permissionRuntime.autoplayStore
        )
        XCTAssertTrue(
            (startupPersistence.permissionStore as AnyObject)
                === (browserManager.permissionRuntime.autoplayStore.permissionStore as AnyObject)
        )
    }

    func testInjectedStartupPersistenceSuppliesAutoplayConfigurationStore() async throws {
        let container = try makeInMemoryStartupContainer()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(container: container)
        )
        let profile = try XCTUnwrap(browserManager.currentProfile)
        let url = try XCTUnwrap(URL(string: "https://video.example"))

        try await browserManager.browserConfiguration.autoplayPolicyStore.setPolicy(
            .blockAll,
            for: url,
            profile: profile
        )

        let records = try await SwiftDataPermissionStore(container: container)
            .listDecisions(profilePartitionId: profile.id.uuidString)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.key.permissionType, .autoplay)
        XCTAssertEqual(
            browserManager.browserConfiguration.resolvedAutoplayPolicy(
                for: url,
                profile: profile
            ),
            .blockAll
        )
        XCTAssertEqual(
            TabBrowserNavigationRuntimeFactory.navigationDelegateRuntime(
                for: browserManager
            ).autoplayPolicy(url, profile),
            .blockAll
        )
    }

    func testRetiredProfileTombstoneSealsPermissionsBeforeRuntimeStarts() async throws {
        let container = try makeInMemoryStartupContainer()
        let target = Profile(name: "Retired", icon: "Retired icon")
        let retained = Profile(name: "Retained", icon: "Retained icon")
        try persistProfiles([retained, target], in: container)
        try persistRetiredTombstone(
            for: target,
            fallbackID: retained.id,
            in: container
        )

        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(container: container),
            notificationService: FakeSumiNotificationService()
        )

        XCTAssertNotNil(browserManager.runtimePortConnection.current)
        XCTAssertFalse(browserManager.permissionRuntime.isObservingPermissionEvents)
        XCTAssertEqual(browserManager.currentProfile?.id, retained.id)
        XCTAssertFalse(
            browserManager.profileManager.profiles.contains { $0.id == target.id }
        )

        _ = try await browserManager.profileLifecycleBundle
            .retirementStartupRecovery.recover()

        let targetKey = permissionKey(
            profilePartitionId: target.id.uuidString
        )
        let retainedKey = permissionKey(
            profilePartitionId: retained.id.uuidString
        )
        let targetIsRetired = await browserManager.permissionRuntime
            .permissionCoordinator.isProfileRetired(
                target.id.uuidString
            )
        XCTAssertTrue(
            targetIsRetired
        )
        do {
            try await browserManager.permissionRuntime.permissionCoordinator
                .setSiteDecision(
                    for: targetKey,
                    state: .allow,
                    source: .user,
                    reason: "retired-profile-restart-regression"
                )
            XCTFail("Retired profile accepted a permission write after recovery")
        } catch SumiPermissionSiteDecisionError.unavailable {}

        let autoplayURL = try XCTUnwrap(
            URL(string: "https://retired-profile.example/video")
        )
        do {
            try await browserManager.permissionRuntime.autoplayStore.setPolicy(
                .allowAll,
                for: autoplayURL,
                profile: target
            )
            XCTFail("Retired profile accepted an autoplay write after recovery")
        } catch SumiPermissionSiteDecisionError.unavailable {}

        try await browserManager.permissionRuntime.permissionCoordinator
            .setSiteDecision(
                for: retainedKey,
                state: .allow,
                source: .user,
                reason: "retained-profile-restart-regression"
            )
        try await browserManager.permissionRuntime.autoplayStore.setPolicy(
            .allowAll,
            for: autoplayURL,
            profile: retained
        )

        browserManager.startRuntimeAfterStartupRecovery()
        XCTAssertTrue(browserManager.permissionRuntime.isObservingPermissionEvents)
    }

    func testFailedRetiredProfileRecoveryDoesNotStartRuntime() async throws {
        let container = try makeInMemoryStartupContainer()
        let target = Profile(name: "Retired", icon: "Retired icon")
        let retained = Profile(name: "Retained", icon: "Retained icon")
        try persistProfiles([retained, target], in: container)
        try persistRetiredTombstone(
            for: target,
            fallbackID: retained.id,
            in: container
        )
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(container: container),
            notificationService: FailingRetirementNotificationService()
        )

        XCTAssertFalse(browserManager.permissionRuntime.isObservingPermissionEvents)
        let report = try await browserManager.profileLifecycleBundle
            .retirementStartupRecovery.recover()
        XCTAssertEqual(report.issues.map(\.profileID), [target.id])
        XCTAssertTrue(report.hasDeferredRecovery)
        XCTAssertFalse(browserManager.permissionRuntime.isObservingPermissionEvents)
    }

    func testStartupRecoveryTransactionClaimsConcurrentScenesExactlyOnce() async {
        let transaction = SumiStartupRecoveryTransaction()
        let suspension = StartupRecoverySuspension()
        var profileRecoveryCount = 0
        var importRecoveryCount = 0
        var runtimeStartCount = 0

        let first = Task { @MainActor in
            await transaction.recoverIfNeeded(
                preflight: .ready,
                recoverProfileRetirement: {
                    profileRecoveryCount += 1
                    await suspension.wait()
                    return ProfileRetirementStartupRecoveryReport()
                },
                recoverImport: {
                    importRecoveryCount += 1
                    return nil
                },
                startRuntime: {
                    runtimeStartCount += 1
                }
            )
        }
        await suspension.waitUntilSuspended()

        let second = Task { @MainActor in
            await transaction.recoverIfNeeded(
                preflight: .ready,
                recoverProfileRetirement: {
                    profileRecoveryCount += 1
                    return ProfileRetirementStartupRecoveryReport()
                },
                recoverImport: {
                    importRecoveryCount += 1
                    return nil
                },
                startRuntime: {
                    runtimeStartCount += 1
                }
            )
        }
        _ = await second.value
        XCTAssertEqual(profileRecoveryCount, 1)
        XCTAssertEqual(importRecoveryCount, 0)
        XCTAssertEqual(runtimeStartCount, 0)

        suspension.resume()
        _ = await first.value

        XCTAssertEqual(profileRecoveryCount, 1)
        XCTAssertEqual(importRecoveryCount, 1)
        XCTAssertEqual(runtimeStartCount, 1)
        guard case .ready = transaction.state else {
            return XCTFail("Successful startup recovery did not become ready")
        }
    }

    func testStartupRecoveryTransactionRunsStagesInOrder() async {
        let transaction = SumiStartupRecoveryTransaction()
        var events: [String] = []

        let outcome = await transaction.recoverIfNeeded(
            preflight: .ready,
            recoverProfileRetirement: {
                events.append("profile retirement")
                return ProfileRetirementStartupRecoveryReport()
            },
            recoverImport: {
                events.append("import")
                return nil
            },
            hasSafeProfile: {
                events.append("safe profile")
                return true
            },
            startRuntime: {
                events.append("runtime")
            }
        )

        guard case .recovered = outcome else {
            return XCTFail("Ordered startup recovery did not complete")
        }
        XCTAssertEqual(
            events,
            ["profile retirement", "safe profile", "import", "runtime"]
        )
    }

    func testStartupRecoveryTransactionFailureIsTerminalAndNeverStartsRuntime()
        async {
        let transaction = SumiStartupRecoveryTransaction()
        var profileRecoveryCount = 0
        var importRecoveryCount = 0
        var runtimeStartCount = 0

        _ = await transaction.recoverIfNeeded(
            preflight: .ready,
            recoverProfileRetirement: {
                profileRecoveryCount += 1
                throw StartupRecoveryTestError.failed
            },
            recoverImport: {
                importRecoveryCount += 1
                return nil
            },
            startRuntime: {
                runtimeStartCount += 1
            }
        )
        _ = await transaction.recoverIfNeeded(
            preflight: .ready,
            recoverProfileRetirement: {
                profileRecoveryCount += 1
                return ProfileRetirementStartupRecoveryReport()
            },
            recoverImport: {
                importRecoveryCount += 1
                return nil
            },
            startRuntime: {
                runtimeStartCount += 1
            }
        )

        XCTAssertEqual(profileRecoveryCount, 1)
        XCTAssertEqual(importRecoveryCount, 0)
        XCTAssertEqual(runtimeStartCount, 0)
        guard case .failed = transaction.state else {
            return XCTFail("Failed startup recovery did not remain terminal")
        }
    }

    func testDeferredProfileRecoveryStillStartsRuntime() async {
        let transaction = SumiStartupRecoveryTransaction()
        let profileID = UUID()
        var importRecoveryCount = 0
        var runtimeStartCount = 0
        let report = ProfileRetirementStartupRecoveryReport(
            issues: [
                ProfileRetirementRecoveryIssue(
                    profileID: profileID,
                    phase: ProfileRetirementPhase.cleaning.rawValue,
                    kind: .cleanup,
                    reason: "Deferred test cleanup",
                    requiresReferenceSanitization: false
                )
            ]
        )

        let outcome = await transaction.recoverIfNeeded(
            preflight: .ready,
            recoverProfileRetirement: { report },
            recoverImport: {
                importRecoveryCount += 1
                return nil
            },
            hasSafeProfile: { true },
            startRuntime: {
                runtimeStartCount += 1
            }
        )

        guard case .recovered(_, let recoveredReport) = outcome else {
            return XCTFail("Deferred retirement should not fail startup")
        }
        XCTAssertEqual(recoveredReport, report)
        XCTAssertEqual(importRecoveryCount, 1)
        XCTAssertEqual(runtimeStartCount, 1)
        guard case .ready = transaction.state else {
            return XCTFail("Deferred retirement did not become ready")
        }
    }

    func testStartupRecoveryWithoutSafeProfileRemainsTerminal() async {
        let transaction = SumiStartupRecoveryTransaction()
        var importRecoveryCount = 0
        var runtimeStartCount = 0

        _ = await transaction.recoverIfNeeded(
            preflight: .ready,
            recoverProfileRetirement: {
                ProfileRetirementStartupRecoveryReport()
            },
            recoverImport: {
                importRecoveryCount += 1
                return nil
            },
            hasSafeProfile: { false },
            startRuntime: {
                runtimeStartCount += 1
            }
        )

        XCTAssertEqual(importRecoveryCount, 0)
        XCTAssertEqual(runtimeStartCount, 0)
        guard case .failed = transaction.state else {
            return XCTFail("Missing safe profile should remain terminal")
        }
    }

    func testExplicitBrowserConfigurationRemainsTheCanonicalPermissionOverride() async throws {
        let startupContainer = try makeInMemoryStartupContainer()
        let overrideContainer = try makeInMemoryStartupContainer()
        let overrideStore = SwiftDataPermissionStore(container: overrideContainer)
        let overrideAutoplayStore = SumiAutoplayPolicyStoreAdapter(
            persistentStore: overrideStore
        )
        let browserConfiguration = BrowserConfiguration(
            autoplayPolicyStore: overrideAutoplayStore
        )
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: startupContainer
            ),
            browserConfiguration: browserConfiguration
        )
        let profile = try XCTUnwrap(browserManager.currentProfile)
        let url = try XCTUnwrap(URL(string: "https://override.example"))

        XCTAssertIdentical(browserManager.browserConfiguration, browserConfiguration)
        XCTAssertIdentical(browserManager.permissionRuntime.autoplayStore, overrideAutoplayStore)

        try await browserManager.permissionRuntime.autoplayStore.setPolicy(
            .blockAudible,
            for: url,
            profile: profile
        )

        let overrideRecords = try await overrideStore.listDecisions(
            profilePartitionId: profile.id.uuidString
        )
        let startupRecords = try await SwiftDataPermissionStore(container: startupContainer)
            .listDecisions(profilePartitionId: profile.id.uuidString)
        XCTAssertEqual(overrideRecords.count, 1)
        XCTAssertTrue(startupRecords.isEmpty)
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func persistProfiles(
        _ profiles: [Profile],
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        for (index, profile) in profiles.enumerated() {
            context.insert(
                ProfileEntity(
                    id: profile.id,
                    name: profile.name,
                    icon: profile.icon,
                    index: index
                )
            )
        }
        try context.save()
    }

    private func persistRetiredTombstone(
        for profile: Profile,
        fallbackID: UUID,
        in container: ModelContainer
    ) throws {
        let ledger = try ProfileReferenceAdmissionLedger(
            context: ModelContext(container)
        )
        let token = try ledger.reserve(
            profile: profile,
            fallbackID: fallbackID
        )
        XCTAssertTrue(try ledger.beginReferenceMigration(token))
        XCTAssertTrue(try ledger.commitLogicalDeletion(token))
        XCTAssertTrue(try ledger.beginCleaning(token))
        for step in ProfileRetirementCleanupStep.ordered {
            XCTAssertTrue(try ledger.completeCleanupStep(step, using: token))
        }
        XCTAssertTrue(try ledger.markRetired(token))
    }

    private func permissionKey(profilePartitionId: String) -> SumiPermissionKey {
        let origin = SumiPermissionOrigin(string: "https://example.com")
        return SumiPermissionKey(
            requestingOrigin: origin,
            topOrigin: origin,
            permissionType: .geolocation,
            profilePartitionId: profilePartitionId
        )
    }
}

private actor FailingRetirementNotificationService: SumiNotificationServicing {
    func post(
        _ payload: SumiNotificationPayload
    ) async -> SumiNotificationDeliveryResult {
        .failed(identifier: payload.identifier, reason: "test-only")
    }

    func close(identifier _: SumiNotificationIdentifier) async {}

    func retireProfile(profilePartitionId _: String) async -> Bool {
        false
    }
}

@MainActor
private final class StartupRecoverySuspension {
    private var continuation: CheckedContinuation<Void, Never>?
    private var suspendedWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let waiters = suspendedWaiters
            suspendedWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilSuspended() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { continuation in
            suspendedWaiters.append(continuation)
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private enum StartupRecoveryTestError: Error {
    case failed
}
