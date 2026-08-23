import Foundation
import SumiDomain

/// Produces a deterministic value plan for merging a persisted session into
/// the live tab graph. It has no access to mutable browser state or persistence.
struct TabLastSessionMergePlanner {
    func makePlan(
        snapshot: TabPersistenceSnapshot,
        live: TabLastSessionLiveState
    ) -> TabLastSessionMergePlan {
        let orderedSnapshotSpaces = uniqueById(
            stableSorted(snapshot.spaces, index: \.index, id: \.id),
            id: \.id
        )
        let snapshotSpacesById = Dictionary(
            uniqueKeysWithValues: orderedSnapshotSpaces.map { ($0.id, $0) }
        )
        let snapshotSpaceIds = Set(snapshotSpacesById.keys)
        let orderedSpaceIds = orderedSnapshotSpaces.map(\.id)
            + live.spaces.map(\.id).filter { !snapshotSpaceIds.contains($0) }
        let finalSpaceIds = Set(orderedSpaceIds)
        let profileBySpace = Dictionary(
            uniqueKeysWithValues: orderedSpaceIds.compactMap { spaceId in
                if let liveSpace = live.spaces.first(where: { $0.id == spaceId }) {
                    return (spaceId, liveSpace.profileId)
                }
                if let snapshotSpace = snapshotSpacesById[spaceId] {
                    return (spaceId, snapshotSpace.profileId)
                }
                return nil
            }
        )

        let folders = mergeFolders(
            snapshot.folders,
            live: live,
            finalSpaceIds: finalSpaceIds
        )
        let shortcutsAndTabs = mergeTabs(
            snapshot.tabs,
            live: live,
            finalSpaceIds: finalSpaceIds,
            profileBySpace: profileBySpace,
            reservedIds: Set(folders.values.joined().map(\.id))
        )

        let selectedSpace: TabLastSessionSpaceSelection
        if let requestedSpaceId = snapshot.state.currentSpaceID,
           finalSpaceIds.contains(requestedSpaceId) {
            selectedSpace = .select(requestedSpaceId)
        } else if live.currentSpaceId == nil {
            selectedSpace = .select(orderedSpaceIds.first)
        } else {
            selectedSpace = .keepCurrent
        }

        return TabLastSessionMergePlan(
            orderedSpaceIds: orderedSpaceIds,
            restoredSpacesById: snapshotSpacesById,
            foldersBySpace: folders,
            favoritePinsByProfile: shortcutsAndTabs.favoritePinsByProfile,
            spacePinnedShortcuts: shortcutsAndTabs.spacePinnedShortcuts,
            regularTabsBySpace: shortcutsAndTabs.regularTabsBySpace,
            spaceSelection: selectedSpace,
            requestedCurrentTabId: snapshot.state.currentTabID
        )
    }
}

private extension TabLastSessionMergePlanner {
    struct MergedTabs {
        let favoritePinsByProfile: [UUID: [TabLastSessionShortcutDescriptor]]
        let spacePinnedShortcuts: [UUID: [TabLastSessionShortcutDescriptor]]
        let regularTabsBySpace: [UUID: [TabLastSessionRegularTabPlacement]]
    }

    func mergeFolders(
        _ snapshotFolders: [TabPersistenceFolder],
        live: TabLastSessionLiveState,
        finalSpaceIds: Set<UUID>
    ) -> [UUID: [TabLastSessionFolderPlacement]] {
        var placements = live.foldersBySpace.mapValues { folders in
            folders.map {
                TabLastSessionFolderPlacement(
                    id: $0.id,
                    spaceId: $0.spaceId,
                    parentFolderId: $0.parentFolderId,
                    index: $0.index,
                    restoredValues: nil
                )
            }
        }
        var locationById: [UUID: UUID] = [:]
        for spaceId in live.spaces.map(\.id) {
            for folder in placements[spaceId] ?? [] where locationById[folder.id] == nil {
                locationById[folder.id] = spaceId
            }
        }

        for folder in uniqueById(
            stableSorted(snapshotFolders, index: \.index, id: \.id),
            id: \.id
        ) {
            guard finalSpaceIds.contains(folder.spaceId) else { continue }
            if let existingSpaceId = locationById[folder.id] {
                guard existingSpaceId == folder.spaceId,
                      let index = placements[existingSpaceId]?.firstIndex(where: { $0.id == folder.id })
                else { continue }
                placements[existingSpaceId]?[index] = TabLastSessionFolderPlacement(
                    id: folder.id,
                    spaceId: folder.spaceId,
                    parentFolderId: folder.parentFolderId,
                    index: folder.index,
                    restoredValues: folder
                )
                continue
            }

            locationById[folder.id] = folder.spaceId
            placements[folder.spaceId, default: []].append(
                TabLastSessionFolderPlacement(
                    id: folder.id,
                    spaceId: folder.spaceId,
                    parentFolderId: folder.parentFolderId,
                    index: folder.index,
                    restoredValues: folder
                )
            )
        }

        for spaceId in finalSpaceIds {
            placements[spaceId, default: []].sort(by: folderPlacementOrder)
        }
        return placements
    }

    func mergeTabs(
        _ snapshotTabs: [TabPersistenceTab],
        live: TabLastSessionLiveState,
        finalSpaceIds: Set<UUID>,
        profileBySpace: [UUID: UUID?],
        reservedIds: Set<UUID>
    ) -> MergedTabs {
        var favoritePins = live.favoritePinsByProfile
        var spacePins = live.spacePinnedShortcuts
        var regularTabs: [UUID: [TabLastSessionRegularTabPlacement]] = [:]
        for (spaceId, tabs) in live.regularTabsBySpace {
            regularTabs[spaceId] = tabs.map {
                .existing(id: $0.id, spaceId: spaceId, index: $0.index)
            }
        }
        var knownIds = live.allPersistedItemIds.union(reservedIds)

        for tab in uniqueById(
            stableSorted(snapshotTabs, index: \.index, id: \.id),
            id: \.id
        ) {
            guard knownIds.insert(tab.id).inserted else { continue }

            if tab.isPinned {
                guard let profileId = tab.profileId,
                      let launchURL = absoluteURL(tab.urlString),
                      SumiSurface.isEmptyNewTabURL(launchURL) == false
                else { continue }
                favoritePins[profileId, default: []].append(
                    shortcut(from: tab, kind: .favorite, launchURL: launchURL)
                )
                continue
            }

            if tab.isSpacePinned {
                guard let spaceId = tab.spaceId,
                      finalSpaceIds.contains(spaceId),
                      let launchURL = absoluteURL(tab.urlString),
                      SumiSurface.isEmptyNewTabURL(launchURL) == false
                else { continue }
                spacePins[spaceId, default: []].append(
                    shortcut(from: tab, kind: .spacePinned, launchURL: launchURL)
                )
                continue
            }

            guard let spaceId = tab.spaceId,
                  finalSpaceIds.contains(spaceId) else { continue }
            let rawDestination = tab.currentURLString ?? tab.urlString
            let candidate = absoluteURL(rawDestination)
                ?? absoluteURL(tab.urlString)
            let url: URL
            let isRestoreFailure: Bool
            switch tab.pageKind {
            case .empty:
                url = SumiSurface.emptyTabURL
                isRestoreFailure = false
            case .restoreFailure:
                url = SumiSurface.restoreFailureURL
                isRestoreFailure = true
            case .web, nil:
                if let candidate,
                   SumiSurface.isEmptyNewTabURL(candidate) == false {
                    url = candidate
                    isRestoreFailure = false
                } else {
                    url = SumiSurface.restoreFailureURL
                    isRestoreFailure = true
                }
            }
            let restored = TabLastSessionRestoredTab(
                id: tab.id,
                url: url,
                name: tab.name,
                spaceId: spaceId,
                index: tab.index,
                profileId: tab.profileId ?? profileBySpace[spaceId] ?? nil,
                canGoBack: false,
                canGoForward: false,
                isRestoreFailure: isRestoreFailure,
                restoreFailureRawDestination: isRestoreFailure
                    ? rawDestination : nil,
                restoreFailureDestination: isRestoreFailure
                    ? candidate : nil
            )
            regularTabs[spaceId, default: []].append(.restored(restored))
        }

        favoritePins = favoritePins.mapValues { descriptors in
            descriptors.sorted(by: shortcutOrder).enumerated().map { offset, descriptor in
                descriptor.placed(at: offset)
            }
        }
        spacePins = spacePins.mapValues { $0.sorted(by: shortcutOrder) }
        regularTabs = regularTabs.mapValues { $0.sorted(by: regularTabOrder) }
        for spaceId in finalSpaceIds {
            regularTabs[spaceId, default: []] = regularTabs[spaceId, default: []]
                .sorted(by: regularTabOrder)
        }

        return MergedTabs(
            favoritePinsByProfile: favoritePins,
            spacePinnedShortcuts: spacePins,
            regularTabsBySpace: regularTabs
        )
    }

    func absoluteURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme?.isEmpty == false else { return nil }
        return url
    }

    func shortcut(
        from tab: TabPersistenceTab,
        kind: TabLastSessionShortcutKind,
        launchURL: URL
    ) -> TabLastSessionShortcutDescriptor {
        TabLastSessionShortcutDescriptor(
            id: tab.id,
            kind: kind,
            profileId: tab.profileId,
            executionProfileId: kind == .spacePinned
                ? tab.executionProfileId ?? tab.profileId
                : tab.executionProfileId,
            spaceId: tab.spaceId,
            index: tab.index,
            folderId: tab.folderId,
            launchURL: launchURL,
            title: tab.name,
            iconAsset: tab.iconAsset,
            titleIsCustom: tab.titleIsCustom
        )
    }

    func stableSorted<T>(
        _ values: [T],
        index: KeyPath<T, Int>,
        id: KeyPath<T, UUID>
    ) -> [T] {
        values.enumerated().sorted { lhs, rhs in
            let lhsIndex = lhs.element[keyPath: index]
            let rhsIndex = rhs.element[keyPath: index]
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            let lhsId = lhs.element[keyPath: id].uuidString
            let rhsId = rhs.element[keyPath: id].uuidString
            if lhsId != rhsId { return lhsId < rhsId }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    func uniqueById<T>(_ values: [T], id: KeyPath<T, UUID>) -> [T] {
        var ids = Set<UUID>()
        return values.filter { value in
            ids.insert(value[keyPath: id]).inserted
        }
    }

    func folderPlacementOrder(
        _ lhs: TabLastSessionFolderPlacement,
        _ rhs: TabLastSessionFolderPlacement
    ) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func shortcutOrder(
        _ lhs: TabLastSessionShortcutDescriptor,
        _ rhs: TabLastSessionShortcutDescriptor
    ) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func regularTabOrder(
        _ lhs: TabLastSessionRegularTabPlacement,
        _ rhs: TabLastSessionRegularTabPlacement
    ) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
