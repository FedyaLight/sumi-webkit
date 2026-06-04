import XCTest
@testable import Sumi

final class SumiImportExportTests: XCTestCase {
    func testBrowser2ZenLegacyNormalizesSidebarConcepts() throws {
        let json = """
        {
          "source": "arc",
          "total_spaces": 1,
          "spaces": [
            {
              "space_id": "arc-space-1",
              "space_name": "Work",
              "icon": "💼",
              "color": {"r": 0.1, "g": 0.2, "b": 0.3},
              "pinned_tabs": [
                {
                  "url": "https://mail.example.com",
                  "title": "Mail",
                  "folder_path": [],
                  "parent_id": "",
                  "index": 0,
                  "is_essential": true
                },
                {
                  "url": "https://docs.example.com",
                  "title": "Docs",
                  "folder_path": ["Parent", "Child"],
                  "parent_id": "folder-child",
                  "index": 1,
                  "is_essential": false
                }
              ],
              "open_tabs": [
                {
                  "url": "https://open.example.com",
                  "title": "Open",
                  "index": 0
                }
              ],
              "folders": [
                {
                  "folder_id": "folder-parent",
                  "title": "Parent",
                  "parent_id": "",
                  "space_id": "arc-space-1",
                  "children_ids": ["folder-child"],
                  "index": 0
                },
                {
                  "folder_id": "folder-child",
                  "title": "Child",
                  "parent_id": "folder-parent",
                  "space_id": "arc-space-1",
                  "children_ids": [],
                  "index": 1
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let document = try JSONDecoder().decode(SumiBrowser2ZenDocument.self, from: json)
        let data = SumiBrowser2ZenNormalizer.normalizedData(from: document)

        XCTAssertEqual(data.profiles.map(\.name), ["Arc Import"])
        XCTAssertEqual(data.spaces.map(\.name), ["Work"])
        XCTAssertEqual(data.essentials.map(\.title), ["Mail"])
        XCTAssertEqual(data.pinnedLaunchers.map(\.title), ["Docs"])
        XCTAssertEqual(data.pinnedLaunchers.first?.folderId, "folder-child")
        XCTAssertEqual(data.regularTabs.map(\.title), ["Open"])
        XCTAssertEqual(data.folders.map(\.sourcePath), [["Parent"], ["Parent", "Child"]])
    }

    @MainActor
    func testSumiExtensionBlockImportsExactPortableData() throws {
        let exact = SumiPortableData(
            profiles: [
                SumiPortableProfile(id: "profile-a", name: "Profile A", icon: "person", index: 0)
            ],
            spaces: [
                SumiPortableSpace(
                    id: "space-a",
                    name: "Space A",
                    icon: "🌐",
                    index: 0,
                    profileId: "profile-a",
                    themeDataBase64: nil,
                    color: nil
                )
            ],
            folders: [],
            essentials: [],
            pinnedLaunchers: [],
            regularTabs: [],
            bookmarks: []
        )
        let document = SumiBrowser2ZenDocument(
            source: "sumi",
            totalSpaces: 0,
            spaces: [],
            sumi: SumiBrowser2ZenExtension(formatVersion: 1, data: exact)
        )
        let payload = try JSONEncoder().encode(document)

        let imported = try SumiTransferExportService().importBrowser2ZenDocument(from: payload)

        XCTAssertEqual(imported, exact)
    }

    func testSumiBackupArchiveCarriesVersionedLogicalData() throws {
        let data = SumiPortableData(
            profiles: [
                SumiPortableProfile(id: "profile-a", name: "Profile A", icon: "person", index: 0)
            ]
        )
        let archive = SumiPortableArchive(
            includedCategories: [.profiles],
            warnings: ["logical only"],
            data: data
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(archive)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(SumiPortableArchive.self, from: payload)

        XCTAssertEqual(decoded.format, SumiPortableArchive.format)
        XCTAssertEqual(decoded.version, SumiPortableArchive.currentVersion)
        XCTAssertEqual(decoded.includedCategories, [.profiles])
        XCTAssertEqual(decoded.data, data)
    }
}
