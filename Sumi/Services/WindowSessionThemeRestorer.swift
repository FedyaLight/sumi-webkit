import Foundation

@MainActor
struct WindowSessionThemeRestorer {
    let tabManager: TabManager
    let spaceResolver: WindowSessionSpaceResolver
    let themeCommitter: any WindowSessionThemeCommitting

    func restore(
        for windowState: BrowserWindowState,
        source: String
    ) {
        if let space = spaceResolver.space(for: windowState.currentSpaceId) {
            windowState.currentProfileId = space.profileId
            themeCommitter.commitWorkspaceTheme(
                space.workspaceTheme,
                for: windowState
            )
            return
        }

        if let spaceId = windowState.currentSpaceId,
           tabManager.startupRestoreLifecycle.hasLoadedInitialData == false {
            RuntimeDiagnostics.debug(
                "Preserving bootstrap workspace theme for window \(windowState.id.uuidString) while waiting for initial TabManager data; source=\(source) currentSpace=\(spaceId.uuidString)",
                category: "WindowSessionRestore"
            )
            return
        }

        if let spaceId = windowState.currentSpaceId {
            RuntimeDiagnostics.debug(
                "Applying default workspace theme fallback for window \(windowState.id.uuidString); source=\(source) missingSpace=\(spaceId.uuidString)",
                category: "WindowSessionRestore"
            )
        }
        themeCommitter.commitWorkspaceTheme(.default, for: windowState)
    }
}
