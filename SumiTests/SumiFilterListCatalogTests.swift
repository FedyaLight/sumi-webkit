import XCTest

@testable import Sumi

final class SumiFilterListCatalogTests: XCTestCase {
    func testLoadsFullCatalogAndRecommendedDefaults() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }

        let catalog = try SumiFilterListCatalog.load(
            from: fixture.bundleDirectory.appendingPathComponent(
                "filter-catalog.json"
            )
        )

        XCTAssertEqual(catalog.lists.count, 79)
        XCTAssertEqual(catalog.defaultEnabledIDs.count, 8)
        XCTAssertEqual(
            Set(
                catalog.lists
                    .filter(\.defaultEnabled)
                    .map(\.displayName)
            ),
            [
                "AdGuard Base Filter",
                "AdGuard Tracking Protection Filter",
                "AdGuard URL Tracking Protection Filter",
                "Actually Legitimate URL Shortener Tool",
                "EasyPrivacy",
                "Online Security Filter",
                "Peter Lowe's Blocklist",
                "Anti-Adblock List",
            ]
        )
    }

    @MainActor
    func testSelectionDefaultsToggleResetAndAppliedState() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try SumiFilterListCatalog.load(
            from: fixture.bundleDirectory.appendingPathComponent(
                "filter-catalog.json"
            )
        )
        let suite = "SumiFilterListCatalogTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SumiProtectionSettings(userDefaults: defaults)

        XCTAssertEqual(
            settings.selectedFilterListIDs(in: catalog),
            catalog.defaultEnabledIDs
        )
        XCTAssertFalse(settings.filterListSelectionApplyNeeded(in: catalog))

        settings.setFilterList("list-20", enabled: true, catalog: catalog)
        XCTAssertTrue(
            settings.selectedFilterListIDs(in: catalog).contains("list-20")
        )
        XCTAssertTrue(settings.filterListSelectionApplyNeeded(in: catalog))

        settings.markFilterListSelectionApplied(in: catalog)
        XCTAssertFalse(settings.filterListSelectionApplyNeeded(in: catalog))

        settings.resetFilterListsToDefaults()
        XCTAssertEqual(
            settings.selectedFilterListIDs(in: catalog),
            catalog.defaultEnabledIDs
        )
        XCTAssertTrue(settings.filterListSelectionApplyNeeded(in: catalog))
    }
}

private struct CatalogFixture {
    let bundleDirectory: URL

    init() throws {
        bundleDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundleDirectory,
            withIntermediateDirectories: true
        )
        let defaults = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "AdGuard URL Tracking Protection Filter",
            "Actually Legitimate URL Shortener Tool",
            "EasyPrivacy",
            "Online Security Filter",
            "Peter Lowe's Blocklist",
            "Anti-Adblock List",
        ]
        let lists: [[String: Any]] = (0..<79).map { index in
            let name = index < defaults.count
                ? defaults[index]
                : "Optional list \(index)"
            return [
                "id": "list-\(index)",
                "displayName": name,
                "url": "https://example.org/list-\(index).txt",
                "category": index.isMultiple(of: 2) ? "ads" : "foreign",
                "defaultEnabled": index < defaults.count,
                "description": "Fixture list \(index)",
            ]
        }
        let data = try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "lists": lists,
            ],
            options: [.sortedKeys]
        )
        try data.write(
            to: bundleDirectory.appendingPathComponent("filter-catalog.json")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: bundleDirectory)
    }
}
