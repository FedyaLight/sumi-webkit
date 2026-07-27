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
        let store = makeStore()
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
        let store = makeStore()
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
        let store = makeStore()

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
        let database = makeDatabase()
        let store = makeStore(database: database)

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

        let reloadedStore = makeStore(database: database)
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

    func testPersistentMutationDoesNotOverwriteUnreadableBaseline() throws {
        let database = makeDatabase()
        let storageKey = "adblock.zapper-states"
        let corruptPayload = Data("not-json".utf8)
        try database.transaction {
            try $0.documents.save(corruptPayload, forKey: storageKey)
        }
        let store = makeStore(database: database)

        store.setRules(
            [".late-rule"],
            forHost: "example.com",
            profilePartitionId: ProfileID.a,
            isEphemeralProfile: false
        )

        XCTAssertEqual(
            try database.read { try $0.documents.data(forKey: storageKey) },
            corruptPayload
        )
        XCTAssertEqual(
            store.state(
                forHost: "example.com",
                profilePartitionId: ProfileID.a,
                isEphemeralProfile: false
            ),
            .empty
        )
    }

    private func makeDatabase() -> SumiDatabase {
        try! SumiDatabase.inMemory()
    }

    private func makeStore(
        database: SumiDatabase? = nil
    ) -> SumiAdblockZapperStore {
        SumiAdblockZapperStore(
            database: database ?? makeDatabase(),
            profileReferenceAdmission: .testingAllowingReferences()
        )
    }
}
