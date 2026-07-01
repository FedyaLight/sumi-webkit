import XCTest

@testable import Sumi

@MainActor
final class SumiAdblockZapperStoreTests: XCTestCase {
    func testPersistentProfilesDoNotShareZapperStateForSameHost() {
        let defaults = makeDefaults()
        let store = SumiAdblockZapperStore(userDefaults: defaults)

        store.setRules(
            [".ad-slot"],
            forHost: "Example.com",
            profilePartitionId: "profile-a",
            isEphemeralProfile: false
        )
        store.setRules(
            [".promo"],
            forHost: "example.com",
            profilePartitionId: "profile-b",
            isEphemeralProfile: false
        )
        store.setEnabled(
            false,
            forHost: "example.com",
            profilePartitionId: "profile-a",
            isEphemeralProfile: false
        )

        let profileAState = store.state(
            forHost: "example.com",
            profilePartitionId: "profile-a",
            isEphemeralProfile: false
        )
        let profileBState = store.state(
            forHost: "example.com",
            profilePartitionId: "profile-b",
            isEphemeralProfile: false
        )

        XCTAssertEqual(profileAState.rules, [".ad-slot"])
        XCTAssertTrue(profileAState.disabled)
        XCTAssertEqual(profileBState.rules, [".promo"])
        XCTAssertFalse(profileBState.disabled)
    }

    func testEphemeralProfileZapperStateIsSessionOnlyAndSeparateFromPersistentProfile() {
        let defaults = makeDefaults()
        let store = SumiAdblockZapperStore(userDefaults: defaults)

        store.setRules(
            [".persistent"],
            forHost: "example.com",
            profilePartitionId: "profile-a",
            isEphemeralProfile: false
        )
        store.setRules(
            [".private"],
            forHost: "example.com",
            profilePartitionId: "profile-a",
            isEphemeralProfile: true
        )

        XCTAssertEqual(
            store.state(
                forHost: "example.com",
                profilePartitionId: "profile-a",
                isEphemeralProfile: false
            ).rules,
            [".persistent"]
        )
        XCTAssertEqual(
            store.state(
                forHost: "example.com",
                profilePartitionId: "profile-a",
                isEphemeralProfile: true
            ).rules,
            [".private"]
        )

        let reloadedStore = SumiAdblockZapperStore(userDefaults: defaults)
        XCTAssertEqual(
            reloadedStore.state(
                forHost: "example.com",
                profilePartitionId: "profile-a",
                isEphemeralProfile: false
            ).rules,
            [".persistent"]
        )
        XCTAssertEqual(
            reloadedStore.state(
                forHost: "example.com",
                profilePartitionId: "profile-a",
                isEphemeralProfile: true
            ),
            .empty
        )
    }

    func testLegacyHostOnlyDefaultsAreNotLoadedAsProfileState() throws {
        let defaults = makeDefaults()
        let legacyState = [
            "example.com": SumiAdblockZapperStore.State(rules: [".legacy"], disabled: false),
        ]
        let legacyData = try JSONEncoder().encode(legacyState)
        defaults.set(legacyData, forKey: "settings.adblock.zapper.statesByHost.v1")

        let store = SumiAdblockZapperStore(userDefaults: defaults)

        XCTAssertEqual(
            store.state(
                forHost: "example.com",
                profilePartitionId: "profile-a",
                isEphemeralProfile: false
            ),
            .empty
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SumiAdblockZapperStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? preconditionFailure("Unable to create test user defaults")
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
