import Foundation

@MainActor
final class BrowserChromeBundle {
    let commands: BrowserChromeCommands
    let activePageCommands: ActivePageCommandService
    let sidebarActionOwner: BrowserSidebarActionOwner
    let sidebarPresentationOwner: BrowserSidebarPresentationOwner
    let workspaceThemeTransitionOwner: BrowserWorkspaceThemeTransitionOwner
    let workspaceThemeEditorOwner: BrowserWorkspaceThemeEditorOwner
    let nativeSurfaceRoutingOwner: BrowserNativeSurfaceRoutingOwner
    let zoomCommandOwner: BrowserZoomCommandOwner
    let sharingPickerPresentationOwner: BrowserSharingPickerPresentationOwner
    let nativeDialogPresentationOwner: BrowserNativeDialogPresentationOwner

    init(
        commands: BrowserChromeCommands,
        activePageCommands: ActivePageCommandService,
        sidebarActionOwner: BrowserSidebarActionOwner,
        sidebarPresentationOwner: BrowserSidebarPresentationOwner,
        workspaceThemeTransitionOwner: BrowserWorkspaceThemeTransitionOwner,
        workspaceThemeEditorOwner: BrowserWorkspaceThemeEditorOwner,
        nativeSurfaceRoutingOwner: BrowserNativeSurfaceRoutingOwner,
        zoomCommandOwner: BrowserZoomCommandOwner,
        sharingPickerPresentationOwner: BrowserSharingPickerPresentationOwner,
        nativeDialogPresentationOwner: BrowserNativeDialogPresentationOwner
    ) {
        self.commands = commands
        self.activePageCommands = activePageCommands
        self.sidebarActionOwner = sidebarActionOwner
        self.sidebarPresentationOwner = sidebarPresentationOwner
        self.workspaceThemeTransitionOwner = workspaceThemeTransitionOwner
        self.workspaceThemeEditorOwner = workspaceThemeEditorOwner
        self.nativeSurfaceRoutingOwner = nativeSurfaceRoutingOwner
        self.zoomCommandOwner = zoomCommandOwner
        self.sharingPickerPresentationOwner = sharingPickerPresentationOwner
        self.nativeDialogPresentationOwner = nativeDialogPresentationOwner
    }
}
