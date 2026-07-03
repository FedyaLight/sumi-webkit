import Foundation
import XCTest

@testable import Sumi

final class WebExtensionStorageCleanupPlannerTests: XCTestCase {
    private let planner = WebExtensionStorageCleanupPlanner.shared
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testStoredDataCandidateIgnoresStateOnlyDirectory() {
        XCTAssertFalse(
            planner.hasStoredDataCandidate(
                in: .init(
                    directoryExists: false,
                    entryNames: [],
                    hasRegisteredContentScriptsStore: false,
                    hasLocalStorageStore: false,
                    hasSyncStorageStore: false
                )
            )
        )

        XCTAssertFalse(
            planner.hasStoredDataCandidate(
                in: .init(
                    directoryExists: true,
                    entryNames: ["State.plist"],
                    hasRegisteredContentScriptsStore: false,
                    hasLocalStorageStore: false,
                    hasSyncStorageStore: false
                )
            )
        )

        XCTAssertTrue(
            planner.hasStoredDataCandidate(
                in: .init(
                    directoryExists: true,
                    entryNames: ["LocalStorage.db", "State.plist"],
                    hasRegisteredContentScriptsStore: false,
                    hasLocalStorageStore: true,
                    hasSyncStorageStore: false
                )
            )
        )
    }

    func testCapabilitySnapshotReportsStorageAndDynamicScriptStores() {
        let snapshot = planner.storeCapabilitySnapshot(
            for: [
                "permissions": ["storage", "scripting", "tabs"],
            ],
            unsupportedAPIs: [
                "browser.scripting.registerContentScripts",
                "browser.tabs.executeScript",
            ]
        )

        XCTAssertFalse(snapshot.usesWebKitCompatibilityPrelude)
        XCTAssertTrue(snapshot.mayTouchDynamicContentScriptStore)
        XCTAssertTrue(snapshot.mayTouchSyncStorageStore)
        XCTAssertEqual(snapshot.declaredPermissions, ["scripting", "storage", "tabs"])
        XCTAssertEqual(
            snapshot.unsupportedAPIs,
            [
                "browser.scripting.registerContentScripts",
                "browser.tabs.executeScript",
            ]
        )
    }

    func testMissingOptionalStoreCleanupErrorIsBenignWithoutActionableSignals() {
        let classification = planner.classifyCleanupErrors(
            [
                NSError(
                    domain: "NSCocoaErrorDomain",
                    code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "open(/tmp/ext/LocalStorage.db): No such file or directory",
                    ]
                ),
            ],
            extensionId: "ext-cleanup",
            preCleanupSnapshot: stateOnlySnapshot(),
            postCleanupSnapshot: stateOnlySnapshot()
        )

        XCTAssertEqual(classification.benignOptionalStoreDiagnostics.count, 1)
        XCTAssertTrue(classification.actionableDiagnostics.isEmpty)
    }

    func testNonOptionalCleanupErrorRemainsActionable() {
        let classification = planner.classifyCleanupErrors(
            [
                NSError(
                    domain: "NSCocoaErrorDomain",
                    code: 13,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "open(/tmp/ext/ImportantStore.db): Permission denied",
                    ]
                ),
            ],
            extensionId: "ext-cleanup",
            preCleanupSnapshot: stateOnlySnapshot(),
            postCleanupSnapshot: stateOnlySnapshot()
        )

        XCTAssertTrue(classification.benignOptionalStoreDiagnostics.isEmpty)
        XCTAssertEqual(classification.actionableDiagnostics.count, 1)
    }

    func testStorageCleanupStoreResolvesDirectoryUnderInjectedLibraryDirectory() throws {
        let controllerStorageId = UUID()
        let libraryDirectory = makeTemporaryLibraryDirectory()
        let store = WebExtensionStorageCleanupStore(
            controllerStorageId: controllerStorageId,
            libraryDirectoryProvider: { libraryDirectory }
        )

        let directory = try XCTUnwrap(store.directory(for: "resolved-extension"))
        let expectedDirectory = libraryDirectory
            .appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
            .appendingPathComponent("WebExtensions", isDirectory: true)
            .appendingPathComponent(controllerStorageId.uuidString.uppercased(), isDirectory: true)
            .appendingPathComponent("resolved-extension", isDirectory: true)
            .standardizedFileURL

        XCTAssertEqual(directory.standardizedFileURL.path, expectedDirectory.path)
    }

    func testStorageCleanupStoreSnapshotsAndPrunesStateOnlyDirectory() throws {
        let store = makeCleanupStore()
        let extensionId = "state-only-extension"

        XCTAssertFalse(store.hasStoredDataCandidate(for: extensionId))
        XCTAssertTrue(store.ensureDirectoryExists(for: extensionId))

        let storageDirectory = try XCTUnwrap(store.directory(for: extensionId))
        try Data().write(to: storageDirectory.appendingPathComponent("State.plist"))

        let snapshot = store.snapshot(for: extensionId)
        XCTAssertTrue(snapshot.directoryExists)
        XCTAssertEqual(snapshot.entryNames, ["State.plist"])
        XCTAssertFalse(store.hasStoredDataCandidate(for: extensionId))

        XCTAssertTrue(store.pruneEmptyOrStateOnlyDirectory(for: extensionId))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageDirectory.path))
    }

    func testStorageCleanupStorePreservesDirectoryWithDataCandidate() throws {
        let store = makeCleanupStore()
        let extensionId = "extension-with-store"

        XCTAssertTrue(store.ensureDirectoryExists(for: extensionId))
        let storageDirectory = try XCTUnwrap(store.directory(for: extensionId))
        try Data().write(to: storageDirectory.appendingPathComponent("LocalStorage.db"))
        try Data().write(to: storageDirectory.appendingPathComponent("State.plist"))

        let snapshot = store.snapshot(for: extensionId)
        XCTAssertEqual(snapshot.entryNames, ["LocalStorage.db", "State.plist"])
        XCTAssertTrue(snapshot.hasLocalStorageStore)
        XCTAssertTrue(store.hasStoredDataCandidate(for: extensionId))

        XCTAssertFalse(store.pruneEmptyOrStateOnlyDirectory(for: extensionId))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageDirectory.path))
    }

    func testStorageCleanupStoreWithoutControllerIdentifierIsZeroCost() {
        let store = WebExtensionStorageCleanupStore(
            controllerStorageId: nil,
            libraryDirectoryProvider: {
                XCTFail("Library directory should not be resolved without a controller id")
                return nil
            }
        )

        XCTAssertNil(store.directory(for: "extension-id"))
        XCTAssertFalse(store.ensureDirectoryExists(for: "extension-id"))
        XCTAssertFalse(store.pruneEmptyOrStateOnlyDirectory(for: "extension-id"))
        XCTAssertFalse(store.snapshot(for: "extension-id").directoryExists)
        XCTAssertFalse(store.hasStoredDataCandidate(for: "extension-id"))
    }

    func testStoreResolvesDirectoryThroughStorageNameResolver() throws {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        let store = WebExtensionStorageCleanupStore(
            controllerStorageId: UUID(),
            libraryDirectoryProvider: { libraryDirectory },
            storageDirectoryNameResolver: { "\($0) (TEAMID123)" }
        )

        let directory = try XCTUnwrap(store.directory(for: "com.vendor.ext"))
        XCTAssertEqual(directory.lastPathComponent, "com.vendor.ext (TEAMID123)")
    }

    func testAdoptLegacyStorageMovesLegacyDirectoryWhenComposedMissing() throws {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        let identityStore = WebExtensionStorageCleanupStore(
            controllerStorageId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            libraryDirectoryProvider: { libraryDirectory }
        )
        let composedStore = WebExtensionStorageCleanupStore(
            controllerStorageId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            libraryDirectoryProvider: { libraryDirectory },
            storageDirectoryNameResolver: { "\($0) (TEAMID123)" }
        )
        let extensionId = "com.vendor.ext"

        XCTAssertTrue(identityStore.ensureDirectoryExists(for: extensionId))
        let legacyDirectory = try XCTUnwrap(identityStore.directory(for: extensionId))
        try Data("session".utf8).write(
            to: legacyDirectory.appendingPathComponent("LocalStorage.db")
        )

        composedStore.adoptLegacyStorageDirectoryIfNeeded(for: extensionId)

        let composedDirectory = try XCTUnwrap(composedStore.directory(for: extensionId))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: composedDirectory.appendingPathComponent("LocalStorage.db").path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    func testAdoptLegacyStorageReplacesStateOnlyComposedDirectory() throws {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        let controllerId = UUID()
        let identityStore = WebExtensionStorageCleanupStore(
            controllerStorageId: controllerId,
            libraryDirectoryProvider: { libraryDirectory }
        )
        let composedStore = WebExtensionStorageCleanupStore(
            controllerStorageId: controllerId,
            libraryDirectoryProvider: { libraryDirectory },
            storageDirectoryNameResolver: { "\($0) (TEAMID123)" }
        )
        let extensionId = "com.vendor.ext"

        XCTAssertTrue(identityStore.ensureDirectoryExists(for: extensionId))
        let legacyDirectory = try XCTUnwrap(identityStore.directory(for: extensionId))
        try Data("session".utf8).write(
            to: legacyDirectory.appendingPathComponent("LocalStorage.db")
        )

        XCTAssertTrue(composedStore.ensureDirectoryExists(for: extensionId))
        let composedDirectory = try XCTUnwrap(composedStore.directory(for: extensionId))
        try Data().write(to: composedDirectory.appendingPathComponent("State.plist"))

        composedStore.adoptLegacyStorageDirectoryIfNeeded(for: extensionId)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: composedDirectory.appendingPathComponent("LocalStorage.db").path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    func testAdoptLegacyStorageNeverReplacesComposedDirectoryWithData() throws {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        let controllerId = UUID()
        let identityStore = WebExtensionStorageCleanupStore(
            controllerStorageId: controllerId,
            libraryDirectoryProvider: { libraryDirectory }
        )
        let composedStore = WebExtensionStorageCleanupStore(
            controllerStorageId: controllerId,
            libraryDirectoryProvider: { libraryDirectory },
            storageDirectoryNameResolver: { "\($0) (TEAMID123)" }
        )
        let extensionId = "com.vendor.ext"

        XCTAssertTrue(identityStore.ensureDirectoryExists(for: extensionId))
        let legacyDirectory = try XCTUnwrap(identityStore.directory(for: extensionId))
        try Data("legacy".utf8).write(
            to: legacyDirectory.appendingPathComponent("LocalStorage.db")
        )

        XCTAssertTrue(composedStore.ensureDirectoryExists(for: extensionId))
        let composedDirectory = try XCTUnwrap(composedStore.directory(for: extensionId))
        try Data("current".utf8).write(
            to: composedDirectory.appendingPathComponent("LocalStorage.db")
        )

        composedStore.adoptLegacyStorageDirectoryIfNeeded(for: extensionId)

        XCTAssertEqual(
            try String(
                contentsOf: composedDirectory.appendingPathComponent("LocalStorage.db"),
                encoding: .utf8
            ),
            "current"
        )
        // The legacy directory is retired (renamed, bytes preserved) so the
        // destructive adoption branch can never re-arm on a later load.
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
        let retired = try retiredSiblings(
            of: legacyDirectory,
            prefix: ".sumi-legacy-retired"
        )
        XCTAssertEqual(retired.count, 1)
        XCTAssertEqual(
            try String(
                contentsOf: retired[0].appendingPathComponent("LocalStorage.db"),
                encoding: .utf8
            ),
            "legacy"
        )
    }

    func testAdoptLegacyRemovesStateOnlyLegacyDirectory() throws {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        let controllerId = UUID()
        let identityStore = WebExtensionStorageCleanupStore(
            controllerStorageId: controllerId,
            libraryDirectoryProvider: { libraryDirectory }
        )
        let composedStore = WebExtensionStorageCleanupStore(
            controllerStorageId: controllerId,
            libraryDirectoryProvider: { libraryDirectory },
            storageDirectoryNameResolver: { "\($0) (TEAMID123)" }
        )
        let extensionId = "com.vendor.ext"

        XCTAssertTrue(identityStore.ensureDirectoryExists(for: extensionId))
        let legacyDirectory = try XCTUnwrap(identityStore.directory(for: extensionId))
        try Data().write(to: legacyDirectory.appendingPathComponent("State.plist"))

        XCTAssertTrue(composedStore.ensureDirectoryExists(for: extensionId))
        let composedDirectory = try XCTUnwrap(composedStore.directory(for: extensionId))
        try Data("current".utf8).write(
            to: composedDirectory.appendingPathComponent("LocalStorage.db")
        )

        composedStore.adoptLegacyStorageDirectoryIfNeeded(for: extensionId)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
        XCTAssertEqual(
            try String(
                contentsOf: composedDirectory.appendingPathComponent("LocalStorage.db"),
                encoding: .utf8
            ),
            "current"
        )
    }

    func testAdoptLegacyReplaceSetsComposedDirectoryAsideInsteadOfDeleting() throws {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        let controllerId = UUID()
        let identityStore = WebExtensionStorageCleanupStore(
            controllerStorageId: controllerId,
            libraryDirectoryProvider: { libraryDirectory }
        )
        let composedStore = WebExtensionStorageCleanupStore(
            controllerStorageId: controllerId,
            libraryDirectoryProvider: { libraryDirectory },
            storageDirectoryNameResolver: { "\($0) (TEAMID123)" }
        )
        let extensionId = "com.vendor.ext"

        XCTAssertTrue(identityStore.ensureDirectoryExists(for: extensionId))
        let legacyDirectory = try XCTUnwrap(identityStore.directory(for: extensionId))
        try Data("legacy".utf8).write(
            to: legacyDirectory.appendingPathComponent("LocalStorage.db")
        )

        XCTAssertTrue(composedStore.ensureDirectoryExists(for: extensionId))
        let composedDirectory = try XCTUnwrap(composedStore.directory(for: extensionId))
        try Data().write(to: composedDirectory.appendingPathComponent("State.plist"))

        composedStore.adoptLegacyStorageDirectoryIfNeeded(for: extensionId)

        // The state-only composed directory must be set aside by rename —
        // never deleted in place, because WebKit may have created and opened
        // store files inside it after the emptiness check ("vnode unlinked
        // while in use" corruption).
        let setAside = try retiredSiblings(
            of: composedDirectory,
            prefix: ".sumi-replaced"
        )
        XCTAssertEqual(setAside.count, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: setAside[0].appendingPathComponent("State.plist").path
            )
        )
    }

    private func retiredSiblings(of directory: URL, prefix: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    func testAdoptLegacyStorageIsNoOpWithIdentityResolver() throws {
        let store = makeCleanupStore()
        let extensionId = "com.vendor.ext"
        XCTAssertTrue(store.ensureDirectoryExists(for: extensionId))
        // Identity resolver means no composed identifier — nothing to adopt.
        store.adoptLegacyStorageDirectoryIfNeeded(for: extensionId)
        let directory = try XCTUnwrap(store.directory(for: extensionId))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    private func stateOnlySnapshot() -> WebExtensionStorageCleanupPlanner.StorageSnapshot {
        .init(
            directoryExists: true,
            entryNames: ["State.plist"],
            hasRegisteredContentScriptsStore: false,
            hasLocalStorageStore: false,
            hasSyncStorageStore: false
        )
    }

    private func makeCleanupStore() -> WebExtensionStorageCleanupStore {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        return WebExtensionStorageCleanupStore(
            controllerStorageId: UUID(),
            libraryDirectoryProvider: { libraryDirectory }
        )
    }

    private func makeTemporaryLibraryDirectory() -> URL {
        let libraryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiWebExtensionCleanupStoreTests-\(UUID().uuidString)",
                isDirectory: true
            )
        temporaryDirectories.append(libraryDirectory)
        return libraryDirectory
    }
}
