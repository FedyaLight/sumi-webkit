import Compression
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
        let sessionsURL = profileURL.appendingPathComponent("zen-sessions.jsonlz4")
        guard FileManager.default.fileExists(atPath: sessionsURL.path) else {
            throw SumiImportExportError.unsupportedFile("This Zen profile does not contain zen-sessions.jsonlz4.")
        }
        let jsonData = try SumiMozLZ4.decode(Data(contentsOf: sessionsURL))
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
            let firstContainerId = tabsByWorkspace[workspaceId]?
                .compactMap { $0["userContextId"] as? Int }
                .first(where: { $0 != 0 }) ?? 0
            let profile = profilesByContainer[firstContainerId] ?? defaultProfile
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

        for (idx, tab) in zenTabs.enumerated() {
            guard (tab["zenIsEmpty"] as? Bool) != true,
                  let entry = (tab["entries"] as? [[String: Any]])?.last,
                  let url = entry["url"] as? String,
                  url.isEmpty == false,
                  url != "about:blank"
            else { continue }
            let title = SumiImportTextNormalization.nilIfBlank(entry["title"] as? String) ?? url
            let workspaceId = (tab["zenWorkspace"] as? String) ?? spaces.first?.id ?? "zen-default-space"
            let profileId = workspaceProfileId[workspaceId] ?? profilesByContainer[0]?.id
            let syncId = (tab["zenSyncId"] as? String) ?? UUID().uuidString
            let isPinned = tab["pinned"] as? Bool ?? false
            let isEssential = tab["zenEssential"] as? Bool ?? false
            if isPinned && isEssential {
                essentials.append(
                    SumiPortableLauncher(
                        id: syncId,
                        title: title,
                        urlString: url,
                        index: idx,
                        profileId: profileId,
                        executionProfileId: profileId,
                        spaceId: nil,
                        folderId: nil,
                        iconAsset: nil,
                        sourceSpaceId: workspaceId
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
                    sourceSpaceId: workspaceId
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
                        folderId: nil
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
        let folderRecords = flattenZenFolders(zenFolders, pinnedSiblingIndexes: pinnedSiblingIndexes)

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
        pinnedSiblingIndexes: [String: Int] = [:]
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
                spaceId: folder["workspaceId"] as? String ?? "",
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

private enum SumiMozLZ4 {
    static func decode(_ data: Data) throws -> Data {
        let magic = Data([0x6D, 0x6F, 0x7A, 0x4C, 0x7A, 0x34, 0x30, 0x00])
        guard data.count >= 12, Data(data.prefix(8)) == magic else {
            throw SumiImportExportError.unsupportedFile("Zen sessions file is not Mozilla LZ4.")
        }
        let size = data[8..<12].enumerated().reduce(UInt32(0)) { partial, item in
            partial | (UInt32(item.element) << UInt32(item.offset * 8))
        }
        let compressed = data.dropFirst(12)
        var output = Data(count: Int(size))
        let decoded = output.withUnsafeMutableBytes { outPtr in
            compressed.withUnsafeBytes { inPtr in
                compression_decode_buffer(
                    outPtr.bindMemory(to: UInt8.self).baseAddress!,
                    Int(size),
                    inPtr.bindMemory(to: UInt8.self).baseAddress!,
                    compressed.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }
        guard decoded == Int(size) else {
            throw SumiImportExportError.unsupportedFile("Sumi could not decode Zen's LZ4 session data.")
        }
        return output
    }
}
