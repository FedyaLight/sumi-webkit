import Foundation
import SwiftData

struct TabRestoreSpaceDTO: Sendable {
    let id: UUID
    let name: String
    let icon: String
    let workspaceTheme: WorkspaceTheme
    let profileId: UUID?
}

struct TabRestoreTabDTO: Sendable {
    let id: UUID
    let url: URL
    let name: String
    let index: Int
    let spaceId: UUID
    let folderId: UUID?
    let canGoBack: Bool
    let canGoForward: Bool
}

struct TabRestoreShortcutDTO: Sendable {
    let id: UUID
    let role: ShortcutPinRole
    let profileId: UUID?
    let spaceId: UUID?
    let index: Int
    let folderId: UUID?
    let launchURL: URL
    let title: String
    let faviconCacheKey: String?
    let iconAsset: String?
}

struct TabRestorePayload: Sendable {
    let spaces: [TabRestoreSpaceDTO]
    let regularTabsBySpace: [UUID: [TabRestoreTabDTO]]
    let foldersBySpace: [UUID: [TabSnapshotRepository.SnapshotFolder]]
    let pinnedShortcutsByProfile: [UUID: [TabRestoreShortcutDTO]]
    let pendingPinnedShortcuts: [TabRestoreShortcutDTO]
    let spacePinnedShortcutsBySpace: [UUID: [TabRestoreShortcutDTO]]
    let currentSpaceId: UUID?
    let currentTabId: UUID?
    let snapshot: TabSnapshotRepository.Snapshot
    let repairReasons: [String]
    let totalTabCount: Int
    let pinnedCount: Int
    let spacePinnedCount: Int
    let regularCount: Int
}

actor TabRestoreLoader {
    private let container: ModelContainer
    private let defaultRestoreURL = URL(string: "about:blank")!

    init(container: ModelContainer) {
        self.container = container
    }

    func load(defaultProfileId: UUID?) async throws -> TabRestorePayload {
        try PerformanceTrace.withInterval("TabRestoreLoader.offMainRestore") {
            let raw = try fetchRawStore()
            return buildPayload(from: raw, defaultProfileId: defaultProfileId)
        }
    }

    private struct RawStore {
        let spaces: [RawSpace]
        let tabs: [RawTab]
        let folders: [RawFolder]
        let states: [RawState]
    }

    private struct RawSpace {
        let id: UUID
        let name: String
        let icon: String
        let index: Int
        let gradientData: Data
        let workspaceThemeData: Data?
        let profileId: UUID?
    }

    private struct RawTab {
        let id: UUID
        let urlString: String
        let name: String
        let isPinned: Bool
        let isSpacePinned: Bool
        let index: Int
        let spaceId: UUID?
        let profileId: UUID?
        let folderId: UUID?
        let iconAsset: String?
        let currentURLString: String?
        let canGoBack: Bool
        let canGoForward: Bool
    }

    private struct RawFolder {
        let id: UUID
        let name: String
        let icon: String
        let color: String
        let spaceId: UUID
        let isOpen: Bool
        let index: Int
    }

    private struct RawState {
        let currentTabID: UUID?
        let currentSpaceID: UUID?
    }

    private func fetchRawStore() throws -> RawStore {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        let spaces = try ctx.fetch(FetchDescriptor<SpaceEntity>()).map { entity in
            RawSpace(
                id: entity.id,
                name: entity.name,
                icon: entity.icon,
                index: entity.index,
                gradientData: entity.gradientData,
                workspaceThemeData: entity.workspaceThemeData,
                profileId: entity.profileId
            )
        }

        let tabs = try ctx.fetch(FetchDescriptor<TabEntity>()).map { entity in
            RawTab(
                id: entity.id,
                urlString: entity.urlString,
                name: entity.name,
                isPinned: entity.isPinned,
                isSpacePinned: entity.isSpacePinned,
                index: entity.index,
                spaceId: entity.spaceId,
                profileId: entity.profileId,
                folderId: entity.folderId,
                iconAsset: entity.iconAsset,
                currentURLString: entity.currentURLString,
                canGoBack: entity.canGoBack,
                canGoForward: entity.canGoForward
            )
        }

        let folders = try ctx.fetch(FetchDescriptor<FolderEntity>()).map { entity in
            RawFolder(
                id: entity.id,
                name: entity.name,
                icon: entity.icon,
                color: entity.color,
                spaceId: entity.spaceId,
                isOpen: entity.isOpen,
                index: entity.index
            )
        }

        let states = try ctx.fetch(FetchDescriptor<TabsStateEntity>()).map { entity in
            RawState(currentTabID: entity.currentTabID, currentSpaceID: entity.currentSpaceID)
        }

        return RawStore(spaces: spaces, tabs: tabs, folders: folders, states: states)
    }

    private func buildPayload(
        from raw: RawStore,
        defaultProfileId: UUID?
    ) -> TabRestorePayload {
        var repairReasons: Set<String> = []
        var spaces = makeSpaces(from: raw.spaces, defaultProfileId: defaultProfileId, repairReasons: &repairReasons)
        if spaces.isEmpty {
            let personal = TabRestoreSpaceDTO(
                id: UUID(),
                name: "Personal",
                icon: "person.crop.circle",
                workspaceTheme: .default,
                profileId: defaultProfileId
            )
            spaces = [personal]
            repairReasons.insert("created default space")
        }

        let validSpaceIds = Set(spaces.map(\.id))
        let foldersBySpace = makeFoldersBySpace(
            from: raw.folders,
            validSpaceIds: validSpaceIds,
            repairReasons: &repairReasons
        )
        let validFolderIdsBySpace = Dictionary(
            uniqueKeysWithValues: foldersBySpace.map { spaceId, folders in
                (spaceId, Set(folders.map(\.id)))
            }
        )

        let categorizedTabs = makeTabs(
            from: raw.tabs,
            defaultProfileId: defaultProfileId,
            validSpaceIds: validSpaceIds,
            validFolderIdsBySpace: validFolderIdsBySpace,
            repairReasons: &repairReasons
        )

        let selection = resolveSelection(
            states: raw.states,
            spaces: spaces,
            regularTabsBySpace: categorizedTabs.regularTabsBySpace,
            repairReasons: &repairReasons
        )

        let snapshot = makeSnapshot(
            spaces: spaces,
            regularTabsBySpace: categorizedTabs.regularTabsBySpace,
            foldersBySpace: foldersBySpace,
            pinnedShortcutsByProfile: categorizedTabs.pinnedShortcutsByProfile,
            pendingPinnedShortcuts: categorizedTabs.pendingPinnedShortcuts,
            spacePinnedShortcutsBySpace: categorizedTabs.spacePinnedShortcutsBySpace,
            currentSpaceId: selection.currentSpaceId,
            currentTabId: selection.currentTabId
        )

        return TabRestorePayload(
            spaces: spaces,
            regularTabsBySpace: categorizedTabs.regularTabsBySpace,
            foldersBySpace: foldersBySpace,
            pinnedShortcutsByProfile: categorizedTabs.pinnedShortcutsByProfile,
            pendingPinnedShortcuts: categorizedTabs.pendingPinnedShortcuts,
            spacePinnedShortcutsBySpace: categorizedTabs.spacePinnedShortcutsBySpace,
            currentSpaceId: selection.currentSpaceId,
            currentTabId: selection.currentTabId,
            snapshot: snapshot,
            repairReasons: repairReasons.sorted(),
            totalTabCount: raw.tabs.count,
            pinnedCount: categorizedTabs.pinnedCount,
            spacePinnedCount: categorizedTabs.spacePinnedCount,
            regularCount: categorizedTabs.regularCount
        )
    }

    private func makeSpaces(
        from rawSpaces: [RawSpace],
        defaultProfileId: UUID?,
        repairReasons: inout Set<String>
    ) -> [TabRestoreSpaceDTO] {
        var seenIds: Set<UUID> = []
        return rawSpaces
            .sorted(by: sortRawSpaces)
            .compactMap { raw in
                guard seenIds.insert(raw.id).inserted else {
                    repairReasons.insert("removed duplicate space")
                    return nil
                }

                let workspaceTheme = WorkspaceTheme.decode(raw.workspaceThemeData ?? Data())
                    ?? WorkspaceTheme(gradient: SpaceGradient.decode(raw.gradientData))
                let profileId = raw.profileId ?? defaultProfileId
                if raw.profileId == nil, defaultProfileId != nil {
                    repairReasons.insert("assigned default profile to space")
                }

                return TabRestoreSpaceDTO(
                    id: raw.id,
                    name: raw.name,
                    icon: raw.icon,
                    workspaceTheme: workspaceTheme,
                    profileId: profileId
                )
            }
    }

    private func makeFoldersBySpace(
        from rawFolders: [RawFolder],
        validSpaceIds: Set<UUID>,
        repairReasons: inout Set<String>
    ) -> [UUID: [TabSnapshotRepository.SnapshotFolder]] {
        var seenIds: Set<UUID> = []
        var foldersBySpace: [UUID: [TabSnapshotRepository.SnapshotFolder]] = [:]

        for raw in rawFolders.sorted(by: sortRawFolders) {
            guard seenIds.insert(raw.id).inserted else {
                repairReasons.insert("removed duplicate folder")
                continue
            }
            guard validSpaceIds.contains(raw.spaceId) else {
                repairReasons.insert("removed folder with missing space")
                continue
            }

            let normalizedIcon = SumiZenFolderIconCatalog.normalizedFolderIconValue(raw.icon)
            if normalizedIcon != raw.icon {
                repairReasons.insert("normalized folder icon")
            }

            foldersBySpace[raw.spaceId, default: []].append(
                TabSnapshotRepository.SnapshotFolder(
                    id: raw.id,
                    name: raw.name,
                    icon: normalizedIcon,
                    color: raw.color,
                    spaceId: raw.spaceId,
                    isOpen: raw.isOpen,
                    index: raw.index
                )
            )
        }

        for spaceId in foldersBySpace.keys {
            foldersBySpace[spaceId] = foldersBySpace[spaceId]?.sorted(by: sortSnapshotFolders)
        }
        return foldersBySpace
    }

    private struct CategorizedTabs {
        var regularTabsBySpace: [UUID: [TabRestoreTabDTO]]
        var pinnedShortcutsByProfile: [UUID: [TabRestoreShortcutDTO]]
        var pendingPinnedShortcuts: [TabRestoreShortcutDTO]
        var spacePinnedShortcutsBySpace: [UUID: [TabRestoreShortcutDTO]]
        var pinnedCount: Int
        var spacePinnedCount: Int
        var regularCount: Int
    }

    private func makeTabs(
        from rawTabs: [RawTab],
        defaultProfileId: UUID?,
        validSpaceIds: Set<UUID>,
        validFolderIdsBySpace: [UUID: Set<UUID>],
        repairReasons: inout Set<String>
    ) -> CategorizedTabs {
        var seenIds: Set<UUID> = []
        var regularTabsBySpace: [UUID: [TabRestoreTabDTO]] = [:]
        var pinnedShortcutsByProfile: [UUID: [TabRestoreShortcutDTO]] = [:]
        var pendingPinnedShortcuts: [TabRestoreShortcutDTO] = []
        var spacePinnedShortcutsBySpace: [UUID: [TabRestoreShortcutDTO]] = [:]
        var pinnedCount = 0
        var spacePinnedCount = 0
        var regularCount = 0

        for raw in rawTabs.sorted(by: sortRawTabs) {
            guard seenIds.insert(raw.id).inserted else {
                repairReasons.insert("removed duplicate tab")
                continue
            }

            if raw.isPinned {
                if raw.isSpacePinned {
                    repairReasons.insert("normalized tab with both pinned flags")
                }

                let launchURL = restoreURL(from: raw.urlString, repairReasons: &repairReasons)
                let profileId = raw.profileId ?? defaultProfileId
                if raw.profileId == nil, defaultProfileId != nil {
                    repairReasons.insert("assigned default profile to pinned launcher")
                }

                let shortcut = TabRestoreShortcutDTO(
                    id: raw.id,
                    role: .essential,
                    profileId: profileId,
                    spaceId: nil,
                    index: raw.index,
                    folderId: nil,
                    launchURL: launchURL,
                    title: raw.name,
                    faviconCacheKey: SumiFaviconResolver.cacheKey(for: launchURL),
                    iconAsset: raw.iconAsset
                )

                if let profileId {
                    pinnedShortcutsByProfile[profileId, default: []].append(shortcut)
                } else {
                    pendingPinnedShortcuts.append(shortcut)
                }
                pinnedCount += 1
                continue
            }

            if raw.isSpacePinned {
                guard let spaceId = raw.spaceId, validSpaceIds.contains(spaceId) else {
                    repairReasons.insert("removed space-pinned launcher with missing space")
                    continue
                }

                var folderId = raw.folderId
                if let existingFolderId = folderId,
                   validFolderIdsBySpace[spaceId]?.contains(existingFolderId) != true {
                    folderId = nil
                    repairReasons.insert("moved launcher out of missing folder")
                }

                let launchURL = restoreURL(from: raw.urlString, repairReasons: &repairReasons)
                let shortcut = TabRestoreShortcutDTO(
                    id: raw.id,
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: spaceId,
                    index: raw.index,
                    folderId: folderId,
                    launchURL: launchURL,
                    title: raw.name,
                    faviconCacheKey: SumiFaviconResolver.cacheKey(for: launchURL),
                    iconAsset: raw.iconAsset
                )
                spacePinnedShortcutsBySpace[spaceId, default: []].append(shortcut)
                spacePinnedCount += 1
                continue
            }

            guard raw.folderId == nil else {
                repairReasons.insert("removed regular tab with folder relationship")
                continue
            }
            guard let spaceId = raw.spaceId, validSpaceIds.contains(spaceId) else {
                repairReasons.insert("removed regular tab with missing space")
                continue
            }

            let url = restoreURL(
                from: raw.currentURLString ?? raw.urlString,
                fallback: raw.urlString,
                repairReasons: &repairReasons
            )
            regularTabsBySpace[spaceId, default: []].append(
                TabRestoreTabDTO(
                    id: raw.id,
                    url: url,
                    name: raw.name,
                    index: raw.index,
                    spaceId: spaceId,
                    folderId: nil,
                    canGoBack: raw.canGoBack,
                    canGoForward: raw.canGoForward
                )
            )
            regularCount += 1
        }

        for profileId in pinnedShortcutsByProfile.keys {
            pinnedShortcutsByProfile[profileId] = pinnedShortcutsByProfile[profileId]?.sorted(by: sortShortcuts)
        }
        pendingPinnedShortcuts = pendingPinnedShortcuts.sorted(by: sortShortcuts)
        for spaceId in spacePinnedShortcutsBySpace.keys {
            spacePinnedShortcutsBySpace[spaceId] = spacePinnedShortcutsBySpace[spaceId]?.sorted(by: sortShortcuts)
        }
        for spaceId in regularTabsBySpace.keys {
            regularTabsBySpace[spaceId] = regularTabsBySpace[spaceId]?.sorted(by: sortTabs)
        }

        return CategorizedTabs(
            regularTabsBySpace: regularTabsBySpace,
            pinnedShortcutsByProfile: pinnedShortcutsByProfile,
            pendingPinnedShortcuts: pendingPinnedShortcuts,
            spacePinnedShortcutsBySpace: spacePinnedShortcutsBySpace,
            pinnedCount: pinnedCount,
            spacePinnedCount: spacePinnedCount,
            regularCount: regularCount
        )
    }

    private func resolveSelection(
        states: [RawState],
        spaces: [TabRestoreSpaceDTO],
        regularTabsBySpace: [UUID: [TabRestoreTabDTO]],
        repairReasons: inout Set<String>
    ) -> (currentSpaceId: UUID?, currentTabId: UUID?) {
        guard let firstSpace = spaces.first else {
            return (nil, nil)
        }

        let state = states.first
        let validSpaceIds = Set(spaces.map(\.id))
        let currentSpaceId: UUID
        if let stateSpaceId = state?.currentSpaceID, validSpaceIds.contains(stateSpaceId) {
            currentSpaceId = stateSpaceId
        } else {
            currentSpaceId = firstSpace.id
            if state?.currentSpaceID != nil {
                repairReasons.insert("repaired stale selected space")
            }
        }

        let selectionTabs = regularTabsBySpace[currentSpaceId] ?? []
        let currentTabId: UUID?
        if let selectedTabId = state?.currentTabID,
           selectionTabs.contains(where: { $0.id == selectedTabId }) {
            currentTabId = selectedTabId
        } else {
            currentTabId = selectionTabs.first?.id
            if state?.currentTabID != nil {
                repairReasons.insert("repaired stale selected tab")
            }
        }

        return (currentSpaceId, currentTabId)
    }

    private func makeSnapshot(
        spaces: [TabRestoreSpaceDTO],
        regularTabsBySpace: [UUID: [TabRestoreTabDTO]],
        foldersBySpace: [UUID: [TabSnapshotRepository.SnapshotFolder]],
        pinnedShortcutsByProfile: [UUID: [TabRestoreShortcutDTO]],
        pendingPinnedShortcuts: [TabRestoreShortcutDTO],
        spacePinnedShortcutsBySpace: [UUID: [TabRestoreShortcutDTO]],
        currentSpaceId: UUID?,
        currentTabId: UUID?
    ) -> TabSnapshotRepository.Snapshot {
        let snapshotSpaces = spaces.enumerated().map { index, space in
            TabSnapshotRepository.SnapshotSpace(
                id: space.id,
                name: space.name,
                icon: space.icon,
                index: index,
                gradientData: space.workspaceTheme.gradient.encoded,
                workspaceThemeData: space.workspaceTheme.encoded,
                profileId: space.profileId
            )
        }

        var snapshotTabs: [TabSnapshotRepository.SnapshotTab] = []
        for profileId in pinnedShortcutsByProfile.keys.sorted(by: uuidLessThan) {
            let shortcuts = pinnedShortcutsByProfile[profileId] ?? []
            snapshotTabs.append(contentsOf: shortcuts.enumerated().map { index, shortcut in
                makeSnapshotTab(from: shortcut, index: index)
            })
        }
        snapshotTabs.append(contentsOf: pendingPinnedShortcuts.enumerated().map { index, shortcut in
            makeSnapshotTab(from: shortcut, index: index)
        })

        for space in spaces {
            let shortcuts = spacePinnedShortcutsBySpace[space.id] ?? []
            snapshotTabs.append(contentsOf: shortcuts.enumerated().map { index, shortcut in
                makeSnapshotTab(from: shortcut, index: index)
            })

            let tabs = regularTabsBySpace[space.id] ?? []
            snapshotTabs.append(contentsOf: tabs.enumerated().map { index, tab in
                TabSnapshotRepository.SnapshotTab(
                    id: tab.id,
                    urlString: tab.url.absoluteString,
                    name: tab.name,
                    index: index,
                    spaceId: tab.spaceId,
                    isPinned: false,
                    isSpacePinned: false,
                    profileId: nil,
                    folderId: nil,
                    iconAsset: nil,
                    currentURLString: tab.url.absoluteString,
                    canGoBack: tab.canGoBack,
                    canGoForward: tab.canGoForward
                )
            })
        }

        var snapshotFolders: [TabSnapshotRepository.SnapshotFolder] = []
        for space in spaces {
            snapshotFolders.append(contentsOf: (foldersBySpace[space.id] ?? []).enumerated().map { index, folder in
                TabSnapshotRepository.SnapshotFolder(
                    id: folder.id,
                    name: folder.name,
                    icon: folder.icon,
                    color: folder.color,
                    spaceId: folder.spaceId,
                    isOpen: folder.isOpen,
                    index: index
                )
            })
        }

        return TabSnapshotRepository.Snapshot(
            spaces: snapshotSpaces,
            tabs: snapshotTabs,
            folders: snapshotFolders,
            state: TabSnapshotRepository.SnapshotState(
                currentTabID: currentTabId,
                currentSpaceID: currentSpaceId
            )
        )
    }

    private func makeSnapshotTab(
        from shortcut: TabRestoreShortcutDTO,
        index: Int
    ) -> TabSnapshotRepository.SnapshotTab {
        TabSnapshotRepository.SnapshotTab(
            id: shortcut.id,
            urlString: shortcut.launchURL.absoluteString,
            name: shortcut.title,
            index: index,
            spaceId: shortcut.spaceId,
            isPinned: shortcut.role == .essential,
            isSpacePinned: shortcut.role == .spacePinned,
            profileId: shortcut.profileId,
            folderId: shortcut.folderId,
            iconAsset: shortcut.iconAsset,
            currentURLString: shortcut.launchURL.absoluteString,
            canGoBack: false,
            canGoForward: false
        )
    }

    private func restoreURL(
        from primary: String,
        fallback: String? = nil,
        repairReasons: inout Set<String>
    ) -> URL {
        if let url = URL(string: primary) {
            return url
        }
        if let fallback, let url = URL(string: fallback) {
            repairReasons.insert("repaired invalid restored url")
            return url
        }
        repairReasons.insert("repaired invalid restored url")
        return defaultRestoreURL
    }

    private func sortRawSpaces(_ lhs: RawSpace, _ rhs: RawSpace) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return uuidLessThan(lhs.id, rhs.id)
    }

    private func sortRawFolders(_ lhs: RawFolder, _ rhs: RawFolder) -> Bool {
        if lhs.spaceId != rhs.spaceId { return uuidLessThan(lhs.spaceId, rhs.spaceId) }
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return uuidLessThan(lhs.id, rhs.id)
    }

    private func sortRawTabs(_ lhs: RawTab, _ rhs: RawTab) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
        if lhs.isSpacePinned != rhs.isSpacePinned { return lhs.isSpacePinned && !rhs.isSpacePinned }
        let lhsSpace = lhs.spaceId?.uuidString ?? ""
        let rhsSpace = rhs.spaceId?.uuidString ?? ""
        if lhsSpace != rhsSpace { return lhsSpace < rhsSpace }
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return uuidLessThan(lhs.id, rhs.id)
    }

    private func sortTabs(_ lhs: TabRestoreTabDTO, _ rhs: TabRestoreTabDTO) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return uuidLessThan(lhs.id, rhs.id)
    }

    private func sortShortcuts(_ lhs: TabRestoreShortcutDTO, _ rhs: TabRestoreShortcutDTO) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return uuidLessThan(lhs.id, rhs.id)
    }

    private func sortSnapshotFolders(
        _ lhs: TabSnapshotRepository.SnapshotFolder,
        _ rhs: TabSnapshotRepository.SnapshotFolder
    ) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return uuidLessThan(lhs.id, rhs.id)
    }

    private func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
