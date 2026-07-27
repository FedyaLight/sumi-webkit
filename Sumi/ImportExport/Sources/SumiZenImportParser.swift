import Foundation
import SumiDomain

struct SumiZenImportResult {
    var data: SumiPortableData
    var warnings: [String]
}

struct SumiZenImportParser {
    func parse(profileURL: URL) throws -> SumiPortableData {
        var warnings: [String] = []
        return try parse(profileURL: profileURL, warnings: &warnings)
    }

    func parseWithDiagnostics(profileURL: URL) throws -> SumiZenImportResult {
        var warnings: [String] = []
        let data = try parse(profileURL: profileURL, warnings: &warnings)
        return SumiZenImportResult(data: data, warnings: warnings)
    }

    private func parse(profileURL: URL, warnings: inout [String]) throws -> SumiPortableData {
        // `zen-sessions.jsonlz4` is the authority, but a profile that has not
        // been opened by a Zen build new enough to write it still describes its
        // tabs in the Firefox session files.
        let sessionCandidates = [
            "zen-sessions.jsonlz4",
            "sessionstore.jsonlz4",
            "sessionstore-backups/recovery.jsonlz4",
            "sessionstore-backups/recovery.baklz4",
        ].map(profileURL.appendingPathComponent)
        guard let sessionsURL = sessionCandidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw SumiImportExportError.unsupportedFile("This Zen profile does not contain a session file.")
        }
        if sessionsURL.lastPathComponent != "zen-sessions.jsonlz4" {
            warnings.append(
                "Zen workspaces were read from \(sessionsURL.lastPathComponent) because zen-sessions.jsonlz4 is missing; "
                    + "spaces and folders may be incomplete."
            )
        }
        let jsonData = try SumiMozillaLZ4Decoder.decode(Data(contentsOf: sessionsURL))
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw SumiImportExportError.unsupportedFile("Zen sessions file did not decode to JSON.")
        }

        let containers = parseContainers(profileURL: profileURL, warnings: &warnings)
        let zenSpaces = root["spaces"] as? [[String: Any]] ?? []
        let zenFolders = root["folders"] as? [[String: Any]] ?? []
        let zenTabs = root["tabs"] as? [[String: Any]] ?? []

        let defaultProfile = SumiPortableProfile(
            id: "zen-container-0",
            name: "Default",
            index: 0
        )
        var profilesByContainer: [Int: SumiPortableProfile] = [0: defaultProfile]
        for container in containers.sorted(by: { $0.key < $1.key }) where container.key != 0 {
            profilesByContainer[container.key] = SumiPortableProfile(
                id: "zen-container-\(container.key)",
                name: SumiImportTextNormalization.nilIfBlank(container.value) ?? "Container \(container.key)",
                index: profilesByContainer.count
            )
        }

        let tabsByWorkspace = Dictionary(grouping: zenTabs, by: { ($0["zenWorkspace"] as? String) ?? "" })
        var spaces: [SumiPortableSpace] = []
        var workspaceProfileId: [String: String] = [:]
        for (idx, space) in zenSpaces.enumerated() {
            let workspaceId = (space["uuid"] as? String) ?? UUID().uuidString
            // Take the container most of the workspace's tabs actually use. The
            // first non-zero id in file order is whichever tab happened to be
            // serialized first, which mis-assigns a workspace whose single
            // stray container tab precedes the rest.
            let containerCounts = (tabsByWorkspace[workspaceId] ?? [])
                .compactMap { $0["userContextId"] as? Int }
                .filter { $0 != 0 }
                .reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
            let dominantContainerId = containerCounts
                .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
                .first?.key ?? 0
            let profile = profilesByContainer[dominantContainerId] ?? defaultProfile
            workspaceProfileId[workspaceId] = profile.id
            let theme = zenTheme(from: space)
            spaces.append(
                SumiPortableSpace(
                    id: workspaceId,
                    name: SumiImportTextNormalization.nilIfBlank(space["name"] as? String) ?? "Zen Space",
                    icon: space["icon"] as? String ?? "🌐",
                    index: idx,
                    profileId: profile.id,
                    themeDataBase64: nil,
                    color: theme?.colors.first,
                    colors: theme?.colors,
                    themeOpacity: theme?.opacity
                )
            )
        }

        let folderIds = Set(zenFolders.compactMap { $0["id"] as? String })
        var essentials: [SumiPortableLauncher] = []
        var pinned: [SumiPortableLauncher] = []
        var pinnedSiblingIndexes: [String: Int] = [:]
        var regularTabs: [SumiPortableRegularTab] = []
        var workspaceByFolderId: [String: String] = [:]
        for tab in zenTabs {
            guard let groupId = SumiImportTextNormalization.nilIfBlank(tab["groupId"] as? String),
                  folderIds.contains(groupId),
                  let workspaceId = SumiImportTextNormalization.nilIfBlank(tab["zenWorkspace"] as? String)
            else { continue }
            workspaceByFolderId[groupId] = workspaceId
        }

        for (idx, tab) in zenTabs.enumerated() {
            guard (tab["zenIsEmpty"] as? Bool) != true,
                  let entry = Self.currentEntry(of: tab),
                  let url = entry["url"] as? String,
                  url.isEmpty == false,
                  url != "about:blank"
            else { continue }
            let staticLabel = SumiImportTextNormalization.nilIfBlank(
                tab["zenStaticLabel"] as? String
            )
            let title = staticLabel
                ?? SumiImportTextNormalization.nilIfBlank(
                    entry["title"] as? String
                )
                ?? url
            let workspaceId = (tab["zenWorkspace"] as? String) ?? spaces.first?.id ?? "zen-default-space"
            let profileId = workspaceProfileId[workspaceId] ?? profilesByContainer[0]?.id
            let syncId = (tab["zenSyncId"] as? String) ?? UUID().uuidString
            let isPinned = tab["pinned"] as? Bool ?? false
            let isEssential = tab["zenEssential"] as? Bool ?? false
            if isPinned && isEssential {
                // Essentials are keyed by profile, so they follow their own
                // container rather than the container their workspace mostly
                // uses.
                let essentialProfileId = (tab["userContextId"] as? Int)
                    .flatMap { profilesByContainer[$0]?.id } ?? profileId
                essentials.append(
                    SumiPortableLauncher(
                        id: syncId,
                        title: title,
                        urlString: url,
                        index: idx,
                        profileId: essentialProfileId,
                        executionProfileId: essentialProfileId,
                        spaceId: nil,
                        folderId: nil,
                        iconAsset: nil,
                        sourceSpaceId: workspaceId,
                        titleIsCustom: staticLabel != nil
                    )
                )
            } else if isPinned {
                let folderId = (tab["groupId"] as? String).flatMap { folderIds.contains($0) ? $0 : nil }
                let launcher = SumiPortableLauncher(
                    id: syncId,
                    title: title,
                    urlString: url,
                    index: idx,
                    profileId: nil,
                    executionProfileId: profileId,
                    spaceId: workspaceId,
                    folderId: folderId,
                    iconAsset: nil,
                    sourceSpaceId: workspaceId,
                    titleIsCustom: staticLabel != nil
                )
                pinned.append(launcher)
                for siblingId in zenTabSiblingIdentifiers(from: tab, fallbackId: syncId) {
                    pinnedSiblingIndexes[siblingId] = idx
                }
            } else {
                regularTabs.append(
                    SumiPortableRegularTab(
                        id: syncId,
                        title: title,
                        urlString: url,
                        index: idx,
                        spaceId: workspaceId,
                        profileId: profileId,
                        folderId: (tab["groupId"] as? String).flatMap { folderIds.contains($0) ? $0 : nil }
                    )
                )
            }
        }

        let bookmarkSource = SumiBookmarkImportSource(
            id: "zen-\(profileURL.lastPathComponent)",
            title: "Zen",
            fileURL: profileURL.appendingPathComponent("places.sqlite"),
            kind: .firefoxSQLite
        )
        let bookmarks: [SumiPortableBookmarkNode]
        if FileManager.default.fileExists(atPath: bookmarkSource.fileURL.path) {
            do {
                bookmarks = try SumiBookmarkPortableBridge.portableNodes(
                    from: bookmarkSource.readBookmarks()
                )
            } catch {
                warnings.append("Zen bookmarks were skipped because places.sqlite could not be imported: \(error.localizedDescription)")
                bookmarks = []
            }
        } else {
            bookmarks = []
        }
        var folderWarnings: [String] = []
        let folderRecords = flattenZenFolders(
            zenFolders,
            pinnedSiblingIndexes: pinnedSiblingIndexes,
            workspaceByFolderId: workspaceByFolderId,
            fallbackSpaceId: spaces.first?.id,
            warningSink: { folderWarnings.append($0) }
        )
        warnings.append(contentsOf: folderWarnings)

        return SumiPortableData(
            profiles: Array(profilesByContainer.values).sorted { $0.index < $1.index },
            spaces: spaces,
            folders: folderRecords,
            essentials: essentials,
            pinnedLaunchers: pinned,
            regularTabs: regularTabs,
            bookmarks: bookmarks
        )
    }

    private func parseContainers(profileURL: URL, warnings: inout [String]) -> [Int: String] {
        let url = profileURL.appendingPathComponent("containers.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            warnings.append("Zen containers were skipped because containers.json could not be read: \(error.localizedDescription)")
            return [:]
        }

        let identities: [[String: Any]]
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let decodedIdentities = root["identities"] as? [[String: Any]]
            else {
                warnings.append("Zen containers were skipped because containers.json did not contain identities.")
                return [:]
            }
            identities = decodedIdentities
        } catch {
            warnings.append("Zen containers were skipped because containers.json could not be decoded: \(error.localizedDescription)")
            return [:]
        }

        var output: [Int: String] = [:]
        for identity in identities {
            if let id = identity["userContextId"] as? Int {
                output[id] = identity["name"] as? String ?? "Container \(id)"
            }
        }
        return output
    }

    func flattenZenFolders(
        _ folders: [[String: Any]],
        pinnedSiblingIndexes: [String: Int] = [:],
        workspaceByFolderId: [String: String] = [:],
        fallbackSpaceId: String? = nil,
        warningSink: ((String) -> Void)? = nil
    ) -> [SumiPortableFolder] {
        var rawById: [String: [String: Any]] = [:]
        for folder in folders {
            if let id = folder["id"] as? String {
                rawById[id] = folder
            }
        }

        var pathCache: [String: [String]] = [:]
        func path(for id: String, visited: Set<String> = []) -> [String] {
            if let cached = pathCache[id] { return cached }
            guard let folder = rawById[id] else { return [] }
            guard visited.contains(id) == false else {
                return [folder["name"] as? String ?? "Untitled Folder"]
            }
            var nextVisited = visited
            nextVisited.insert(id)
            let parent = (folder["parentId"] as? String)
                .flatMap { rawById[$0] == nil ? nil : path(for: $0, visited: nextVisited) } ?? []
            let resolved = parent + [folder["name"] as? String ?? "Untitled Folder"]
            pathCache[id] = resolved
            return resolved
        }

        // A folder whose `workspaceId` is blank would carry an empty space id
        // all the way to the plan builder, which silently drops it along with
        // everything inside. Recover the workspace from a tab that lives in the
        // folder, then from an ancestor, then from the first space.
        var unresolvedFolderNames: [String] = []
        func resolvedSpaceId(for folder: [String: Any], id: String) -> String? {
            if let declared = SumiImportTextNormalization.nilIfBlank(folder["workspaceId"] as? String) {
                return declared
            }
            if let fromTabs = workspaceByFolderId[id] { return fromTabs }
            var ancestorId = SumiImportTextNormalization.nilIfBlank(folder["parentId"] as? String)
            var visited: Set<String> = [id]
            while let current = ancestorId, visited.insert(current).inserted {
                if let ancestor = rawById[current] {
                    if let declared = SumiImportTextNormalization.nilIfBlank(ancestor["workspaceId"] as? String) {
                        return declared
                    }
                    if let fromTabs = workspaceByFolderId[current] { return fromTabs }
                    ancestorId = SumiImportTextNormalization.nilIfBlank(ancestor["parentId"] as? String)
                } else {
                    ancestorId = nil
                }
            }
            unresolvedFolderNames.append(folder["name"] as? String ?? "Untitled Folder")
            return fallbackSpaceId
        }

        var previousSiblingInfoById: [String: (type: String, id: String?)] = [:]
        var records = folders.enumerated().compactMap { idx, folder -> SumiPortableFolder? in
            guard let id = folder["id"] as? String else { return nil }
            if let info = folder["prevSiblingInfo"] as? [String: Any],
               let type = info["type"] as? String {
                previousSiblingInfoById[id] = (type: type, id: SumiImportTextNormalization.nilIfBlank(info["id"] as? String))
            }
            let folderPath = path(for: id)
            return SumiPortableFolder(
                id: id,
                name: folderPath.last ?? "Untitled Folder",
                icon: SumiZenFolderIconCatalog.normalizedFolderIconValue(folder["userIcon"] as? String),
                colorHex: "#000000",
                spaceId: resolvedSpaceId(for: folder, id: id) ?? "",
                parentFolderId: SumiImportTextNormalization.nilIfBlank(folder["parentId"] as? String),
                isOpen: !(folder["collapsed"] as? Bool ?? false),
                index: idx,
                sourcePath: folderPath
            )
        }
        applyZenPreviousSiblingOrder(
            to: &records,
            previousSiblingInfoById: previousSiblingInfoById,
            pinnedSiblingIndexes: pinnedSiblingIndexes
        )
        if unresolvedFolderNames.isEmpty == false {
            let names = unresolvedFolderNames.sorted().joined(separator: ", ")
            warningSink?(
                fallbackSpaceId == nil
                    ? "Zen folders without a workspace were skipped: \(names)."
                    : "Zen folders without a workspace were moved to the first space: \(names)."
            )
        }
        return SumiPortableFolderHierarchyRepair.repaired(records)
    }

    private func applyZenPreviousSiblingOrder(
        to records: inout [SumiPortableFolder],
        previousSiblingInfoById: [String: (type: String, id: String?)],
        pinnedSiblingIndexes: [String: Int]
    ) {
        var folderIndexById = Dictionary(
            records.map { ($0.id, $0.index) },
            uniquingKeysWith: { first, _ in first }
        )
        let folderContainerById = Dictionary(
            records.map { ($0.id, "\($0.spaceId)|\($0.parentFolderId ?? "")") },
            uniquingKeysWith: { first, _ in first }
        )

        func previousIndex(for folder: SumiPortableFolder) -> Int? {
            guard let info = previousSiblingInfoById[folder.id] else { return nil }
            switch info.type {
            case "start":
                return -1
            case "group":
                guard let previousFolderId = info.id,
                      folderContainerById[previousFolderId] == folderContainerById[folder.id],
                      let index = folderIndexById[previousFolderId] else {
                    return nil
                }
                return index
            case "tab":
                guard let previousTabId = info.id,
                      let index = pinnedSiblingIndexes[previousTabId] else {
                    return nil
                }
                return index
            default:
                return nil
            }
        }

        for _ in 0..<max(records.count, 1) {
            var changed = false
            for idx in records.indices {
                guard let index = previousIndex(for: records[idx]).map({ $0 + 1 }),
                      records[idx].index != index else {
                    continue
                }
                records[idx].index = index
                folderIndexById[records[idx].id] = index
                changed = true
            }
            if changed == false { break }
        }
    }

    /// A session tab's `index` is a 1-based cursor into its back/forward
    /// history, so a tab the user navigated back in is not described by its
    /// last entry. Falls back to the last entry when `index` is absent or out
    /// of range.
    static func currentEntry(of tab: [String: Any]) -> [String: Any]? {
        guard let entries = tab["entries"] as? [[String: Any]], entries.isEmpty == false else { return nil }
        if let index = tab["index"] as? Int, index >= 1, index <= entries.count {
            return entries[index - 1]
        }
        return entries.last
    }

    private func zenTabSiblingIdentifiers(from tab: [String: Any], fallbackId: String) -> [String] {
        var ids: [String] = [fallbackId]
        for key in ["id", "zenSyncId", "tabId"] {
            if let id = SumiImportTextNormalization.nilIfBlank(tab[key] as? String) {
                ids.append(id)
            }
        }
        if let attributes = tab["attributes"] as? [String: Any] {
            for key in ["id", "zenSyncId", "tabId"] {
                if let id = SumiImportTextNormalization.nilIfBlank(attributes[key] as? String) {
                    ids.append(id)
                }
            }
        }

        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }

    private func zenTheme(from space: [String: Any]) -> (colors: [SumiPortableRGBColor], opacity: Double?)? {
        guard let theme = space["theme"] as? [String: Any],
              let gradientColors = theme["gradientColors"] as? [[String: Any]]
        else { return nil }

        let colors = gradientColors.compactMap { zenColor(components: $0["c"] as? [Any]) }
        guard colors.isEmpty == false else { return nil }

        let opacity = (theme["opacity"] as? Double)
            ?? (theme["opacity"] as? Int).map(Double.init)
        return (colors, opacity)
    }

    private func zenColor(components: [Any]?) -> SumiPortableRGBColor? {
        guard let components, components.count >= 3 else { return nil }
        let raw: [Double] = (0..<3).compactMap { idx in
            if let value = components[idx] as? Double { return value }
            if let value = components[idx] as? Int { return Double(value) }
            return nil
        }
        guard raw.count == 3 else { return nil }
        // Zen stores gradient stops either as 0-255 components or already
        // normalized 0-1 floats. Decide by magnitude: a genuinely 0-255 array
        // with every component <= 1 is near-black either way.
        let scale: Double = raw.contains(where: { $0 > 1.0 }) ? 255 : 1
        return SumiPortableRGBColor(r: raw[0] / scale, g: raw[1] / scale, b: raw[2] / scale)
    }
}
