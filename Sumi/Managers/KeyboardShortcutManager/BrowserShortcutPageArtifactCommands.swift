import SumiDomain

/// Shortcut commands that turn the current page into a saved artifact: a
/// screenshot captured with the user's stored settings, or a new Boost opened
/// in its editor. Each exposes the availability question alongside the command
/// so the dispatcher can answer menu validation without duplicating the rules.
@MainActor
final class BrowserShortcutPageArtifactCommands {
    private let pageActions: URLBarHubPageActionOwner
    private let boosts: SumiBoostsModule

    init(
        pageActions: URLBarHubPageActionOwner,
        boosts: SumiBoostsModule
    ) {
        self.pageActions = pageActions
        self.boosts = boosts
    }

    func captureScreenshot(in context: BrowserShortcutContext) -> Bool {
        pageActions.captureUsingSavedSettings(context.page)
    }

    func canCaptureScreenshot(in context: BrowserShortcutContext) -> Bool {
        pageActions.canCapture(context.page)
    }

    /// Boost creation opens an editor, so it is deferred off the dispatch turn
    /// to keep the shortcut from presenting UI inside the key-handling call.
    func createBoost(in context: BrowserShortcutContext) -> Bool {
        guard let target = context.page else { return false }
        DispatchQueue.main.async { [boosts] in
            do {
                try boosts.createBoostAndOpenEditor(
                    tab: target.tab,
                    profile: target.tab.resolveProfile(),
                    windowState: context.windowState
                )
            } catch {
                RuntimeDiagnostics.debug(
                    "Command palette Boost creation failed: \(error)",
                    category: "CommandPalette"
                )
            }
        }
        return true
    }

    func canCreateBoost(in context: BrowserShortcutContext) -> Bool {
        context.page?.source == .selectedTab
            && boosts.canBoost(url: context.page?.url)
    }
}
