import XCTest

@testable import Sumi

final class SumiPermissionAntiAbuseStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testRecordsAndFiltersEventsByCanonicalPermissionKey() async {
        let store = SumiPermissionAntiAbuseStore(userDefaults: nil)
        let key = antiAbuseKey(.camera)
        let other = antiAbuseKey(.microphone)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        await store.record(event(.promptShown, key: key, at: now))
        await store.record(event(.userDismissed, key: other, at: now))

        let events = await store.events(for: key, now: now)

        XCTAssertEqual(events.map(\.type), [.promptShown])
        XCTAssertEqual(events.first?.key.requestingOrigin.identity, "https://example.com")
        XCTAssertFalse(events.first?.key.requestingOrigin.identity.contains("?") ?? true)
    }

    func testPersistentProfilesSurviveStoreRecreationButEphemeralProfilesDoNotPersist() async {
        let suiteName = "SumiAntiAbuseStoreTests-\(UUID().uuidString)"
        let storageKey = "anti-abuse-\(UUID().uuidString)"
        let persistentKey = antiAbuseKey(.camera)
        let ephemeralKey = antiAbuseKey(.camera, profile: "ephemeral", isEphemeral: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let firstStore = SumiPermissionAntiAbuseStore(
            userDefaults: UserDefaults(suiteName: suiteName)!,
            storageKey: storageKey
        )
        await firstStore.record(event(.userDismissed, key: persistentKey, at: now))
        await firstStore.record(event(.userDismissed, key: ephemeralKey, at: now))

        let secondStore = SumiPermissionAntiAbuseStore(
            userDefaults: UserDefaults(suiteName: suiteName)!,
            storageKey: storageKey
        )
        let persistentEvents = await secondStore.events(for: persistentKey, now: now)
        let ephemeralEvents = await secondStore.events(for: ephemeralKey, now: now)

        XCTAssertEqual(persistentEvents.map(\.type), [.userDismissed])
        XCTAssertTrue(ephemeralEvents.isEmpty)
    }

    func testUnreadablePersistentPayloadIsPreservedForDiagnostics() async throws {
        let suiteName = "SumiAntiAbuseStoreTests-\(UUID().uuidString)"
        let setupDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let storageKey = "anti-abuse-\(UUID().uuidString)"
        let unreadablePayload = Data("not-json".utf8)
        setupDefaults.set(unreadablePayload, forKey: storageKey)

        let store = SumiPermissionAntiAbuseStore(
            userDefaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)),
            storageKey: storageKey
        )
        _ = await store.events(for: antiAbuseKey(.camera), now: Date(timeIntervalSince1970: 1_800_000_000))

        let assertionDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertEqual(assertionDefaults.data(forKey: storageKey), unreadablePayload)
        XCTAssertEqual(assertionDefaults.data(forKey: "\(storageKey).unreadable"), unreadablePayload)
    }

    func testUnreadableFilePayloadIsPreservedAndNotOverwrittenByRead() async throws {
        let directory = try temporaryDirectory()
        let payloadURL = directory.appendingPathComponent("permission-anti-abuse-events.v1.json")
        let unreadablePayload = Data("not-json".utf8)
        try unreadablePayload.write(to: payloadURL)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SumiAntiAbuseFileTests-\(UUID().uuidString)"))
        let store = SumiPermissionAntiAbuseStore(
            userDefaults: defaults,
            storageDirectory: directory
        )

        let events = await store.events(
            for: antiAbuseKey(.camera),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let diagnostics = await store.diagnostics()

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(try Data(contentsOf: payloadURL), unreadablePayload)
        XCTAssertEqual(try Data(contentsOf: payloadURL.appendingPathExtension("unreadable")), unreadablePayload)
        if case .failedFileDecode = diagnostics.loadOutcome {
            // Expected classification.
        } else {
            XCTFail("Expected failed file decode, got \(diagnostics.loadOutcome)")
        }
    }

    func testLegacyUserDefaultsPayloadMigratesToVersionedFileSnapshot() async throws {
        let directory = try temporaryDirectory()
        let suiteName = "SumiAntiAbuseMigrationTests-\(UUID().uuidString)"
        let storageKey = "anti-abuse-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let key = antiAbuseKey(.camera)
        let legacyEvents = [event(.userDismissed, key: key, at: now)]
        defaults.set(try JSONEncoder().encode(legacyEvents), forKey: storageKey)

        let store = SumiPermissionAntiAbuseStore(
            userDefaults: defaults,
            storageKey: storageKey,
            storageDirectory: directory
        )
        let events = await store.events(for: key, now: now)
        let diagnostics = await store.diagnostics()

        XCTAssertEqual(events.map(\.type), [.userDismissed])
        XCTAssertEqual(diagnostics.loadOutcome, .loadedLegacyUserDefaults)
        let migrated = try Data(contentsOf: directory.appendingPathComponent("permission-anti-abuse-events.v1.json"))
        XCTAssertGreaterThan(migrated.count, 0)
    }

    func testRetentionCapRemovesOldAndExcessEvents() async {
        let store = SumiPermissionAntiAbuseStore(
            userDefaults: nil,
            retentionInterval: 100,
            maximumEventsPerProfile: 2
        )
        let key = antiAbuseKey(.camera)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        await store.record(event(.promptShown, key: key, at: now.addingTimeInterval(-200)))
        await store.record(event(.userDismissed, key: key, at: now.addingTimeInterval(-3)))
        await store.record(event(.userDismissed, key: key, at: now.addingTimeInterval(-2)))
        await store.record(event(.userDismissed, key: key, at: now.addingTimeInterval(-1)))

        let events = await store.events(for: key, now: now)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.createdAt), [
            now.addingTimeInterval(-2),
            now.addingTimeInterval(-1),
        ])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiAntiAbuseStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }
}
