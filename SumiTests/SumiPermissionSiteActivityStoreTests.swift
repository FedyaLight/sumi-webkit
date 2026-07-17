import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class SumiPermissionSiteActivityStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func setUp() {
        super.setUp()
        temporaryDirectories.removeAll()
    }

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testRetiredProfileCannotRecreateSiteActivityAfterCleanup() async throws {
        let authority = SumiPermissionPersistenceAuthority()
        let store = SumiPermissionSiteActivityStore(
            persistenceAuthority: authority
        )
        let antiAbuseStore = SumiPermissionAntiAbuseStore(
            persistenceAuthority: authority
        )
        let targetKey = siteActivityKey(
            .camera,
            profilePartitionId: "target-profile"
        )
        let retainedKey = siteActivityKey(
            .camera,
            profilePartitionId: "retained-profile"
        )
        for key in [targetKey, retainedKey] {
            store.recordSettingsChange(
                displayDomain: key.displayDomain,
                key: key,
                state: .allow,
                reason: "before-retirement"
            )
        }

        store.retireProfile("target-profile")
        try await authority.deleteProfileData(
            profilePartitionId: "target-profile"
        )
        store.recordSettingsChange(
            displayDomain: targetKey.displayDomain,
            key: targetKey,
            state: .deny,
            reason: "late-recreation"
        )
        store.recordSettingsChange(
            displayDomain: retainedKey.displayDomain,
            key: retainedKey,
            state: .deny,
            reason: "retained-profile-write"
        )
        await antiAbuseStore.record(
            SumiPermissionAntiAbuseEvent(
                type: .userDenied,
                key: targetKey
            )
        )
        await antiAbuseStore.record(
            SumiPermissionAntiAbuseEvent(
                type: .userDenied,
                key: retainedKey
            )
        )

        XCTAssertTrue(
            store.records(
                forSiteOf: targetKey.topOrigin,
                profilePartitionId: "target-profile",
                isEphemeralProfile: false
            ).isEmpty
        )
        XCTAssertEqual(
            store.records(
                forSiteOf: retainedKey.topOrigin,
                profilePartitionId: "retained-profile",
                isEphemeralProfile: false
            ).first?.reason,
            "retained-profile-write"
        )
        let targetEvents = await antiAbuseStore.events(
            for: targetKey,
            now: Date()
        )
        let retainedEvents = await antiAbuseStore.events(
            for: retainedKey,
            now: Date()
        )
        XCTAssertTrue(targetEvents.isEmpty)
        XCTAssertEqual(retainedEvents.count, 1)
    }

    func testFileBackedSnapshotPersistsAndReloadsRecords() async throws {
        let directory = try temporaryDirectory()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SumiSiteActivityFileTests-\(UUID().uuidString)"))
        let key = siteActivityKey(.camera)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let firstStore = SumiPermissionSiteActivityStore(
            storageDirectory: directory
        )
        firstStore.recordSettingsChange(
            displayDomain: "example.com",
            key: key,
            state: .allow,
            reason: "test-setting",
            now: now
        )
        await assertFlushSucceeds(firstStore.persistenceAuthority)

        let secondStore = SumiPermissionSiteActivityStore(
            storageDirectory: directory
        )
        let records = secondStore.records(
            forSiteOf: key.topOrigin,
            profilePartitionId: key.profilePartitionId,
            isEphemeralProfile: false
        )

        XCTAssertEqual(secondStore.persistenceDiagnostics.loadOutcome, .loadedFile)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.lastState, .allow)
        XCTAssertEqual(records.first?.reason, "test-setting")
    }

    func testCanonicalSnapshotCombinesAntiAbuseAndSiteActivityState() async throws {
        let directory = try temporaryDirectory()
        let authority = SumiPermissionPersistenceAuthority(
            storageDirectory: directory
        )
        let antiAbuseStore = SumiPermissionAntiAbuseStore(persistenceAuthority: authority)
        let siteActivityStore = SumiPermissionSiteActivityStore(persistenceAuthority: authority)
        let key = siteActivityKey(.camera)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        await antiAbuseStore.record(event(.userAllowed, key: key, at: now))
        siteActivityStore.recordSettingsChange(
            displayDomain: "example.com",
            key: key,
            state: .allow,
            reason: "shared-authority",
            now: now
        )

        await assertFlushSucceeds(authority)
        XCTAssertGreaterThanOrEqual(authority.persistenceDiagnostics.successfulWriteCount, 1)

        let canonicalURL = directory.appendingPathComponent(
            SumiPermissionPersistenceAuthority.canonicalFileName
        )
        let envelope = try JSONDecoder().decode(
            PermissionCanonicalEnvelope.self,
            from: Data(contentsOf: canonicalURL)
        )
        XCTAssertEqual(envelope.version, 1)
        XCTAssertEqual(envelope.generation, 2)
        XCTAssertEqual(envelope.antiAbuseEvents.map(\.type), [.userAllowed])
        XCTAssertEqual(envelope.siteActivityRecords.map(\.lastState), [.allow])
        let reloadedAuthority = SumiPermissionPersistenceAuthority(
            storageDirectory: directory
        )
        let reloadedAntiAbuseStore = SumiPermissionAntiAbuseStore(
            persistenceAuthority: reloadedAuthority
        )
        let reloadedSiteActivityStore = SumiPermissionSiteActivityStore(
            persistenceAuthority: reloadedAuthority
        )
        let reloadedEvents = await reloadedAntiAbuseStore.events(for: key, now: now)
        let reloadedRecords = reloadedSiteActivityStore.records(
            forSiteOf: key.topOrigin,
            profilePartitionId: key.profilePartitionId,
            isEphemeralProfile: false
        )

        XCTAssertEqual(reloadedAuthority.persistenceDiagnostics.loadOutcome, .loadedFile)
        XCTAssertEqual(reloadedEvents.map(\.type), [.userAllowed])
        XCTAssertEqual(reloadedRecords.map(\.reason), ["shared-authority"])
    }

    func testPublicationStageFailuresStayDirtyAndPreRenameFailuresKeepOldGeneration() async throws {
        for stage in SumiPermissionCanonicalSnapshotPublisher.Stage.allCases {
            let directory = try temporaryDirectory()
            let key = siteActivityKey(.camera)
            let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
            let baselineAuthority = SumiPermissionPersistenceAuthority(
                storageDirectory: directory
            )
            let baselineStore = SumiPermissionSiteActivityStore(
                persistenceAuthority: baselineAuthority
            )
            baselineStore.recordSettingsChange(
                displayDomain: "example.com",
                key: key,
                state: .allow,
                reason: "durable-generation",
                now: firstDate
            )
            await assertFlushSucceeds(baselineAuthority)

            let fault = OneShotPermissionPublishingFault(stage: stage)
            let failingAuthority = SumiPermissionPersistenceAuthority(
                storageDirectory: directory,
                publishingFaultInjector: { stage, _ in try fault.inject(at: stage) }
            )
            let failingStore = SumiPermissionSiteActivityStore(
                persistenceAuthority: failingAuthority
            )
            failingStore.recordSettingsChange(
                displayDomain: "example.com",
                key: key,
                state: .deny,
                reason: "failed-generation",
                now: firstDate.addingTimeInterval(60)
            )

            await assertFlushFails(failingAuthority)
            XCTAssertEqual(
                failingAuthority.persistenceDiagnostics.successfulWriteCount,
                0,
                "stage: \(stage)"
            )
            XCTAssertNotNil(
                failingAuthority.persistenceDiagnostics.lastWriteFailure,
                "stage: \(stage)"
            )

            let canonicalURL = directory.appendingPathComponent(
                SumiPermissionPersistenceAuthority.canonicalFileName
            )
            let durableEnvelope = try JSONDecoder().decode(
                PermissionCanonicalEnvelope.self,
                from: Data(contentsOf: canonicalURL)
            )
            if stage == .parentDirectorySync {
                // Rename is already visible, but the authority must not
                // acknowledge it until the directory entry is durable.
                XCTAssertEqual(durableEnvelope.generation, 2, "stage: \(stage)")
                XCTAssertEqual(
                    durableEnvelope.siteActivityRecords.map(\.reason),
                    ["failed-generation"],
                    "stage: \(stage)"
                )
            } else {
                XCTAssertEqual(durableEnvelope.generation, 1, "stage: \(stage)")
                XCTAssertEqual(
                    durableEnvelope.siteActivityRecords.map(\.reason),
                    ["durable-generation"],
                    "stage: \(stage)"
                )

                let restartedAuthority = SumiPermissionPersistenceAuthority(
                    storageDirectory: directory
                )
                let restartedStore = SumiPermissionSiteActivityStore(
                    persistenceAuthority: restartedAuthority
                )
                XCTAssertEqual(
                    restartedStore.records(
                        forSiteOf: key.topOrigin,
                        profilePartitionId: key.profilePartitionId,
                        isEphemeralProfile: false
                    ).map(\.reason),
                    ["durable-generation"],
                    "stage: \(stage)"
                )
            }

            await assertFlushSucceeds(failingAuthority)
            XCTAssertEqual(
                failingAuthority.persistenceDiagnostics.successfulWriteCount,
                1,
                "stage: \(stage)"
            )
            let retriedEnvelope = try JSONDecoder().decode(
                PermissionCanonicalEnvelope.self,
                from: Data(contentsOf: canonicalURL)
            )
            XCTAssertEqual(retriedEnvelope.generation, 2, "stage: \(stage)")
            XCTAssertEqual(
                retriedEnvelope.siteActivityRecords.map(\.reason),
                ["failed-generation"],
                "stage: \(stage)"
            )
        }
    }

    func testConvenienceStoresUseDistinctMemoryOnlyAuthorities() async {
        let firstStore = SumiPermissionSiteActivityStore()
        let secondStore = SumiPermissionSiteActivityStore()
        let key = siteActivityKey(.camera)

        XCTAssertFalse(firstStore.persistenceAuthority === secondStore.persistenceAuthority)
        firstStore.recordSettingsChange(
            displayDomain: "example.com",
            key: key,
            state: .allow,
            reason: "memory-only"
        )

        await assertFlushSucceeds(firstStore.persistenceAuthority)
        XCTAssertEqual(firstStore.persistenceDiagnostics.successfulWriteCount, 0)
    }

    private func assertFlushSucceeds(
        _ authority: SumiPermissionPersistenceAuthority,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let didFlush = await authority.flushPendingWrites()
        XCTAssertTrue(didFlush, file: file, line: line)
    }

    private func assertFlushFails(
        _ authority: SumiPermissionPersistenceAuthority,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let didFlush = await authority.flushPendingWrites()
        XCTAssertFalse(didFlush, file: file, line: line)
    }

    private func siteActivityKey(
        _ type: SumiPermissionType,
        profilePartitionId: String = "profile-a"
    ) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com/path"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            permissionType: type,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: false
        )
    }

    private func activityRecord(
        key: SumiPermissionKey,
        state: SumiPermissionState,
        reason: String,
        now: Date
    ) -> SumiPermissionSiteActivityRecord {
        SumiPermissionSiteActivityRecord(
            id: [
                key.profilePartitionId,
                "persistent",
                "example.com",
                key.permissionType.identity,
            ].joined(separator: "|"),
            profilePartitionId: key.profilePartitionId,
            isEphemeralProfile: false,
            siteHost: "example.com",
            displayDomain: "example.com",
            permissionType: key.permissionType,
            hasRequested: false,
            hasAutoDetected: false,
            hasResolvedPolicy: true,
            hasSettingsChange: true,
            lastState: state,
            autoplayPolicy: nil,
            source: .user,
            reason: reason,
            firstSeenAt: now,
            updatedAt: now,
            lastRequestedAt: nil,
            lastAutoDetectedAt: nil,
            lastResolvedAt: now,
            lastSettingsChangedAt: now,
            count: 1
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiSiteActivityStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }
}

private struct PermissionCanonicalEnvelope: Decodable {
    let version: Int
    let generation: UInt64
    let antiAbuseEvents: [SumiPermissionAntiAbuseEvent]
    let siteActivityRecords: [SumiPermissionSiteActivityRecord]
}

private enum PermissionPublishingFaultError: Error {
    case injected
}

private final class OneShotPermissionPublishingFault: @unchecked Sendable {
    private let lock = NSLock()
    private let failingStage: SumiPermissionCanonicalSnapshotPublisher.Stage
    private var hasFailed = false

    init(stage: SumiPermissionCanonicalSnapshotPublisher.Stage) {
        failingStage = stage
    }

    func inject(at stage: SumiPermissionCanonicalSnapshotPublisher.Stage) throws {
        lock.lock()
        defer { lock.unlock() }
        guard stage == failingStage, !hasFailed else { return }
        hasFailed = true
        throw PermissionPublishingFaultError.injected
    }
}

private final class FirstParentBarrierFailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var didFail = false
    private var urls: [URL] = []

    var attemptedURLs: [URL] {
        lock.withLock { urls }
    }

    func inject(
        at stage: SumiPermissionCanonicalSnapshotPublisher.Stage,
        url: URL
    ) throws {
        guard stage == .parentDirectorySync else { return }
        let shouldFail = lock.withLock {
            urls.append(url.standardizedFileURL)
            guard !didFail else { return false }
            didFail = true
            return true
        }
        if shouldFail {
            throw PermissionPublishingFaultError.injected
        }
    }
}
