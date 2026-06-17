import XCTest

@testable import Sumi

@MainActor
final class SumiBoostStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testStoreIsolatesBoostsByProfile() throws {
        let store = SumiBoostStore(rootDirectory: temporaryDirectory())
        let url = URL(string: "https://example.test/page")!
        let profileA = UUID()
        let profileB = UUID()

        _ = try store.createDraft(for: url, profileId: profileA, isEphemeral: false)

        XCTAssertEqual(store.boosts(for: url, profileId: profileA).count, 1)
        XCTAssertTrue(store.boosts(for: url, profileId: profileB).isEmpty)
    }

    func testStoreMatchesExactNormalizedHostOnly() throws {
        let store = SumiBoostStore(rootDirectory: temporaryDirectory())
        let profileId = UUID()

        _ = try store.createDraft(
            for: URL(string: "https://example.test:8443/page")!,
            profileId: profileId,
            isEphemeral: false
        )

        XCTAssertEqual(
            store.boosts(for: URL(string: "https://example.test/other")!, profileId: profileId).count,
            1
        )
        XCTAssertTrue(
            store.boosts(for: URL(string: "https://www.example.test/")!, profileId: profileId).isEmpty
        )
    }

    func testDiscardUnchangedDraftRemovesDraft() throws {
        let store = SumiBoostStore(rootDirectory: temporaryDirectory())
        let profileId = UUID()
        let url = URL(string: "https://example.test/")!
        let boost = try store.createDraft(for: url, profileId: profileId, isEphemeral: false)

        store.discardUnchangedDraft(boost)

        XCTAssertTrue(store.boosts(for: url, profileId: profileId).isEmpty)
        XCTAssertNil(store.activeBoost(for: url, profileId: profileId))
    }

    func testCustomCSSPersistsInSplitFileAndLoadsBack() throws {
        let directory = temporaryDirectory()
        let store = SumiBoostStore(rootDirectory: directory)
        let profileId = UUID()
        let url = URL(string: "https://example.test/")!
        let boost = try store.createDraft(for: url, profileId: profileId, isEphemeral: false)
        _ = try store.updateBoost(
            id: boost.id,
            profileId: profileId,
            host: "example.test",
            isEphemeral: false,
            mutate: { data in
                data.customCSS = ".hero { color: red; }"
            }
        )

        // updateBoost debounces disk writes (editor edits can fire many times
        // per second); flush so the on-disk state is observable synchronously.
        store.flushPendingWrites()

        let json = try String(
            contentsOf: directory.appendingPathComponent("boosts.json"),
            encoding: .utf8
        )
        let cssURL = directory
            .appendingPathComponent("css", isDirectory: true)
            .appendingPathComponent("\(boost.id.uuidString.lowercased()).css")

        XCTAssertFalse(json.contains(".hero { color: red; }"))
        XCTAssertEqual(try String(contentsOf: cssURL, encoding: .utf8), ".hero { color: red; }")

        let reloadedStore = SumiBoostStore(rootDirectory: directory)
        XCTAssertEqual(
            reloadedStore.activeBoost(for: url, profileId: profileId)?.data.customCSS,
            ".hero { color: red; }"
        )
    }

    func testExportImportKeepsBoostDataAndActivatesImportedBoost() throws {
        let sourceStore = SumiBoostStore(rootDirectory: temporaryDirectory())
        let targetStore = SumiBoostStore(rootDirectory: temporaryDirectory())
        let profileId = UUID()
        let url = URL(string: "https://example.test/")!
        let boost = try sourceStore.createDraft(for: url, profileId: profileId, isEphemeral: false)
        let updated = try sourceStore.updateBoost(
            id: boost.id,
            profileId: profileId,
            host: "example.test",
            isEphemeral: false,
            mutate: { data in
                data.boostName = "Imported"
                data.customCSS = "body { opacity: .9; }"
            }
        )

        let imported = try targetStore.importBoost(
            from: sourceStore.exportData(for: updated),
            for: url,
            profileId: profileId,
            isEphemeral: false
        )

        XCTAssertEqual(imported.data.boostName, "Imported")
        XCTAssertEqual(imported.data.customCSS, "body { opacity: .9; }")
        XCTAssertEqual(targetStore.activeBoost(for: url, profileId: profileId)?.id, imported.id)
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiBoostStoreTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }
}
