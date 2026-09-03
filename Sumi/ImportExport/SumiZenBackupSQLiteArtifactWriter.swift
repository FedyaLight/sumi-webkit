import Foundation
import GRDB

/// Writes the foreign SQLite artifacts embedded in a user-authored Zen backup.
/// It does not open or mutate Sumi's canonical database.
struct SumiZenBackupSQLiteArtifactWriter {
    func writePlaces(
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

            var nextPlaceID: Int64 = 100
            var nextBookmarkID: Int64 = 100
            var nextVisitID: Int64 = 1
            var placeIDByURL: [String: Int64] = [:]

            func placeID(urlString: String, title: String) throws -> Int64 {
                if let existing = placeIDByURL[urlString] { return existing }
                let id = nextPlaceID
                nextPlaceID += 1
                try insertPlace(
                    database,
                    id: id,
                    urlString: urlString,
                    title: title
                )
                placeIDByURL[urlString] = id
                return id
            }

            func insertNodes(
                _ nodes: [SumiPortableBookmarkNode],
                parent: Int64
            ) throws {
                for (position, node) in nodes.enumerated() {
                    let id = nextBookmarkID
                    nextBookmarkID += 1
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
                        let place = try placeID(
                            urlString: urlString,
                            title: node.name
                        )
                        try insertBookmark(
                            database,
                            id: id,
                            placeID: place,
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
                let place = try placeID(
                    urlString: visit.urlString,
                    title: visit.title
                )
                try insertVisit(
                    database,
                    id: nextVisitID,
                    placeID: place,
                    visitedAt: visit.visitedAt
                )
                nextVisitID += 1
            }
        }
    }

    func writeCookies(
        _ cookiesByProfileID: [String: [HTTPCookie]],
        contextByProfile: [String: Int],
        to url: URL
    ) throws {
        try withDatabase(at: url) { database in
            try database.execute(sql: Self.cookiesSchema)
            let nowMicroseconds = Int64(Date().timeIntervalSince1970 * 1_000_000)
            var id: Int64 = 1
            for profileID in contextByProfile.keys.sorted() {
                guard let contextID = contextByProfile[profileID] else {
                    continue
                }
                for cookie in cookiesByProfileID[profileID] ?? [] {
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
                            "^userContextId=\(contextID)",
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
        placeID: Int64,
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
                placeID,
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
        placeID: Int64,
        visitedAt: Date
    ) throws {
        let timestamp = Int64(visitedAt.timeIntervalSince1970 * 1_000_000)
        try database.execute(
            sql: """
            INSERT INTO moz_historyvisits
            (id, from_visit, place_id, visit_date, visit_type, session)
            VALUES (?, 0, ?, ?, 1, 0)
            """,
            arguments: [id, placeID, timestamp]
        )
        try database.execute(
            sql: """
            UPDATE moz_places
            SET visit_count = visit_count + 1, last_visit_date = ?
            WHERE id = ?
            """,
            arguments: [timestamp, placeID]
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

    // Full Firefox-compatible schema (mirrors toolkit/components/places
    // nsPlacesTables.h). A minimal 3-table file round-trips through Sumi's
    // own reader, but real Zen/Firefox treats it as corrupt: it expects the
    // origins/keywords/annos/meta tables, the newer moz_places columns, and
    // the hash/parent indexes. Missing tables mean bookmarks and history
    // silently vanish on restore, which reads as "export doesn't work".
    private static let placesSchema = """
        CREATE TABLE moz_origins (
            id INTEGER PRIMARY KEY, prefix TEXT NOT NULL, host TEXT NOT NULL,
            frecency INTEGER NOT NULL, UNIQUE (prefix, host)
        );
        CREATE TABLE moz_places (
            id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR,
            rev_host LONGVARCHAR, visit_count INTEGER DEFAULT 0,
            hidden INTEGER DEFAULT 0 NOT NULL, typed INTEGER DEFAULT 0 NOT NULL,
            frecency INTEGER DEFAULT -1 NOT NULL, last_visit_date INTEGER,
            guid TEXT, foreign_count INTEGER DEFAULT 0 NOT NULL,
            url_hash INTEGER DEFAULT 0 NOT NULL,
            description TEXT, preview_image_url TEXT, site_name TEXT,
            origin_id INTEGER REFERENCES moz_origins(id),
            recalc_frecency INTEGER NOT NULL DEFAULT 0, alt_frecency INTEGER,
            recalc_alt_frecency INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX moz_places_url_hashindex ON moz_places (url_hash);
        CREATE INDEX moz_places_hostindex ON moz_places (rev_host);
        CREATE INDEX moz_places_visitcount ON moz_places (visit_count);
        CREATE INDEX moz_places_frecencyindex ON moz_places (frecency);
        CREATE INDEX moz_places_lastvisitdateindex ON moz_places (last_visit_date);
        CREATE UNIQUE INDEX moz_places_guid_uniqueindex ON moz_places (guid);
        CREATE INDEX moz_places_originidindex ON moz_places (origin_id);
        CREATE TABLE moz_historyvisits (
            id INTEGER PRIMARY KEY, from_visit INTEGER, place_id INTEGER,
            visit_date INTEGER, visit_type INTEGER, session INTEGER
        );
        CREATE INDEX moz_historyvisits_placedateindex ON moz_historyvisits (place_id, visit_date);
        CREATE INDEX moz_historyvisits_fromindex ON moz_historyvisits (from_visit);
        CREATE INDEX moz_historyvisits_dateindex ON moz_historyvisits (visit_date);
        CREATE TABLE moz_inputhistory (
            place_id INTEGER NOT NULL, input LONGVARCHAR NOT NULL, use_count INTEGER,
            PRIMARY KEY (place_id, input)
        );
        CREATE TABLE moz_bookmarks (
            id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER DEFAULT NULL,
            parent INTEGER, position INTEGER, title LONGVARCHAR,
            keyword_id INTEGER, folder_type TEXT, dateAdded INTEGER,
            lastModified INTEGER, guid TEXT,
            syncStatus INTEGER NOT NULL DEFAULT 0,
            syncChangeCounter INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE moz_bookmarks_deleted (
            guid TEXT PRIMARY KEY, dateRemoved INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX moz_bookmarks_itemindex ON moz_bookmarks (fk, type);
        CREATE INDEX moz_bookmarks_parentindex ON moz_bookmarks (parent, position);
        CREATE INDEX moz_bookmarks_itemlastmodifiedindex ON moz_bookmarks (fk, lastModified);
        CREATE INDEX moz_bookmarks_dateaddedindex ON moz_bookmarks (dateAdded);
        CREATE UNIQUE INDEX moz_bookmarks_guid_uniqueindex ON moz_bookmarks (guid);
        CREATE TABLE moz_keywords (
            id INTEGER PRIMARY KEY AUTOINCREMENT, keyword TEXT UNIQUE,
            place_id INTEGER, post_data TEXT
        );
        CREATE UNIQUE INDEX moz_keywords_placepostdata_uniqueindex ON moz_keywords (place_id, post_data);
        CREATE TABLE moz_anno_attributes (
            id INTEGER PRIMARY KEY, name VARCHAR(32) UNIQUE NOT NULL
        );
        CREATE TABLE moz_annos (
            id INTEGER PRIMARY KEY, place_id INTEGER NOT NULL,
            anno_attribute_id INTEGER, content LONGVARCHAR,
            flags INTEGER DEFAULT 0, expiration INTEGER DEFAULT 0,
            type INTEGER DEFAULT 0, dateAdded INTEGER DEFAULT 0,
            lastModified INTEGER DEFAULT 0
        );
        CREATE UNIQUE INDEX moz_annos_placeattributeindex ON moz_annos (place_id, anno_attribute_id);
        CREATE TABLE moz_items_annos (
            id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL,
            anno_attribute_id INTEGER, content LONGVARCHAR,
            flags INTEGER DEFAULT 0, expiration INTEGER DEFAULT 0,
            type INTEGER DEFAULT 0, dateAdded INTEGER DEFAULT 0,
            lastModified INTEGER DEFAULT 0
        );
        CREATE UNIQUE INDEX moz_items_annos_itemattributeindex ON moz_items_annos (item_id, anno_attribute_id);
        CREATE TABLE moz_meta (key TEXT PRIMARY KEY, value NOT NULL) WITHOUT ROWID;
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
