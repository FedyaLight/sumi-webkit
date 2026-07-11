import Foundation

@MainActor
protocol NativeBrowserSurfaceOpening: AnyObject {
    func openNativeBrowserSurface(
        _ kind: SumiNativeBrowserSurfaceKind,
        url: URL,
        in windowState: BrowserWindowState,
        preferredSpaceId: UUID?
    )
}

extension BrowserNativeSurfaceRoutingOwner: NativeBrowserSurfaceOpening {}
