import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class WebExtensionRuntimeStoragePreparationTests: XCTestCase {
    func testPrepareUsesExactControllerAndRuntimeIdentifiers() throws {
        let libraryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: libraryDirectory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try FileManager.default.removeItem(at: libraryDirectory)
        }
        let controllerID = UUID()
        let otherControllerID = UUID()
        let extensionID = "internal-extension-id"
        let runtimeIdentifier = "com.example.extension (TEAMID)"
        let controller = WKWebExtensionController(
            configuration: .init(identifier: controllerID)
        )
        let preparation = WebExtensionRuntimeStoragePreparation(
            extensionID: extensionID,
            runtimeIdentifier: runtimeIdentifier,
            controller: controller,
            planner: .init(),
            libraryDirectoryProvider: { libraryDirectory }
        )

        preparation.prepare()

        XCTAssertTrue(preparation.snapshot().directoryExists)
        let exactStore = WebExtensionStorageCleanupStore(
            controllerStorageId: controllerID,
            libraryDirectoryProvider: { libraryDirectory },
            planner: .init(),
            storageDirectoryNameResolver: { _ in runtimeIdentifier }
        )
        XCTAssertTrue(exactStore.snapshot(for: extensionID).directoryExists)
        let extensionIDStore = WebExtensionStorageCleanupStore(
            controllerStorageId: controllerID,
            libraryDirectoryProvider: { libraryDirectory },
            planner: .init()
        )
        XCTAssertFalse(extensionIDStore.snapshot(for: extensionID).directoryExists)
        let otherControllerStore = WebExtensionStorageCleanupStore(
            controllerStorageId: otherControllerID,
            libraryDirectoryProvider: { libraryDirectory },
            planner: .init(),
            storageDirectoryNameResolver: { _ in runtimeIdentifier }
        )
        XCTAssertFalse(
            otherControllerStore.snapshot(for: extensionID).directoryExists
        )
    }

    func testPrepareAdoptsLegacyDataIntoExactRuntimeIdentifier() throws {
        let libraryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: libraryDirectory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try FileManager.default.removeItem(at: libraryDirectory)
        }
        let controllerID = UUID()
        let extensionID = "legacy-extension-id"
        let runtimeIdentifier = "com.example.legacy (TEAMID)"
        let identityStore = WebExtensionStorageCleanupStore(
            controllerStorageId: controllerID,
            libraryDirectoryProvider: { libraryDirectory },
            planner: .init()
        )
        XCTAssertTrue(identityStore.ensureDirectoryExists(for: extensionID))
        let legacyDirectory = try XCTUnwrap(
            identityStore.directory(for: extensionID)
        )
        try Data("legacy".utf8).write(
            to: legacyDirectory.appendingPathComponent("LocalStorage.db")
        )
        let controller = WKWebExtensionController(
            configuration: .init(identifier: controllerID)
        )
        let preparation = WebExtensionRuntimeStoragePreparation(
            extensionID: extensionID,
            runtimeIdentifier: runtimeIdentifier,
            controller: controller,
            planner: .init(),
            libraryDirectoryProvider: { libraryDirectory }
        )

        preparation.prepare()

        let snapshot = preparation.snapshot()
        XCTAssertTrue(snapshot.directoryExists)
        XCTAssertTrue(snapshot.hasLocalStorageStore)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyDirectory.path)
        )
    }
}
