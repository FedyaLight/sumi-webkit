import Compression
import SQLite3

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

    func testZenImportWarnsWhenBookmarksCannotBeRead() throws {
        let profileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZenProfile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profileURL) }
        let sessionJSON = Data(
            """
            {
              "spaces": [
                { "uuid": "workspace-a", "name": "Work", "icon": "💼" }
              ],
              "folders": [],
              "tabs": []
            }
            """.utf8
        )
        try mozLZ4(sessionJSON).write(
            to: profileURL.appendingPathComponent("zen-sessions.jsonlz4")
        )
        try FileManager.default.createDirectory(
            at: profileURL.appendingPathComponent("places.sqlite"),
            withIntermediateDirectories: true
        )

        let result = try SumiZenImportParser().parseWithDiagnostics(profileURL: profileURL)

        XCTAssertTrue(result.data.bookmarks.isEmpty)
        XCTAssertTrue(
            result.warnings.contains {
                $0.contains("Zen bookmarks were skipped because places.sqlite could not be imported")
            }
        )
    }

    func testZenWorkspaceThemeColorsParseBothComponentScales() throws {
        let profileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZenProfile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profileURL) }
        let sessionJSON = Data(
            """
            {
              "spaces": [
                {
                  "uuid": "workspace-int",
                  "name": "Ints",
                  "icon": "💼",
                  "theme": { "gradientColors": [ { "c": [244, 239, 223] } ] }
                },
                {
                  "uuid": "workspace-float",
                  "name": "Floats",
                  "icon": "🎨",
                  "theme": { "gradientColors": [ { "c": [0.956, 0.937, 0.874] } ] }
                },
                {
                  "uuid": "workspace-multi",
                  "name": "Gradient",
                  "icon": "🌈",
                  "theme": {
                    "opacity": 0.5,
                    "gradientColors": [
                      { "c": [244, 239, 223] },
                      { "c": [221, 243, 216] },
                      { "c": [243, 216, 225] }
                    ]
                  }
                }
              ],
              "folders": [],
              "tabs": []
            }
            """.utf8
        )
        try mozLZ4(sessionJSON).write(
            to: profileURL.appendingPathComponent("zen-sessions.jsonlz4")
        )

        let result = try SumiZenImportParser().parseWithDiagnostics(profileURL: profileURL)

        let intSpace = try XCTUnwrap(result.data.spaces.first(where: { $0.id == "workspace-int" }))
        XCTAssertEqual(intSpace.color?.hex, "#F4EFDF")

        // Normalized 0-1 floats must not be divided by 255 again (that used to
        // collapse every imported Zen theme to near-black #010101).
        let floatSpace = try XCTUnwrap(result.data.spaces.first(where: { $0.id == "workspace-float" }))
        XCTAssertEqual(floatSpace.color?.hex, "#F4EFDF")

        let multiSpace = try XCTUnwrap(result.data.spaces.first(where: { $0.id == "workspace-multi" }))
        XCTAssertEqual(multiSpace.colors?.count, 3)
        XCTAssertEqual(multiSpace.colors?.last?.hex, "#F3D8E1")
        XCTAssertEqual(try XCTUnwrap(multiSpace.themeOpacity), 0.5, accuracy: 0.0001)
    }

    func testZenImportKeepsOnlyCookiePartitionsUsedByWorkspaces() throws {
        let profileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("abc.default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profileURL) }
        let sessionJSON = Data(
            """
            {
              "spaces": [
                { "uuid": "personal", "name": "Personal" },
                { "uuid": "banking", "name": "Banking", "containerTabId": 2 }
              ],
              "folders": [],
              "tabs": [
                {
                  "zenWorkspace": "personal",
                  "userContextId": 0,
                  "entries": [{ "url": "https://personal.example" }]
                },
                {
                  "zenWorkspace": "personal",
                  "userContextId": -1,
                  "entries": [{ "url": "about:thumbnail" }]
                }
              ]
            }
            """.utf8
        )
        try mozLZ4(sessionJSON).write(
            to: profileURL.appendingPathComponent("zen-sessions.jsonlz4")
        )
        try JSONSerialization.data(withJSONObject: [
            "identities": [
                ["userContextId": 1, "name": "Unused", "public": true],
                ["userContextId": 2, "l10nID": "user-context-banking", "public": true],
                ["userContextId": -1, "l10nID": "userContextIdInternal.thumbnail", "public": true],
                ["userContextId": 99, "name": "Extension internals", "public": false],
            ],
        ]).write(to: profileURL.appendingPathComponent("containers.json"))

        let data = try SumiZenImportParser().parse(profileURL: profileURL)

        XCTAssertEqual(data.profiles.map(\.name), ["default", "Banking"])
        XCTAssertEqual(
            data.profiles.map(\.id),
            ["zen-abc.default-container-0", "zen-abc.default-container-2"]
        )
        XCTAssertEqual(
            data.profiles.compactMap(\.sourceDirectoryKey),
            ["abc.default|userContextId=0", "abc.default|userContextId=2"]
        )
        XCTAssertEqual(
            data.spaces.map(\.profileId),
            data.profiles.map(\.id)
        )
    }

    func testZenProfileDetectionSkipsDirectoriesWithoutPlacesDatabase() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZenHome-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let profilesRoot = home.appendingPathComponent(
            "Library/Application Support/zen/Profiles",
            isDirectory: true
        )

        for name in ["Beta.default", "Alpha.default", "MissingPlaces.default"] {
            try FileManager.default.createDirectory(
                at: profilesRoot.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        for name in ["Beta.default", "Alpha.default"] {
            try Data().write(to: profilesRoot.appendingPathComponent("\(name)/places.sqlite"))
        }
        try Data().write(to: profilesRoot.appendingPathComponent("NotAProfile.txt"))

        let zen = try XCTUnwrap(
            SumiBrowserSourceCatalog
                .detect(homeDirectory: home, applications: NoApplicationsInstalled())
                .first { $0.family == .zen }
        )

        XCTAssertEqual(zen.profiles.map(\.sourceDirectoryKey), ["Alpha.default", "Beta.default"])
        XCTAssertNil(zen.accessIssue)
    }

    /// Detection must still find a browser whose data is on disk even when the
    /// application itself is not installed.
    private struct NoApplicationsInstalled: SumiInstalledApplicationLocating {
        func isInstalled(bundleIdentifier: String) -> Bool { false }
        func isRunning(bundleIdentifier: String) -> Bool { false }
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

        let normalized = SumiImportDataNormalizer.normalizedSidebarContainerIndices(
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
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.structuralCollectionMutationOwner.setFolders([parent, child], for: space.id)
        browserManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)

        let portableData = SumiImportExportSnapshot.makeData(
            profiles: browserManager.profileManager.profiles,
            state: browserManager.tabStateStore,
            bookmarks: browserManager.bookmarkManager
                .snapshot(sortMode: .manual).root.children
        )
        let payload = try SumiTransferExportService()
            .exportBrowser2ZenDocument(from: portableData)
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
                SumiPortableProfile(id: "profile-a", name: "Profile A", index: 0),
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
                SumiPortableProfile(id: "profile-a", name: "Profile A", index: 0),
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

    func testZenBackupExportIsRestorableByBrowser2ZenV1Layout() throws {
        let profileId = "profile-a"
        let spaceId = "space-a"
        let data = SumiPortableData(
            profiles: [
                SumiPortableProfile(id: profileId, name: "Personal", index: 0),
            ],
            spaces: [
                SumiPortableSpace(
                    id: spaceId,
                    name: "Home",
                    icon: "🏠",
                    index: 0,
                    profileId: profileId,
                    themeDataBase64: nil,
                    color: SumiPortableRGBColor(r: 0.2, g: 0.4, b: 0.8)
                ),
            ],
            folders: [
                SumiPortableFolder(
                    id: "folder-a",
                    name: "Daily",
                    icon: "folder",
                    colorHex: "#000000",
                    spaceId: spaceId,
                    parentFolderId: nil,
                    isOpen: true,
                    index: 0,
                    sourcePath: ["Daily"]
                ),
            ],
            essentials: [],
            pinnedLaunchers: [
                SumiPortableLauncher(
                    id: "pin-a",
                    title: "Mail",
                    urlString: "https://mail.example.com",
                    index: 0,
                    profileId: nil,
                    executionProfileId: profileId,
                    spaceId: spaceId,
                    folderId: "folder-a",
                    iconAsset: nil,
                    sourceSpaceId: spaceId
                ),
            ],
            regularTabs: [
                SumiPortableRegularTab(
                    id: "tab-a",
                    title: "Docs",
                    urlString: "https://docs.example.com",
                    index: 0,
                    spaceId: spaceId,
                    profileId: profileId,
                    folderId: nil
                ),
            ],
            bookmarks: [
                SumiPortableBookmarkNode(
                    name: "Example",
                    kind: .bookmark,
                    urlString: "https://example.com",
                    children: []
                ),
            ]
        )
        let cookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .name: "session",
                .value: "abc123",
                .domain: ".example.com",
                .path: "/",
                .expires: Date(timeIntervalSince1970: 4_102_444_800),
                .secure: "TRUE",
            ])
        )
        let archive = temporaryImportFile(named: "Sumi-\(UUID().uuidString).zenbackup")
        let extracted = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiZenExtract-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: archive)
            try? FileManager.default.removeItem(at: extracted)
        }

        try SumiZenBackupExportService().write(
            data: data,
            cookiesByProfileId: [profileId: [cookie]],
            history: [
                SumiZenHistoryVisit(
                    urlString: "https://history.example.com",
                    title: "History",
                    visitedAt: Date(timeIntervalSince1970: 1_700_000_000)
                ),
            ],
            to: archive
        )
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try extractTarGzip(archive, to: extracted)

        let manifestData = try Data(contentsOf: extracted.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        XCTAssertEqual(manifest["format_version"] as? Int, 1)
        XCTAssertEqual(
            Set(manifest["included"] as? [String] ?? []),
            ["workspaces", "browsing", "cookies"]
        )

        let sessionsData = try SumiMozillaLZ4Decoder.decode(
            Data(contentsOf: extracted.appendingPathComponent("profile/zen-sessions.jsonlz4"))
        )
        let sessions = try XCTUnwrap(
            JSONSerialization.jsonObject(with: sessionsData) as? [String: Any]
        )
        let sessionFolders = try XCTUnwrap(sessions["folders"] as? [[String: Any]])
        let sessionGroups = try XCTUnwrap(sessions["groups"] as? [[String: Any]])
        let sessionTabs = try XCTUnwrap(sessions["tabs"] as? [[String: Any]])
        XCTAssertEqual(sessionGroups.map { $0["id"] as? String }, ["folder-a"])
        let emptyId = try XCTUnwrap((sessionFolders.first?["emptyTabIds"] as? [String])?.first)
        let placeholder = try XCTUnwrap(
            sessionTabs.first { ($0["zenSyncId"] as? String) == emptyId }
        )
        XCTAssertEqual(placeholder["zenIsEmpty"] as? Bool, true)
        XCTAssertEqual(placeholder["groupId"] as? String, "folder-a")
        let pinned = try XCTUnwrap(
            sessionTabs.first { ($0["zenSyncId"] as? String) == "pin-a" }
        )
        XCTAssertNotNil(pinned["_zenPinnedInitialState"] as? [String: Any])

        let restored = try SumiZenImportParser().parse(
            profileURL: extracted.appendingPathComponent("profile", isDirectory: true)
        )
        XCTAssertEqual(restored.spaces.map(\.name), ["Home"])
        XCTAssertEqual(restored.folders.map(\.name), ["Daily"])
        XCTAssertEqual(restored.pinnedLaunchers.map(\.urlString), ["https://mail.example.com"])
        XCTAssertEqual(restored.regularTabs.map(\.urlString), ["https://docs.example.com"])
        XCTAssertEqual(restored.bookmarks.reduce(0) { $0 + $1.totalBookmarkCount }, 1)

        let placesURL = extracted.appendingPathComponent("profile/places.sqlite")
        var placesDatabase: OpaquePointer?
        XCTAssertEqual(sqlite3_open(placesURL.path, &placesDatabase), SQLITE_OK)
        defer { sqlite3_close(placesDatabase) }
        var hashStatement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                placesDatabase,
                "SELECT COUNT(*) FROM moz_places WHERE url_hash != 0",
                -1,
                &hashStatement,
                nil
            ),
            SQLITE_OK
        )
        defer { sqlite3_finalize(hashStatement) }
        XCTAssertEqual(sqlite3_step(hashStatement), SQLITE_ROW)
        XCTAssertGreaterThan(sqlite3_column_int(hashStatement, 0), 0)

        let cookiesURL = extracted.appendingPathComponent("profile/cookies.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(cookiesURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                "SELECT name, value, originAttributes FROM moz_cookies",
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 0)), "session")
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 1)), "abc123")
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 2)), "^userContextId=1")
    }

    func testBackupV1ScopeMatchesPortableModelAndNamesEveryExclusion() {
        XCTAssertEqual(
            SumiBackupV1Scope.portableCategories,
            [.profiles, .spaces, .themes, .bookmarks, .essentials,
             .pinnedLaunchers, .folders, .regularTabs]
        )
        XCTAssertEqual(
            SumiBackupV1Scope.excludedDataFamilies,
            [.history, .permissionDecisions, .extensionMetadataAndPayloads,
             .cookies, .passwords, .webKitWebsiteData, .caches, .downloads,
             .preferencesAndSessionSettings]
        )
        for exclusion in SumiBackupV1Scope.excludedDataFamilies {
            XCTAssertTrue(
                SumiBackupV1Scope.warning.contains(exclusion.warningLabel),
                "Backup warning omitted \(exclusion.rawValue)"
            )
        }
    }

    @MainActor
    func testPreviewFileImportReportsNewerSumiBackupInsteadOfFallingBackToBrowser2Zen() async throws {
        var archive = SumiPortableArchive(
            includedCategories: [.profiles],
            data: SumiPortableData(
                profiles: [
                    SumiPortableProfile(id: "profile-a", name: "Profile A", index: 0),
                ]
            )
        )
        archive.version = SumiPortableArchive.currentVersion + 1
        let url = temporaryImportFile(named: "future-\(UUID().uuidString).sumibackup")
        try encodeBackup(archive).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await SumiBrowserImportService().previewFileImport(fileURL: url)
            XCTFail("Expected unsupported Sumi backup error")
        } catch {
            guard case SumiImportExportError.unsupportedFile(let message) = error else {
                XCTFail("Expected unsupported Sumi backup error, got \(error)")
                return
            }
            XCTAssertEqual(message, "This Sumi backup was created by a newer version of Sumi.")
        }
    }

    @MainActor
    func testPreviewFileImportReportsCorruptSumiBackupInsteadOfFallingBackToBrowser2Zen() async throws {
        let url = temporaryImportFile(named: "corrupt-\(UUID().uuidString).sumibackup")
        try Data("{".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await SumiBrowserImportService().previewFileImport(fileURL: url)
            XCTFail("Expected corrupt Sumi backup error")
        } catch {
            guard case SumiImportExportError.unsupportedFile(let message) = error else {
                XCTFail("Expected unsupported Sumi backup error, got \(error)")
                return
            }
            XCTAssertTrue(
                message.hasPrefix("This Sumi backup could not be read:"),
                "Unexpected corrupt backup error: \(message)"
            )
        }
    }

    @MainActor
    func testPreviewFileImportRecognizesRenamedSumiBackupByFormat() async throws {
        let archive = SumiPortableArchive(
            includedCategories: [.profiles],
            warnings: ["logical only"],
            data: SumiPortableData(
                profiles: [
                    SumiPortableProfile(id: "profile-a", name: "Profile A", index: 0),
                ]
            )
        )
        let url = temporaryImportFile(named: "backup-\(UUID().uuidString).json")
        try encodeBackup(archive).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let preview = try await SumiBrowserImportService().previewFileImport(fileURL: url)

        XCTAssertEqual(preview.sourceKind, .sumiBackup)
        XCTAssertEqual(preview.defaultMode, .replace)
        XCTAssertEqual(preview.data.profiles.map(\.name), ["Profile A"])
        XCTAssertEqual(preview.warnings, ["logical only"])
    }

    @MainActor
    func testPreviewFileImportKeepsBrowser2ZenFallbackForNonBackupJSON() async throws {
        let document = SumiBrowser2ZenDocument(
            source: "arc",
            totalSpaces: 1,
            spaces: [
                SumiBrowser2ZenSpace(
                    spaceId: "space-a",
                    spaceName: "Work",
                    icon: nil,
                    color: nil,
                    totalPinnedTabs: nil,
                    totalOpenTabs: nil,
                    totalFolders: nil,
                    pinnedTabs: [
                        SumiBrowser2ZenTab(
                            url: "https://docs.example.com",
                            title: "Docs",
                            spaceId: nil,
                            spaceName: nil,
                            folderPath: [],
                            tabId: "tab-a",
                            parentId: nil,
                            index: 0,
                            isEssential: false
                        ),
                    ],
                    openTabs: [],
                    folders: []
                ),
            ],
            sumi: nil
        )
        let url = temporaryImportFile(named: "browser2zen-\(UUID().uuidString).json")
        try JSONEncoder().encode(document).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let preview = try await SumiBrowserImportService().previewFileImport(fileURL: url)

        XCTAssertEqual(preview.sourceKind, .browser2zen)
        XCTAssertEqual(preview.defaultMode, .merge)
        XCTAssertEqual(preview.data.spaces.map(\.name), ["Work"])
        XCTAssertEqual(preview.data.pinnedLaunchers.map(\.title), ["Docs"])
    }

    private func temporaryImportFile(named name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: false)
    }

    private func encodeBackup(_ archive: SumiPortableArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    private func mozLZ4(_ payload: Data) throws -> Data {
        let outputCapacity = payload.count + 64
        var output = Data(count: outputCapacity)
        let compressedSize = output.withUnsafeMutableBytes { outPtr in
            payload.withUnsafeBytes { inPtr in
                compression_encode_buffer(
                    outPtr.bindMemory(to: UInt8.self).baseAddress!,
                    outputCapacity,
                    inPtr.bindMemory(to: UInt8.self).baseAddress!,
                    payload.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }
        guard compressedSize > 0 else {
            throw SumiImportExportError.exportFailed("Could not build test LZ4 payload.")
        }

        var archive = Data([0x6D, 0x6F, 0x7A, 0x4C, 0x7A, 0x34, 0x30, 0x00])
        let size = UInt32(payload.count)
        archive.append(UInt8(size & 0xFF))
        archive.append(UInt8((size >> 8) & 0xFF))
        archive.append(UInt8((size >> 16) & 0xFF))
        archive.append(UInt8((size >> 24) & 0xFF))
        archive.append(output.prefix(compressedSize))
        return archive
    }

    private func extractTarGzip(_ archive: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archive.path, "-C", directory.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "SumiZenBackupTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: String(
                        decoding: errors.fileHandleForReading.readDataToEndOfFile(),
                        as: UTF8.self
                    ),
                ]
            )
        }
    }
}
