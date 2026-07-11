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
    private let regularTabs: @MainActor (UUID) -> [Tab]
    private let spacePinnedPins: @MainActor (UUID) -> [ShortcutPin]
    private let folders: @MainActor (UUID) -> [TabFolder]
    private let shortcutHostedSplitGroups: @MainActor (UUID) -> [SplitGroup]
    private let liveShortcutTabs: @MainActor (UUID) -> [Tab]
    private let transientShortcutTabsByWindow: @MainActor () -> [UUID: [UUID: Tab]]

    init(
        regularTabs: @escaping @MainActor (UUID) -> [Tab],
        spacePinnedPins: @escaping @MainActor (UUID) -> [ShortcutPin],
        folders: @escaping @MainActor (UUID) -> [TabFolder],
        shortcutHostedSplitGroups: @escaping @MainActor (UUID) -> [SplitGroup],
        liveShortcutTabs: @escaping @MainActor (UUID) -> [Tab],
        transientShortcutTabsByWindow: @escaping @MainActor () -> [UUID: [UUID: Tab]]
    ) {
        self.regularTabs = regularTabs
        self.spacePinnedPins = spacePinnedPins
        self.folders = folders
        self.shortcutHostedSplitGroups = shortcutHostedSplitGroups
        self.liveShortcutTabs = liveShortcutTabs
        self.transientShortcutTabsByWindow = transientShortcutTabsByWindow
    }

    convenience init(tabManager: TabManager) {
        self.init(
            regularTabs: { [weak tabManager] spaceId in
                tabManager?.regularTabCollectionOwner.tabs(in: spaceId) ?? []
            },
            spacePinnedPins: { [weak tabManager] spaceId in
                tabManager?.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId) ?? []
            },
            folders: { [weak tabManager] spaceId in
                tabManager?.folderCollectionStateOwner.folders(for: spaceId) ?? []
            },
            shortcutHostedSplitGroups: { [weak tabManager] spaceId in
                tabManager?.splitGroupSidebarOrdering.groups(for: spaceId) ?? []
            },
            liveShortcutTabs: { [weak tabManager] windowId in
                tabManager?.shortcutPresentationOwner.liveShortcutTabs(in: windowId) ?? []
            },
            transientShortcutTabsByWindow: { [weak tabManager] in
                tabManager?.transientTabRegistryOwner.transientShortcutTabsByWindow ?? [:]
            }
        )
    }

    func projection(
        for spaceId: UUID,
        in windowId: UUID? = nil
    ) -> SpaceLauncherProjectionSnapshot {
        let projectedRegularTabs = regularTabs(spaceId)
        let persistedPins = spacePinnedPins(spaceId)
        let shortcutHostedHiddenPinIds = Set(
            shortcutHostedSplitGroups(spaceId).flatMap { group in
                group.memberIDs.compactMap { memberID -> UUID? in
                    guard case .shortcutPin(let pinID) = memberID else {
                        return nil
                    }
                    return pinID
                }
            }
        )
        let visiblePersistedPins = persistedPins.filter { !shortcutHostedHiddenPinIds.contains($0.id) }
        let spaceFolders = folders(spaceId)
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
            candidateLiveTabs = liveShortcutTabs(windowId)
        } else {
            candidateLiveTabs = transientShortcutTabsByWindow().values
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
