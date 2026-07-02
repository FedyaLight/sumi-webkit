import Foundation

/// Read-only view of the live tab structure used to materialize persistence
/// snapshots without coupling the cache to the tab model owner.
@MainActor
struct TabStructuralSnapshotSource {
    let spaces: [Space]
    let splitGroups: [SplitGroup]
    let pinnedByProfile: [UUID: [ShortcutPin]]
    let spacePinnedShortcuts: [UUID: [ShortcutPin]]
    let tabsBySpace: [UUID: [Tab]]
    let foldersBySpace: [UUID: [TabFolder]]
    let currentTabId: UUID?
    let currentSpaceId: UUID?
    let shouldPersistRegularTab: (Tab) -> Bool
}

/// Incrementally invalidated cache of persistence snapshot fragments so full
/// snapshot rebuilds only re-materialize the structures that changed.
@MainActor
struct TabStructuralSnapshotCache {
    private typealias SnapshotSpace = TabSnapshotRepository.SnapshotSpace
    private typealias SnapshotTab = TabSnapshotRepository.SnapshotTab
    private typealias SnapshotFolder = TabSnapshotRepository.SnapshotFolder

    private var spaceSnapshots: [SnapshotSpace] = []
    private var splitGroupSnapshots: [SplitGroup] = []
    private var pinnedTabsByProfile: [UUID: [SnapshotTab]] = [:]
    private var spacePinnedTabsBySpace: [UUID: [SnapshotTab]] = [:]
    private var regularTabsBySpace: [UUID: [SnapshotTab]] = [:]
    private var folderSnapshotsBySpace: [UUID: [SnapshotFolder]] = [:]
    private let materializer = TabStructuralSnapshotMaterializer()

    private var spacesDirty = true
    private var splitGroupsDirty = true
    private var dirtyPinnedProfileIds: Set<UUID> = []
    private var dirtySpacePinnedSpaceIds: Set<UUID> = []
    private var dirtyRegularTabSpaceIds: Set<UUID> = []
    private var dirtyFolderSpaceIds: Set<UUID> = []

    mutating func invalidateAll() {
        spacesDirty = true
        splitGroupsDirty = true
        dirtyPinnedProfileIds = []
        dirtySpacePinnedSpaceIds = []
        dirtyRegularTabSpaceIds = []
        dirtyFolderSpaceIds = []
        pinnedTabsByProfile.removeAll(keepingCapacity: true)
        spacePinnedTabsBySpace.removeAll(keepingCapacity: true)
        regularTabsBySpace.removeAll(keepingCapacity: true)
        folderSnapshotsBySpace.removeAll(keepingCapacity: true)
    }

    mutating func invalidateSpaces() {
        spacesDirty = true
    }

    mutating func invalidateSplitGroups() {
        splitGroupsDirty = true
    }

    mutating func invalidatePinned(profileId: UUID) {
        dirtyPinnedProfileIds.insert(profileId)
    }

    mutating func invalidateSpacePinned(spaceId: UUID) {
        dirtySpacePinnedSpaceIds.insert(spaceId)
    }

    mutating func invalidateRegularTabs(spaceId: UUID) {
        dirtyRegularTabSpaceIds.insert(spaceId)
    }

    mutating func invalidateFolders(spaceId: UUID) {
        dirtyFolderSpaceIds.insert(spaceId)
    }

    mutating func makeSnapshot(from source: TabStructuralSnapshotSource) -> TabSnapshotRepository.Snapshot {
        let orderedSpaces = source.spaces
        let liveSpaceIds = Set(orderedSpaces.map(\.id))

        if spacesDirty {
            spaceSnapshots = materializer.makeSpaceSnapshots(spaces: orderedSpaces)
            spacesDirty = false
        }
        if splitGroupsDirty {
            splitGroupSnapshots = materializer.makeSplitGroupSnapshots(source.splitGroups)
            splitGroupsDirty = false
        }

        refreshPinnedTabs(from: source)
        refreshSpacePinnedTabs(from: source, liveSpaceIds: liveSpaceIds)
        refreshRegularTabs(from: source, liveSpaceIds: liveSpaceIds)
        refreshFolders(from: source, liveSpaceIds: liveSpaceIds)

        var tabSnapshots: [SnapshotTab] = []
        tabSnapshots.reserveCapacity(
            pinnedTabsByProfile.values.reduce(0) { $0 + $1.count }
                + spacePinnedTabsBySpace.values.reduce(0) { $0 + $1.count }
                + regularTabsBySpace.values.reduce(0) { $0 + $1.count }
        )

        for profileId in source.pinnedByProfile.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            tabSnapshots.append(contentsOf: pinnedTabsByProfile[profileId] ?? [])
        }
        for space in orderedSpaces {
            tabSnapshots.append(contentsOf: spacePinnedTabsBySpace[space.id] ?? [])
            tabSnapshots.append(contentsOf: regularTabsBySpace[space.id] ?? [])
        }

        var folderSnapshots: [SnapshotFolder] = []
        folderSnapshots.reserveCapacity(folderSnapshotsBySpace.values.reduce(0) { $0 + $1.count })
        for space in orderedSpaces {
            folderSnapshots.append(contentsOf: folderSnapshotsBySpace[space.id] ?? [])
        }

        return materializer.makeSnapshot(
            spaces: spaceSnapshots,
            tabs: tabSnapshots,
            folders: folderSnapshots,
            splitGroups: splitGroupSnapshots,
            currentTabId: source.currentTabId,
            currentSpaceId: source.currentSpaceId
        )
    }

    private mutating func refreshPinnedTabs(from source: TabStructuralSnapshotSource) {
        let liveProfileIds = Set(source.pinnedByProfile.keys)
        pinnedTabsByProfile = pinnedTabsByProfile.filter { liveProfileIds.contains($0.key) }

        let profileIdsToRefresh: Set<UUID>
        if pinnedTabsByProfile.isEmpty, liveProfileIds.isEmpty == false {
            profileIdsToRefresh = liveProfileIds
        } else {
            profileIdsToRefresh = dirtyPinnedProfileIds
        }

        for profileId in profileIdsToRefresh {
            let pins = Array(source.pinnedByProfile[profileId] ?? [])
            pinnedTabsByProfile[profileId] = materializer.makePinnedTabSnapshots(
                profileId: profileId,
                pins: pins
            )
        }
        dirtyPinnedProfileIds.removeAll(keepingCapacity: true)
    }

    private mutating func refreshSpacePinnedTabs(
        from source: TabStructuralSnapshotSource,
        liveSpaceIds: Set<UUID>
    ) {
        spacePinnedTabsBySpace = spacePinnedTabsBySpace.filter { liveSpaceIds.contains($0.key) }

        let liveIds = Set(source.spacePinnedShortcuts.keys)
        let missingIds = liveIds.subtracting(spacePinnedTabsBySpace.keys)
        let refreshIds = dirtySpacePinnedSpaceIds.union(missingIds)
        for spaceId in refreshIds {
            guard liveSpaceIds.contains(spaceId) else {
                spacePinnedTabsBySpace.removeValue(forKey: spaceId)
                continue
            }
            let shortcutPins = Array(source.spacePinnedShortcuts[spaceId] ?? [])
            spacePinnedTabsBySpace[spaceId] = materializer.makeSpacePinnedTabSnapshots(
                spaceId: spaceId,
                pins: shortcutPins
            )
        }
        dirtySpacePinnedSpaceIds.removeAll(keepingCapacity: true)
    }

    private mutating func refreshRegularTabs(
        from source: TabStructuralSnapshotSource,
        liveSpaceIds: Set<UUID>
    ) {
        regularTabsBySpace = regularTabsBySpace.filter { liveSpaceIds.contains($0.key) }

        let liveIds = Set(source.tabsBySpace.keys)
        let missingIds = liveIds.subtracting(regularTabsBySpace.keys)
        let refreshIds = dirtyRegularTabSpaceIds.union(missingIds)
        for spaceId in refreshIds {
            guard liveSpaceIds.contains(spaceId) else {
                regularTabsBySpace.removeValue(forKey: spaceId)
                continue
            }
            let regularTabs = Array(source.tabsBySpace[spaceId] ?? [])
            regularTabsBySpace[spaceId] = materializer.makeRegularTabSnapshots(
                spaceId: spaceId,
                tabs: regularTabs,
                shouldPersistRegularTab: source.shouldPersistRegularTab
            )
        }
        dirtyRegularTabSpaceIds.removeAll(keepingCapacity: true)
    }

    private mutating func refreshFolders(
        from source: TabStructuralSnapshotSource,
        liveSpaceIds: Set<UUID>
    ) {
        folderSnapshotsBySpace = folderSnapshotsBySpace.filter { liveSpaceIds.contains($0.key) }

        let liveIds = Set(source.foldersBySpace.keys)
        let missingIds = liveIds.subtracting(folderSnapshotsBySpace.keys)
        let refreshIds = dirtyFolderSpaceIds.union(missingIds)
        for spaceId in refreshIds {
            guard liveSpaceIds.contains(spaceId) else {
                folderSnapshotsBySpace.removeValue(forKey: spaceId)
                continue
            }
            let folders = source.foldersBySpace[spaceId] ?? []
            folderSnapshotsBySpace[spaceId] = materializer.makeFolderSnapshots(
                spaceId: spaceId,
                folders: folders
            )
        }
        dirtyFolderSpaceIds.removeAll(keepingCapacity: true)
    }
}
