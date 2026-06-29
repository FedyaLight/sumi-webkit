import AppKit
import Foundation

@MainActor
struct SumiImportApplyResult: Sendable {
    var warnings: [String]
    var preRestoreBackupURL: URL?
}

@MainActor
final class SumiImportApplier {
    static let maxEssentialsPerProfile = 12

    private let backupService: SumiBackupService

    init(backupService: SumiBackupService = SumiBackupService()) {
        self.backupService = backupService
    }

    func apply(
        _ incoming: SumiPortableData,
        to browserManager: BrowserManager,
        categories: Set<SumiImportCategory>,
        mode: SumiImportApplyMode
    ) async throws -> SumiImportApplyResult {
        var warnings: [String] = []
        let preRestoreURL: URL?
        if mode == .replace {
            preRestoreURL = try backupService.writeAutomaticPreRestoreBackup(from: browserManager)
        } else {
            preRestoreURL = nil
        }

        var base = SumiImportExportSnapshot.makeData(from: browserManager)
        base = mergedData(
            base: base,
            incoming: incoming,
            categories: categories,
            mode: mode,
            warnings: &warnings
        )

        try render(base, into: browserManager, warnings: &warnings)
        let didPersist = await browserManager.tabManager.persistFullReconcileAwaitingResult(
            reason: "import/export apply"
        )
        if !didPersist {
            throw SumiImportExportError.importFailed("Sumi could not persist the imported browser data.")
        }

        if categories.contains(.bookmarks) {
            try applyBookmarks(
                incoming.bookmarks,
                to: browserManager.bookmarkManager,
                mode: mode
            )
        }

        return SumiImportApplyResult(warnings: warnings, preRestoreBackupURL: preRestoreURL)
    }

    private func mergedData(
        base: SumiPortableData,
        incoming: SumiPortableData,
        categories: Set<SumiImportCategory>,
        mode: SumiImportApplyMode,
        warnings: inout [String]
    ) -> SumiPortableData {
        var output = base
        if mode == .replace {
            if categories.contains(.profiles) { output.profiles.removeAll() }
            if categories.contains(.spaces) { output.spaces.removeAll() }
            if categories.contains(.themes) {
                output.spaces = output.spaces.map {
                    var copy = $0
                    copy.themeDataBase64 = nil
                    copy.color = nil
                    return copy
                }
            }
            if categories.contains(.folders) { output.folders.removeAll() }
            if categories.contains(.essentials) { output.essentials.removeAll() }
            if categories.contains(.pinnedLaunchers) { output.pinnedLaunchers.removeAll() }
            if categories.contains(.regularTabs) { output.regularTabs.removeAll() }
            if categories.contains(.bookmarks) { output.bookmarks.removeAll() }
        }

        let idMap = makeIdMap(base: output, incoming: incoming, categories: categories, mode: mode)

        if categories.contains(.profiles) {
            output.profiles.append(contentsOf: incoming.profiles.enumerated().map { offset, profile in
                SumiPortableProfile(
                    id: idMap.profileId(profile.id),
                    name: uniqueName(profile.name, existing: output.profiles.map(\.name)),
                    icon: profile.icon,
                    index: output.profiles.count + offset
                )
            })
        }
        if output.profiles.isEmpty {
            output.profiles.append(SumiPortableProfile(
                id: UUID().uuidString,
                name: "Default",
                icon: SumiProfileIcon.defaultIcon,
                index: 0
            ))
        }

        if categories.contains(.spaces) {
            output.spaces.append(contentsOf: incoming.spaces.enumerated().map { offset, space in
                SumiPortableSpace(
                    id: idMap.spaceId(space.id),
                    name: uniqueName(space.name, existing: output.spaces.map(\.name)),
                    icon: space.icon,
                    index: output.spaces.count + offset,
                    profileId: space.profileId.map(idMap.profileId(_:)) ?? output.profiles.first?.id,
                    themeDataBase64: categories.contains(.themes) ? space.themeDataBase64 : nil,
                    color: categories.contains(.themes) ? space.color : nil
                )
            })
        } else if categories.contains(.themes) {
            let incomingById = Dictionary(uniqueKeysWithValues: incoming.spaces.map { ($0.id, $0) })
            output.spaces = output.spaces.map { space in
                var copy = space
                if let update = incomingById[space.id] {
                    copy.themeDataBase64 = update.themeDataBase64
                    copy.color = update.color
                }
                return copy
            }
        }

        if output.spaces.isEmpty {
            output.spaces.append(SumiPortableSpace(
                id: UUID().uuidString,
                name: "Personal",
                icon: "🏠",
                index: 0,
                profileId: output.profiles.first?.id,
                themeDataBase64: nil,
                color: nil
            ))
        }

        if categories.contains(.folders) {
            output.folders.append(contentsOf: incoming.folders.enumerated().compactMap { offset, folder in
                let mappedSpaceId = idMap.spaceId(folder.spaceId)
                guard output.spaces.contains(where: { $0.id == mappedSpaceId }) else { return nil }
                let mappedParentFolderId = folder.parentFolderId.map(idMap.folderId(_:))
                return SumiPortableFolder(
                    id: idMap.folderId(folder.id),
                    name: uniqueFolderName(
                        folder.name,
                        spaceId: mappedSpaceId,
                        parentFolderId: mappedParentFolderId,
                        existing: output.folders
                    ),
                    icon: folder.icon,
                    colorHex: folder.colorHex,
                    spaceId: mappedSpaceId,
                    parentFolderId: mappedParentFolderId,
                    isOpen: folder.isOpen,
                    index: folder.index + offset,
                    sourcePath: folder.sourcePath
                )
            })
        }

        if categories.contains(.essentials) {
            var demoted: [SumiPortableLauncher] = []
            let importedEssentials = incoming.essentials.compactMap { launcher -> SumiPortableLauncher? in
                guard URL(string: launcher.urlString) != nil else { return nil }
                var copy = remappedLauncher(launcher, idMap: idMap, output: output)
                copy.spaceId = nil
                copy.folderId = nil
                copy.profileId = launcher.profileId.map(idMap.profileId(_:)) ?? output.profiles.first?.id
                return copy
            }
            output.essentials.append(contentsOf: importedEssentials)
            enforceEssentialLimit(in: &output, demoted: &demoted)
            if demoted.isEmpty == false {
                warnings.append("\(demoted.count) essentials exceeded Sumi's 12-item profile limit and were imported as space-pinned launchers.")
            }
        }

        if categories.contains(.pinnedLaunchers) {
            output.pinnedLaunchers.append(contentsOf: incoming.pinnedLaunchers.compactMap { launcher in
                guard URL(string: launcher.urlString) != nil else { return nil }
                return remappedLauncher(launcher, idMap: idMap, output: output)
            })
        }

        if categories.contains(.regularTabs) {
            output.regularTabs.append(contentsOf: incoming.regularTabs.compactMap { tab in
                guard URL(string: tab.urlString) != nil else { return nil }
                let mappedSpaceId = idMap.spaceId(tab.spaceId)
                guard output.spaces.contains(where: { $0.id == mappedSpaceId }) else { return nil }
                return SumiPortableRegularTab(
                    id: UUID().uuidString,
                    title: tab.title,
                    urlString: tab.urlString,
                    index: tab.index,
                    spaceId: mappedSpaceId,
                    profileId: tab.profileId.map(idMap.profileId(_:)),
                    folderId: categories.contains(.folders) ? tab.folderId.map(idMap.folderId(_:)) : nil
                )
            })
        }

        if categories.contains(.bookmarks) {
            output.bookmarks.append(contentsOf: incoming.bookmarks)
        }

        repairFolderParentRelationships(in: &output)
        deduplicateRuntimeBuckets(in: &output)
        normalizeIndices(in: &output)
        return output
    }

    private func makeIdMap(
        base: SumiPortableData,
        incoming: SumiPortableData,
        categories: Set<SumiImportCategory>,
        mode: SumiImportApplyMode
    ) -> SumiImportIdMap {
        let preserveIds = mode == .replace
        return SumiImportIdMap(
            preserveIds: preserveIds,
            fallbackProfileId: base.profiles.first?.id,
            fallbackSpaceId: base.spaces.first?.id,
            incomingProfileIds: Set(incoming.profiles.map(\.id)),
            incomingSpaceIds: Set(incoming.spaces.map(\.id)),
            incomingFolderIds: Set(incoming.folders.map(\.id)),
            importsProfiles: categories.contains(.profiles),
            importsSpaces: categories.contains(.spaces),
            importsFolders: categories.contains(.folders)
        )
    }

    private func remappedLauncher(
        _ launcher: SumiPortableLauncher,
        idMap: SumiImportIdMap,
        output: SumiPortableData
    ) -> SumiPortableLauncher {
        let mappedSpaceId = launcher.spaceId.map(idMap.spaceId(_:))
            ?? launcher.sourceSpaceId.map(idMap.spaceId(_:))
            ?? output.spaces.first?.id
        return SumiPortableLauncher(
            id: UUID().uuidString,
            title: launcher.title,
            urlString: launcher.urlString,
            index: launcher.index,
            profileId: launcher.profileId.map(idMap.profileId(_:)),
            executionProfileId: launcher.executionProfileId.map(idMap.profileId(_:)) ?? launcher.profileId.map(idMap.profileId(_:)),
            spaceId: mappedSpaceId,
            folderId: launcher.folderId.map(idMap.folderId(_:)),
            iconAsset: launcher.iconAsset,
            sourceSpaceId: mappedSpaceId
        )
    }

    private func enforceEssentialLimit(
        in data: inout SumiPortableData,
        demoted: inout [SumiPortableLauncher]
    ) {
        let grouped = Dictionary(grouping: data.essentials, by: { $0.profileId ?? "" })
        var kept: [SumiPortableLauncher] = []
        for (_, launchers) in grouped {
            let sorted = launchers.sorted { $0.index < $1.index }
            kept.append(contentsOf: sorted.prefix(Self.maxEssentialsPerProfile))
            let overflow = sorted.dropFirst(Self.maxEssentialsPerProfile).map { launcher in
                var copy = launcher
                copy.id = UUID().uuidString
                copy.profileId = nil
                copy.spaceId = launcher.sourceSpaceId ?? data.spaces.first?.id
                copy.folderId = nil
                return copy
            }
            demoted.append(contentsOf: overflow)
        }
        data.essentials = kept
        data.pinnedLaunchers.append(contentsOf: demoted)
    }

    private func render(
        _ data: SumiPortableData,
        into browserManager: BrowserManager,
        warnings: inout [String]
    ) throws {
        let profiles = data.profiles.sorted { $0.index < $1.index }.map { record in
            Profile(
                id: UUID(uuidString: record.id) ?? UUID(),
                name: record.name,
                icon: record.icon
            )
        }
        browserManager.profileManager.profiles = profiles
        browserManager.profileManager.persistProfiles()
        if let current = browserManager.currentProfile,
           profiles.contains(where: { $0.id == current.id }) == false {
            browserManager.currentProfile = profiles.first
        } else if browserManager.currentProfile == nil {
            browserManager.currentProfile = profiles.first
        }

        let validProfileIds = Set(profiles.map(\.id))
        let spaces = data.spaces.sorted { $0.index < $1.index }.map { record in
            let profileId = record.profileId.flatMap(UUID.init(uuidString:)).flatMap {
                validProfileIds.contains($0) ? $0 : nil
            }
            return Space(
                id: UUID(uuidString: record.id) ?? UUID(),
                name: record.name,
                icon: record.icon,
                workspaceTheme: workspaceTheme(from: record),
                profileId: profileId ?? profiles.first?.id
            )
        }
        var foldersBySpace: [UUID: [TabFolder]] = [:]
        let folderRecordsBySpace = Dictionary(grouping: data.folders, by: \.spaceId)
        for space in spaces {
            foldersBySpace[space.id] = (folderRecordsBySpace[space.id.uuidString] ?? [])
                .sorted { $0.index < $1.index }
                .map { record in
                    let folder = TabFolder(
                        id: UUID(uuidString: record.id) ?? UUID(),
                        name: record.name,
                        spaceId: space.id,
                        parentFolderId: record.parentFolderId.flatMap(UUID.init(uuidString:)),
                        icon: record.icon,
                        color: NSColor(hex: record.colorHex) ?? .controlAccentColor,
                        index: record.index
                    )
                    folder.isOpen = record.isOpen
                    return folder
                }
        }
        repairTabFolderParentRelationships(in: &foldersBySpace)
        let folderSpaceById = Dictionary(
            foldersBySpace.flatMap { spaceId, folders in
                folders.map { ($0.id, spaceId) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        var tabsBySpace: [UUID: [Tab]] = [:]
        let tabRecordsBySpace = Dictionary(grouping: data.regularTabs, by: \.spaceId)
        for space in spaces {
            tabsBySpace[space.id] = (tabRecordsBySpace[space.id.uuidString] ?? [])
                .sorted { $0.index < $1.index }
                .compactMap { record in
                    guard let url = URL(string: record.urlString) else {
                        warnings.append("Skipped invalid tab URL: \(record.urlString)")
                        return nil
                    }
                    let tab = Tab(
                        id: UUID(uuidString: record.id) ?? UUID(),
                        url: url,
                        name: record.title.isEmpty ? url.absoluteString : record.title,
                        favicon: "globe",
                        spaceId: space.id,
                        index: record.index,
                        browserManager: browserManager,
                        loadsCachedFaviconOnInit: false
                    )
                    tab.profileId = record.profileId.flatMap(UUID.init(uuidString:))
                    if let folderId = record.folderId.flatMap(UUID.init(uuidString:)),
                       folderSpaceById[folderId] == space.id {
                        tab.folderId = folderId
                    }
                    return tab
                }
        }

        var pinnedByProfile: [UUID: [ShortcutPin]] = [:]
        let essentialsByProfile = Dictionary(grouping: data.essentials, by: { $0.profileId ?? "" })
        for profile in profiles {
            pinnedByProfile[profile.id] = (essentialsByProfile[profile.id.uuidString] ?? [])
                .sorted { $0.index < $1.index }
                .compactMap { record in
                    guard let url = URL(string: record.urlString) else {
                        warnings.append("Skipped invalid essential URL: \(record.urlString)")
                        return nil
                    }
                    return ShortcutPin(
                        id: UUID(uuidString: record.id) ?? UUID(),
                        role: .essential,
                        profileId: profile.id,
                        executionProfileId: record.executionProfileId.flatMap(UUID.init(uuidString:)) ?? profile.id,
                        index: record.index,
                        launchURL: url,
                        title: record.title.isEmpty ? url.absoluteString : record.title,
                        iconAsset: record.iconAsset
                    )
                }
        }

        var spacePinnedShortcuts: [UUID: [ShortcutPin]] = [:]
        let pinsBySpace = Dictionary(grouping: data.pinnedLaunchers, by: { $0.spaceId ?? "" })
        for space in spaces {
            spacePinnedShortcuts[space.id] = (pinsBySpace[space.id.uuidString] ?? [])
                .sorted { $0.index < $1.index }
                .compactMap { record in
                    guard let url = URL(string: record.urlString) else {
                        warnings.append("Skipped invalid pinned URL: \(record.urlString)")
                        return nil
                    }
                    let folderId = record.folderId.flatMap(UUID.init(uuidString:)).flatMap {
                        folderSpaceById[$0] == space.id ? $0 : nil
                    }
                    return ShortcutPin(
                        id: UUID(uuidString: record.id) ?? UUID(),
                        role: .spacePinned,
                        executionProfileId: record.executionProfileId.flatMap(UUID.init(uuidString:)) ?? space.profileId,
                        spaceId: space.id,
                        index: record.index,
                        folderId: folderId,
                        launchURL: url,
                        title: record.title.isEmpty ? url.absoluteString : record.title,
                        iconAsset: record.iconAsset
                    )
                }
        }

        browserManager.tabManager.withStructuralUpdateTransaction {
            browserManager.tabManager.spaces = spaces
            browserManager.tabManager.tabsBySpace = tabsBySpace
            browserManager.tabManager.foldersBySpace = foldersBySpace
            browserManager.tabManager.pinnedByProfile = pinnedByProfile
            browserManager.tabManager.spacePinnedShortcuts = spacePinnedShortcuts
            browserManager.tabManager.pendingPinnedWithoutProfile.removeAll()
            browserManager.tabManager.splitGroups.removeAll()
            browserManager.tabManager.currentSpace = browserManager.tabManager.currentSpace.flatMap { current in
                spaces.first(where: { $0.id == current.id })
            } ?? spaces.first
            let currentSpaceId = browserManager.tabManager.currentSpace?.id
            browserManager.tabManager.currentTab = currentSpaceId.flatMap { tabsBySpace[$0]?.first }
            browserManager.tabManager.rebuildTabLookupForRestore()
            browserManager.tabManager.markSnapshotCacheDirty()
            browserManager.tabManager.resetStructuralDirtySet()
            browserManager.tabManager.requestStructuralPublish()
        }
        browserManager.dataServices.faviconService.syncShortcutPins(
            Array(pinnedByProfile.values.joined()) + Array(spacePinnedShortcuts.values.joined())
        )
    }

    private func applyBookmarks(
        _ bookmarks: [SumiPortableBookmarkNode],
        to bookmarkManager: SumiBookmarkManager,
        mode: SumiImportApplyMode
    ) throws {
        if mode == .replace {
            let rootChildren = bookmarkManager.snapshot(sortMode: .manual).root.children.map(\.id)
            if rootChildren.isEmpty == false {
                try bookmarkManager.removeEntities(ids: rootChildren)
            }
        }
        let nodes = SumiBookmarkPortableBridge.importNodes(from: bookmarks)
        if nodes.isEmpty == false {
            _ = try bookmarkManager.importBookmarks(nodes)
        }
    }

    private func workspaceTheme(from record: SumiPortableSpace) -> WorkspaceTheme {
        if let encoded = record.themeDataBase64.flatMap({ Data(base64Encoded: $0) }),
           let theme = WorkspaceTheme.decode(encoded) {
            return theme
        }
        if let color = record.color {
            return WorkspaceTheme(
                gradientTheme: WorkspaceGradientTheme(
                    colors: [
                        WorkspaceThemeColor(
                            hex: color.hex,
                            isCustom: false,
                            isPrimary: true,
                            algorithm: .floating,
                            position: .monochrome
                        ),
                    ],
                    opacity: 0.62,
                    texture: 1.0 / 16.0
                ),
                usesExplicitColorScheme: true
            )
        }
        return .default
    }

    private func deduplicateRuntimeBuckets(in data: inout SumiPortableData) {
        data.essentials = deduped(data.essentials) { "\($0.profileId ?? "")|\(normalizedURLKey($0.urlString))" }
        data.pinnedLaunchers = deduped(data.pinnedLaunchers) {
            "\($0.spaceId ?? "")|\($0.folderId ?? "")|\(normalizedURLKey($0.urlString))"
        }
        data.regularTabs = deduped(data.regularTabs) {
            "\($0.spaceId)|\($0.folderId ?? "")|\(normalizedURLKey($0.urlString))"
        }
    }

    private func repairFolderParentRelationships(in data: inout SumiPortableData) {
        data.folders = SumiPortableFolderHierarchyRepair.repaired(data.folders)
        let folderSpaceById = Dictionary(
            data.folders.map { ($0.id, $0.spaceId) },
            uniquingKeysWith: { first, _ in first }
        )
        data.pinnedLaunchers = data.pinnedLaunchers.map { launcher in
            var copy = launcher
            if let folderId = launcher.folderId,
               folderSpaceById[folderId] != launcher.spaceId {
                copy.folderId = nil
            }
            return copy
        }
        data.regularTabs = data.regularTabs.map { tab in
            var copy = tab
            if let folderId = tab.folderId,
               folderSpaceById[folderId] != tab.spaceId {
                copy.folderId = nil
            }
            return copy
        }
    }

    private func repairTabFolderParentRelationships(in foldersBySpace: inout [UUID: [TabFolder]]) {
        for (spaceId, folders) in foldersBySpace {
            let folderById = Dictionary(
                folders.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for folder in folders {
                guard let parentId = folder.parentFolderId else { continue }
                guard parentId != folder.id,
                      let parent = folderById[parentId],
                      parent.spaceId == spaceId,
                      createsTabFolderCycle(folderId: folder.id, parentId: parentId, folderById: folderById) == false else {
                    folder.parentFolderId = nil
                    continue
                }
            }
            foldersBySpace[spaceId] = folders
        }
    }

    private func createsTabFolderCycle(
        folderId: UUID,
        parentId: UUID,
        folderById: [UUID: TabFolder]
    ) -> Bool {
        var visited: Set<UUID> = [folderId]
        var cursor: UUID? = parentId
        while let current = cursor {
            guard visited.insert(current).inserted else { return true }
            cursor = folderById[current]?.parentFolderId
        }
        return false
    }

    private func normalizeIndices(in data: inout SumiPortableData) {
        data.profiles = data.profiles.sorted { $0.index < $1.index }.enumerated().map { idx, item in
            var copy = item
            copy.index = idx
            return copy
        }
        data.spaces = data.spaces.sorted { $0.index < $1.index }.enumerated().map { idx, item in
            var copy = item
            copy.index = idx
            return copy
        }
        (data.folders, data.pinnedLaunchers) = Self.normalizedSidebarContainerIndices(
            folders: data.folders,
            pinnedLaunchers: data.pinnedLaunchers
        )
        data.essentials = normalizeLaunchers(data.essentials, bucket: { $0.profileId ?? "" })
        data.regularTabs = normalizeByBucket(data.regularTabs, bucket: \.spaceId) { tab, index in
            tab.index = index
        }
    }

    static func normalizedSidebarContainerIndices(
        folders: [SumiPortableFolder],
        pinnedLaunchers: [SumiPortableLauncher]
    ) -> (folders: [SumiPortableFolder], pinnedLaunchers: [SumiPortableLauncher]) {
        struct ContainerKey: Hashable {
            let spaceId: String
            let folderId: String?
        }

        enum SidebarEntry {
            case folder(arrayIndex: Int, sourceIndex: Int, id: String)
            case pinnedLauncher(arrayIndex: Int, sourceIndex: Int, id: String)

            var sourceIndex: Int {
                switch self {
                case .folder(_, let sourceIndex, _),
                     .pinnedLauncher(_, let sourceIndex, _):
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
                case .folder(_, _, let id),
                     .pinnedLauncher(_, _, let id):
                    return id
                }
            }
        }

        var grouped: [ContainerKey: [SidebarEntry]] = [:]
        for (idx, folder) in folders.enumerated() {
            let key = ContainerKey(spaceId: folder.spaceId, folderId: folder.parentFolderId)
            grouped[key, default: []].append(.folder(arrayIndex: idx, sourceIndex: folder.index, id: folder.id))
        }
        for (idx, launcher) in pinnedLaunchers.enumerated() {
            let key = ContainerKey(spaceId: launcher.spaceId ?? "", folderId: launcher.folderId)
            grouped[key, default: []].append(.pinnedLauncher(arrayIndex: idx, sourceIndex: launcher.index, id: launcher.id))
        }

        var normalizedFolders = folders
        var normalizedPinnedLaunchers = pinnedLaunchers
        for key in grouped.keys.sorted(by: { lhs, rhs in
            if lhs.spaceId != rhs.spaceId { return lhs.spaceId < rhs.spaceId }
            return (lhs.folderId ?? "") < (rhs.folderId ?? "")
        }) {
            let entries = (grouped[key] ?? []).sorted { lhs, rhs in
                if lhs.sourceIndex != rhs.sourceIndex { return lhs.sourceIndex < rhs.sourceIndex }
                if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
                return lhs.stableId < rhs.stableId
            }
            for (idx, entry) in entries.enumerated() {
                switch entry {
                case .folder(let arrayIndex, _, _):
                    normalizedFolders[arrayIndex].index = idx
                case .pinnedLauncher(let arrayIndex, _, _):
                    normalizedPinnedLaunchers[arrayIndex].index = idx
                }
            }
        }
        return (normalizedFolders, normalizedPinnedLaunchers)
    }

    private func normalizeLaunchers(
        _ items: [SumiPortableLauncher],
        bucket: (SumiPortableLauncher) -> String
    ) -> [SumiPortableLauncher] {
        Dictionary(grouping: items, by: bucket).values.flatMap { group in
            group.sorted { $0.index < $1.index }.enumerated().map { idx, item in
                var copy = item
                copy.index = idx
                return copy
            }
        }
    }

    private func normalizeByBucket<T>(
        _ items: [T],
        bucket: KeyPath<T, String>,
        setIndex: (inout T, Int) -> Void
    ) -> [T] {
        Dictionary(grouping: items, by: { $0[keyPath: bucket] }).values.flatMap { group in
            group.enumerated().map { idx, item in
                var copy = item
                setIndex(&copy, idx)
                return copy
            }
        }
    }

    private func deduped<T>(_ items: [T], key: (T) -> String) -> [T] {
        var seen: Set<String> = []
        var output: [T] = []
        for item in items {
            let key = key(item)
            guard seen.insert(key).inserted else { continue }
            output.append(item)
        }
        return output
    }

    private func normalizedURLKey(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else {
            return raw.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path == "/" { components.path = "" }
        return components.string ?? raw.lowercased()
    }

    private func uniqueName(_ base: String, existing: [String]) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmed.isEmpty ? "Imported" : trimmed
        var candidate = root
        var suffix = 2
        let existingSet = Set(existing)
        while existingSet.contains(candidate) {
            candidate = "\(root) (\(suffix))"
            suffix += 1
        }
        return candidate
    }

    private func uniqueFolderName(
        _ base: String,
        spaceId: String,
        parentFolderId: String?,
        existing: [SumiPortableFolder]
    ) -> String {
        uniqueName(
            base,
            existing: existing
                .filter { $0.spaceId == spaceId && $0.parentFolderId == parentFolderId }
                .map(\.name)
        )
    }
}

private final class SumiImportIdMap {
    let preserveIds: Bool
    let fallbackProfileId: String?
    let fallbackSpaceId: String?
    let incomingProfileIds: Set<String>
    let incomingSpaceIds: Set<String>
    let incomingFolderIds: Set<String>
    let importsProfiles: Bool
    let importsSpaces: Bool
    let importsFolders: Bool

    private var generatedProfiles: [String: String] = [:]
    private var generatedSpaces: [String: String] = [:]
    private var generatedFolders: [String: String] = [:]

    init(
        preserveIds: Bool,
        fallbackProfileId: String?,
        fallbackSpaceId: String?,
        incomingProfileIds: Set<String>,
        incomingSpaceIds: Set<String>,
        incomingFolderIds: Set<String>,
        importsProfiles: Bool,
        importsSpaces: Bool,
        importsFolders: Bool
    ) {
        self.preserveIds = preserveIds
        self.fallbackProfileId = fallbackProfileId
        self.fallbackSpaceId = fallbackSpaceId
        self.incomingProfileIds = incomingProfileIds
        self.incomingSpaceIds = incomingSpaceIds
        self.incomingFolderIds = incomingFolderIds
        self.importsProfiles = importsProfiles
        self.importsSpaces = importsSpaces
        self.importsFolders = importsFolders
    }

    func profileId(_ source: String) -> String {
        guard importsProfiles || preserveIds else { return fallbackProfileId ?? UUID().uuidString }
        return Self.mapped(source, preserveIds: preserveIds, storage: &generatedProfiles)
    }

    func spaceId(_ source: String) -> String {
        guard importsSpaces || preserveIds else { return fallbackSpaceId ?? UUID().uuidString }
        return Self.mapped(source, preserveIds: preserveIds, storage: &generatedSpaces)
    }

    func folderId(_ source: String) -> String {
        guard importsFolders || preserveIds else { return UUID().uuidString }
        return Self.mapped(source, preserveIds: preserveIds, storage: &generatedFolders)
    }

    private static func mapped(_ source: String, preserveIds: Bool, storage: inout [String: String]) -> String {
        if preserveIds, UUID(uuidString: source) != nil {
            return source
        }
        if let existing = storage[source] {
            return existing
        }
        let generated = UUID().uuidString
        storage[source] = generated
        return generated
    }
}
