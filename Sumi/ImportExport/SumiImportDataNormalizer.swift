import Foundation

enum SumiImportDataNormalizer {
    static func normalize(_ data: SumiPortableData) -> SumiPortableData {
        var output = data
        repairMissingReferences(in: &output)
        output.folders = SumiPortableFolderHierarchyRepair.repaired(output.folders)
        clearCrossSpaceFolderReferences(in: &output)
        deduplicateRuntimeBuckets(in: &output)
        normalizeIndices(in: &output)
        return output
    }

    private static func repairMissingReferences(in data: inout SumiPortableData) {
        let validProfileIds = Set(data.profiles.map(\.id))
        let fallbackProfileId = data.profiles.first?.id
        let validSpaceIds = Set(data.spaces.map(\.id))
        let fallbackSpaceId = data.spaces.first?.id

        data.spaces = data.spaces.map { space in
            var copy = space
            if copy.profileId.map(validProfileIds.contains) != true {
                copy.profileId = fallbackProfileId
            }
            return copy
        }
        let profileBySpaceId = Dictionary(
            data.spaces.map { ($0.id, $0.profileId) },
            uniquingKeysWith: { first, _ in first }
        )
        data.folders = data.folders.compactMap { folder in
            guard let targetSpaceId = validSpaceIds.contains(folder.spaceId)
                ? folder.spaceId
                : fallbackSpaceId else { return nil }
            var copy = folder
            copy.spaceId = targetSpaceId
            return copy
        }
        data.favorite = data.favorite.compactMap { launcher in
            guard let profileId = launcher.profileId.flatMap({ validProfileIds.contains($0) ? $0 : nil })
                ?? fallbackProfileId else { return nil }
            var copy = launcher
            copy.profileId = profileId
            if copy.executionProfileId.map(validProfileIds.contains) != true {
                copy.executionProfileId = profileId
            }
            return copy
        }
        data.pinnedLaunchers = data.pinnedLaunchers.compactMap { launcher in
            guard let spaceId = launcher.spaceId.flatMap({ validSpaceIds.contains($0) ? $0 : nil })
                ?? launcher.sourceSpaceId.flatMap({ validSpaceIds.contains($0) ? $0 : nil })
                ?? fallbackSpaceId else { return nil }
            var copy = launcher
            copy.spaceId = spaceId
            copy.sourceSpaceId = spaceId
            if copy.executionProfileId.map(validProfileIds.contains) != true {
                copy.executionProfileId = profileBySpaceId[spaceId] ?? fallbackProfileId
            }
            return copy
        }
        data.regularTabs = data.regularTabs.compactMap { tab in
            guard let spaceId = validSpaceIds.contains(tab.spaceId) ? tab.spaceId : fallbackSpaceId else {
                return nil
            }
            var copy = tab
            copy.spaceId = spaceId
            if copy.profileId.map(validProfileIds.contains) != true {
                copy.profileId = profileBySpaceId[spaceId] ?? fallbackProfileId
            }
            return copy
        }
    }

    static func normalizedSidebarContainerIndices(
        folders: [SumiPortableFolder],
        pinnedLaunchers: [SumiPortableLauncher]
    ) -> (folders: [SumiPortableFolder], pinnedLaunchers: [SumiPortableLauncher]) {
        struct ContainerKey: Hashable, Comparable {
            let spaceId: String
            let folderId: String?

            static func < (lhs: Self, rhs: Self) -> Bool {
                if lhs.spaceId != rhs.spaceId { return lhs.spaceId < rhs.spaceId }
                return (lhs.folderId ?? "") < (rhs.folderId ?? "")
            }
        }

        enum SidebarEntry {
            case folder(arrayIndex: Int, sourceIndex: Int, id: String)
            case pinnedLauncher(arrayIndex: Int, sourceIndex: Int, id: String)

            var sourceIndex: Int {
                switch self {
                case .folder(_, let sourceIndex, _), .pinnedLauncher(_, let sourceIndex, _):
                    return sourceIndex
                }
            }

            var sortRank: Int {
                switch self {
                case .folder: return 0
                case .pinnedLauncher: return 1
                }
            }

            var stableId: String {
                switch self {
                case .folder(_, _, let id), .pinnedLauncher(_, _, let id):
                    return id
                }
            }
        }

        var grouped: [ContainerKey: [SidebarEntry]] = [:]
        for (index, folder) in folders.enumerated() {
            let key = ContainerKey(spaceId: folder.spaceId, folderId: folder.parentFolderId)
            grouped[key, default: []].append(
                .folder(arrayIndex: index, sourceIndex: folder.index, id: folder.id)
            )
        }
        for (index, launcher) in pinnedLaunchers.enumerated() {
            let key = ContainerKey(spaceId: launcher.spaceId ?? "", folderId: launcher.folderId)
            grouped[key, default: []].append(
                .pinnedLauncher(arrayIndex: index, sourceIndex: launcher.index, id: launcher.id)
            )
        }

        var normalizedFolders = folders
        var normalizedPinnedLaunchers = pinnedLaunchers
        for key in grouped.keys.sorted() {
            let entries = (grouped[key] ?? []).sorted { lhs, rhs in
                if lhs.sourceIndex != rhs.sourceIndex { return lhs.sourceIndex < rhs.sourceIndex }
                if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
                return lhs.stableId < rhs.stableId
            }
            for (index, entry) in entries.enumerated() {
                switch entry {
                case .folder(let arrayIndex, _, _):
                    normalizedFolders[arrayIndex].index = index
                case .pinnedLauncher(let arrayIndex, _, _):
                    normalizedPinnedLaunchers[arrayIndex].index = index
                }
            }
        }
        return (normalizedFolders, normalizedPinnedLaunchers)
    }

    private static func clearCrossSpaceFolderReferences(in data: inout SumiPortableData) {
        let folderSpaceById = Dictionary(
            data.folders.map { ($0.id, $0.spaceId) },
            uniquingKeysWith: { first, _ in first }
        )
        data.pinnedLaunchers = data.pinnedLaunchers.map { launcher in
            var copy = launcher
            if let folderId = copy.folderId, folderSpaceById[folderId] != copy.spaceId {
                copy.folderId = nil
            }
            return copy
        }
        data.regularTabs = data.regularTabs.map { tab in
            var copy = tab
            if let folderId = copy.folderId, folderSpaceById[folderId] != copy.spaceId {
                copy.folderId = nil
            }
            return copy
        }
    }

    private static func deduplicateRuntimeBuckets(in data: inout SumiPortableData) {
        data.profiles = deduped(data.profiles, key: \.id)
        data.spaces = deduped(data.spaces, key: \.id)
        data.folders = deduped(data.folders, key: \.id)
        data.favorite = deduped(data.favorite, key: \.id)
        data.pinnedLaunchers = deduped(data.pinnedLaunchers, key: \.id)
        data.regularTabs = deduped(data.regularTabs, key: \.id)
        data.favorite = deduped(data.favorite) {
            "\($0.profileId ?? "")|\(normalizedURLKey($0.urlString))"
        }
        data.pinnedLaunchers = deduped(data.pinnedLaunchers) {
            "\($0.spaceId ?? "")|\($0.folderId ?? "")|\(normalizedURLKey($0.urlString))"
        }
        data.regularTabs = deduped(data.regularTabs) {
            "\($0.spaceId)|\($0.folderId ?? "")|\(normalizedURLKey($0.urlString))"
        }
    }

    private static func normalizeIndices(in data: inout SumiPortableData) {
        data.profiles = reindexed(data.profiles, index: \.index, stableId: \.id)
        data.spaces = reindexed(data.spaces, index: \.index, stableId: \.id)
        (data.folders, data.pinnedLaunchers) = normalizedSidebarContainerIndices(
            folders: data.folders,
            pinnedLaunchers: data.pinnedLaunchers
        )
        data.favorite = normalizeByBucket(
            data.favorite,
            bucket: { $0.profileId ?? "" },
            sourceIndex: \.index,
            stableId: \.id
        ) { $0.index = $1 }
        data.regularTabs = normalizeByBucket(
            data.regularTabs,
            bucket: { $0.spaceId },
            sourceIndex: \.index,
            stableId: \.id
        ) { $0.index = $1 }
    }

    private static func reindexed<T>(
        _ items: [T],
        index: WritableKeyPath<T, Int>,
        stableId: KeyPath<T, String>
    ) -> [T] {
        items.sorted { lhs, rhs in
            if lhs[keyPath: index] != rhs[keyPath: index] {
                return lhs[keyPath: index] < rhs[keyPath: index]
            }
            return lhs[keyPath: stableId] < rhs[keyPath: stableId]
        }.enumerated().map { offset, item in
            var copy = item
            copy[keyPath: index] = offset
            return copy
        }
    }

    private static func normalizeByBucket<T>(
        _ items: [T],
        bucket: (T) -> String,
        sourceIndex: KeyPath<T, Int>,
        stableId: KeyPath<T, String>,
        setIndex: (inout T, Int) -> Void
    ) -> [T] {
        let grouped = Dictionary(grouping: items, by: bucket)
        return grouped.keys.sorted().flatMap { key in
            let group = (grouped[key] ?? []).sorted { lhs, rhs in
                if lhs[keyPath: sourceIndex] != rhs[keyPath: sourceIndex] {
                    return lhs[keyPath: sourceIndex] < rhs[keyPath: sourceIndex]
                }
                return lhs[keyPath: stableId] < rhs[keyPath: stableId]
            }
            return group.enumerated().map { index, item in
                var copy = item
                setIndex(&copy, index)
                return copy
            }
        }
    }

    private static func deduped<T>(_ items: [T], key: (T) -> String) -> [T] {
        var seen: Set<String> = []
        return items.filter { seen.insert(key($0)).inserted }
    }

    private static func deduped<T>(_ items: [T], key: KeyPath<T, String>) -> [T] {
        deduped(items) { $0[keyPath: key] }
    }

    private static func normalizedURLKey(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else { return raw.lowercased() }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path == "/" { components.path = "" }
        return components.string ?? raw.lowercased()
    }
}
