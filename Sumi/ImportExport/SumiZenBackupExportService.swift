import Compression
import Foundation

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
        let sqliteWriter = SumiZenBackupSQLiteArtifactWriter()
        try sqliteWriter.writePlaces(
            bookmarks: data.bookmarks,
            history: history,
            to: profile.appendingPathComponent("places.sqlite")
        )
        try sqliteWriter.writeCookies(
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
            "version": 6,
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
                    favorite: false,
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
        for pin in data.favorite {
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
                    favorite: true,
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
                    favorite: false,
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
        favorite: Bool,
        folderId: String?,
        index: Int
    ) -> [String: Any] {
        var tab: [String: Any] = [
            "entries": [["url": url, "title": title]],
            // `index` is the 1-based cursor into `entries`, not the tab order.
            // Every exported tab carries a single entry, so it is always 1;
            // the workspace order lives in `indexInWorkspace`. Writing
            // `order + 1` here produces an out-of-range cursor that Zen
            // discards for every tab after the first.
            "index": 1,
            "lastAccessed": Int(Date().timeIntervalSince1970 * 1_000),
            "pinned": pinned,
            "hidden": false,
            "zenWorkspace": workspaceId,
            "zenSyncId": id,
            "zenEssential": favorite,
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

    private func archive(root: URL, outputURL: URL) throws {
        // Tar writes directly to the destination, so a mid-archive failure
        // would leave a corrupt partial file behind. Stage inside the temp
        // root first, then move atomically over any previous export.
        let staged = root.appendingPathComponent("SumiZenBackup-stage.tgz", isDirectory: false)
        if FileManager.default.fileExists(atPath: staged.path) {
            try FileManager.default.removeItem(at: staged)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.currentDirectoryURL = root
        process.arguments = ["-czf", staged.path, "manifest.json", "profile"]
        // Suppress macOS AppleDouble `._` sidecars: they pollute the archive
        // and serve no purpose for Zen.
        var environment = ProcessInfo.processInfo.environment
        environment["COPYFILE_DISABLE"] = "1"
        process.environment = environment
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw SumiImportExportError.exportFailed(
                "Could not start the archive tool: \(error.localizedDescription)"
            )
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: staged)
            throw SumiImportExportError.exportFailed(
                detail.isEmpty
                    ? "Could not create the Zen backup archive."
                    : "Could not create the Zen backup archive: \(detail)"
            )
        }
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.moveItem(at: staged, to: outputURL)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw SumiImportExportError.exportFailed(
                "Could not save the Zen backup archive: \(error.localizedDescription)"
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
            throw SumiImportExportError.exportFailed("Could not encode Zen workspace data.")
        }
        var output = Data("mozLz40\0".utf8)
        var payloadSize = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &payloadSize) { output.append(contentsOf: $0) }
        output.append(compressed.prefix(size))
        return output
    }

    private static let containerColors = [
        "blue", "cyan", "green", "yellow", "orange", "red", "pink", "purple",
    ]
}
