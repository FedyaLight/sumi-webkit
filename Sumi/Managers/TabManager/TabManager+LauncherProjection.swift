import Foundation

@MainActor
extension TabManager {
    struct SpaceLauncherProjection {
        let spaceId: UUID
        let regularTabs: [Tab]
        let topLevelFolders: [TabFolder]
        let topLevelPins: [ShortcutPin]
        let folderPins: [UUID: [ShortcutPin]]
        let liveTabsByPinId: [UUID: Tab]

        var launcherCount: Int {
            topLevelPins.count + folderPins.values.reduce(0) { $0 + $1.count }
        }

        var userVisibleTabCount: Int {
            regularTabs.count + launcherCount
        }

        var hasVisibleContent: Bool {
            userVisibleTabCount > 0 || topLevelFolders.isEmpty == false
        }

        func liveTab(for pinId: UUID) -> Tab? {
            liveTabsByPinId[pinId]
        }
    }

    func launcherProjection(
        for spaceId: UUID,
        in windowId: UUID? = nil
    ) -> SpaceLauncherProjection {
        let regularTabs = Array(tabsBySpace[spaceId] ?? [])
        let persistedPins = spacePinnedPins(for: spaceId)
        let topLevelFolders = (foldersBySpace[spaceId] ?? []).sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let topLevelPins = persistedPins
            .filter { $0.folderId == nil }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        let folderPins = Dictionary(
            grouping: persistedPins.filter { $0.folderId != nil },
            by: { $0.folderId! }
        ).mapValues { pins in
            pins.sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }

        let candidateLiveTabs: [Tab]
        if let windowId {
            candidateLiveTabs = liveShortcutTabs(in: windowId)
        } else {
            candidateLiveTabs = transientShortcutTabsByWindow.values
                .flatMap(\.values)
        }

        let liveTabsByPinId = candidateLiveTabs.reduce(into: [UUID: Tab]()) { result, tab in
            guard tab.shortcutPinRole == .spacePinned,
                  tab.spaceId == spaceId,
                  let pinId = tab.shortcutPinId,
                  result[pinId] == nil else { return }
            result[pinId] = tab
        }

        return SpaceLauncherProjection(
            spaceId: spaceId,
            regularTabs: regularTabs,
            topLevelFolders: topLevelFolders,
            topLevelPins: topLevelPins,
            folderPins: folderPins,
            liveTabsByPinId: liveTabsByPinId
        )
    }
}
