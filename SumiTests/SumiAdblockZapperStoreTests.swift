import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiAdblockZapperStoreTests: XCTestCase {
    private enum ProfileID {
        static let a = "00000000-0000-0000-0000-00000000000A"
        static let b = "00000000-0000-0000-0000-00000000000B"
    }

    override func tearDown() async throws {
        await MainActor.run {
            SumiAdblockZapperInjector.resetForTesting()
        }
        try await super.tearDown()
    }

    func testInjectorSkipsJavaScriptWhenHostHasNoRules() {
        let store = SumiAdblockZapperStore(userDefaults: makeDefaults())
        let webView = WKWebView()
        var evaluatedScripts: [String] = []
        SumiAdblockZapperInjector.evaluateScript = { _, script in
            evaluatedScripts.append(script)
        }

        SumiAdblockZapperInjector.applySavedRules(
            to: webView,
            host: "example.com",
            profilePartitionId: ProfileID.a,
            isEphemeralProfile: false,
            store: store
        )
        SumiAdblockZapperInjector.clearAppliedRules(to: webView)

        XCTAssertTrue(evaluatedScripts.isEmpty)
    }

    func testInjectorClearsOnlyAfterRulesWereApplied() {
        let defaults = makeDefaults()
        let store = SumiAdblockZapperStore(userDefaults: defaults)
        store.setRules(
            [".ad-slot"],
            forHost: "example.com",
            profilePartitionId: ProfileID.a,
            isEphemeralProfile: false
        )
        let webView = WKWebView()
        var evaluatedScripts: [String] = []
        SumiAdblockZapperInjector.evaluateScript = { _, script in
            evaluatedScripts.append(script)
        }

        SumiAdblockZapperInjector.applySavedRules(
            to: webView,
            host: "example.com",
            profilePartitionId: ProfileID.a,
            isEphemeralProfile: false,
            store: store
        )
        XCTAssertEqual(evaluatedScripts.count, 1)
        XCTAssertTrue(evaluatedScripts[0].contains(".ad-slot"))

        SumiAdblockZapperInjector.clearAppliedRules(to: webView)
        XCTAssertEqual(evaluatedScripts.count, 2)

        // The clear removed the tracking flag, so further clears are skipped.
        SumiAdblockZapperInjector.clearAppliedRules(to: webView)
        XCTAssertEqual(evaluatedScripts.count, 2)
    }

    func testPersistentProfilesDoNotShareZapperStateForSameHost() {
        let defaults = makeDefaults()
        let store = SumiAdblockZapperStore(userDefaults: defaults)

        store.setRules(
            [".ad-slot"],
            forHost: "Example.com",
            profilePartitionId: ProfileID.a,
            isEphemeralProfile: false
        )
        store.setRules(
            [".promo"],
            forHost: "example.com",
            profilePartitionId: ProfileID.b,
            isEphemeralProfile: false
        )
        store.setEnabled(
            false,
            forHost: "example.com",
            profilePartitionId: ProfileID.a,
            isEphemeralProfile: false
        )

        let profileAState = store.state(
            forHost: "example.com",
            profilePartitionId: ProfileID.a,
            isEphemeralProfile: false
        )
        let profileBState = store.state(
            forHost: "example.com",
            profilePartitionId: ProfileID.b,
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
            profilePartitionId: ProfileID.a,
            isEphemeralProfile: false
        )
        store.setRules(
            [".private"],
            forHost: "example.com",
            profilePartitionId: ProfileID.a,
            isEphemeralProfile: true
        )

        XCTAssertEqual(
            store.state(
                forHost: "example.com",
                profilePartitionId: ProfileID.a,
                isEphemeralProfile: false
            ).rules,
            [".persistent"]
        )
        XCTAssertEqual(
            store.state(
                forHost: "example.com",
                profilePartitionId: ProfileID.a,
                isEphemeralProfile: true
            ).rules,
            [".private"]
        )

        let reloadedStore = SumiAdblockZapperStore(userDefaults: defaults)
        XCTAssertEqual(
            reloadedStore.state(
                forHost: "example.com",
                profilePartitionId: ProfileID.a,
                isEphemeralProfile: false
            ).rules,
            [".persistent"]
        )
        XCTAssertEqual(
            reloadedStore.state(
                forHost: "example.com",
                profilePartitionId: ProfileID.a,
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
                profilePartitionId: ProfileID.a,
                isEphemeralProfile: false
            ),
            .empty
        )
    }

    func testPersistentMutationDoesNotOverwriteUnreadableBaseline() {
        let defaults = makeDefaults()
        let storageKey =
            "settings.adblock.zapper.statesByPersistentProfileAndHost.v1"
        let corruptPayload = Data("not-json".utf8)
        defaults.set(corruptPayload, forKey: storageKey)
        let store = SumiAdblockZapperStore(userDefaults: defaults)

        store.setRules(
            [".late-rule"],
            forHost: "example.com",
            profilePartitionId: ProfileID.a,
            isEphemeralProfile: false
        )

        XCTAssertEqual(defaults.data(forKey: storageKey), corruptPayload)
        XCTAssertEqual(
            store.state(
                forHost: "example.com",
                profilePartitionId: ProfileID.a,
                isEphemeralProfile: false
            ),
            .empty
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SumiAdblockZapperStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
