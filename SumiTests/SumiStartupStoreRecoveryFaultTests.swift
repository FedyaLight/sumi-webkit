import XCTest

@testable import Sumi

@MainActor
extension SumiStartupPersistenceTests {
    func testEveryRestoreTransitionFailureBlocksRecoveryOpenAndResumes() throws {
        for failingOperation in StartupRecoveryOperationFixtures.restore {
            let fixture = try makeFaultStoreFixture()
            var didInjectFailure = false
            var openAttempts = 0

            XCTAssertThrowsError(
                try SumiStartupPersistence.makePersistentContainerForStartup(
                    storeURL: fixture.storeURL,
                    quarantineRootURL: fixture.quarantineRootURL,
                    performRecoveryOperation: { operation, body in
                        if operation == failingOperation, !didInjectFailure {
                            didInjectFailure = true
                            throw StartupPersistenceInjectedFault()
                        }
                        try body()
                    },
                    openPersistentContainer: { _ -> String in
                        openAttempts += 1
                        if openAttempts == 1 {
                            throw StartupPersistenceFixtures.corruptStore
                        }
                        XCTFail("Recovery open preceded \(failingOperation).")
                        return "unexpected-recovery-open"
                    }
                )
            )

            XCTAssertTrue(didInjectFailure)
            XCTAssertEqual(openAttempts, 1)
            let quarantine = try publishedQuarantine(for: fixture)
            let archivedSnapshot = try quarantineSnapshot(quarantine)
            try resumeOrRetryRestore(quarantine, fixture: fixture)

            XCTAssertEqual(try faultStoreFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
            XCTAssertFalse(FileManager.default.fileExists(atPath: faultTransitionMarkerURL(for: fixture).path))
            XCTAssertEqual(try quarantineSnapshot(quarantine), archivedSnapshot)
        }
    }

    func testEveryFreshTransitionFailureBlocksFreshOpenAndResumes() throws {
        for failingOperation in StartupRecoveryOperationFixtures.fresh {
            let fixture = try makeFaultStoreFixture()
            var didInjectFailure = false
            var openAttempts = 0

            XCTAssertThrowsError(
                try SumiStartupPersistence.makePersistentContainerForStartup(
                    storeURL: fixture.storeURL,
                    quarantineRootURL: fixture.quarantineRootURL,
                    performRecoveryOperation: { operation, body in
                        if operation == failingOperation, !didInjectFailure {
                            didInjectFailure = true
                            throw StartupPersistenceInjectedFault()
                        }
                        try body()
                    },
                    openPersistentContainer: { _ -> String in
                        openAttempts += 1
                        if openAttempts < 3 {
                            throw StartupPersistenceFixtures.corruptStore
                        }
                        XCTFail("Fresh open preceded \(failingOperation).")
                        return "unexpected-fresh-open"
                    }
                )
            )

            XCTAssertTrue(didInjectFailure)
            XCTAssertEqual(openAttempts, 2)
            let quarantine = try publishedQuarantine(for: fixture)
            let archivedSnapshot = try quarantineSnapshot(quarantine)
            try resumeOrRetryFreshPreparation(quarantine, fixture: fixture)

            XCTAssertTrue(try faultStoreFamilySnapshot(at: fixture.storeURL).isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: faultTransitionMarkerURL(for: fixture).path))
            XCTAssertEqual(try quarantineSnapshot(quarantine), archivedSnapshot)
        }
    }

    func testSameLengthPreservedFamilyTamperBlocksRestoreBeforeActiveMutation() throws {
        for fileName in StartupPersistenceFixtures.corruptStoreFamily.keys.sorted() {
            let fixture = try makeFaultStoreFixture()
            let quarantine = try makeQuarantine(for: fixture)
            try overwritePreservedFileWithSameLength(
                named: fileName,
                in: quarantine,
                fixture: fixture
            )

            XCTAssertThrowsError(
                try SumiStartupStoreRecovery.restorePreservedFamily(
                    from: quarantine,
                    to: fixture.storeURL
                )
            )
            XCTAssertEqual(try faultStoreFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
            XCTAssertFalse(FileManager.default.fileExists(atPath: faultTransitionMarkerURL(for: fixture).path))
        }
    }

    func testSameLengthTamperBlocksExistingFreshMarkerBeforeDeletion() throws {
        let fixture = try makeFaultStoreFixture()
        let quarantine = try makeQuarantine(for: fixture)
        try SumiStartupStoreRecovery.beginFreshStorePreparation(
            at: fixture.storeURL,
            preserving: quarantine
        )
        try overwritePreservedFileWithSameLength(
            named: "default.store-wal",
            in: quarantine,
            fixture: fixture
        )

        XCTAssertThrowsError(
            try SumiStartupStoreRecovery.resumeInterruptedTransition(at: fixture.storeURL)
        )
        XCTAssertEqual(try faultStoreFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
        XCTAssertTrue(FileManager.default.fileExists(atPath: faultTransitionMarkerURL(for: fixture).path))
    }
}

private extension SumiStartupPersistenceTests {
    func makeFaultStoreFixture() throws -> StartupPersistenceStoreFixture {
        let fixture = try StartupPersistenceStoreFixture()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fixture.rootURL)
        }
        return fixture
    }

    func makeQuarantine(
        for fixture: StartupPersistenceStoreFixture
    ) throws -> SumiStartupStoreRecovery.Quarantine {
        try SumiStartupStoreRecovery.quarantine(
            storeURL: fixture.storeURL,
            quarantineRootURL: fixture.quarantineRootURL,
            failure: StartupPersistenceFixtures.corruptStore
        )
    }

    func publishedQuarantine(
        for fixture: StartupPersistenceStoreFixture
    ) throws -> SumiStartupStoreRecovery.Quarantine {
        let contents = try FileManager.default.contentsOfDirectory(
            at: fixture.quarantineRootURL,
            includingPropertiesForKeys: nil
        )
        let directoryURL = try XCTUnwrap(
            contents.first { $0.lastPathComponent.hasPrefix("incident-") }
        )
        return SumiStartupStoreRecovery.Quarantine(
            directoryURL: directoryURL,
            preservedStoreURL: directoryURL
                .appendingPathComponent(
                    SumiStartupStoreRecovery.preservedDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(fixture.storeURL.lastPathComponent, isDirectory: false)
        )
    }

    func quarantineSnapshot(
        _ quarantine: SumiStartupStoreRecovery.Quarantine
    ) throws -> [String: Data] {
        var snapshot = [
            SumiStartupStoreRecovery.manifestFileName: try Data(
                contentsOf: quarantine.directoryURL.appendingPathComponent(
                    SumiStartupStoreRecovery.manifestFileName,
                    isDirectory: false
                )
            ),
        ]
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let fileURL = suffix.isEmpty
                ? quarantine.preservedStoreURL
                : URL(fileURLWithPath: quarantine.preservedStoreURL.path + suffix)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            snapshot["original/\(fileURL.lastPathComponent)"] = try Data(contentsOf: fileURL)
        }
        return snapshot
    }

    func resumeOrRetryRestore(
        _ quarantine: SumiStartupStoreRecovery.Quarantine,
        fixture: StartupPersistenceStoreFixture
    ) throws {
        if FileManager.default.fileExists(atPath: faultTransitionMarkerURL(for: fixture).path) {
            try SumiStartupStoreRecovery.resumeInterruptedTransition(at: fixture.storeURL)
        } else {
            try SumiStartupStoreRecovery.restorePreservedFamily(
                from: quarantine,
                to: fixture.storeURL
            )
        }
    }

    func resumeOrRetryFreshPreparation(
        _ quarantine: SumiStartupStoreRecovery.Quarantine,
        fixture: StartupPersistenceStoreFixture
    ) throws {
        if FileManager.default.fileExists(atPath: faultTransitionMarkerURL(for: fixture).path) {
            try SumiStartupStoreRecovery.resumeInterruptedTransition(at: fixture.storeURL)
        } else {
            try SumiStartupStoreRecovery.prepareFreshStore(
                at: fixture.storeURL,
                preserving: quarantine
            )
        }
    }

    func overwritePreservedFileWithSameLength(
        named fileName: String,
        in quarantine: SumiStartupStoreRecovery.Quarantine,
        fixture: StartupPersistenceStoreFixture
    ) throws {
        let originalData = try XCTUnwrap(fixture.originalFamily[fileName])
        let fileURL = quarantine.preservedStoreURL.deletingLastPathComponent()
            .appendingPathComponent(fileName, isDirectory: false)
        try Data(repeating: 0xA5, count: originalData.count).write(to: fileURL)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
            originalData.count
        )
    }

    func faultStoreFamilySnapshot(at storeURL: URL) throws -> [String: Data] {
        var snapshot: [String: Data] = [:]
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let fileURL = suffix.isEmpty
                ? storeURL
                : URL(fileURLWithPath: storeURL.path + suffix, isDirectory: false)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            snapshot[fileURL.lastPathComponent] = try Data(contentsOf: fileURL)
        }
        return snapshot
    }

    func faultTransitionMarkerURL(for fixture: StartupPersistenceStoreFixture) -> URL {
        fixture.rootURL.appendingPathComponent(
            SumiStartupStoreRecovery.transitionMarkerFileName,
            isDirectory: false
        )
    }
}

@MainActor
enum StartupRecoveryOperationFixtures {
    typealias Operation = SumiStartupStoreRecovery.RecoveryOperation

    static let quarantine: [Operation] = [
        .createQuarantineRoot,
        .synchronizeQuarantineRootParent,
        .createStagingTree,
        .copyFamilyFile("default.store"),
        .synchronizeFamilyFile("default.store"),
        .copyFamilyFile("default.store-wal"),
        .synchronizeFamilyFile("default.store-wal"),
        .copyFamilyFile("default.store-shm"),
        .synchronizeFamilyFile("default.store-shm"),
        .synchronizePreservedDirectory,
        .writeManifest,
        .synchronizeManifest,
        .synchronizeStagingDirectory,
        .publishIncident,
        .synchronizeQuarantineRoot,
    ]

    static let restore: [Operation] = [
        .writeTransitionMarker(.restoringPreservedFamily),
        .synchronizeTransitionMarker(.restoringPreservedFamily),
        .publishTransitionMarker(.restoringPreservedFamily),
        .synchronizeTransitionParent(.restoringPreservedFamily),
        .removeActiveFamilyFile(.restoringPreservedFamily, "default.store-shm"),
        .removeActiveFamilyFile(.restoringPreservedFamily, "default.store-wal"),
        .removeActiveFamilyFile(.restoringPreservedFamily, "default.store"),
        .synchronizeActiveDirectoryAfterRemoval(.restoringPreservedFamily),
        .copyRestoredFamilyFile("default.store"),
        .synchronizeRestoredFamilyFile("default.store"),
        .copyRestoredFamilyFile("default.store-wal"),
        .synchronizeRestoredFamilyFile("default.store-wal"),
        .copyRestoredFamilyFile("default.store-shm"),
        .synchronizeRestoredFamilyFile("default.store-shm"),
        .synchronizeRestoredDirectory,
        .removeTransitionMarker(.restoringPreservedFamily),
        .synchronizeTransitionCompletionDirectory(.restoringPreservedFamily),
    ]

    static let fresh: [Operation] = [
        .writeTransitionMarker(.preparingFreshStore),
        .synchronizeTransitionMarker(.preparingFreshStore),
        .publishTransitionMarker(.preparingFreshStore),
        .synchronizeTransitionParent(.preparingFreshStore),
        .removeActiveFamilyFile(.preparingFreshStore, "default.store-shm"),
        .removeActiveFamilyFile(.preparingFreshStore, "default.store-wal"),
        .removeActiveFamilyFile(.preparingFreshStore, "default.store"),
        .synchronizeActiveDirectoryAfterRemoval(.preparingFreshStore),
        .removeTransitionMarker(.preparingFreshStore),
        .synchronizeTransitionCompletionDirectory(.preparingFreshStore),
    ]
}
