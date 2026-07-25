import XCTest

@testable import Sumi

/// Fixtures here mirror the shape of a real `StorableSidebar.json` taken from an
/// Arc install that never completed a Firebase sync: `spaceModels` is empty and
/// every space lives only in `sidebar.containers[1]`.
final class SumiArcImportParserTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    /// The headline regression: reading space metadata only from the Firebase
    /// mirror made the whole import throw on installs where that mirror is
    /// empty, which is the common case for a signed-out Arc.
    func testParsesSpacesFromLocalSidebarWhenSyncDataIsEmpty() throws {
        let url = try writeSidebar(sidebar(spaces: [
            arcSpace(id: "space-a", title: "Work", icon: ["emoji_v2": "🛠"]),
        ]))

        let result = try SumiArcImportParser().parseWithDiagnostics(sidebarURL: url)

        XCTAssertEqual(result.data.spaces.map(\.name), ["Work"])
        XCTAssertEqual(result.data.spaces.first?.icon, "🛠")
    }

    func testDerivesSpaceNameWhenTitleIsMissing() throws {
        let url = try writeSidebar(sidebar(spaces: [
            arcSpace(id: "thebrowser.company.defaultPersonalSpaceId", title: nil, icon: nil),
            arcSpace(id: "E99F70B7-2312-47E9-9000-000000000000", title: nil, icon: nil),
        ]))

        let result = try SumiArcImportParser().parseWithDiagnostics(sidebarURL: url)

        // Never a raw identifier: the default space is recognised by name, and
        // anything else falls back to its position.
        XCTAssertEqual(result.data.spaces.map(\.name), ["Personal", "Space 2"])
    }

    func testTranslatesArcGlyphIconAndDropsUnknownOnes() throws {
        let url = try writeSidebar(sidebar(spaces: [
            arcSpace(id: "space-a", title: "A", icon: ["icon": "planet"]),
            arcSpace(id: "space-b", title: "B", icon: ["icon": "not-a-real-glyph"]),
        ]))

        let result = try SumiArcImportParser().parseWithDiagnostics(sidebarURL: url)

        XCTAssertEqual(result.data.spaces.first?.icon, "globe.americas")
        XCTAssertEqual(result.data.spaces.last?.icon, "", "unknown glyphs fall back to the default dot")
    }

    func testSpaceGradientUsesTheWholeArcPalette() throws {
        let space = arcSpace(
            id: "space-a",
            title: "A",
            icon: nil,
            palette: [
                "midTone": ["red": 1.0, "green": 0.0, "blue": 0.0],
                "shaded": ["red": 0.0, "green": 1.0, "blue": 0.0],
                "tintedLight": ["red": 0.0, "green": 0.0, "blue": 1.0],
            ]
        )
        let url = try writeSidebar(sidebar(spaces: [space]))

        let result = try SumiArcImportParser().parseWithDiagnostics(sidebarURL: url)

        XCTAssertEqual(result.data.spaces.first?.colors?.map(\.hex), ["#FF0000", "#00FF00", "#0000FF"])
        XCTAssertEqual(result.data.spaces.first?.color?.hex, "#FF0000")
    }

    /// Arc stores extendedSRGB components, which go negative for wide-gamut
    /// colours; they must clamp rather than produce nonsense hex.
    func testClampsWideGamutColourComponents() throws {
        let url = try writeSidebar(sidebar(spaces: [
            arcSpace(
                id: "space-a",
                title: "A",
                icon: nil,
                palette: ["midTone": ["red": -0.409, "green": 0.848, "blue": 0.263]]
            ),
        ]))

        let result = try SumiArcImportParser().parseWithDiagnostics(sidebarURL: url)

        XCTAssertEqual(result.data.spaces.first?.color?.hex, "#00D843")
    }

    /// Essentials used to be gathered by walking an unordered dictionary, so the
    /// same install imported a different pin order on every run.
    func testEssentialsFollowTopAppsContainerOrder() throws {
        var items: [Any] = []
        for (index, title) in ["First", "Second", "Third"].enumerated() {
            items.append("essential-\(index)")
            items.append([
                "id": "essential-\(index)",
                "title": title,
                "data": ["tab": ["savedURL": "https://example.com/\(index)"]],
            ])
        }
        items.append("top-apps-container")
        items.append([
            "id": "top-apps-container",
            "childrenIds": ["essential-0", "essential-1", "essential-2"],
            "data": ["itemContainer": ["containerType": ["topApps": ["_0": ["default": true]]]]],
        ])

        var root = sidebar(spaces: [arcSpace(id: "space-a", title: "A", icon: nil)])
        var local = ((root["sidebar"] as! [String: Any])["containers"] as! [Any])[1] as! [String: Any]
        local["items"] = items
        local["topAppsContainerIDs"] = [["default": true], "top-apps-container"]
        root["sidebar"] = ["containers": [[:], local]]

        let result = try SumiArcImportParser().parseWithDiagnostics(sidebarURL: try writeSidebar(root))

        XCTAssertEqual(result.data.essentials.map(\.title), ["First", "Second", "Third"])
        XCTAssertEqual(result.data.essentials.map(\.index), [0, 1, 2])
    }

    // MARK: - Fixture construction

    private func sidebar(spaces: [(id: String, object: [String: Any])]) -> [String: Any] {
        var flattened: [Any] = []
        for space in spaces {
            flattened.append(space.id)
            flattened.append(space.object)
        }
        return [
            "version": 4,
            "sidebar": ["containers": [[:], ["spaces": flattened, "items": []]]],
            // Deliberately empty: this is the state that used to fail.
            "firebaseSyncState": ["syncData": ["spaceModels": []]],
        ]
    }

    private func arcSpace(
        id: String,
        title: String?,
        icon: [String: Any]?,
        palette: [String: Any]? = nil
    ) -> (id: String, object: [String: Any]) {
        var customInfo: [String: Any] = [:]
        if let icon { customInfo["iconType"] = icon }
        if let palette { customInfo["windowTheme"] = ["primaryColorPalette": palette] }

        var object: [String: Any] = [
            "id": id,
            "containerIDs": ["unpinned", "\(id)-unpinned", "pinned", "\(id)-pinned"],
            "profile": ["custom": ["_0": ["directoryBasename": "Default"]]],
        ]
        if let title { object["title"] = title }
        if customInfo.isEmpty == false { object["customInfo"] = customInfo }
        return (id, object)
    }

    private func writeSidebar(_ root: [String: Any]) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SumiArcImportParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let url = directory.appendingPathComponent("StorableSidebar.json")
        try JSONSerialization.data(withJSONObject: root).write(to: url)
        return url
    }
}
