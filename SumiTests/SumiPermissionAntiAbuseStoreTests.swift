import XCTest

@testable import Sumi
import SumiDomain

final class SumiPermissionAntiAbuseStoreTests: XCTestCase {
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

    func testRecordsAndFiltersEventsByCanonicalPermissionKey() async {
        let store = SumiPermissionAntiAbuseStore()
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

    func testPersistentProfilesSurviveStoreRecreationButEphemeralProfilesDoNotPersist() async throws {
        let directory = try temporaryDirectory()
        let suiteName = "SumiAntiAbuseStoreTests-\(UUID().uuidString)"
        let storageKey = "anti-abuse-\(UUID().uuidString)"
        let persistentKey = antiAbuseKey(.camera)
        let ephemeralKey = antiAbuseKey(.camera, profile: "ephemeral", isEphemeral: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let firstStore = SumiPermissionAntiAbuseStore(
            storageDirectory: directory
        )
        await firstStore.record(event(.userDismissed, key: persistentKey, at: now))
        await firstStore.record(event(.userDismissed, key: ephemeralKey, at: now))
        let firstAuthority = await firstStore.persistenceAuthority
        let didFlush = await firstAuthority.flushPendingWrites()
        XCTAssertTrue(didFlush)

        let secondStore = SumiPermissionAntiAbuseStore(
            storageDirectory: directory
        )
        let persistentEvents = await secondStore.events(for: persistentKey, now: now)
        let ephemeralEvents = await secondStore.events(for: ephemeralKey, now: now)

        XCTAssertEqual(persistentEvents.map(\.type), [.userDismissed])
        XCTAssertTrue(ephemeralEvents.isEmpty)
    }

    func testOneThousandRapidMutationsPublishOneGeneratedSnapshot() async throws {
        let directory = try temporaryDirectory()
        let authority = SumiPermissionPersistenceAuthority(
            storageDirectory: directory
        )
        let key = antiAbuseKey(.camera)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        for index in 0..<1_000 {
            authority.mutateAntiAbuseEvents { records in
                records = [
                    SumiPermissionAntiAbuseEvent(
                        id: "event-\(index)",
                        type: .promptShown,
                        key: key,
                        createdAt: now
                    ),
                ]
            }
        }

        XCTAssertEqual(authority.persistenceDiagnostics.successfulWriteCount, 0)
        let didFlush = await authority.flushPendingWrites()
        XCTAssertTrue(didFlush)
        XCTAssertEqual(authority.persistenceDiagnostics.successfulWriteCount, 1)

        let envelope = try JSONDecoder().decode(
            AntiAbuseCanonicalEnvelope.self,
            from: Data(
                contentsOf: directory.appendingPathComponent(
                    SumiPermissionPersistenceAuthority.canonicalFileName
                )
            )
        )
        XCTAssertEqual(envelope.version, 1)
        XCTAssertEqual(envelope.generation, 1_000)
        XCTAssertEqual(envelope.antiAbuseEvents.map(\.id), ["event-999"])
    }

    func testRetentionCapRemovesOldAndExcessEvents() async {
        let store = SumiPermissionAntiAbuseStore(
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

private struct AntiAbuseCanonicalEnvelope: Decodable {
    let version: Int
    let generation: UInt64
    let antiAbuseEvents: [SumiPermissionAntiAbuseEvent]
}
