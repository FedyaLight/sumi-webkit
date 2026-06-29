import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionSiteActivityStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
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

    func testFileBackedSnapshotPersistsAndReloadsRecords() throws {
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

    private func siteActivityKey(_ type: SumiPermissionType) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com/path"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            permissionType: type,
            profilePartitionId: "profile-a",
            isEphemeralProfile: false
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
