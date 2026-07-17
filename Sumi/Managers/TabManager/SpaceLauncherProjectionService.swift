import Foundation
import SumiDomain

struct SpaceLauncherProjectionSnapshot {
    let regularTabs: [Tab]
    let topLevelFolders: [TabFolder]
    let topLevelPins: [ShortcutPin]
    let childFolders: [UUID: [TabFolder]]
    let folderPins: [UUID: [ShortcutPin]]
    let liveTabsByPinId: [UUID: Tab]

    var launcherCount: Int {
        topLevelPins.count + folderPins.values.reduce(0) { $0 + $1.count }
    }

    var userVisibleTabCount: Int {
        regularTabs.count + launcherCount
    }
}

@MainActor
final class SpaceLauncherProjectionService {
    private let regularTabs: RegularTabCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner
    private let splitOrdering: SplitGroupSidebarOrderingService
    private let transientTabs: TabTransientTabRegistryOwner

    init(
        regularTabs: RegularTabCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        splitOrdering: SplitGroupSidebarOrderingService,
        transientTabs: TabTransientTabRegistryOwner
    ) {
        self.regularTabs = regularTabs
        self.pins = pins
        self.folders = folders
        self.splitOrdering = splitOrdering
        self.transientTabs = transientTabs
    }

    func projection(
        for spaceId: UUID,
        in windowId: UUID? = nil
    ) -> SpaceLauncherProjectionSnapshot {
        let projectedRegularTabs = regularTabs.tabs(in: spaceId)
        let persistedPins = pins.spacePinnedPins(for: spaceId)
        let shortcutHostedHiddenPinIds = Set(
            splitOrdering.groups(for: spaceId).flatMap { group in
                group.memberIDs.compactMap { memberID -> UUID? in
                    guard case .shortcutPin(let pinID) = memberID else {
                        return nil
                    }
                    return pinID
                }
            }
        )
        let visiblePersistedPins = persistedPins.filter { !shortcutHostedHiddenPinIds.contains($0.id) }
        let spaceFolders = folders.folders(for: spaceId)
        let topLevelFolders = spaceFolders.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        .filter { $0.parentFolderId == nil }
        let childFolders = Dictionary(
            grouping: spaceFolders.filter { $0.parentFolderId != nil },
            by: { $0.parentFolderId! }
        ).mapValues { childFolderGroup in
            childFolderGroup.sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
        let topLevelPins = visiblePersistedPins
            .filter { $0.folderId == nil }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        let folderPins = Dictionary(
            grouping: visiblePersistedPins.filter { $0.folderId != nil },
            by: { $0.folderId! }
        ).mapValues { pins in
            pins.sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }

        let candidateLiveTabs: [Tab]
        if let windowId {
            candidateLiveTabs = transientTabs
                .transientShortcutTabsByWindow[windowId]
                .map { Array($0.values) } ?? []
        } else {
            candidateLiveTabs = transientTabs.transientShortcutTabsByWindow.values
                .flatMap(\.values)
        }

        let liveTabsByPinId = candidateLiveTabs.reduce(into: [UUID: Tab]()) { result, tab in
            guard tab.shortcutPinRole == .spacePinned,
                  tab.spaceId == spaceId,
                  let pinId = tab.shortcutPinId,
                  result[pinId] == nil else { return }
            result[pinId] = tab
        }

        return SpaceLauncherProjectionSnapshot(
            regularTabs: projectedRegularTabs,
            topLevelFolders: topLevelFolders,
            topLevelPins: topLevelPins,
            childFolders: childFolders,
            folderPins: folderPins,
            liveTabsByPinId: liveTabsByPinId
        )
    }
}
