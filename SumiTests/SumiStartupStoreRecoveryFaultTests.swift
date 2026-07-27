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
                try SumiStartupPersistence.makePersistentDatabaseForStartup(
                    storeURL: fixture.storeURL,
                    quarantineRootURL: fixture.quarantineRootURL,
                    performRecoveryOperation: { operation, body in
                        if operation == failingOperation, !didInjectFailure {
                            didInjectFailure = true
                            throw StartupPersistenceInjectedFault()
                        }
                        try body()
                    },
                    openDatabase: { _ -> String in
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
                try SumiStartupPersistence.makePersistentDatabaseForStartup(
                    storeURL: fixture.storeURL,
                    quarantineRootURL: fixture.quarantineRootURL,
                    performRecoveryOperation: { operation, body in
                        if operation == failingOperation, !didInjectFailure {
                            didInjectFailure = true
                            throw StartupPersistenceInjectedFault()
                        }
                        try body()
                    },
                    openDatabase: { _ -> String in
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
            named: "Sumi.sqlite-wal",
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
        .copyFamilyFile("Sumi.sqlite"),
        .synchronizeFamilyFile("Sumi.sqlite"),
        .copyFamilyFile("Sumi.sqlite-wal"),
        .synchronizeFamilyFile("Sumi.sqlite-wal"),
        .copyFamilyFile("Sumi.sqlite-shm"),
        .synchronizeFamilyFile("Sumi.sqlite-shm"),
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
        .removeActiveFamilyFile(.restoringPreservedFamily, "Sumi.sqlite-shm"),
        .removeActiveFamilyFile(.restoringPreservedFamily, "Sumi.sqlite-wal"),
        .removeActiveFamilyFile(.restoringPreservedFamily, "Sumi.sqlite"),
        .synchronizeActiveDirectoryAfterRemoval(.restoringPreservedFamily),
        .copyRestoredFamilyFile("Sumi.sqlite"),
        .synchronizeRestoredFamilyFile("Sumi.sqlite"),
        .copyRestoredFamilyFile("Sumi.sqlite-wal"),
        .synchronizeRestoredFamilyFile("Sumi.sqlite-wal"),
        .copyRestoredFamilyFile("Sumi.sqlite-shm"),
        .synchronizeRestoredFamilyFile("Sumi.sqlite-shm"),
        .synchronizeRestoredDirectory,
        .removeTransitionMarker(.restoringPreservedFamily),
        .synchronizeTransitionCompletionDirectory(.restoringPreservedFamily),
    ]

    static let fresh: [Operation] = [
        .writeTransitionMarker(.preparingFreshStore),
        .synchronizeTransitionMarker(.preparingFreshStore),
        .publishTransitionMarker(.preparingFreshStore),
        .synchronizeTransitionParent(.preparingFreshStore),
        .removeActiveFamilyFile(.preparingFreshStore, "Sumi.sqlite-shm"),
        .removeActiveFamilyFile(.preparingFreshStore, "Sumi.sqlite-wal"),
        .removeActiveFamilyFile(.preparingFreshStore, "Sumi.sqlite"),
        .synchronizeActiveDirectoryAfterRemoval(.preparingFreshStore),
        .removeTransitionMarker(.preparingFreshStore),
        .synchronizeTransitionCompletionDirectory(.preparingFreshStore),
    ]
}

struct StartupPersistenceInjectedFault: Error {}

enum StartupPersistenceFixtures {
    static let corruptStore = NSError(
        domain: NSSQLiteErrorDomain,
        code: 11,
        userInfo: [NSLocalizedDescriptionKey: "database disk image is malformed"]
    )

    static let corruptStoreFamily = [
        "Sumi.sqlite": Data("corrupt-primary-store-bytes".utf8),
        "Sumi.sqlite-wal": Data("pending-wal-browser-data".utf8),
        "Sumi.sqlite-shm": Data("shared-memory-browser-data".utf8),
    ]
}

struct StartupPersistenceStoreFixture {
    let rootURL: URL
    let storeURL: URL
    let quarantineRootURL: URL
    let originalFamily: [String: Data]

    init(fileManager: FileManager = .default) throws {
        rootURL = fileManager.temporaryDirectory.appendingPathComponent(
            "SumiStartupPersistenceTests-\(UUID().uuidString)",
            isDirectory: true
        )
        storeURL = rootURL.appendingPathComponent("Sumi.sqlite", isDirectory: false)
        quarantineRootURL = rootURL.appendingPathComponent("quarantine", isDirectory: true)
        originalFamily = StartupPersistenceFixtures.corruptStoreFamily

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for (name, data) in originalFamily {
            try data.write(
                to: rootURL.appendingPathComponent(name, isDirectory: false),
                options: .withoutOverwriting
            )
        }
    }
}
