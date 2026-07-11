import Foundation
import SumiDomain

@MainActor
final class SidebarURLDropService {
    private let tabOpening: any URLTabOpening
    private let nativeSurfaces: any NativeBrowserSurfaceOpening
    private let destinations: any SidebarURLDropDestinationResolving
    private let shortcutInsertion: any ShortcutURLInserting

    init(
        tabOpening: any URLTabOpening,
        nativeSurfaces: any NativeBrowserSurfaceOpening,
        destinations: any SidebarURLDropDestinationResolving,
        shortcutInsertion: any ShortcutURLInserting
    ) {
        self.tabOpening = tabOpening
        self.nativeSurfaces = nativeSurfaces
        self.destinations = destinations
        self.shortcutInsertion = shortcutInsertion
    }

    func open(
        _ url: URL,
        in windowState: BrowserWindowState,
        at slot: DropZoneSlot
    ) -> Bool {
        guard slot != .empty else { return false }

        if windowState.isIncognito {
            return openEphemeral(url, in: windowState)
        }

        switch slot {
        case .spaceRegular(let spaceID, let index):
            guard let space = destinations.space(spaceID) else { return false }
            if let nativeKind = nativeSurfaceKind(for: url) {
                nativeSurfaces.openNativeBrowserSurface(
                    nativeKind,
                    url: url,
                    in: windowState,
                    preferredSpaceId: space.id
                )
                return true
            }
            guard url.scheme?.lowercased() != "sumi" else { return false }
            _ = tabOpening.openNewTab(
                url: url.absoluteString,
                context: .foreground(
                    windowState: windowState,
                    preferredSpaceId: space.id,
                    regularInsertionIndex: index
                )
            )
            return true

        case .spacePinned(let spaceID, let index):
            guard url.scheme?.lowercased() != "sumi",
                  let space = destinations.space(spaceID)
            else { return false }
            return shortcutInsertion.insert(
                url,
                placement: ShortcutURLPlacement(
                    role: .spacePinned,
                    profileID: nil,
                    executionProfileID: space.profileId,
                    spaceID: space.id,
                    folderID: nil,
                    index: index,
                    openTargetFolder: true
                ),
                in: windowState
            )

        case .folder(let folderID, let index):
            guard url.scheme?.lowercased() != "sumi",
                  let destination = destinations.folder(folderID)
            else { return false }
            return shortcutInsertion.insert(
                url,
                placement: ShortcutURLPlacement(
                    role: .spacePinned,
                    profileID: nil,
                    executionProfileID: destination.space.profileId,
                    spaceID: destination.space.id,
                    folderID: destination.folder.id,
                    index: index,
                    openTargetFolder: false
                ),
                in: windowState
            )

        case .essentials(let index):
            guard url.scheme?.lowercased() != "sumi",
                  let insertion = destinations.essentialsInsertion(
                    in: windowState,
                    at: index
                  )
            else { return false }
            return shortcutInsertion.insert(
                url,
                placement: ShortcutURLPlacement(
                    role: .essential,
                    profileID: insertion.profileId,
                    executionProfileID: insertion.profileId,
                    spaceID: nil,
                    folderID: nil,
                    index: insertion.index,
                    openTargetFolder: true
                ),
                in: windowState
            )

        case .empty:
            return false
        }
    }

    private func openEphemeral(
        _ url: URL,
        in windowState: BrowserWindowState
    ) -> Bool {
        if let nativeKind = nativeSurfaceKind(for: url) {
            nativeSurfaces.openNativeBrowserSurface(
                nativeKind,
                url: url,
                in: windowState,
                preferredSpaceId: nil
            )
            return true
        }
        guard url.scheme?.lowercased() != "sumi" else { return false }
        _ = tabOpening.openNewTab(
            url: url.absoluteString,
            context: .foreground(windowState: windowState)
        )
        return true
    }

    private func nativeSurfaceKind(for url: URL) -> SumiNativeBrowserSurfaceKind? {
        if SumiSurface.isSettingsSurfaceURL(url) { return .settings }
        if SumiSurface.isHistorySurfaceURL(url) { return .history }
        if SumiSurface.isBookmarksSurfaceURL(url) { return .bookmarks }
        return nil
    }
}
