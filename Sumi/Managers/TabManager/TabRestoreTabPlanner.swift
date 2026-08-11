import Foundation

struct TabRestoreTabPlanner: Sendable {
    private let pages = TabRestorePageResolver()

    func categorize(
        _ records: [TabRestoreTabRecord],
        defaultProfileId: UUID?,
        blockedProfileIDs: Set<UUID>,
        validSpaceIds: Set<UUID>,
        validFolderIdsBySpace: [UUID: Set<UUID>],
        repairReasons: inout Set<String>
    ) -> TabRestoreCategorizedTabs {
        var seenIds: Set<UUID> = []
        var result = TabRestoreCategorizedTabs(
            regularTabsBySpace: [:],
            pinnedShortcutsByProfile: [:],
            pendingPinnedShortcuts: [],
            spacePinnedShortcutsBySpace: [:],
            pinnedCount: 0,
            spacePinnedCount: 0,
            regularCount: 0
        )

        for record in records.sorted(by: isOrderedBefore) {
            guard isRetiredSettingsSurface(record) == false else {
                repairReasons.insert("removed retired settings surface")
                continue
            }
            guard seenIds.insert(record.id).inserted else {
                repairReasons.insert("removed duplicate tab")
                continue
            }
            if record.isPinned {
                appendFavorite(
                    record,
                    defaultProfileId: defaultProfileId,
                    blockedProfileIDs: blockedProfileIDs,
                    to: &result,
                    repairReasons: &repairReasons
                )
            } else if record.isSpacePinned {
                appendSpacePinned(
                    record,
                    blockedProfileIDs: blockedProfileIDs,
                    validSpaceIds: validSpaceIds,
                    validFolderIdsBySpace: validFolderIdsBySpace,
                    to: &result,
                    repairReasons: &repairReasons
                )
            } else {
                appendRegular(
                    record,
                    blockedProfileIDs: blockedProfileIDs,
                    validSpaceIds: validSpaceIds,
                    to: &result,
                    repairReasons: &repairReasons
                )
            }
        }

        for profileId in result.pinnedShortcutsByProfile.keys {
            result.pinnedShortcutsByProfile[profileId]?.sort(by: isOrderedBefore)
        }
        result.pendingPinnedShortcuts.sort(by: isOrderedBefore)
        for spaceId in result.spacePinnedShortcutsBySpace.keys {
            result.spacePinnedShortcutsBySpace[spaceId]?.sort(by: isOrderedBefore)
        }
        for spaceId in result.regularTabsBySpace.keys {
            result.regularTabsBySpace[spaceId]?.sort(by: isOrderedBefore)
        }
        return result
    }

    private func appendFavorite(
        _ record: TabRestoreTabRecord,
        defaultProfileId: UUID?,
        blockedProfileIDs: Set<UUID>,
        to result: inout TabRestoreCategorizedTabs,
        repairReasons: inout Set<String>
    ) {
        if record.isSpacePinned {
            repairReasons.insert("normalized tab with both pinned flags")
        }
        let storedProfileID = allowed(record.profileId, blocked: blockedProfileIDs)
        let profileId = storedProfileID ?? defaultProfileId
        if record.profileId != nil, storedProfileID == nil {
            repairReasons.insert("reassigned blocked launcher profile")
        } else if record.profileId == nil, defaultProfileId != nil {
            repairReasons.insert("assigned default profile to pinned launcher")
        }
        guard let launchURL = pages.launchURL(
            record.urlString,
            repairReasons: &repairReasons
        ) else {
            repairReasons.insert("removed launcher with invalid destination")
            return
        }
        let shortcut = TabRestoreShortcutDTO(
            id: record.id,
            role: .favorite,
            profileId: profileId,
            executionProfileId: allowed(
                record.executionProfileId,
                blocked: blockedProfileIDs
            ),
            spaceId: nil,
            index: record.index,
            folderId: nil,
            launchURL: launchURL,
            title: record.name,
            iconAsset: record.iconAsset,
            titleIsCustom: record.titleIsCustom
        )
        if let profileId {
            result.pinnedShortcutsByProfile[profileId, default: []].append(shortcut)
        } else {
            result.pendingPinnedShortcuts.append(shortcut)
        }
        result.pinnedCount += 1
    }

    private func appendSpacePinned(
        _ record: TabRestoreTabRecord,
        blockedProfileIDs: Set<UUID>,
        validSpaceIds: Set<UUID>,
        validFolderIdsBySpace: [UUID: Set<UUID>],
        to result: inout TabRestoreCategorizedTabs,
        repairReasons: inout Set<String>
    ) {
        guard let spaceId = record.spaceId, validSpaceIds.contains(spaceId) else {
            repairReasons.insert("removed space-pinned launcher with missing space")
            return
        }

        var folderId = record.folderId
        if let existingFolderId = folderId,
           validFolderIdsBySpace[spaceId]?.contains(existingFolderId) != true {
            folderId = nil
            repairReasons.insert("moved launcher out of missing folder")
        }
        guard let launchURL = pages.launchURL(
            record.urlString,
            repairReasons: &repairReasons
        ) else {
            repairReasons.insert("removed launcher with invalid destination")
            return
        }
        result.spacePinnedShortcutsBySpace[spaceId, default: []].append(
            TabRestoreShortcutDTO(
                id: record.id,
                role: .spacePinned,
                profileId: nil,
                executionProfileId: allowed(
                    record.executionProfileId ?? record.profileId,
                    blocked: blockedProfileIDs
                ),
                spaceId: spaceId,
                index: record.index,
                folderId: folderId,
                launchURL: launchURL,
                title: record.name,
                iconAsset: record.iconAsset,
                titleIsCustom: record.titleIsCustom
            )
        )
        result.spacePinnedCount += 1
    }

    private func appendRegular(
        _ record: TabRestoreTabRecord,
        blockedProfileIDs: Set<UUID>,
        validSpaceIds: Set<UUID>,
        to result: inout TabRestoreCategorizedTabs,
        repairReasons: inout Set<String>
    ) {
        guard record.folderId == nil else {
            repairReasons.insert("removed regular tab with folder relationship")
            return
        }
        guard let spaceId = record.spaceId, validSpaceIds.contains(spaceId) else {
            repairReasons.insert("removed regular tab with missing space")
            return
        }
        let page = pages.resolveRegularPage(
            record,
            repairReasons: &repairReasons
        )
        let url = page.url
        guard ExtensionURLIdentity.isOwned(url) == false else {
            repairReasons.insert("removed extension-owned restored tab")
            return
        }
        result.regularTabsBySpace[spaceId, default: []].append(
            TabRestoreTabDTO(
                id: record.id,
                url: url,
                name: record.name,
                index: record.index,
                spaceId: spaceId,
                profileId: allowed(record.profileId, blocked: blockedProfileIDs),
                folderId: nil,
                canGoBack: false,
                canGoForward: false,
                isRestoreFailure: page.isRestoreFailure,
                restoreFailureDestination: page.failureDestination,
                restoreFailureRawDestination: page.failureRawDestination
            )
        )
        result.regularCount += 1
    }

    private func allowed(
        _ profileID: UUID?,
        blocked: Set<UUID>
    ) -> UUID? {
        profileID.flatMap { blocked.contains($0) ? nil : $0 }
    }

    /// Settings moved to a standalone scene. Retired persisted surfaces are
    /// rejected only at restore admission so the old URL never becomes an
    /// active browser or WebKit surface again.
    private func isRetiredSettingsSurface(_ record: TabRestoreTabRecord) -> Bool {
        [record.urlString, record.currentURLString]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .contains { url in
                url.scheme?.lowercased() == "sumi"
                    && url.host?.lowercased() == "settings"
            }
    }

    private func isOrderedBefore(
        _ lhs: TabRestoreTabRecord,
        _ rhs: TabRestoreTabRecord
    ) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned && lhs.isPinned != rhs.isPinned }
        if lhs.isSpacePinned != rhs.isSpacePinned {
            return lhs.isSpacePinned && lhs.isSpacePinned != rhs.isSpacePinned
        }
        let lhsSpace = lhs.spaceId?.uuidString ?? ""
        let rhsSpace = rhs.spaceId?.uuidString ?? ""
        if lhsSpace != rhsSpace { return lhsSpace < rhsSpace }
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func isOrderedBefore(
        _ lhs: TabRestoreShortcutDTO,
        _ rhs: TabRestoreShortcutDTO
    ) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func isOrderedBefore(_ lhs: TabRestoreTabDTO, _ rhs: TabRestoreTabDTO) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
