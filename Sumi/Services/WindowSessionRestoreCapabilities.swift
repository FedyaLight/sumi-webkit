import Foundation

/// Selection side effects required while reconciling a restored window.
/// The restore subsystem deliberately does not know about `BrowserManager`.
@MainActor
protocol WindowSessionSelectionApplying: AnyObject {
    func applyTabSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        updateTheme: Bool,
        rememberSelection: Bool,
        persistSelection: Bool
    )

    func showEmptyState(
        in windowState: BrowserWindowState,
        presentNewTabFloatingBar: Bool
    )

    func syncShortcutSelectionState(for windowState: BrowserWindowState)
}

@MainActor
protocol WindowSessionFloatingBarSanitizing: AnyObject {
    func sanitize(in windowState: BrowserWindowState)
}

@MainActor
protocol WindowSessionThemeCommitting: AnyObject {
    func commitWorkspaceTheme(
        _ workspaceTheme: WorkspaceTheme,
        for windowState: BrowserWindowState
    )
}

@MainActor
protocol WindowSessionSplitFocusing: AnyObject {
    func focusSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState)
}

extension BrowserManager: WindowSessionSelectionApplying {}
extension FloatingBarPresentationService: WindowSessionFloatingBarSanitizing {}
extension BrowserWorkspaceThemeTransitionOwner: WindowSessionThemeCommitting {}
extension SplitShortcutFocusService: WindowSessionSplitFocusing {}
