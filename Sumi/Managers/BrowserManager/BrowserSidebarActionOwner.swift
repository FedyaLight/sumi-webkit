import AppKit
import Foundation

@MainActor
final class BrowserSidebarActionOwner {
    private let tabManager: @MainActor @Sendable () -> TabManager?
    private let liveFolderManager: @MainActor @Sendable () -> SumiLiveFolderManager?
    private let sumiSettings: @MainActor () -> SumiSettingsService?

    init(
        tabManager: @escaping @MainActor @Sendable () -> TabManager?,
        liveFolderManager: @escaping @MainActor @Sendable () -> SumiLiveFolderManager?,
        sumiSettings: @escaping @MainActor () -> SumiSettingsService?
    ) {
        self.tabManager = tabManager
        self.liveFolderManager = liveFolderManager
        self.sumiSettings = sumiSettings
    }

    func spaceForSidebarActions(in windowState: BrowserWindowState) -> Space? {
        guard let tabManager = tabManager() else { return nil }
        if let windowSpaceId = windowState.currentSpaceId,
           let windowSpace = tabManager.spaceStateOwner.spaces.first(where: { $0.id == windowSpaceId }) {
            return windowSpace
        }

        return nil
    }

    func createFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        _ = tabManager()?.folderMutationOwner.createFolder(for: space.id)
    }

    func createRSSLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState),
              let feedURLString = promptForLiveFolderFeedURL(in: windowState)
        else {
            return
        }
        liveFolderManager()?.createRSSFolder(in: space.id, feedURLString: feedURLString)
    }

    func createGitHubPRFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        liveFolderManager()?.createGitHubFolder(in: space.id, kind: .githubPullRequests)
    }

    func createGitHubIssuesFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        liveFolderManager()?.createGitHubFolder(in: space.id, kind: .githubIssues)
    }

    private func promptForLiveFolderFeedURL(in windowState: BrowserWindowState) -> String? {
        let alert = NSAlert()
        alert.messageText = "New RSS Live Folder"
        alert.informativeText = "Enter an RSS or Atom feed URL."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://example.com/feed.xml"
        alert.accessoryView = field
        alert.sumiApplyNativeSurfaceAppearance(
            windowState: windowState,
            settings: sumiSettings()
        )

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return value
    }
}
