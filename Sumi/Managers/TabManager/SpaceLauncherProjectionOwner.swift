import Foundation

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
final class SpaceLauncherProjectionOwner {
    struct Dependencies {
        let regularTabs: @MainActor (UUID) -> [Tab]
        let spacePinnedPins: @MainActor (UUID) -> [ShortcutPin]
        let folders: @MainActor (UUID) -> [TabFolder]
        let shortcutHostedSplitGroups: @MainActor (UUID) -> [SplitGroup]
        let liveShortcutTabs: @MainActor (UUID) -> [Tab]
        let transientShortcutTabsByWindow: @MainActor () -> [UUID: [UUID: Tab]]
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func projection(
        for spaceId: UUID,
        in windowId: UUID? = nil
    ) -> SpaceLauncherProjectionSnapshot {
        let regularTabs = dependencies.regularTabs(spaceId)
        let persistedPins = dependencies.spacePinnedPins(spaceId)
        let shortcutHostedHiddenPinIds = Set(
            dependencies.shortcutHostedSplitGroups(spaceId).flatMap { group in
                group.members.compactMap(\.pinId)
            }
        )
        let visiblePersistedPins = persistedPins.filter { !shortcutHostedHiddenPinIds.contains($0.id) }
        let topLevelFolders = dependencies.folders(spaceId).sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        .filter { $0.parentFolderId == nil }
        let childFolders = Dictionary(
            grouping: dependencies.folders(spaceId).filter { $0.parentFolderId != nil },
            by: { $0.parentFolderId! }
        ).mapValues { folders in
            folders.sorted { lhs, rhs in
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
            candidateLiveTabs = dependencies.liveShortcutTabs(windowId)
        } else {
            candidateLiveTabs = dependencies.transientShortcutTabsByWindow().values
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
            regularTabs: regularTabs,
            topLevelFolders: topLevelFolders,
            topLevelPins: topLevelPins,
            childFolders: childFolders,
            folderPins: folderPins,
            liveTabsByPinId: liveTabsByPinId
        )
    }
}
