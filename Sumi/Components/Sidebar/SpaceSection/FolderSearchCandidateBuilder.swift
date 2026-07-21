import SumiDomain
import SwiftUI

enum FolderSearchCandidateKind: Equatable {
    case shortcut(UUID)
    case liveItem(folderId: UUID, itemId: String)
    case splitGroupItem(groupId: UUID, itemId: UUID)
}

/// How a preview row resolves its icon.
///
/// A shortcut stays unresolved on purpose: the row hands these inputs to
/// `SidebarShortcutIconResolver` — the same call the sidebar row makes — after
/// loading the stored favicon, because a folder that was never expanded this
/// session has nothing in the in-memory cache yet.
@MainActor
enum FolderSearchCandidateIcon {
    case shortcut(
        pin: ShortcutPin,
        liveTab: Tab?,
        partition: SumiFaviconPartition,
        imageReader: any BrowserFaviconImageReading
    )
    case systemImage(String)
    case resolved(Image)
}

@MainActor
struct FolderSearchCandidate: Identifiable {
    let id: String
    let kind: FolderSearchCandidateKind
    let title: String
    let secondaryText: String
    let icon: FolderSearchCandidateIcon
    let searchText: String
    let activate: @MainActor () -> Void
}

@MainActor
protocol FolderSearchLiveFolderProviding: AnyObject {
    func source(for folderId: UUID) -> SumiLiveFolderSource?
    func visibleItems(for folderId: UUID) -> [SumiLiveFolderItem]
}

extension SumiLiveFolderManager: FolderSearchLiveFolderProviding {}

@MainActor
struct FolderSearchActivationActions {
    var activateShortcut: (ShortcutPin) -> Void
    var activateLiveItem: (SumiLiveFolderItem) -> Void
    var activateSplitGroupItem: (SplitGroupSidebarItem, SplitGroup) -> Void
}

@MainActor
struct FolderSearchCandidateBuilder {
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let windowState: BrowserWindowState
    let liveFolderProvider: FolderSearchLiveFolderProviding
    let faviconImageReader: any BrowserFaviconImageReading
    /// Same projection the folder's own rows use, so a preview row lands on the
    /// identical favicon partition instead of guessing one.
    let pinProjection: SidebarPinFolderProjection
    let actions: FolderSearchActivationActions

    init(
        inventory: SidebarSpaceInventorySnapshot,
        selection: SidebarWindowSelectionQuery,
        windowState: BrowserWindowState,
        liveFolderProvider: FolderSearchLiveFolderProviding,
        faviconImageReader: any BrowserFaviconImageReading,
        pinProjection: SidebarPinFolderProjection,
        actions: FolderSearchActivationActions
    ) {
        self.inventory = inventory
        self.selection = selection
        self.windowState = windowState
        self.liveFolderProvider = liveFolderProvider
        self.faviconImageReader = faviconImageReader
        self.pinProjection = pinProjection
        self.actions = actions
    }

    func candidates(
        for folder: TabFolder,
        in space: Space,
        excludingVisibleCollapsedProjectionIDs visibleCollapsedProjectionIDs: Set<UUID>
    ) -> [FolderSearchCandidate] {
        var visitedFolderIDs = Set<UUID>()
        return candidates(
            forFolderID: folder.id,
            in: space,
            folderPath: [],
            excludingVisibleCollapsedProjectionIDs: visibleCollapsedProjectionIDs,
            visitedFolderIDs: &visitedFolderIDs
        )
    }

    private func candidates(
        forFolderID folderID: UUID,
        in space: Space,
        folderPath: [String],
        excludingVisibleCollapsedProjectionIDs visibleCollapsedProjectionIDs: Set<UUID>,
        visitedFolderIDs: inout Set<UUID>
    ) -> [FolderSearchCandidate] {
        guard visitedFolderIDs.insert(folderID).inserted else { return [] }
        defer { visitedFolderIDs.remove(folderID) }

        if liveFolderProvider.source(for: folderID) != nil {
            return liveFolderProvider.visibleItems(for: folderID).map { item in
                liveCandidate(
                    item,
                    folderID: folderID,
                    folderPath: folderPath
                )
            }
        }

        return inventory.folderItems(for: folderID).flatMap { item -> [FolderSearchCandidate] in
            switch item {
            case .shortcut(let pinID):
                guard !visibleCollapsedProjectionIDs.contains(pinID),
                      let pin = inventory.pin(id: pinID)
                else { return [] }
                return [shortcutCandidate(pin, folderPath: folderPath)]

            case .folder(let childFolderID):
                guard let childFolder = inventory.folder(id: childFolderID) else {
                    return []
                }
                return candidates(
                    forFolderID: childFolderID,
                    in: space,
                    folderPath: folderPath + [childFolder.name],
                    excludingVisibleCollapsedProjectionIDs: visibleCollapsedProjectionIDs,
                    visitedFolderIDs: &visitedFolderIDs
                )

            case .splitGroup(let groupID):
                guard !visibleCollapsedProjectionIDs.contains(groupID),
                      let group = inventory.splitGroup(id: groupID)
                else { return [] }
                return SplitGroupSidebarModel.items(
                    for: group,
                    inventory: inventory,
                    selection: selection,
                    windowState: windowState
                ).map { item in
                    splitGroupCandidate(
                        item,
                        group: group,
                        folderPath: folderPath
                    )
                }
            }
        }
    }

    private func shortcutCandidate(
        _ pin: ShortcutPin,
        folderPath: [String]
    ) -> FolderSearchCandidate {
        let title = pin.preferredDisplayTitle
        let urlString = pin.launchURL.absoluteString
        let host = pin.launchURL.host ?? ""
        let secondaryText = secondaryText(host: host, folderPath: folderPath)

        return FolderSearchCandidate(
            id: "shortcut-\(pin.id.uuidString)",
            kind: .shortcut(pin.id),
            title: title,
            secondaryText: secondaryText,
            icon: shortcutIcon(pin),
            searchText: FolderSearchMatcher.searchText(
                components: [title, host, urlString] + folderPath
            ),
            activate: { actions.activateShortcut(pin) }
        )
    }

    /// Same inputs the folder's own row feeds the shared icon resolver: the
    /// projection's partition and the pin's live tab, if it has one.
    private func shortcutIcon(_ pin: ShortcutPin) -> FolderSearchCandidateIcon {
        .shortcut(
            pin: pin,
            liveTab: selection.liveTab(for: pin.id, in: windowState),
            partition: pinProjection.faviconPartition(
                for: pin,
                currentSpaceID: windowState.currentSpaceId
            ),
            imageReader: faviconImageReader
        )
    }

    private func liveCandidate(
        _ item: SumiLiveFolderItem,
        folderID: UUID,
        folderPath: [String]
    ) -> FolderSearchCandidate {
        let host = item.url?.host ?? ""
        let secondaryText = secondaryText(
            host: item.subtitle?.isEmpty == false ? item.subtitle ?? host : host,
            folderPath: folderPath
        )

        return FolderSearchCandidate(
            id: "live-\(folderID.uuidString)-\(item.id)",
            kind: .liveItem(folderId: folderID, itemId: item.id),
            title: item.title,
            secondaryText: secondaryText,
            icon: .systemImage(item.iconSystemName ?? "link"),
            searchText: FolderSearchMatcher.searchText(
                components: [item.title, item.subtitle ?? "", host, item.urlString] + folderPath
            ),
            activate: { actions.activateLiveItem(item) }
        )
    }

    private func splitGroupCandidate(
        _ item: SplitGroupSidebarItem,
        group: SplitGroup,
        folderPath: [String]
    ) -> FolderSearchCandidate {
        let url = item.tab?.url ?? item.pin?.launchURL
        let urlString = url?.absoluteString ?? ""
        let host = url?.host ?? ""
        let title = item.title
        let icon = SplitGroupMemberIconResolver.resolve(
            item: item,
            loadedStoredFavicon: nil,
            imageReader: faviconImageReader
        ).image

        return FolderSearchCandidate(
            id: "split-\(group.id.uuidString)-\(item.stableIDDescription)",
            kind: .splitGroupItem(
                groupId: group.id,
                itemId: item.persistentID
            ),
            title: title,
            secondaryText: secondaryText(host: host, folderPath: folderPath),
            icon: .resolved(icon),
            searchText: FolderSearchMatcher.searchText(
                components: [title, host, urlString] + folderPath
            ),
            activate: { actions.activateSplitGroupItem(item, group) }
        )
    }

    private func secondaryText(host: String, folderPath: [String]) -> String {
        let path = folderPath.joined(separator: " / ")
        switch (host.isEmpty, path.isEmpty) {
        case (true, true):
            return ""
        case (false, true):
            return host
        case (true, false):
            return path
        case (false, false):
            return "\(host) • \(path)"
        }
    }
}

enum FolderSearchMatcher {
    static func filteredCandidates(
        _ candidates: [FolderSearchCandidate],
        query: String
    ) -> [FolderSearchCandidate] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return candidates }
        return candidates.filter { $0.searchText.contains(normalizedQuery) }
    }

    static func searchText(components: [String]) -> String {
        normalized(components.joined(separator: " "))
    }

    static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
