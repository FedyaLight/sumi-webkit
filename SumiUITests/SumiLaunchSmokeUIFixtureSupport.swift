import AppKit
import Darwin
import Foundation
import XCTest

extension SumiLaunchSmokeUITestCase {
    func loadPersonalSidebarFixture() throws -> PersonalSidebarFixture {
        let storeURL = try prepareSmokeStoreURL()

        let personalSpaceID = try requiredScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZSPACEENTITY
            WHERE ZNAME = 'Personal'
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Current profile does not contain a Personal space"
        )

        let profileID = try requiredScalar(
            sql: """
            SELECT lower(hex(ZPROFILEID)) AS value
            FROM ZSPACEENTITY
            WHERE lower(hex(ZID)) = '\(personalSpaceID)'
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Personal space \(personalSpaceID) does not have a profile id"
        )

        let topLevelLauncherID = try optionalScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZTABENTITY
            WHERE ZISSPACEPINNED = 1
              AND lower(hex(ZSPACEID)) = '\(personalSpaceID)'
              AND ZFOLDERID IS NULL
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Personal space \(personalSpaceID) does not have a top-level launcher"
        ) ?? insertSmokeTab(
            storeURL: storeURL,
            name: "Smoke Launcher",
            urlString: "https://example.com/sumi-smoke-launcher",
            isPinned: false,
            isSpacePinned: true,
            spaceID: personalSpaceID,
            profileID: nil,
            folderID: nil,
            indexWhereClause: """
            ZISSPACEPINNED = 1
              AND lower(hex(ZSPACEID)) = '\(personalSpaceID)'
              AND ZFOLDERID IS NULL
            """
        )

        let regularTabWhereClause = """
        lower(hex(ZSPACEID)) = '\(personalSpaceID)'
          AND COALESCE(ZISSPACEPINNED, 0) = 0
          AND COALESCE(ZISPINNED, 0) = 0
          AND ZFOLDERID IS NULL
        """
        let regularTabID = try insertSmokeTab(
            storeURL: storeURL,
            name: "Smoke Regular Tab",
            urlString: "https://example.com/sumi-smoke-regular",
            isPinned: false,
            isSpacePinned: false,
            spaceID: personalSpaceID,
            profileID: profileID,
            folderID: nil,
            indexWhereClause: regularTabWhereClause
        )
        let secondaryRegularTabID = try insertSmokeTab(
            storeURL: storeURL,
            name: "Smoke Secondary Regular Tab",
            urlString: "https://example.com/sumi-smoke-regular-secondary",
            isPinned: false,
            isSpacePinned: false,
            spaceID: personalSpaceID,
            profileID: profileID,
            folderID: nil,
            indexWhereClause: regularTabWhereClause
        )
        try moveSmokeRegularTabsToTop(
            storeURL: storeURL,
            personalSpaceID: personalSpaceID,
            primaryTabID: regularTabID,
            secondaryTabID: secondaryRegularTabID
        )

        let folderID = try optionalScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZFOLDERENTITY
            WHERE lower(hex(ZSPACEID)) = '\(personalSpaceID)'
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Personal space \(personalSpaceID) does not have a folder"
        ) ?? insertSmokeFolder(
            storeURL: storeURL,
            name: "Smoke Folder",
            spaceID: personalSpaceID
        )

        let folderLauncherID = try optionalScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZTABENTITY
            WHERE ZISSPACEPINNED = 1
              AND lower(hex(ZFOLDERID)) = '\(folderID)'
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Folder \(folderID) does not have a launcher child"
        ) ?? insertSmokeTab(
            storeURL: storeURL,
            name: "Smoke Folder Launcher",
            urlString: "https://example.com/sumi-smoke-folder-launcher",
            isPinned: false,
            isSpacePinned: true,
            spaceID: personalSpaceID,
            profileID: nil,
            folderID: folderID,
            indexWhereClause: """
            ZISSPACEPINNED = 1
              AND lower(hex(ZFOLDERID)) = '\(folderID)'
            """
        )

        let essentialID = try optionalScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZTABENTITY
            WHERE ZISPINNED = 1
              AND lower(hex(ZPROFILEID)) = '\(profileID)'
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Profile \(profileID) does not have an essential shortcut"
        ) ?? insertSmokeTab(
            storeURL: storeURL,
            name: "Smoke Essential",
            urlString: "https://example.com/sumi-smoke-essential",
            isPinned: true,
            isSpacePinned: false,
            spaceID: nil,
            profileID: profileID,
            folderID: nil,
            indexWhereClause: """
            ZISPINNED = 1
              AND lower(hex(ZPROFILEID)) = '\(profileID)'
            """
        )

        return PersonalSidebarFixture(
            personalSpaceID: try accessibilityUUIDString(fromHex: personalSpaceID),
            profileID: profileID,
            topLevelLauncherID: try accessibilityUUIDString(fromHex: topLevelLauncherID),
            regularTabID: try accessibilityUUIDString(fromHex: regularTabID),
            secondaryRegularTabID: try accessibilityUUIDString(fromHex: secondaryRegularTabID),
            folderID: try accessibilityUUIDString(fromHex: folderID),
            folderLauncherID: try accessibilityUUIDString(fromHex: folderLauncherID),
            essentialID: try accessibilityUUIDString(fromHex: essentialID)
        )
    }

    func prepareSmokeStoreURL() throws -> URL {
        let sourceStoreURL = defaultStoreURL()
        guard FileManager.default.fileExists(atPath: sourceStoreURL.path) else {
            throw FixtureError.missingStore(sourceStoreURL.path)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let storeURL = directory.appendingPathComponent("default.store", isDirectory: false)
        try backupSQLiteStore(sourceStoreURL, to: storeURL)

        smokeAppSupportURL = directory
        smokeAppSupportDirectories.append(directory)
        return storeURL
    }

    func prepareStartupThemeSmokeFixture() throws -> URL {
        let storeURL = try prepareSmokeStoreURL()
        let spaceID = try firstSpaceID(in: storeURL)

        let themeData = try startupSmokeWorkspaceThemeData()
        try executeSQLite(
            sql: """
            UPDATE ZSPACEENTITY
            SET ZWORKSPACETHEMEDATA = \(sqlBlob(hexString(from: themeData)))
            WHERE lower(hex(ZID)) = '\(spaceID)';
            """,
            storeURL: storeURL
        )

        let snapshotData = try startupSmokeWindowSessionData(spaceID: spaceID)
        return try preparePreferencesHome(windowSessionSnapshotData: snapshotData)
    }

    func prepareSmokePreferencesHome(isSidebarVisible: Bool = true) throws -> URL {
        let storeURL = smokeStoreURL ?? defaultStoreURL()
        let spaceID = try preferredSmokeStartupSpaceID(in: storeURL)
        let snapshotData = try startupSmokeWindowSessionData(
            spaceID: spaceID,
            isSidebarVisible: isSidebarVisible
        )
        return try preparePreferencesHome(windowSessionSnapshotData: snapshotData)
    }

    func preferredSmokeStartupSpaceID(in storeURL: URL) throws -> String {
        try optionalScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZSPACEENTITY
            WHERE ZNAME = 'Personal'
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Current profile does not contain a Personal space"
        ) ?? firstSpaceID(in: storeURL)
    }

    func firstSpaceID(in storeURL: URL) throws -> String {
        try requiredScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZSPACEENTITY
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Current profile does not contain a space"
        )
    }

    func startupSmokeWorkspaceThemeData() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "gradientTheme": [
                    "type": "gradient",
                    "opacity": 1.0,
                    "texture": 0.0,
                    "colors": [
                        [
                            "id": UUID().uuidString,
                            "hex": "#FF3B30",
                            "isCustom": false,
                            "isPrimary": true,
                            "algorithm": "floating",
                            "lightness": 0.52,
                            "position": [
                                "x": 0.20,
                                "y": 0.24,
                            ],
                            "type": "explicit-lightness",
                        ],
                        [
                            "id": UUID().uuidString,
                            "hex": "#34C759",
                            "isCustom": false,
                            "isPrimary": false,
                            "algorithm": "floating",
                            "lightness": 0.64,
                            "position": [
                                "x": 0.50,
                                "y": 0.82,
                            ],
                            "type": "explicit-lightness",
                        ],
                    ],
                ],
                "usesExplicitColorScheme": true,
            ],
            options: []
        )
    }

    func startupSmokeWindowSessionData(
        spaceID: String,
        isSidebarVisible: Bool = true
    ) throws -> Data {
        let snapshot: [String: Any] = [
            "currentSpaceId": try accessibilityUUIDString(fromHex: spaceID),
            "isShowingEmptyState": false,
            "activeTabsBySpace": [],
            "activeShortcutsBySpace": [],
            "sidebarWidth": 250.0,
            "savedSidebarWidth": 250.0,
            "sidebarContentWidth": 234.0,
            "isSidebarVisible": isSidebarVisible,
            "floatingBarDraft": [
                "text": "",
                "navigateCurrentTab": false,
            ],
        ]
        return try JSONSerialization.data(withJSONObject: snapshot, options: [])
    }

    func preparePreferencesHome(windowSessionSnapshotData: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiSmokePrefs-\(UUID().uuidString)", isDirectory: true)
        let preferencesDirectory = directory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: preferencesDirectory, withIntermediateDirectories: true)

        let preferencesURL = preferencesDirectory
            .appendingPathComponent("com.sumi.browser.plist", isDirectory: false)
        let plist: [String: Any] = [
            "sumi.windowSession.last.v3": windowSessionSnapshotData,
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .binary,
            options: 0
        )
        try plistData.write(to: preferencesURL, options: .atomic)
        let windowSessionOverrideURL = directory
            .appendingPathComponent(smokeWindowSessionOverrideFileName, isDirectory: false)
        try windowSessionSnapshotData.write(to: windowSessionOverrideURL, options: .atomic)

        smokeAppSupportDirectories.append(directory)
        return directory
    }

    func dominantBlackPixelRatio(in screenshot: XCUIScreenshot) throws -> Double {
        guard let bitmap = NSBitmapImageRep(data: screenshot.pngRepresentation) else {
            throw FixtureError.screenshotFailure("Unable to decode launch screenshot")
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else {
            throw FixtureError.screenshotFailure("Launch screenshot is empty")
        }

        let step = max(1, min(width, height) / 120)
        var blackPixels = 0
        var sampledPixels = 0

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.05
                else { continue }

                let luminance = 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                if luminance < 0.08 {
                    blackPixels += 1
                }
                sampledPixels += 1
            }
        }

        guard sampledPixels > 0 else {
            throw FixtureError.screenshotFailure("Launch screenshot has no sampleable pixels")
        }
        return Double(blackPixels) / Double(sampledPixels)
    }

    func insertSmokeFolder(
        storeURL: URL,
        name: String,
        spaceID: String
    ) throws -> String {
        let entity = try nextPrimaryKeyInfo(entityName: "FolderEntity", storeURL: storeURL)
        let folderID = uuidHexString()
        let index = try nextIndex(
            storeURL: storeURL,
            tableName: "ZFOLDERENTITY",
            whereClause: "lower(hex(ZSPACEID)) = '\(spaceID)'"
        )

        try executeSQLite(
            sql: """
            INSERT INTO ZFOLDERENTITY (
                Z_PK, Z_ENT, Z_OPT, ZINDEX, ZISOPEN, ZCOLOR, ZICON, ZNAME, ZID, ZSPACEID
            ) VALUES (
                \(entity.primaryKey), \(entity.entity), 1, \(index), 1,
                \(sqlString("#007AFF")), \(sqlString("")), \(sqlString(name)),
                \(sqlBlob(folderID)), \(sqlBlob(spaceID))
            );
            UPDATE Z_PRIMARYKEY
            SET Z_MAX = MAX(Z_MAX, \(entity.primaryKey))
            WHERE Z_NAME = 'FolderEntity';
            """,
            storeURL: storeURL
        )

        return folderID
    }

    func insertSmokeTab(
        storeURL: URL,
        name: String,
        urlString: String,
        isPinned: Bool,
        isSpacePinned: Bool,
        spaceID: String?,
        profileID: String?,
        folderID: String?,
        indexWhereClause: String
    ) throws -> String {
        let entity = try nextPrimaryKeyInfo(entityName: "TabEntity", storeURL: storeURL)
        let tabID = uuidHexString()
        let index = try nextIndex(
            storeURL: storeURL,
            tableName: "ZTABENTITY",
            whereClause: indexWhereClause
        )

        try executeSQLite(
            sql: """
            INSERT INTO ZTABENTITY (
                Z_PK, Z_ENT, Z_OPT, ZCANGOBACK, ZCANGOFORWARD, ZINDEX,
                ZISPINNED, ZISSPACEPINNED, ZCURRENTURLSTRING, ZICONASSET,
                ZNAME, ZURLSTRING, ZFOLDERID, ZID, ZPROFILEID, ZSPACEID
            ) VALUES (
                \(entity.primaryKey), \(entity.entity), 1, 0, 0, \(index),
                \(isPinned ? 1 : 0), \(isSpacePinned ? 1 : 0),
                \(sqlString(urlString)), \(sqlString("globe")),
                \(sqlString(name)), \(sqlString(urlString)),
                \(sqlBlob(folderID)), \(sqlBlob(tabID)), \(sqlBlob(profileID)), \(sqlBlob(spaceID))
            );
            UPDATE Z_PRIMARYKEY
            SET Z_MAX = MAX(Z_MAX, \(entity.primaryKey))
            WHERE Z_NAME = 'TabEntity';
            """,
            storeURL: storeURL
        )

        return tabID
    }

    func moveSmokeRegularTabsToTop(
        storeURL: URL,
        personalSpaceID: String,
        primaryTabID: String,
        secondaryTabID: String
    ) throws {
        let existingMinimum = try requiredScalar(
            sql: """
            SELECT COALESCE(MIN(ZINDEX), 0) AS value
            FROM ZTABENTITY
            WHERE lower(hex(ZSPACEID)) = '\(personalSpaceID)'
              AND COALESCE(ZISSPACEPINNED, 0) = 0
              AND COALESCE(ZISPINNED, 0) = 0
              AND ZFOLDERID IS NULL
              AND lower(hex(ZID)) NOT IN (\(sqlString(primaryTabID)), \(sqlString(secondaryTabID)));
            """,
            storeURL: storeURL,
            description: "Unable to determine regular tab order for Personal space \(personalSpaceID)"
        )
        let firstIndex = (Int(existingMinimum) ?? 0) - 2
        let secondIndex = firstIndex + 1

        try executeSQLite(
            sql: """
            UPDATE ZTABENTITY
            SET ZINDEX = CASE lower(hex(ZID))
                WHEN \(sqlString(primaryTabID)) THEN \(firstIndex)
                WHEN \(sqlString(secondaryTabID)) THEN \(secondIndex)
                ELSE ZINDEX
            END
            WHERE lower(hex(ZID)) IN (\(sqlString(primaryTabID)), \(sqlString(secondaryTabID)));
            """,
            storeURL: storeURL
        )
    }

    func nextPrimaryKeyInfo(
        entityName: String,
        storeURL: URL
    ) throws -> (entity: String, primaryKey: String) {
        let rows = try sqliteRows(
            sql: """
            SELECT Z_ENT AS entity, COALESCE(Z_MAX, 0) + 1 AS primaryKey
            FROM Z_PRIMARYKEY
            WHERE Z_NAME = \(sqlString(entityName))
            LIMIT 1;
            """,
            storeURL: storeURL
        )
        guard let row = rows.first,
              let entity = row["entity"],
              let primaryKey = row["primaryKey"]
        else {
            throw FixtureError.missingValue("Missing primary key metadata for \(entityName)")
        }
        return (entity, primaryKey)
    }

    func nextIndex(
        storeURL: URL,
        tableName: String,
        whereClause: String
    ) throws -> String {
        try requiredScalar(
            sql: """
            SELECT COALESCE(MAX(ZINDEX), -1) + 1 AS value
            FROM \(tableName)
            WHERE \(whereClause);
            """,
            storeURL: storeURL,
            description: "Unable to allocate smoke fixture index for \(tableName)"
        )
    }

    func executeSQLite(
        sql: String,
        storeURL: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [storeURL.path, sql]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown sqlite3 error"
            throw FixtureError.sqliteFailure(message)
        }
    }

    func backupSQLiteStore(
        _ sourceURL: URL,
        to targetURL: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [sourceURL.path, ".backup '\(targetURL.path)'"]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown sqlite3 backup error"
            throw FixtureError.sqliteFailure(message)
        }
    }

    func sqlString(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    func sqlBlob(_ hex: String?) -> String {
        guard let hex, !hex.isEmpty else { return "NULL" }
        return "X'\(hex)'"
    }

    func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    func uuidHexString() -> String {
        UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    func requiredScalar(
        sql: String,
        storeURL: URL,
        description: String
    ) throws -> String {
        let rows = try sqliteRows(sql: sql, storeURL: storeURL)
        guard let value = rows.first?["value"], !value.isEmpty else {
            throw FixtureError.missingValue(description)
        }
        return value
    }

    func optionalScalar(
        sql: String,
        storeURL: URL,
        description: String
    ) throws -> String? {
        let rows = try sqliteRows(sql: sql, storeURL: storeURL)
        guard let value = rows.first?["value"], !value.isEmpty else {
            return nil
        }
        return value
    }

    func sqliteRows(
        sql: String,
        storeURL: URL
    ) throws -> [[String: String]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", storeURL.path, sql]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown sqlite3 error"
            throw FixtureError.sqliteFailure(message)
        }

        guard stdoutData.isEmpty == false else { return [] }
        guard let object = try JSONSerialization.jsonObject(with: stdoutData) as? [[String: Any]] else {
            throw FixtureError.malformedJSON
        }

        return object.map { row in
            row.reduce(into: [:]) { partialResult, entry in
                switch entry.value {
                case let string as String:
                    partialResult[entry.key] = string
                case let number as NSNumber:
                    partialResult[entry.key] = number.stringValue
                default:
                    break
                }
            }
        }
    }

    @MainActor
    func waitForRegularTabRelativeOrder(
        _ sourceTabID: String,
        _ targetTabID: String,
        in fixture: PersonalSidebarFixture,
        sourceShouldBeAfterTarget: Bool,
        timeout: TimeInterval
    ) -> Bool {
        guard let storeURL = smokeStoreURL,
              let sourceHex = try? hexUUIDString(fromAccessibilityUUID: sourceTabID),
              let targetHex = try? hexUUIDString(fromAccessibilityUUID: targetTabID),
              let personalSpaceHex = try? hexUUIDString(fromAccessibilityUUID: fixture.personalSpaceID)
        else {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let orderedRegularTabIDs = (try? sqliteRows(
                sql: """
                SELECT lower(hex(ZID)) AS value
                FROM ZTABENTITY
                WHERE lower(hex(ZSPACEID)) = '\(personalSpaceHex)'
                  AND COALESCE(ZISSPACEPINNED, 0) = 0
                  AND COALESCE(ZISPINNED, 0) = 0
                  AND ZFOLDERID IS NULL
                ORDER BY ZINDEX;
                """,
                storeURL: storeURL
            ))?.compactMap { $0["value"] } ?? []

            if let sourceIndex = orderedRegularTabIDs.firstIndex(of: sourceHex),
               let targetIndex = orderedRegularTabIDs.firstIndex(of: targetHex),
               sourceShouldBeAfterTarget ? sourceIndex > targetIndex : sourceIndex < targetIndex {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return false
    }

    @MainActor
    func waitForRegularTabCount(
        _ expectedCount: Int,
        in fixture: PersonalSidebarFixture,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if regularTabCount(in: fixture) == expectedCount {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return regularTabCount(in: fixture) == expectedCount
    }

    func regularTabCount(in fixture: PersonalSidebarFixture) -> Int? {
        guard let storeURL = smokeStoreURL,
              let personalSpaceHex = try? hexUUIDString(fromAccessibilityUUID: fixture.personalSpaceID)
        else {
            return nil
        }

        return (try? sqliteRows(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZTABENTITY
            WHERE lower(hex(ZSPACEID)) = '\(personalSpaceHex)'
              AND COALESCE(ZISSPACEPINNED, 0) = 0
              AND COALESCE(ZISPINNED, 0) = 0
              AND ZFOLDERID IS NULL
            ORDER BY ZINDEX;
            """,
            storeURL: storeURL
        ))?.count
    }

    var smokeStoreURL: URL? {
        smokeAppSupportURL?.appendingPathComponent("default.store", isDirectory: false)
    }

    func accessibilityUUIDString(fromHex hex: String) throws -> String {
        guard hex.count == 32 else {
            throw FixtureError.missingValue("Malformed UUID hex value \(hex)")
        }

        let part1 = String(hex.prefix(8))
        let part2 = String(hex.dropFirst(8).prefix(4))
        let part3 = String(hex.dropFirst(12).prefix(4))
        let part4 = String(hex.dropFirst(16).prefix(4))
        let part5 = String(hex.dropFirst(20).prefix(12))
        let dashed = "\(part1)-\(part2)-\(part3)-\(part4)-\(part5)"

        guard let uuid = UUID(uuidString: dashed) else {
            throw FixtureError.missingValue("Malformed UUID value \(hex)")
        }

        return uuid.uuidString
    }

    func hexUUIDString(fromAccessibilityUUID uuidString: String) throws -> String {
        guard let uuid = UUID(uuidString: uuidString) else {
            throw FixtureError.missingValue("Malformed accessibility UUID \(uuidString)")
        }

        return withUnsafeBytes(of: uuid.uuid) { rawBuffer in
            rawBuffer.map { String(format: "%02x", $0) }.joined()
        }
    }

    func defaultStoreURL() -> URL {
        let homeDirectory: URL
        if let passwd = getpwuid(getuid()) {
            homeDirectory = URL(fileURLWithPath: String(cString: passwd.pointee.pw_dir))
        } else {
            homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        }

        return homeDirectory
            .appendingPathComponent("Library/Application Support/com.sumi.browser/default.store")
    }
}
