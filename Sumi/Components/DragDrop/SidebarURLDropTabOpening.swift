import Foundation
import SumiDomain

/// Opens a URL dropped on the sidebar as a page rather than a shortcut: a
/// native browser surface when the URL names one, otherwise a foreground tab.
/// `sumi:` URLs that are not a known native surface are refused so a drop can
/// never navigate to internal scheme space.
@MainActor
final class SidebarURLDropTabOpening {
    private let tabOpening: any URLTabOpening
    private let nativeSurfaces: any NativeBrowserSurfaceOpening

    init(
        tabOpening: any URLTabOpening,
        nativeSurfaces: any NativeBrowserSurfaceOpening
    ) {
        self.tabOpening = tabOpening
        self.nativeSurfaces = nativeSurfaces
    }

    func open(
        _ url: URL,
        in windowState: BrowserWindowState,
        preferredSpaceID: UUID? = nil,
        regularInsertionIndex: Int? = nil
    ) -> Bool {
        if let nativeKind = Self.nativeSurfaceKind(for: url) {
            nativeSurfaces.openNativeBrowserSurface(
                nativeKind,
                url: url,
                in: windowState,
                preferredSpaceId: preferredSpaceID
            )
            return true
        }
        guard url.scheme?.lowercased() != "sumi" else { return false }
        _ = tabOpening.openNewTab(
            url: url.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: preferredSpaceID,
                regularInsertionIndex: regularInsertionIndex
            )
        )
        return true
    }

    static func nativeSurfaceKind(
        for url: URL
    ) -> SumiNativeBrowserSurfaceKind? {
        if SumiSurface.isSettingsSurfaceURL(url) { return .settings }
        if SumiSurface.isHistorySurfaceURL(url) { return .history }
        if SumiSurface.isBookmarksSurfaceURL(url) { return .bookmarks }
        return nil
    }
}
