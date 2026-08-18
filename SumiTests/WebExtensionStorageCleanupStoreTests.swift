import Foundation
import XCTest

@testable import Sumi

final class WebExtensionStorageCleanupStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testPrunesStateOnlyStorage() throws {
        let store = makeStore()
        let extensionID = "state-only-extension"
        let directory = try XCTUnwrap(store.directory(for: extensionID))
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data().write(to: directory.appendingPathComponent("State.plist"))

        XCTAssertFalse(store.hasStoredDataCandidate(for: extensionID))
        XCTAssertTrue(store.pruneEmptyOrStateOnlyDirectory(for: extensionID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testPreservesActualExtensionStorage() throws {
        let store = makeStore()
        let extensionID = "extension-with-store"
        let directory = try XCTUnwrap(store.directory(for: extensionID))
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data().write(to: directory.appendingPathComponent("LocalStorage.db"))

        XCTAssertTrue(store.hasStoredDataCandidate(for: extensionID))
        XCTAssertFalse(store.pruneEmptyOrStateOnlyDirectory(for: extensionID))
    }

    func testDeletesWholeControllerNamespace() throws {
        let store = makeStore()
        let directory = try XCTUnwrap(store.directory(for: "extension"))
        let controllerDirectory = directory.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data().write(to: directory.appendingPathComponent("LocalStorage.db"))

        try store.deleteControllerStorageDirectory()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: controllerDirectory.path)
        )
    }

    private func makeStore() -> WebExtensionStorageCleanupStore {
        let libraryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryDirectories.append(libraryDirectory)
        return WebExtensionStorageCleanupStore(
            controllerStorageId: UUID(),
            libraryDirectoryProvider: { libraryDirectory }
        )
    }
}
