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
        let authority = SumiPermissionPersistenceAuthority(
            userDefaults: nil
        )
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

    func testUnreadablePersistentPayloadIsPreservedForDiagnostics() throws {
        let suiteName = "SumiSiteActivityStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let storageKey = "permissions.siteActivity.v1"
        let unreadablePayload = Data("not-json".utf8)
        defaults.set(unreadablePayload, forKey: storageKey)

        _ = SumiPermissionSiteActivityStore(userDefaults: defaults)

        XCTAssertEqual(defaults.data(forKey: "\(storageKey).unreadable"), unreadablePayload)
    }

    func testFileBackedSnapshotPersistsAndReloadsRecords() async throws {
        let directory = try temporaryDirectory()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SumiSiteActivityFileTests-\(UUID().uuidString)"))
        let key = siteActivityKey(.camera)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let firstStore = SumiPermissionSiteActivityStore(
            userDefaults: defaults,
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
            userDefaults: defaults,
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
            userDefaults: nil,
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
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(
                    SumiPermissionPersistenceAuthority.legacyAntiAbuseFileName
                ).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(
                    SumiPermissionPersistenceAuthority.legacySiteActivityFileName
                ).path
            )
        )

        let reloadedAuthority = SumiPermissionPersistenceAuthority(
            userDefaults: nil,
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

    func testLegacyMigrationSelectsNewerCompleteDefaultsAndRetiresSources() async throws {
        let directory = try temporaryDirectory()
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "SumiPermissionLegacyMerge-\(UUID().uuidString)")
        )
        let antiAbuseStorageKey = "anti-abuse-\(UUID().uuidString)"
        let removedKey = siteActivityKey(.camera)
        let retainedKey = siteActivityKey(.microphone)
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = olderDate.addingTimeInterval(60)
        let removedEvent = SumiPermissionAntiAbuseEvent(
            id: "removed-event",
            type: .userDenied,
            key: removedKey,
            createdAt: olderDate
        )
        let olderRetainedEvent = SumiPermissionAntiAbuseEvent(
            id: "retained-event",
            type: .userDenied,
            key: retainedKey,
            createdAt: olderDate
        )
        let newerRetainedEvent = SumiPermissionAntiAbuseEvent(
            id: "retained-event",
            type: .userAllowed,
            key: retainedKey,
            createdAt: newerDate
        )
        let removedRecord = activityRecord(
            key: removedKey,
            state: .deny,
            reason: "removed-file-record",
            now: olderDate
        )
        let olderRetainedRecord = activityRecord(
            key: retainedKey,
            state: .deny,
            reason: "older-file-record",
            now: olderDate
        )
        let newerRetainedRecord = activityRecord(
            key: retainedKey,
            state: .allow,
            reason: "newer-defaults",
            now: newerDate
        )

        try JSONEncoder().encode(
            LegacyAntiAbuseEnvelope(
                version: 1,
                records: [removedEvent, olderRetainedEvent]
            )
        ).write(
            to: directory.appendingPathComponent(
                SumiPermissionPersistenceAuthority.legacyAntiAbuseFileName
            )
        )
        try JSONEncoder().encode(
            LegacySiteActivityEnvelope(
                version: 1,
                records: [removedRecord, olderRetainedRecord]
            )
        ).write(
            to: directory.appendingPathComponent(
                SumiPermissionPersistenceAuthority.legacySiteActivityFileName
            )
        )
        defaults.set(
            try JSONEncoder().encode([newerRetainedEvent]),
            forKey: antiAbuseStorageKey
        )
        defaults.set(
            try JSONEncoder().encode(
                LegacySiteActivityEnvelope(version: 1, records: [newerRetainedRecord])
            ),
            forKey: SumiPermissionPersistenceAuthority.legacySiteActivityStorageKey
        )

        let authority = SumiPermissionPersistenceAuthority(
            userDefaults: defaults,
            legacyAntiAbuseStorageKey: antiAbuseStorageKey,
            storageDirectory: directory
        )
        let antiAbuseStore = SumiPermissionAntiAbuseStore(persistenceAuthority: authority)
        let siteActivityStore = SumiPermissionSiteActivityStore(persistenceAuthority: authority)
        let removedEvents = await antiAbuseStore.events(for: removedKey, now: newerDate)
        let retainedEvents = await antiAbuseStore.events(for: retainedKey, now: newerDate)
        let loadedRecords = siteActivityStore.records(
            forSiteOf: retainedKey.topOrigin,
            profilePartitionId: retainedKey.profilePartitionId,
            isEphemeralProfile: false
        )

        XCTAssertEqual(authority.persistenceDiagnostics.loadOutcome, .loadedLegacySnapshots)
        XCTAssertTrue(removedEvents.isEmpty)
        XCTAssertEqual(retainedEvents.map(\.type), [.userAllowed])
        XCTAssertEqual(loadedRecords.map(\.permissionType), [.microphone])
        XCTAssertEqual(loadedRecords.map(\.reason), ["newer-defaults"])
        XCTAssertNotNil(defaults.data(forKey: antiAbuseStorageKey))
        XCTAssertNotNil(
            defaults.data(forKey: SumiPermissionPersistenceAuthority.legacySiteActivityStorageKey)
        )
        let legacyAntiAbuseURL = directory.appendingPathComponent(
            SumiPermissionPersistenceAuthority.legacyAntiAbuseFileName
        )
        let legacySiteActivityURL = directory.appendingPathComponent(
            SumiPermissionPersistenceAuthority.legacySiteActivityFileName
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyAntiAbuseURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacySiteActivityURL.path))

        await assertFlushSucceeds(authority)
        XCTAssertNil(defaults.data(forKey: antiAbuseStorageKey))
        XCTAssertNil(
            defaults.data(forKey: SumiPermissionPersistenceAuthority.legacySiteActivityStorageKey)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyAntiAbuseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacySiteActivityURL.path))
    }

    func testCorruptLegacyAntiAbuseDoesNotDiscardValidSiteActivity() async throws {
        let directory = try temporaryDirectory()
        let antiAbuseURL = directory.appendingPathComponent(
            SumiPermissionPersistenceAuthority.legacyAntiAbuseFileName
        )
        let siteActivityURL = directory.appendingPathComponent(
            SumiPermissionPersistenceAuthority.legacySiteActivityFileName
        )
        try Data("not-json".utf8).write(to: antiAbuseURL)
        let key = siteActivityKey(.camera)
        try JSONEncoder().encode(
            LegacySiteActivityEnvelope(
                version: 1,
                records: [
                    activityRecord(
                        key: key,
                        state: .allow,
                        reason: "valid-site-domain",
                        now: Date(timeIntervalSince1970: 1_800_000_000)
                    ),
                ]
            )
        ).write(to: siteActivityURL)

        let authority = SumiPermissionPersistenceAuthority(
            userDefaults: nil,
            storageDirectory: directory
        )
        let siteActivityStore = SumiPermissionSiteActivityStore(
            persistenceAuthority: authority
        )

        XCTAssertEqual(
            siteActivityStore.records(
                forSiteOf: key.topOrigin,
                profilePartitionId: key.profilePartitionId,
                isEphemeralProfile: false
            ).map(\.reason),
            ["valid-site-domain"]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: antiAbuseURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: antiAbuseURL.appendingPathExtension("unreadable").path
            )
        )
        XCTAssertEqual(authority.persistenceDiagnostics.loadOutcome, .loadedLegacySnapshots)
        await assertFlushSucceeds(authority)
    }

    func testLegacyDefaultsRetireOnlyAfterCanonicalWriteSucceeds() async throws {
        let blockingStorageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiPermissionBlockedStorage-\(UUID().uuidString)")
        temporaryDirectories.append(blockingStorageURL)
        try Data("blocks-directory-creation".utf8).write(to: blockingStorageURL)
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "SumiPermissionBlockedMigration-\(UUID().uuidString)")
        )
        let antiAbuseStorageKey = "anti-abuse-\(UUID().uuidString)"
        let legacyData = try JSONEncoder().encode([
            event(
                .userDismissed,
                key: siteActivityKey(.camera),
                at: Date(timeIntervalSince1970: 1_800_000_000)
            ),
        ])
        defaults.set(legacyData, forKey: antiAbuseStorageKey)

        let authority = SumiPermissionPersistenceAuthority(
            userDefaults: defaults,
            legacyAntiAbuseStorageKey: antiAbuseStorageKey,
            storageDirectory: blockingStorageURL
        )

        await assertFlushFails(authority)
        XCTAssertEqual(defaults.data(forKey: antiAbuseStorageKey), legacyData)
        XCTAssertNotNil(authority.persistenceDiagnostics.lastWriteFailure)

        try FileManager.default.removeItem(at: blockingStorageURL)
        try FileManager.default.createDirectory(
            at: blockingStorageURL,
            withIntermediateDirectories: true
        )
        await assertFlushSucceeds(authority)
        XCTAssertNil(defaults.data(forKey: antiAbuseStorageKey))
    }

    func testFailedWriteDoesNotFallbackToDefaultsOrResurrectStaleStateOnRestart() async throws {
        let directory = try temporaryDirectory()
        let durableDirectory = directory.appendingPathExtension("durable")
        defer { try? FileManager.default.removeItem(at: durableDirectory) }
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "SumiPermissionWriteFailure-\(UUID().uuidString)")
        )
        let antiAbuseStorageKey = "anti-abuse-\(UUID().uuidString)"
        let authority = SumiPermissionPersistenceAuthority(
            userDefaults: defaults,
            legacyAntiAbuseStorageKey: antiAbuseStorageKey,
            storageDirectory: directory
        )
        let antiAbuseStore = SumiPermissionAntiAbuseStore(persistenceAuthority: authority)
        let siteActivityStore = SumiPermissionSiteActivityStore(persistenceAuthority: authority)
        let key = siteActivityKey(.camera)
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let durableDate = firstDate.addingTimeInterval(60)
        let failedDate = durableDate.addingTimeInterval(60)

        await antiAbuseStore.record(
            SumiPermissionAntiAbuseEvent(
                id: "durable-first",
                type: .promptShown,
                key: key,
                createdAt: firstDate
            )
        )
        siteActivityStore.recordSettingsChange(
            displayDomain: "example.com",
            key: key,
            state: .allow,
            reason: "first-durable",
            now: firstDate
        )
        await assertFlushSucceeds(authority)

        await antiAbuseStore.record(
            SumiPermissionAntiAbuseEvent(
                id: "durable-newest",
                type: .userAllowed,
                key: key,
                createdAt: durableDate
            )
        )
        siteActivityStore.recordSettingsChange(
            displayDomain: "example.com",
            key: key,
            state: .allow,
            reason: "newest-durable",
            now: durableDate
        )
        await assertFlushSucceeds(authority)

        let staleAntiAbuseData = try JSONEncoder().encode([
            SumiPermissionAntiAbuseEvent(
                id: "stale-defaults",
                type: .userDenied,
                key: key,
                createdAt: firstDate.addingTimeInterval(-60)
            ),
        ])
        let staleSiteActivityData = try JSONEncoder().encode(
            LegacySiteActivityEnvelope(
                version: 1,
                records: [
                    activityRecord(
                        key: key,
                        state: .deny,
                        reason: "stale-defaults",
                        now: firstDate.addingTimeInterval(-60)
                    ),
                ]
            )
        )
        defaults.set(staleAntiAbuseData, forKey: antiAbuseStorageKey)
        defaults.set(
            staleSiteActivityData,
            forKey: SumiPermissionPersistenceAuthority.legacySiteActivityStorageKey
        )

        try FileManager.default.moveItem(at: directory, to: durableDirectory)
        try Data("blocks-directory-creation".utf8).write(to: directory)
        await antiAbuseStore.record(
            SumiPermissionAntiAbuseEvent(
                id: "failed-newest",
                type: .userDenied,
                key: key,
                createdAt: failedDate
            )
        )
        siteActivityStore.recordSettingsChange(
            displayDomain: "example.com",
            key: key,
            state: .deny,
            reason: "failed-newest",
            now: failedDate
        )

        await assertFlushFails(authority)
        XCTAssertEqual(defaults.data(forKey: antiAbuseStorageKey), staleAntiAbuseData)
        XCTAssertEqual(
            defaults.data(forKey: SumiPermissionPersistenceAuthority.legacySiteActivityStorageKey),
            staleSiteActivityData
        )

        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: durableDirectory, to: directory)
        let restartedAuthority = SumiPermissionPersistenceAuthority(
            userDefaults: defaults,
            legacyAntiAbuseStorageKey: antiAbuseStorageKey,
            storageDirectory: directory
        )
        let restartedAntiAbuseStore = SumiPermissionAntiAbuseStore(
            persistenceAuthority: restartedAuthority
        )
        let restartedSiteActivityStore = SumiPermissionSiteActivityStore(
            persistenceAuthority: restartedAuthority
        )
        let restartedEvents = await restartedAntiAbuseStore.events(for: key, now: failedDate)
        let restartedRecords = restartedSiteActivityStore.records(
            forSiteOf: key.topOrigin,
            profilePartitionId: key.profilePartitionId,
            isEphemeralProfile: false
        )

        XCTAssertEqual(restartedAuthority.persistenceDiagnostics.loadOutcome, .loadedFile)
        XCTAssertEqual(restartedEvents.map(\.id), ["durable-first", "durable-newest"])
        XCTAssertEqual(restartedRecords.map(\.lastState), [.allow])
        XCTAssertEqual(restartedRecords.map(\.reason), ["newest-durable"])
    }

    func testPublicationStageFailuresStayDirtyAndPreRenameFailuresKeepOldGeneration() async throws {
        for stage in SumiPermissionCanonicalSnapshotPublisher.Stage.allCases {
            let directory = try temporaryDirectory()
            let key = siteActivityKey(.camera)
            let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
            let baselineAuthority = SumiPermissionPersistenceAuthority(
                userDefaults: nil,
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
                userDefaults: nil,
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
                    userDefaults: nil,
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

    func testLegacySourcesRetireOnlyAfterEveryPublicationStageSucceeds() async throws {
        for stage in SumiPermissionCanonicalSnapshotPublisher.Stage.allCases {
            let directory = try temporaryDirectory()
            let defaults = try XCTUnwrap(
                UserDefaults(suiteName: "SumiPermissionStageMigration-\(UUID().uuidString)")
            )
            let antiAbuseStorageKey = "anti-abuse-\(UUID().uuidString)"
            let legacyData = try JSONEncoder().encode([
                event(
                    .userDismissed,
                    key: siteActivityKey(.camera),
                    at: Date(timeIntervalSince1970: 1_800_000_000)
                ),
            ])
            defaults.set(legacyData, forKey: antiAbuseStorageKey)
            let fault = OneShotPermissionPublishingFault(stage: stage)
            let authority = SumiPermissionPersistenceAuthority(
                userDefaults: defaults,
                legacyAntiAbuseStorageKey: antiAbuseStorageKey,
                storageDirectory: directory,
                publishingFaultInjector: { stage, _ in try fault.inject(at: stage) }
            )
            let canonicalURL = directory.appendingPathComponent(
                SumiPermissionPersistenceAuthority.canonicalFileName
            )

            await assertFlushFails(authority)
            XCTAssertEqual(
                defaults.data(forKey: antiAbuseStorageKey),
                legacyData,
                "stage: \(stage)"
            )
            XCTAssertEqual(authority.persistenceDiagnostics.successfulWriteCount, 0)
            XCTAssertNotNil(authority.persistenceDiagnostics.lastWriteFailure)
            if stage != .parentDirectorySync {
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: canonicalURL.path),
                    "stage: \(stage)"
                )
            }

            await assertFlushSucceeds(authority)
            XCTAssertNil(defaults.data(forKey: antiAbuseStorageKey), "stage: \(stage)")
            XCTAssertEqual(authority.persistenceDiagnostics.successfulWriteCount, 1)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: canonicalURL.path),
                "stage: \(stage)"
            )
        }
    }

    func testParentBarrierRetryRetainsFirstTimeCreatedAncestorChain() async throws {
        let existingBaseDirectory = try temporaryDirectory()
        let appRootDirectory = existingBaseDirectory.appendingPathComponent(
            "app-root",
            isDirectory: true
        )
        let permissionDirectory = appRootDirectory.appendingPathComponent(
            "Permissions",
            isDirectory: true
        )
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "SumiPermissionDirectoryRetry-\(UUID().uuidString)")
        )
        let antiAbuseStorageKey = "anti-abuse-\(UUID().uuidString)"
        let legacyData = try JSONEncoder().encode([
            event(
                .userDismissed,
                key: siteActivityKey(.camera),
                at: Date(timeIntervalSince1970: 1_800_000_000)
            ),
        ])
        defaults.set(legacyData, forKey: antiAbuseStorageKey)
        let barrierRecorder = FirstParentBarrierFailureRecorder()
        let authority = SumiPermissionPersistenceAuthority(
            userDefaults: defaults,
            legacyAntiAbuseStorageKey: antiAbuseStorageKey,
            storageDirectory: permissionDirectory,
            publishingFaultInjector: { stage, url in
                try barrierRecorder.inject(at: stage, url: url)
            }
        )

        await assertFlushFails(authority)
        XCTAssertEqual(barrierRecorder.attemptedURLs, [permissionDirectory.standardizedFileURL])
        XCTAssertEqual(defaults.data(forKey: antiAbuseStorageKey), legacyData)

        await assertFlushSucceeds(authority)

        XCTAssertEqual(
            Array(barrierRecorder.attemptedURLs.dropFirst()),
            [
                permissionDirectory,
                appRootDirectory,
                existingBaseDirectory,
            ].map(\.standardizedFileURL)
        )
        XCTAssertEqual(authority.persistenceDiagnostics.successfulWriteCount, 1)
        XCTAssertNil(defaults.data(forKey: antiAbuseStorageKey))
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

    func testUnreadableFilePayloadIsPreservedForDiagnostics() throws {
        let directory = try temporaryDirectory()
        let payloadURL = directory.appendingPathComponent("permission-site-activity.v1.json")
        let unreadablePayload = Data("not-json".utf8)
        try unreadablePayload.write(to: payloadURL)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SumiSiteActivityUnreadableFile-\(UUID().uuidString)"))

        let store = SumiPermissionSiteActivityStore(
            userDefaults: defaults,
            storageDirectory: directory
        )

        XCTAssertTrue(
            store.records(
                forSiteOf: SumiPermissionOrigin(string: "https://example.com"),
                profilePartitionId: "profile-a",
                isEphemeralProfile: false
            ).isEmpty
        )
        XCTAssertEqual(try Data(contentsOf: payloadURL), unreadablePayload)
        XCTAssertEqual(try Data(contentsOf: payloadURL.appendingPathExtension("unreadable")), unreadablePayload)
        if case .failedFileDecode = store.persistenceDiagnostics.loadOutcome {
            // Expected classification.
        } else {
            XCTFail("Expected failed file decode, got \(store.persistenceDiagnostics.loadOutcome)")
        }
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

private struct LegacyAntiAbuseEnvelope: Codable {
    let version: Int
    let records: [SumiPermissionAntiAbuseEvent]
}

private struct LegacySiteActivityEnvelope: Codable {
    let version: Int
    let records: [SumiPermissionSiteActivityRecord]
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
