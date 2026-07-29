import Compression
import Foundation
import GRDB

struct SumiZenHistoryVisit: Sendable {
    var urlString: String
    var title: String
    var visitedAt: Date
}

struct SumiZenBackupExportService {
    static let formatVersion = 1

    func write(
        data: SumiPortableData,
        cookiesByProfileId: [String: [HTTPCookie]],
        history: [SumiZenHistoryVisit],
        to outputURL: URL
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiZenBackup-\(UUID().uuidString)", isDirectory: true)
        let profile = root.appendingPathComponent("profile", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let contextByProfile = Dictionary(
            uniqueKeysWithValues: data.profiles.sorted { $0.index < $1.index }
                .enumerated().map { ($0.element.id, $0.offset + 1) }
        )
        try writeContainers(
            data.profiles,
            contextByProfile: contextByProfile,
            to: profile.appendingPathComponent("containers.json")
        )
        try writeSessions(
            data,
            contextByProfile: contextByProfile,
            to: profile.appendingPathComponent("zen-sessions.jsonlz4")
        )
        try writePlaces(
            bookmarks: data.bookmarks,
            history: history,
            to: profile.appendingPathComponent("places.sqlite")
        )
        try writeCookies(
            cookiesByProfileId,
            contextByProfile: contextByProfile,
            to: profile.appendingPathComponent("cookies.sqlite")
        )

        let inventory = [
            "containers.json",
            "cookies.sqlite",
            "places.sqlite",
            "zen-sessions.jsonlz4",
        ]
        let manifest: [String: Any] = [
            "format_version": Self.formatVersion,
            "browser2zen_version": "sumi-compatible-1",
            "source_profile_name": "Sumi",
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "included": ["workspaces", "browsing", "cookies"],
            "file_inventory": inventory,
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
        try archive(root: root, outputURL: outputURL)
    }

    private func writeContainers(
        _ profiles: [SumiPortableProfile],
        contextByProfile: [String: Int],
        to url: URL
    ) throws {
        let identities = profiles.sorted { $0.index < $1.index }.map { profile in
            [
                "userContextId": contextByProfile[profile.id] ?? 1,
                "public": true,
                "icon": "fingerprint",
                "color": Self.containerColors[
                    max((contextByProfile[profile.id] ?? 1) - 1, 0)
                        % Self.containerColors.count
                ],
                "name": profile.name,
            ] as [String: Any]
        }
        let document: [String: Any] = [
            "version": 5,
            "lastUserContextId": contextByProfile.values.max() ?? 0,
            "identities": identities,
        ]
        try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: url, options: .atomic)
    }

    private func writeSessions(
        _ data: SumiPortableData,
        contextByProfile: [String: Int],
        to url: URL
    ) throws {
        let spacesById = Dictionary(
            data.spaces.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let folders = data.folders.map { folder -> [String: Any] in
            let placeholderId = "\(folder.id)-empty"
            return [
                "pinned": true,
                "splitViewGroup": false,
                "id": folder.id,
                "name": folder.name,
                "collapsed": !folder.isOpen,
                "saveOnWindowClose": true,
                "parentId": folder.parentFolderId.map { $0 as Any } ?? NSNull(),
                "prevSiblingInfo": NSNull(),
                "emptyTabIds": [placeholderId],
                "userIcon": folder.icon,
                "workspaceId": folder.spaceId,
            ]
        }
        // Zen only materializes a folder when a matching group exists. This is
        // part of browser2zen's session shape even though both records describe
        // the same logical folder.
        let groups = data.folders.map { folder -> [String: Any] in
            [
                "pinned": true,
                "splitView": false,
                "id": folder.id,
                "name": folder.name,
                "color": "zen-workspace-color",
                "collapsed": !folder.isOpen,
                "saveOnWindowClose": true,
            ]
        }
        var tabs = data.folders.map { folder in
            folderPlaceholder(
                id: "\(folder.id)-empty",
                folderId: folder.id
            )
        }
        for pin in data.pinnedLaunchers {
            guard let spaceId = pin.spaceId, let space = spacesById[spaceId] else { continue }
            let profileId = pin.executionProfileId ?? space.profileId
            tabs.append(
                sessionTab(
                    id: pin.id,
                    title: pin.title,
                    url: pin.urlString,
                    workspaceId: spaceId,
                    contextId: profileId.flatMap { contextByProfile[$0] } ?? 0,
                    pinned: true,
                    essential: false,
                    folderId: pin.folderId,
                    index: pin.index
                )
            )
        }
        let firstSpaceByProfile = Dictionary(
            data.spaces.sorted { $0.index < $1.index }.compactMap { space in
                space.profileId.map { ($0, space.id) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        for pin in data.essentials {
            guard let profileId = pin.profileId,
                  let spaceId = firstSpaceByProfile[profileId] else { continue }
            tabs.append(
                sessionTab(
                    id: pin.id,
                    title: pin.title,
                    url: pin.urlString,
                    workspaceId: spaceId,
                    contextId: contextByProfile[profileId] ?? 0,
                    pinned: true,
                    essential: true,
                    folderId: nil,
                    index: pin.index
                )
            )
        }
        for tab in data.regularTabs {
            let profileId = tab.profileId ?? spacesById[tab.spaceId]?.profileId
            tabs.append(
                sessionTab(
                    id: tab.id,
                    title: tab.title,
                    url: tab.urlString,
                    workspaceId: tab.spaceId,
                    contextId: profileId.flatMap { contextByProfile[$0] } ?? 0,
                    pinned: false,
                    essential: false,
                    folderId: tab.folderId,
                    index: tab.index
                )
            )
        }

        let spaces = data.spaces.sorted { $0.index < $1.index }.map { space -> [String: Any] in
            let colors = space.colors ?? space.color.map { [$0] } ?? []
            return [
                "uuid": space.id,
                "name": space.name,
                "icon": space.icon,
                "theme": [
                    "type": "gradient",
                    "gradientColors": colors.map {
                        [
                            "c": [
                                Int(($0.r * 255).rounded()),
                                Int(($0.g * 255).rounded()),
                                Int(($0.b * 255).rounded()),
                            ],
                            "isCustom": true,
                            "algorithm": "floating",
                            "isPrimary": true,
                        ] as [String: Any]
                    },
                    "opacity": space.themeOpacity ?? 0.5,
                    "texture": 0,
                ] as [String: Any],
                "containerTabId": space.profileId.flatMap { contextByProfile[$0] } ?? 0,
                "hasCollapsedPinnedTabs": false,
            ]
        }
        let document: [String: Any] = [
            "spaces": spaces,
            "tabs": tabs,
            "folders": folders,
            "groups": groups,
            "splitViewData": [],
            "lastCollected": Int(Date().timeIntervalSince1970 * 1_000),
        ]
        let payload = try JSONSerialization.data(withJSONObject: document)
        try mozLZ4(payload).write(to: url, options: .atomic)
    }

    private func sessionTab(
        id: String,
        title: String,
        url: String,
        workspaceId: String,
        contextId: Int,
        pinned: Bool,
        essential: Bool,
        folderId: String?,
        index: Int
    ) -> [String: Any] {
        var tab: [String: Any] = [
            "entries": [["url": url, "title": title]],
            "index": max(index + 1, 1),
            "lastAccessed": Int(Date().timeIntervalSince1970 * 1_000),
            "pinned": pinned,
            "hidden": false,
            "zenWorkspace": workspaceId,
            "zenSyncId": id,
            "zenEssential": essential,
            "zenDefaultUserContextId": contextId,
            "zenPinnedIcon": NSNull(),
            "zenIsEmpty": false,
            "zenHasStaticIcon": false,
            "zenGlanceId": NSNull(),
            "zenIsGlance": false,
            "searchMode": NSNull(),
            "userContextId": contextId,
            "attributes": [:],
            "indexInWorkspace": index,
        ]
        if pinned {
            tab["_zenPinnedInitialState"] = [
                "entry": ["url": url, "title": title],
                "image": NSNull(),
            ] as [String: Any]
        }
        if let folderId { tab["groupId"] = folderId }
        return tab
    }

    private func folderPlaceholder(id: String, folderId: String) -> [String: Any] {
        [
            "entries": [
                [
                    "url": "about:blank",
                    "triggeringPrincipal_base64": "{\"3\":{}}",
                ],
            ],
            "lastAccessed": Int(Date().timeIntervalSince1970 * 1_000),
            "pinned": true,
            "hidden": false,
            "groupId": folderId,
            "zenWorkspace": NSNull(),
            "zenSyncId": id,
            "zenEssential": false,
            "zenDefaultUserContextId": NSNull(),
            "zenPinnedIcon": NSNull(),
            "zenIsEmpty": true,
            "zenHasStaticIcon": false,
            "zenGlanceId": NSNull(),
            "zenIsGlance": false,
            "searchMode": NSNull(),
            "userContextId": 0,
            "attributes": [:],
            "index": 1,
        ]
    }

    private func writePlaces(
        bookmarks: [SumiPortableBookmarkNode],
        history: [SumiZenHistoryVisit],
        to url: URL
    ) throws {
        try withDatabase(at: url) { database in
            try database.execute(sql: Self.placesSchema)
            for root in Self.bookmarkRoots {
                try insertBookmarkFolder(
                    database,
                    id: root.id,
                    parent: root.parent,
                    position: Int(root.id - 1),
                    title: root.title,
                    guid: root.guid
                )
            }

            var nextPlaceId: Int64 = 100
            var nextBookmarkId: Int64 = 100
            var nextVisitId: Int64 = 1
            var placeIdByURL: [String: Int64] = [:]

            func placeId(urlString: String, title: String) throws -> Int64 {
                if let existing = placeIdByURL[urlString] { return existing }
                let id = nextPlaceId
                nextPlaceId += 1
                try insertPlace(database, id: id, urlString: urlString, title: title)
                placeIdByURL[urlString] = id
                return id
            }

            func insertNodes(
                _ nodes: [SumiPortableBookmarkNode],
                parent: Int64
            ) throws {
                for (position, node) in nodes.enumerated() {
                    let id = nextBookmarkId
                    nextBookmarkId += 1
                    if node.kind == .folder {
                        try insertBookmarkFolder(
                            database,
                            id: id,
                            parent: parent,
                            position: position,
                            title: node.name,
                            guid: Self.guid(id)
                        )
                        try insertNodes(node.children, parent: id)
                    } else if let urlString = node.urlString {
                        let place = try placeId(urlString: urlString, title: node.name)
                        try insertBookmark(
                            database,
                            id: id,
                            placeId: place,
                            parent: parent,
                            position: position,
                            title: node.name,
                            guid: Self.guid(id)
                        )
                    }
                }
            }
            try insertNodes(bookmarks, parent: 5)

            for visit in history.sorted(by: { $0.visitedAt < $1.visitedAt }) {
                let place = try placeId(urlString: visit.urlString, title: visit.title)
                try insertVisit(
                    database,
                    id: nextVisitId,
                    placeId: place,
                    visitedAt: visit.visitedAt
                )
                nextVisitId += 1
            }
        }
    }

    private func writeCookies(
        _ cookiesByProfileId: [String: [HTTPCookie]],
        contextByProfile: [String: Int],
        to url: URL
    ) throws {
        try withDatabase(at: url) { database in
            try database.execute(sql: Self.cookiesSchema)
            let nowMicroseconds = Int64(Date().timeIntervalSince1970 * 1_000_000)
            var id: Int64 = 1
            for profileId in contextByProfile.keys.sorted() {
                guard let contextId = contextByProfile[profileId] else { continue }
                for cookie in cookiesByProfileId[profileId] ?? [] {
                    let expiryMilliseconds = Int64(
                        (cookie.expiresDate ?? Date().addingTimeInterval(30 * 86_400))
                            .timeIntervalSince1970 * 1_000
                    )
                    try database.execute(
                        sql: """
                        INSERT INTO moz_cookies
                        (id, originAttributes, name, value, host, path, expiry,
                         lastAccessed, creationTime, isSecure, isHttpOnly,
                         inBrowserElement, sameSite, rawSameSite, schemeMap,
                         isPartitionedAttributeSet)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, ?, 0)
                        """,
                        arguments: [
                            id,
                            "^userContextId=\(contextId)",
                            cookie.name,
                            cookie.value,
                            cookie.domain,
                            cookie.path,
                            expiryMilliseconds,
                            nowMicroseconds,
                            nowMicroseconds,
                            cookie.isSecure,
                            cookie.isHTTPOnly,
                            cookie.isSecure ? 2 : 1,
                        ]
                    )
                    id += 1
                }
            }
        }
    }

    private func archive(root: URL, outputURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.currentDirectoryURL = root
        process.arguments = ["-czf", outputURL.path, "manifest.json", "profile"]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw SumiImportExportError.importFailed(
                "Could not create the Zen backup archive: \(detail)"
            )
        }
    }

    private func mozLZ4(_ payload: Data) throws -> Data {
        let capacity = payload.count + payload.count / 255 + 32
        var compressed = Data(count: capacity)
        let size = compressed.withUnsafeMutableBytes { output in
            payload.withUnsafeBytes { input in
                compression_encode_buffer(
                    output.bindMemory(to: UInt8.self).baseAddress!,
                    capacity,
                    input.bindMemory(to: UInt8.self).baseAddress!,
                    payload.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }
        guard size > 0 else {
            throw SumiImportExportError.importFailed("Could not encode Zen workspace data.")
        }
        var output = Data("mozLz40\0".utf8)
        var payloadSize = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &payloadSize) { output.append(contentsOf: $0) }
        output.append(compressed.prefix(size))
        return output
    }

    private func withDatabase(
        at url: URL,
        operation: (Database) throws -> Void
    ) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write(operation)
    }

    private func insertPlace(
        _ database: Database,
        id: Int64,
        urlString: String,
        title: String
    ) throws {
        try database.execute(
            sql: """
            INSERT INTO moz_places
            (id, url, title, rev_host, visit_count, last_visit_date, guid, url_hash)
            VALUES (?, ?, ?, ?, 0, NULL, ?, ?)
            """,
            arguments: [
                id,
                urlString,
                title,
                Self.reversedHost(urlString),
                Self.guid(id),
                Self.pageURLHash(urlString),
            ]
        )
    }

    private func insertBookmarkFolder(
        _ database: Database,
        id: Int64,
        parent: Int64,
        position: Int,
        title: String,
        guid: String
    ) throws {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000_000)
        try database.execute(
            sql: """
            INSERT INTO moz_bookmarks
            (id, type, fk, parent, position, title, dateAdded, lastModified, guid)
            VALUES (?, 2, NULL, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [id, parent, position, title, timestamp, timestamp, guid]
        )
    }

    private func insertBookmark(
        _ database: Database,
        id: Int64,
        placeId: Int64,
        parent: Int64,
        position: Int,
        title: String,
        guid: String
    ) throws {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000_000)
        try database.execute(
            sql: """
            INSERT INTO moz_bookmarks
            (id, type, fk, parent, position, title, dateAdded, lastModified, guid)
            VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                id,
                placeId,
                parent,
                position,
                title,
                timestamp,
                timestamp,
                guid,
            ]
        )
    }

    private func insertVisit(
        _ database: Database,
        id: Int64,
        placeId: Int64,
        visitedAt: Date
    ) throws {
        let timestamp = Int64(visitedAt.timeIntervalSince1970 * 1_000_000)
        try database.execute(
            sql: """
            INSERT INTO moz_historyvisits
            (id, from_visit, place_id, visit_date, visit_type, session)
            VALUES (?, 0, ?, ?, 1, 0)
            """,
            arguments: [id, placeId, timestamp]
        )
        try database.execute(
            sql: """
            UPDATE moz_places
            SET visit_count = visit_count + 1, last_visit_date = ?
            WHERE id = ?
            """,
            arguments: [timestamp, placeId]
        )
    }

    private static func guid(_ id: Int64) -> String {
        String(format: "sumi%08lld", id)
    }

    private static func reversedHost(_ urlString: String) -> String {
        guard let host = URL(string: urlString)?.host else { return "" }
        return String(host.reversed()) + "."
    }

    private static func pageURLHash(_ urlString: String) -> Int64 {
        let full = hashString(urlString)
        let prefix = urlString.firstIndex(of: ":")
            .map { hashString(String(urlString[..<$0])) } ?? 0
        return Int64((UInt64(prefix & 0xFFFF) << 32) | UInt64(full))
    }

    private static func hashString(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32(0)) { hash, byte in
            let rotated = (hash << 5) | (hash >> 27)
            return 0x9E37_79B9 &* (rotated ^ UInt32(byte))
        }
    }

    private static let containerColors = [
        "blue", "turquoise", "green", "yellow", "orange", "red", "pink", "purple",
    ]
    private static let bookmarkRoots: [
        (id: Int64, parent: Int64, title: String, guid: String)
    ] = [
        (1, 0, "", "root________"),
        (2, 1, "menu", "menu________"),
        (3, 1, "toolbar", "toolbar_____"),
        (4, 1, "tags", "tags________"),
        (5, 1, "unfiled", "unfiled_____"),
        (6, 1, "mobile", "mobile______"),
    ]
    private static let placesSchema = """
        CREATE TABLE moz_places (
            id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR,
            rev_host LONGVARCHAR, visit_count INTEGER DEFAULT 0,
            hidden INTEGER DEFAULT 0 NOT NULL, typed INTEGER DEFAULT 0 NOT NULL,
            frecency INTEGER DEFAULT -1 NOT NULL, last_visit_date INTEGER,
            guid TEXT, foreign_count INTEGER DEFAULT 0 NOT NULL,
            url_hash INTEGER DEFAULT 0 NOT NULL
        );
        CREATE TABLE moz_bookmarks (
            id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER DEFAULT NULL,
            parent INTEGER, position INTEGER, title LONGVARCHAR,
            keyword_id INTEGER, folder_type TEXT, dateAdded INTEGER,
            lastModified INTEGER, guid TEXT,
            syncStatus INTEGER NOT NULL DEFAULT 0,
            syncChangeCounter INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE moz_historyvisits (
            id INTEGER PRIMARY KEY, from_visit INTEGER, place_id INTEGER,
            visit_date INTEGER, visit_type INTEGER, session INTEGER
        );
        """
    private static let cookiesSchema = """
        CREATE TABLE moz_cookies (
            id INTEGER PRIMARY KEY,
            originAttributes TEXT NOT NULL DEFAULT '',
            name TEXT, value TEXT, host TEXT, path TEXT, expiry INTEGER,
            lastAccessed INTEGER, creationTime INTEGER, isSecure INTEGER,
            isHttpOnly INTEGER, inBrowserElement INTEGER DEFAULT 0,
            sameSite INTEGER DEFAULT 0, rawSameSite INTEGER DEFAULT 0,
            schemeMap INTEGER DEFAULT 0,
            isPartitionedAttributeSet INTEGER DEFAULT 0, updateTime INTEGER,
            CONSTRAINT moz_uniqueid UNIQUE (name, host, path, originAttributes)
        );
        """
}
