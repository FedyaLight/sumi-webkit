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
