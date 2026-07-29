import AppKit
import Foundation
import SQLite3
import XCTest

enum SumiSmokeFixtureIDs {
    static let profile = "00000000000000000000000000000601"
    static let personalSpace = "0000000000000000000000000000a001"
    static let topLevelLauncher = "0000000000000000000000000000a002"
    static let regularTab = "0000000000000000000000000000a003"
    static let secondaryRegularTab = "0000000000000000000000000000a004"
    static let folder = "0000000000000000000000000000a005"
    static let folderLauncher = "0000000000000000000000000000a006"
    static let essential = "0000000000000000000000000000a007"
    static let primaryThemeColor = "00000000-0000-0000-0000-00000000A008"
    static let secondaryThemeColor = "00000000-0000-0000-0000-00000000A009"
}

extension SumiLaunchSmokeUITestCase {
    func loadPersonalSidebarFixture() throws -> PersonalSidebarFixture {
        let storeURL = try requiredSmokeStoreURL()

        let personalSpaceID = try requiredScalar(
            sql: """
            SELECT lower(hex(id)) AS value
            FROM spaces
            WHERE name = 'Personal'
            ORDER BY position
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Current profile does not contain a Personal space"
        )

        let profileID = try requiredScalar(
            sql: """
            SELECT lower(hex(profile_id)) AS value
            FROM spaces
            WHERE lower(hex(id)) = '\(personalSpaceID)'
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Personal space \(personalSpaceID) does not have a profile id"
        )

        let topLevelLauncherID = try requiredScalar(
            sql: """
            SELECT lower(hex(id)) AS value
            FROM tabs
            WHERE lower(hex(id)) = '\(SumiSmokeFixtureIDs.topLevelLauncher)'
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Personal space \(personalSpaceID) does not have a top-level launcher"
        )

        let regularTabID = try requiredScalar(
            sql: """
            SELECT lower(hex(id)) AS value
            FROM tabs
            WHERE lower(hex(id)) = '\(SumiSmokeFixtureIDs.regularTab)'
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Personal space \(personalSpaceID) does not have the primary regular smoke tab"
        )
        let secondaryRegularTabID = try requiredScalar(
            sql: """
            SELECT lower(hex(id)) AS value
            FROM tabs
            WHERE lower(hex(id)) = '\(SumiSmokeFixtureIDs.secondaryRegularTab)'
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Personal space \(personalSpaceID) does not have the secondary regular smoke tab"
        )

        let folderID = try requiredScalar(
            sql: """
            SELECT lower(hex(id)) AS value
            FROM folders
            WHERE lower(hex(id)) = '\(SumiSmokeFixtureIDs.folder)'
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Personal space \(personalSpaceID) does not have a folder"
        )

        let folderLauncherID = try requiredScalar(
            sql: """
            SELECT lower(hex(id)) AS value
            FROM tabs
            WHERE lower(hex(id)) = '\(SumiSmokeFixtureIDs.folderLauncher)'
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Folder \(folderID) does not have a launcher child"
        )

        let essentialID = try requiredScalar(
            sql: """
            SELECT lower(hex(id)) AS value
            FROM tabs
            WHERE lower(hex(id)) = '\(SumiSmokeFixtureIDs.essential)'
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Profile \(profileID) does not have an essential shortcut"
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
        let fixtureFamily = try SumiSmokeStoreFixture.resolveBundledFamily()
        let directory = try makeSmokeScratchDirectory(prefix: "SumiSmoke")
        var shouldRemoveDirectory = true
        defer {
            if shouldRemoveDirectory {
                try? FileManager.default.removeItem(at: directory)
            }
        }

        let storeURL = try fixtureFamily.copyVerifiedFamily(to: directory)
        try seedSmokeStore(at: storeURL)

        smokeAppSupportURL = directory
        smokeAppSupportDirectories.append(directory)
        shouldRemoveDirectory = false
        return storeURL
    }

    func prepareStartupThemeSmokeFixture() throws -> URL {
        let storeURL = try requiredSmokeStoreURL()
        let spaceID = try firstSpaceID(in: storeURL)

        let themeData = try startupSmokeWorkspaceThemeData()
        try executeSQLite(
            sql: """
            UPDATE spaces
            SET workspace_theme = \(sqlBlob(hexString(from: themeData)))
            WHERE lower(hex(id)) = '\(spaceID)';
            """,
            storeURL: storeURL
        )

        let snapshotData = try startupSmokeWindowSessionData(spaceID: spaceID)
        return try preparePreferencesHome(windowSessionSnapshotData: snapshotData)
    }

    func prepareSmokePreferencesHome(
        isSidebarVisible: Bool = true,
        additionalPreferences: [String: Any] = [:]
    ) throws -> URL {
        let storeURL = try requiredSmokeStoreURL()
        let spaceID = try preferredSmokeStartupSpaceID(in: storeURL)
        let snapshotData = try startupSmokeWindowSessionData(
            spaceID: spaceID,
            isSidebarVisible: isSidebarVisible
        )
        return try preparePreferencesHome(
            windowSessionSnapshotData: snapshotData,
            additionalPreferences: additionalPreferences
        )
    }

    func prepareEmptyDockedSidebarPreferencesHome() throws -> URL {
        let storeURL = try requiredSmokeStoreURL()
        let fixture = try loadPersonalSidebarFixture()
        let personalSpaceHex = try hexUUIDString(
            fromAccessibilityUUID: fixture.personalSpaceID
        )
        try executeSQLite(
            sql: """
            DELETE FROM tabs;
            DELETE FROM folders;
            UPDATE tab_state
            SET current_tab_id = NULL,
                current_space_id = \(sqlBlob(personalSpaceHex)),
                split_groups = X'5B5D';
            """,
            storeURL: storeURL
        )

        let snapshot: [String: Any] = [
            "currentSpaceId": fixture.personalSpaceID,
            "currentProfileId": try accessibilityUUIDString(fromHex: fixture.profileID),
            "isShowingEmptyState": true,
            "activeTabsBySpace": [],
            "activeShortcutsBySpace": [],
            "sidebarWidth": 250.0,
            "savedSidebarWidth": 250.0,
            "sidebarContentWidth": 234.0,
            "isSidebarVisible": true,
            "commandPaletteDraft": [
                "text": "",
                "navigateCurrentTab": false,
            ],
        ]
        let snapshotData = try JSONSerialization.data(withJSONObject: snapshot, options: [])
        return try preparePreferencesHome(windowSessionSnapshotData: snapshotData)
    }

    func prepareSelectedRegularTabPreferencesHome(
        tabURLString: String,
        tabName: String,
        isSidebarVisible: Bool = true,
        additionalPreferences: [String: Any] = [:]
    ) throws -> URL {
        let storeURL = try requiredSmokeStoreURL()
        let sidebar = try loadPersonalSidebarFixture()
        try executeSQLite(
            sql: """
            UPDATE tabs
            SET name = \(sqlString(tabName)),
                url = \(sqlString(tabURLString)),
                current_url = \(sqlString(tabURLString))
            WHERE lower(hex(id)) = \(sqlString(SumiSmokeFixtureIDs.regularTab));
            """,
            storeURL: storeURL
        )

        let profileID = try accessibilityUUIDString(fromHex: sidebar.profileID)
        let snapshot: [String: Any] = [
            "currentTabId": sidebar.regularTabID,
            "currentSpaceId": sidebar.personalSpaceID,
            "currentProfileId": profileID,
            "isShowingEmptyState": false,
            "activeTabsBySpace": [[
                "spaceId": sidebar.personalSpaceID,
                "tabId": sidebar.regularTabID,
            ]],
            "activeShortcutsBySpace": [],
            "sidebarWidth": 250.0,
            "savedSidebarWidth": 250.0,
            "sidebarContentWidth": 234.0,
            "isSidebarVisible": isSidebarVisible,
            "commandPaletteDraft": [
                "text": "",
                "navigateCurrentTab": false,
            ],
        ]
        let snapshotData = try JSONSerialization.data(withJSONObject: snapshot, options: [])
        return try preparePreferencesHome(
            windowSessionSnapshotData: snapshotData,
            additionalPreferences: additionalPreferences
        )
    }

    func preferredSmokeStartupSpaceID(in storeURL: URL) throws -> String {
        try optionalScalar(
            sql: """
            SELECT lower(hex(id)) AS value
            FROM spaces
            WHERE name = 'Personal'
            ORDER BY position
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Current profile does not contain a Personal space"
        ) ?? firstSpaceID(in: storeURL)
    }

    func firstSpaceID(in storeURL: URL) throws -> String {
        try requiredScalar(
            sql: """
            SELECT lower(hex(id)) AS value
            FROM spaces
            ORDER BY position
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
                            "id": SumiSmokeFixtureIDs.primaryThemeColor,
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
                            "id": SumiSmokeFixtureIDs.secondaryThemeColor,
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
            "commandPaletteDraft": [
                "text": "",
                "navigateCurrentTab": false,
            ],
        ]
        return try JSONSerialization.data(withJSONObject: snapshot, options: [])
    }

    func preparePreferencesHome(
        windowSessionSnapshotData: Data,
        additionalPreferences: [String: Any] = [:]
    ) throws -> URL {
        let directory = try makeSmokeScratchDirectory(prefix: "SumiSmokePrefs")
        let preferencesDirectory = directory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: preferencesDirectory, withIntermediateDirectories: true)

        let preferencesURL = preferencesDirectory
            .appendingPathComponent("com.sumi.browser.plist", isDirectory: false)
        let plist = additionalPreferences
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

    func seedSmokeStore(at storeURL: URL) throws {
        let profileID = try requiredScalar(
            sql: """
            SELECT lower(hex(id)) AS value
            FROM profiles
            WHERE lower(hex(id)) = '\(SumiSmokeFixtureIDs.profile)'
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Pinned UI smoke fixture is missing its source profile"
        )

        try insertSmokeSpace(
            storeURL: storeURL,
            id: SumiSmokeFixtureIDs.personalSpace,
            profileID: profileID
        )
        try insertSmokeTab(
            storeURL: storeURL,
            id: SumiSmokeFixtureIDs.topLevelLauncher,
            name: "Smoke Launcher",
            urlString: "https://example.com/sumi-smoke-launcher",
            isPinned: false,
            isSpacePinned: true,
            spaceID: SumiSmokeFixtureIDs.personalSpace,
            profileID: nil,
            folderID: nil,
            indexWhereClause: """
            is_space_pinned = 1
              AND lower(hex(space_id)) = '\(SumiSmokeFixtureIDs.personalSpace)'
              AND folder_id IS NULL
            """
        )

        let regularTabWhereClause = """
        lower(hex(space_id)) = '\(SumiSmokeFixtureIDs.personalSpace)'
          AND is_space_pinned = 0
          AND is_pinned = 0
          AND folder_id IS NULL
        """
        try insertSmokeTab(
            storeURL: storeURL,
            id: SumiSmokeFixtureIDs.regularTab,
            name: "Smoke Regular Tab",
            urlString: "https://example.com/sumi-smoke-regular",
            isPinned: false,
            isSpacePinned: false,
            spaceID: SumiSmokeFixtureIDs.personalSpace,
            profileID: profileID,
            folderID: nil,
            indexWhereClause: regularTabWhereClause
        )
        try insertSmokeTab(
            storeURL: storeURL,
            id: SumiSmokeFixtureIDs.secondaryRegularTab,
            name: "Smoke Secondary Regular Tab",
            urlString: "https://example.com/sumi-smoke-regular-secondary",
            isPinned: false,
            isSpacePinned: false,
            spaceID: SumiSmokeFixtureIDs.personalSpace,
            profileID: profileID,
            folderID: nil,
            indexWhereClause: regularTabWhereClause
        )
        try moveSmokeRegularTabsToTop(
            storeURL: storeURL,
            personalSpaceID: SumiSmokeFixtureIDs.personalSpace,
            primaryTabID: SumiSmokeFixtureIDs.regularTab,
            secondaryTabID: SumiSmokeFixtureIDs.secondaryRegularTab
        )

        try insertSmokeFolder(
            storeURL: storeURL,
            id: SumiSmokeFixtureIDs.folder,
            name: "Smoke Folder",
            spaceID: SumiSmokeFixtureIDs.personalSpace
        )
        try insertSmokeTab(
            storeURL: storeURL,
            id: SumiSmokeFixtureIDs.folderLauncher,
            name: "Smoke Folder Launcher",
            urlString: "https://example.com/sumi-smoke-folder-launcher",
            isPinned: false,
            isSpacePinned: true,
            spaceID: SumiSmokeFixtureIDs.personalSpace,
            profileID: nil,
            folderID: SumiSmokeFixtureIDs.folder,
            indexWhereClause: """
            is_space_pinned = 1
              AND lower(hex(folder_id)) = '\(SumiSmokeFixtureIDs.folder)'
            """
        )
        try insertSmokeTab(
            storeURL: storeURL,
            id: SumiSmokeFixtureIDs.essential,
            name: "Smoke Essential",
            urlString: "https://example.com/sumi-smoke-essential",
            isPinned: true,
            isSpacePinned: false,
            spaceID: nil,
            profileID: profileID,
            folderID: nil,
            indexWhereClause: """
            is_pinned = 1
              AND lower(hex(profile_id)) = '\(profileID)'
            """
        )
    }

    func insertSmokeSpace(
        storeURL: URL,
        id: String,
        profileID: String
    ) throws {
        try executeSQLite(
            sql: """
            INSERT INTO spaces (
                id, profile_id, name, icon, position
            ) VALUES (
                \(sqlBlob(id)), \(sqlBlob(profileID)), \(sqlString("Personal")),
                \(sqlString("house.fill")), 0
            );
            """,
            storeURL: storeURL
        )
    }

    func insertSmokeFolder(
        storeURL: URL,
        id: String,
        name: String,
        spaceID: String
    ) throws {
        let index = try nextIndex(
            storeURL: storeURL,
            tableName: "folders",
            whereClause: "lower(hex(space_id)) = '\(spaceID)'"
        )

        try executeSQLite(
            sql: """
            INSERT INTO folders (
                id, space_id, parent_folder_id, name, icon, color, is_open, position
            ) VALUES (
                \(sqlBlob(id)), \(sqlBlob(spaceID)), NULL, \(sqlString(name)),
                \(sqlString("")), \(sqlString("#007AFF")), 1, \(index)
            );
            """,
            storeURL: storeURL
        )
    }

    func insertSmokeTab(
        storeURL: URL,
        id: String,
        name: String,
        urlString: String,
        isPinned: Bool,
        isSpacePinned: Bool,
        spaceID: String?,
        profileID: String?,
        folderID: String?,
        indexWhereClause: String
    ) throws {
        let index = try nextIndex(
            storeURL: storeURL,
            tableName: "tabs",
            whereClause: indexWhereClause
        )

        try executeSQLite(
            sql: """
            INSERT INTO tabs (
                id, profile_id, execution_profile_id, space_id, folder_id,
                url, name, is_pinned, is_space_pinned, position, icon_asset,
                title_is_custom, current_url, can_go_back, can_go_forward
            ) VALUES (
                \(sqlBlob(id)), \(sqlBlob(profileID)),
                COALESCE(
                    \(sqlBlob(profileID)),
                    (SELECT profile_id FROM spaces WHERE id = \(sqlBlob(spaceID)))
                ),
                \(sqlBlob(spaceID)), \(sqlBlob(folderID)), \(sqlString(urlString)),
                \(sqlString(name)), \(isPinned ? 1 : 0), \(isSpacePinned ? 1 : 0),
                \(index), \(sqlString("globe")), 0, \(sqlString(urlString)), 0, 0
            );
            """,
            storeURL: storeURL
        )
    }

    func moveSmokeRegularTabsToTop(
        storeURL: URL,
        personalSpaceID: String,
        primaryTabID: String,
        secondaryTabID: String
    ) throws {
        let existingMinimum = try requiredScalar(
            sql: """
            SELECT COALESCE(MIN(position), 0) AS value
            FROM tabs
            WHERE lower(hex(space_id)) = '\(personalSpaceID)'
              AND is_space_pinned = 0
              AND is_pinned = 0
              AND folder_id IS NULL
              AND lower(hex(id)) NOT IN (\(sqlString(primaryTabID)), \(sqlString(secondaryTabID)));
            """,
            storeURL: storeURL,
            description: "Unable to determine regular tab order for Personal space \(personalSpaceID)"
        )
        let firstIndex = (Int(existingMinimum) ?? 0) - 2
        let secondIndex = firstIndex + 1

        try executeSQLite(
            sql: """
            UPDATE tabs
            SET position = CASE lower(hex(id))
                WHEN \(sqlString(primaryTabID)) THEN \(firstIndex)
                WHEN \(sqlString(secondaryTabID)) THEN \(secondIndex)
                ELSE position
            END
            WHERE lower(hex(id)) IN (\(sqlString(primaryTabID)), \(sqlString(secondaryTabID)));
            """,
            storeURL: storeURL
        )
    }

    func nextIndex(
        storeURL: URL,
        tableName: String,
        whereClause: String
    ) throws -> String {
        try requiredScalar(
            sql: """
            SELECT COALESCE(MAX(position), -1) + 1 AS value
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
        let database = try openSQLiteDatabase(
            at: storeURL,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        )
        defer { sqlite3_close(database) }

        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? sqliteErrorMessage(database, fallback: "Unknown sqlite3 error")
            sqlite3_free(errorMessage)
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
        let database = try openSQLiteDatabase(
            at: storeURL,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        )
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw FixtureError.sqliteFailure(
                sqliteErrorMessage(database, fallback: "Unknown sqlite3 error")
            )
        }
        defer { sqlite3_finalize(statement) }

        let columnCount = sqlite3_column_count(statement)
        var rows: [[String: String]] = []

        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                return rows
            }
            guard status == SQLITE_ROW else {
                throw FixtureError.sqliteFailure(
                    sqliteErrorMessage(database, fallback: "Unknown sqlite3 error")
                )
            }

            var row: [String: String] = [:]
            for columnIndex in 0..<columnCount {
                guard let name = sqlite3_column_name(statement, columnIndex),
                      let text = sqlite3_column_text(statement, columnIndex)
                else { continue }
                let cString = UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self)
                row[String(cString: name)] = String(cString: cString)
            }
            rows.append(row)
        }
    }

    func makeSmokeScratchDirectory(prefix: String) throws -> URL {
        let baseURL = try smokeScratchBaseURL()

        let directory = baseURL
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func smokeScratchBaseURL() throws -> URL {
        FileManager.default.temporaryDirectory
    }

    func openSQLiteDatabase(
        at url: URL,
        flags: Int32
    ) throws -> OpaquePointer {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            let message = database.map {
                sqliteErrorMessage($0, fallback: "Unable to open database at \(url.path)")
            } ?? "Unable to open database at \(url.path)"
            if let database {
                sqlite3_close(database)
            }
            throw FixtureError.sqliteFailure(message)
        }
        return database
    }

    func sqliteErrorMessage(
        _ database: OpaquePointer,
        fallback: String
    ) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return fallback
        }
        return String(cString: message)
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
                SELECT lower(hex(id)) AS value
                FROM tabs
                WHERE lower(hex(space_id)) = '\(personalSpaceHex)'
                  AND is_space_pinned = 0
                  AND is_pinned = 0
                  AND folder_id IS NULL
                ORDER BY position;
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
            SELECT lower(hex(id)) AS value
            FROM tabs
            WHERE lower(hex(space_id)) = '\(personalSpaceHex)'
              AND is_space_pinned = 0
              AND is_pinned = 0
              AND folder_id IS NULL
            ORDER BY position;
            """,
            storeURL: storeURL
        ))?.count
    }

    var smokeStoreURL: URL? {
        smokeAppSupportURL?.appendingPathComponent("Sumi.sqlite", isDirectory: false)
    }

    func requiredSmokeStoreURL() throws -> URL {
        if let smokeStoreURL {
            return smokeStoreURL
        }
        return try prepareSmokeStoreURL()
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
}
