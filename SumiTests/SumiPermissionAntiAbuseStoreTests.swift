import XCTest

@testable import Sumi

final class SumiPermissionAntiAbuseStoreTests: XCTestCase {
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
}
