import Foundation

// Compatibility model for browser2zen's MIT-licensed legacy JSON shape.
// This is a Sumi-owned Swift implementation; browser2zen is not vendored.
struct SumiBrowser2ZenDocument: Codable, Sendable {
    var source: String
    var totalSpaces: Int
    var spaces: [SumiBrowser2ZenSpace]
    var sumi: SumiBrowser2ZenExtension?

    enum CodingKeys: String, CodingKey {
        case source
        case totalSpaces = "total_spaces"
        case spaces
        case sumi
    }
}

struct SumiBrowser2ZenExtension: Codable, Sendable {
    var formatVersion: Int
    var data: SumiPortableData

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case data
    }
}

struct SumiBrowser2ZenSpace: Codable, Sendable {
    var spaceId: String
    var spaceName: String
    var icon: String?
    var color: SumiPortableRGBColor?
    var totalPinnedTabs: Int?
    var totalOpenTabs: Int?
    var totalFolders: Int?
    var pinnedTabs: [SumiBrowser2ZenTab]
    var openTabs: [SumiBrowser2ZenOpenTab]
    var folders: [SumiBrowser2ZenFolder]

    enum CodingKeys: String, CodingKey {
        case spaceId = "space_id"
        case spaceName = "space_name"
        case icon
        case color
        case totalPinnedTabs = "total_pinned_tabs"
        case totalOpenTabs = "total_open_tabs"
        case totalFolders = "total_folders"
        case pinnedTabs = "pinned_tabs"
        case openTabs = "open_tabs"
        case folders
    }
}

struct SumiBrowser2ZenTab: Codable, Sendable {
    var url: String
    var title: String
    var spaceId: String?
    var spaceName: String?
    var folderPath: [String]
    var tabId: String?
    var parentId: String?
    var index: Int?
    var isEssential: Bool

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case spaceId = "space_id"
        case spaceName = "space_name"
        case folderPath = "folder_path"
        case tabId = "tab_id"
        case parentId = "parent_id"
        case index
        case isEssential = "is_essential"
    }

    init(
        url: String,
        title: String,
        spaceId: String?,
        spaceName: String?,
        folderPath: [String],
        tabId: String?,
        parentId: String?,
        index: Int?,
        isEssential: Bool
    ) {
        self.url = url
        self.title = title
        self.spaceId = spaceId
        self.spaceName = spaceName
        self.folderPath = folderPath
        self.tabId = tabId
        self.parentId = parentId
        self.index = index
        self.isEssential = isEssential
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        spaceId = try container.decodeIfPresent(String.self, forKey: .spaceId)
        spaceName = try container.decodeIfPresent(String.self, forKey: .spaceName)
        folderPath = try container.decodeIfPresent([String].self, forKey: .folderPath) ?? []
        tabId = try container.decodeIfPresent(String.self, forKey: .tabId)
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        isEssential = try container.decodeIfPresent(Bool.self, forKey: .isEssential) ?? false
    }
}

struct SumiBrowser2ZenOpenTab: Codable, Sendable {
    var url: String
    var title: String
    var spaceId: String?
    var spaceName: String?
    var tabId: String?
    var index: Int?

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case spaceId = "space_id"
        case spaceName = "space_name"
        case tabId = "tab_id"
        case index
    }
}

struct SumiBrowser2ZenFolder: Codable, Sendable {
    var folderId: String
    var title: String
    var parentId: String?
    var spaceId: String?
    var childrenIds: [String]
    var index: Int?

    enum CodingKeys: String, CodingKey {
        case folderId = "folder_id"
        case title
        case parentId = "parent_id"
        case spaceId = "space_id"
        case childrenIds = "children_ids"
        case index
    }

    init(
        folderId: String,
        title: String,
        parentId: String?,
        spaceId: String?,
        childrenIds: [String],
        index: Int?
    ) {
        self.folderId = folderId
        self.title = title
        self.parentId = parentId
        self.spaceId = spaceId
        self.childrenIds = childrenIds
        self.index = index
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Folder"
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        if parentId?.isEmpty == true { parentId = nil }
        spaceId = try container.decodeIfPresent(String.self, forKey: .spaceId)
        childrenIds = try container.decodeIfPresent([String].self, forKey: .childrenIds) ?? []
        index = try container.decodeIfPresent(Int.self, forKey: .index)
    }
}

@MainActor
final class SumiTransferExportService {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func exportBrowser2ZenDocument(from browserManager: BrowserManager) throws -> Data {
        let data = SumiImportExportSnapshot.makeData(from: browserManager)
        let document = makeBrowser2ZenDocument(from: data)
        return try encoder.encode(document)
    }

    func importBrowser2ZenDocument(from data: Data) throws -> SumiPortableData {
        let document = try decoder.decode(SumiBrowser2ZenDocument.self, from: data)
        if document.source == "sumi", let exact = document.sumi?.data {
            return exact
        }
        return SumiBrowser2ZenNormalizer.normalizedData(from: document)
    }

    private func makeBrowser2ZenDocument(from data: SumiPortableData) -> SumiBrowser2ZenDocument {
        let firstSpaceIdByProfile = Dictionary(
            data.spaces
                .compactMap { space -> (String, String)? in
                    guard let profileId = space.profileId else { return nil }
                    return (profileId, space.id)
                }
                .reversed(),
            uniquingKeysWith: { first, _ in first }
        )

        let foldersBySpace = Dictionary(grouping: data.folders, by: \.spaceId)
        let pinnedBySpace = Dictionary(grouping: data.pinnedLaunchers, by: { $0.spaceId ?? "" })
        let tabsBySpace = Dictionary(grouping: data.regularTabs, by: \.spaceId)

        let spaces = data.spaces.sorted { $0.index < $1.index }.map { space in
            var pinnedTabs: [SumiBrowser2ZenTab] = []

            let spaceFolders = (foldersBySpace[space.id] ?? []).sorted { $0.index < $1.index }
            let folderLookup = Dictionary(uniqueKeysWithValues: spaceFolders.map { ($0.id, $0) })
            let folderPathById = Self.folderPaths(for: spaceFolders)
            let childFolderIdsByParent = spaceFolders.reduce(into: [String: [String]]()) { result, folder in
                guard let parentId = folder.parentFolderId,
                      folderLookup[parentId] != nil else { return }
                result[parentId, default: []].append(folder.id)
            }
            let spacePinned = (pinnedBySpace[space.id] ?? []).sorted { $0.index < $1.index }
            let pinnedIdsByFolder = spacePinned.reduce(into: [String: [String]]()) { result, pin in
                guard let folderId = pin.folderId,
                      folderLookup[folderId] != nil else { return }
                result[folderId, default: []].append(pin.id)
            }
            let legacyFolders = spaceFolders.map { folder in
                SumiBrowser2ZenFolder(
                    folderId: folder.id,
                    title: folder.name,
                    parentId: folder.parentFolderId.flatMap { folderLookup[$0] == nil ? nil : $0 },
                    spaceId: space.id,
                    childrenIds: (childFolderIdsByParent[folder.id] ?? []) + (pinnedIdsByFolder[folder.id] ?? []),
                    index: folder.index
                )
            }

            pinnedTabs.append(contentsOf: spacePinned.enumerated().map { idx, pin in
                SumiBrowser2ZenTab(
                    url: pin.urlString,
                    title: pin.title,
                    spaceId: space.id,
                    spaceName: space.name,
                    folderPath: pin.folderId.flatMap { folderPathById[$0] } ?? [],
                    tabId: pin.id,
                    parentId: pin.folderId,
                    index: idx,
                    isEssential: false
                )
            })

            let essentialPins = data.essentials.filter { pin in
                guard let profileId = pin.profileId else { return false }
                return firstSpaceIdByProfile[profileId] == space.id
            }
            pinnedTabs.append(contentsOf: essentialPins.enumerated().map { offset, pin in
                SumiBrowser2ZenTab(
                    url: pin.urlString,
                    title: pin.title,
                    spaceId: space.id,
                    spaceName: space.name,
                    folderPath: [],
                    tabId: pin.id,
                    parentId: nil,
                    index: spacePinned.count + offset,
                    isEssential: true
                )
            })

            let openTabs = (tabsBySpace[space.id] ?? []).sorted { $0.index < $1.index }.enumerated().map { idx, tab in
                SumiBrowser2ZenOpenTab(
                    url: tab.urlString,
                    title: tab.title,
                    spaceId: space.id,
                    spaceName: space.name,
                    tabId: tab.id,
                    index: idx
                )
            }

            return SumiBrowser2ZenSpace(
                spaceId: space.id,
                spaceName: space.name,
                icon: space.icon,
                color: space.color,
                totalPinnedTabs: pinnedTabs.count,
                totalOpenTabs: openTabs.count,
                totalFolders: legacyFolders.count,
                pinnedTabs: pinnedTabs,
                openTabs: openTabs,
                folders: legacyFolders
            )
        }

        return SumiBrowser2ZenDocument(
            source: "sumi",
            totalSpaces: spaces.count,
            spaces: spaces,
            sumi: SumiBrowser2ZenExtension(formatVersion: 1, data: data)
        )
    }

    private static func folderPaths(for folders: [SumiPortableFolder]) -> [String: [String]] {
        let foldersById = Dictionary(
            folders.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var cache: [String: [String]] = [:]

        func path(for folderId: String, visited: Set<String> = []) -> [String] {
            if let cached = cache[folderId] { return cached }
            guard let folder = foldersById[folderId] else { return [] }
            guard visited.contains(folderId) == false else { return [folder.name] }

            var nextVisited = visited
            nextVisited.insert(folderId)
            let parentPath = folder.parentFolderId
                .flatMap { foldersById[$0] == nil ? nil : path(for: $0, visited: nextVisited) } ?? []
            let resolved = parentPath + [folder.name]
            cache[folderId] = resolved
            return resolved
        }

        return Dictionary(
            folders.map { ($0.id, path(for: $0.id)) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

enum SumiBrowser2ZenNormalizer {
    static func normalizedData(from document: SumiBrowser2ZenDocument) -> SumiPortableData {
        let profile = SumiPortableProfile(
            id: "browser2zen-default-profile",
            name: "\(document.source.capitalized) Import",
            icon: SumiProfileIcon.defaultIcon,
            index: 0
        )

        var spaces: [SumiPortableSpace] = []
        var folders: [SumiPortableFolder] = []
        var essentials: [SumiPortableLauncher] = []
        var pinnedLaunchers: [SumiPortableLauncher] = []
        var regularTabs: [SumiPortableRegularTab] = []

        for (spaceIndex, legacySpace) in document.spaces.enumerated() {
            let spaceId = legacySpace.spaceId.isEmpty ? UUID().uuidString : legacySpace.spaceId
            spaces.append(
                SumiPortableSpace(
                    id: spaceId,
                    name: legacySpace.spaceName.isEmpty ? "Imported Space" : legacySpace.spaceName,
                    icon: legacySpace.icon ?? "🌐",
                    index: spaceIndex,
                    profileId: profile.id,
                    themeDataBase64: nil,
                    color: legacySpace.color
                )
            )

            let folderRecords = folderRecords(from: legacySpace.folders, spaceId: spaceId)
            folders.append(contentsOf: folderRecords)
            let foldersById = Dictionary(
                folderRecords.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            for (idx, tab) in legacySpace.pinnedTabs.enumerated() {
                guard tab.url.isEmpty == false else { continue }
                let folderId = resolvedFolderId(for: tab, foldersById: foldersById)
                let launcher = SumiPortableLauncher(
                    id: tab.tabId?.nilIfEmpty ?? UUID().uuidString,
                    title: tab.title.nilIfEmpty ?? tab.url,
                    urlString: tab.url,
                    index: tab.index ?? idx,
                    profileId: tab.isEssential ? profile.id : nil,
                    executionProfileId: profile.id,
                    spaceId: tab.isEssential ? nil : spaceId,
                    folderId: tab.isEssential ? nil : folderId,
                    iconAsset: nil,
                    sourceSpaceId: spaceId
                )
                if tab.isEssential {
                    essentials.append(launcher)
                } else {
                    pinnedLaunchers.append(launcher)
                }
            }

            for (idx, tab) in legacySpace.openTabs.enumerated() {
                guard tab.url.isEmpty == false else { continue }
                regularTabs.append(
                    SumiPortableRegularTab(
                        id: tab.tabId?.nilIfEmpty ?? UUID().uuidString,
                        title: tab.title.nilIfEmpty ?? tab.url,
                        urlString: tab.url,
                        index: tab.index ?? idx,
                        spaceId: spaceId,
                        profileId: profile.id,
                        folderId: nil
                    )
                )
            }
        }

        return SumiPortableData(
            profiles: [profile],
            spaces: spaces,
            folders: folders,
            essentials: essentials,
            pinnedLaunchers: pinnedLaunchers,
            regularTabs: regularTabs,
            bookmarks: []
        )
    }

    private static func folderRecords(
        from legacyFolders: [SumiBrowser2ZenFolder],
        spaceId: String
    ) -> [SumiPortableFolder] {
        let sourceIds = Set(legacyFolders.map(\.folderId))
        let outputIds = Dictionary(
            legacyFolders.map { folder in
                (folder.folderId, folder.folderId.nilIfEmpty ?? UUID().uuidString)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let folderById = Dictionary(
            legacyFolders.map { ($0.folderId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var pathCache: [String: [String]] = [:]

        func path(for folder: SumiBrowser2ZenFolder, visited: Set<String> = []) -> [String] {
            if let cached = pathCache[folder.folderId] { return cached }
            guard visited.contains(folder.folderId) == false else {
                return [folder.title]
            }
            var nextVisited = visited
            nextVisited.insert(folder.folderId)
            let parentPath = folder.parentId
                .flatMap { folderById[$0] }
                .map { path(for: $0, visited: nextVisited) } ?? []
            let resolved = parentPath + [folder.title]
            pathCache[folder.folderId] = resolved
            return resolved
        }

        let records = legacyFolders.sorted { ($0.index ?? 0) < ($1.index ?? 0) }.enumerated().map { idx, folder in
            let folderPath = path(for: folder)
            let outputId = outputIds[folder.folderId] ?? UUID().uuidString
            let parentFolderId = folder.parentId
                .flatMap { parentId -> String? in
                    guard parentId != folder.folderId,
                          sourceIds.contains(parentId) else { return nil }
                    return outputIds[parentId]
                }
            return SumiPortableFolder(
                id: outputId,
                name: folder.title.nilIfEmpty ?? "Untitled Folder",
                icon: SumiZenFolderIconCatalog.normalizedFolderIconValue(nil),
                colorHex: "#000000",
                spaceId: folder.spaceId?.nilIfEmpty ?? spaceId,
                parentFolderId: parentFolderId,
                isOpen: true,
                index: folder.index ?? idx,
                sourcePath: folderPath
            )
        }
        return SumiPortableFolderHierarchyRepair.repaired(records)
    }

    private static func resolvedFolderId(
        for tab: SumiBrowser2ZenTab,
        foldersById: [String: SumiPortableFolder]
    ) -> String? {
        if let parentId = tab.parentId?.nilIfEmpty, foldersById[parentId] != nil {
            return parentId
        }
        if tab.folderPath.isEmpty == false,
           let exact = foldersById.values.first(where: { $0.sourcePath == tab.folderPath }) {
            return exact.id
        }
        guard let last = tab.folderPath.last else { return nil }
        return foldersById.values.first { $0.sourcePath.last == last }?.id
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
