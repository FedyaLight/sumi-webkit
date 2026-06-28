@testable import Sumi
import XCTest

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
        XCTAssertNil(data.folders.first(where: { $0.id == "folder-parent" })?.parentFolderId)
        XCTAssertEqual(data.folders.first(where: { $0.id == "folder-child" })?.parentFolderId, "folder-parent")
        XCTAssertEqual(data.folders.first(where: { $0.id == "folder-child" })?.name, "Child")
    }

    func testArcImportPreservesNestedFolderHierarchy() throws {
        let json = """
        {
          "firebaseSyncState": {
            "syncData": {
              "spaceModels": [
                "space-a",
                {
                  "value": {
                    "title": "Work",
                    "customInfo": {
                      "iconType": { "emoji_v2": "💼" }
                    },
                    "profile": {
                      "custom": {
                        "_0": { "directoryBasename": "Default" }
                      }
                    }
                  }
                }
              ]
            }
          },
          "sidebar": {
            "containers": [
              {},
              {
                "spaces": [
                  "space-a",
                  {
                    "containerIDs": ["pinned", "pinned-root", "unpinned", "unpinned-root"]
                  }
                ],
                "items": [
                  "pinned-root",
                  { "childrenIds": ["folder-parent"] },
                  "unpinned-root",
                  { "childrenIds": [] },
                  "folder-parent",
                  {
                    "title": "Parent",
                    "data": { "list": {} },
                    "childrenIds": ["folder-child"]
                  },
                  "folder-child",
                  {
                    "title": "Child",
                    "parentID": "folder-parent",
                    "data": { "list": {} },
                    "childrenIds": ["tab-leaf"]
                  },
                  "tab-leaf",
                  {
                    "title": "Leaf",
                    "parentID": "folder-child",
                    "data": {
                      "tab": {
                        "savedURL": "https://leaf.example.com",
                        "savedTitle": "Leaf"
                      }
                    }
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArcSidebar-\(UUID().uuidString).json")
        try json.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try SumiArcImportParser().parse(sidebarURL: url)

        let parent = try XCTUnwrap(data.folders.first(where: { $0.id == "folder-parent" }))
        let child = try XCTUnwrap(data.folders.first(where: { $0.id == "folder-child" }))
        XCTAssertNil(parent.parentFolderId)
        XCTAssertEqual(child.parentFolderId, parent.id)
        XCTAssertEqual(child.sourcePath, ["Parent", "Child"])
        XCTAssertEqual(data.pinnedLaunchers.first?.folderId, child.id)
    }

    func testZenFolderRecordsPreserveNestedFolderHierarchy() throws {
        let records = SumiZenImportParser().flattenZenFolders([
            [
                "id": "zen-parent",
                "name": "Parent",
                "workspaceId": "zen-space",
                "collapsed": false,
            ],
            [
                "id": "zen-child",
                "name": "Child",
                "workspaceId": "zen-space",
                "parentId": "zen-parent",
                "collapsed": true,
            ],
        ])

        let parent = try XCTUnwrap(records.first(where: { $0.id == "zen-parent" }))
        let child = try XCTUnwrap(records.first(where: { $0.id == "zen-child" }))
        XCTAssertNil(parent.parentFolderId)
        XCTAssertEqual(child.parentFolderId, parent.id)
        XCTAssertEqual(child.sourcePath, ["Parent", "Child"])
        XCTAssertFalse(child.isOpen)
    }

    func testZenFolderRecordsUsePreviousSiblingInfoForNestedPosition() throws {
        let records = SumiZenImportParser().flattenZenFolders(
            [
                [
                    "id": "zen-parent",
                    "name": "Parent",
                    "workspaceId": "zen-space",
                ],
                [
                    "id": "zen-child",
                    "name": "Child",
                    "workspaceId": "zen-space",
                    "parentId": "zen-parent",
                    "prevSiblingInfo": [
                        "type": "tab",
                        "id": "tab-before-child",
                    ],
                ],
            ],
            pinnedSiblingIndexes: ["tab-before-child": 4]
        )

        let child = try XCTUnwrap(records.first(where: { $0.id == "zen-child" }))
        XCTAssertEqual(child.index, 5)
    }

    @MainActor
    func testImportNormalizationPreservesMixedFolderPinnedOrderWithinParent() {
        let spaceId = "space-a"
        let parentId = "folder-parent"
        let childFolderId = "folder-child"
        let firstPinId = "pin-first"
        let secondPinId = "pin-second"
        let childFolder = SumiPortableFolder(
            id: childFolderId,
            name: "Child",
            icon: "folder",
            colorHex: "#000000",
            spaceId: spaceId,
            parentFolderId: parentId,
            isOpen: true,
            index: 1,
            sourcePath: ["Parent", "Child"]
        )
        let firstPin = SumiPortableLauncher(
            id: firstPinId,
            title: "First",
            urlString: "https://first.example.com",
            index: 0,
            profileId: nil,
            executionProfileId: nil,
            spaceId: spaceId,
            folderId: parentId,
            iconAsset: nil,
            sourceSpaceId: spaceId
        )
        let secondPin = SumiPortableLauncher(
            id: secondPinId,
            title: "Second",
            urlString: "https://second.example.com",
            index: 2,
            profileId: nil,
            executionProfileId: nil,
            spaceId: spaceId,
            folderId: parentId,
            iconAsset: nil,
            sourceSpaceId: spaceId
        )

        let normalized = SumiImportApplier.normalizedSidebarContainerIndices(
            folders: [childFolder],
            pinnedLaunchers: [firstPin, secondPin]
        )

        XCTAssertEqual(normalized.pinnedLaunchers.first(where: { $0.id == firstPinId })?.index, 0)
        XCTAssertEqual(normalized.folders.first(where: { $0.id == childFolderId })?.index, 1)
        XCTAssertEqual(normalized.pinnedLaunchers.first(where: { $0.id == secondPinId })?.index, 2)
    }

    @MainActor
    func testBrowser2ZenExportIncludesNestedFolderParentsAndPaths() throws {
        let browserManager = BrowserManager()
        let space = Space(name: "Work", icon: "💼")
        let parent = TabFolder(name: "Parent", spaceId: space.id, index: 0)
        let child = TabFolder(name: "Child", spaceId: space.id, parentFolderId: parent.id, index: 0)
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            folderId: child.id,
            launchURL: URL(string: "https://nested.example.com")!,
            title: "Nested"
        )
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.setFolders([parent, child], for: space.id)
        browserManager.tabManager.setSpacePinnedShortcuts([pin], for: space.id)

        let payload = try SumiTransferExportService().exportBrowser2ZenDocument(from: browserManager)
        let document = try JSONDecoder().decode(SumiBrowser2ZenDocument.self, from: payload)
        let exportedSpace = try XCTUnwrap(document.spaces.first)
        let exportedChild = try XCTUnwrap(exportedSpace.folders.first(where: { $0.folderId == child.id.uuidString }))
        let exportedPin = try XCTUnwrap(exportedSpace.pinnedTabs.first(where: { $0.tabId == pin.id.uuidString }))

        XCTAssertEqual(exportedChild.parentId, parent.id.uuidString)
        XCTAssertEqual(exportedPin.parentId, child.id.uuidString)
        XCTAssertEqual(exportedPin.folderPath, ["Parent", "Child"])
    }

    @MainActor
    func testSumiExtensionBlockImportsExactPortableData() throws {
        let exact = SumiPortableData(
            profiles: [
                SumiPortableProfile(id: "profile-a", name: "Profile A", icon: "person", index: 0),
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
                ),
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
                SumiPortableProfile(id: "profile-a", name: "Profile A", icon: "person", index: 0),
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
