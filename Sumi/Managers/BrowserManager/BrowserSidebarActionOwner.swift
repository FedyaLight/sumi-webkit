import AppKit
import Foundation

@MainActor
final class BrowserSidebarActionOwner {
    struct Dependencies {
        let tabManager: @MainActor @Sendable () -> TabManager
        let liveFolderManager: @MainActor @Sendable () -> SumiLiveFolderManager
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func spaceForSidebarActions(in windowState: BrowserWindowState) -> Space? {
        let tabManager = dependencies.tabManager()
        return windowState.currentSpaceId
            .flatMap { spaceId in tabManager.spaces.first(where: { $0.id == spaceId }) }
            ?? tabManager.currentSpace
    }

    func createFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        _ = dependencies.tabManager().createFolder(for: space.id)
    }

    func createRSSLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState),
              let feedURLString = promptForLiveFolderFeedURL()
        else {
            return
        }
        dependencies.liveFolderManager().createRSSFolder(in: space.id, feedURLString: feedURLString)
    }

    func createGitHubPullRequestsLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        dependencies.liveFolderManager().createGitHubFolder(in: space.id, kind: .githubPullRequests)
    }

    func createGitHubIssuesLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        dependencies.liveFolderManager().createGitHubFolder(in: space.id, kind: .githubIssues)
    }

    private func promptForLiveFolderFeedURL() -> String? {
        let alert = NSAlert()
        alert.messageText = "New RSS Live Folder"
        alert.informativeText = "Enter an RSS or Atom feed URL."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://example.com/feed.xml"
        alert.accessoryView = field

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

extension BrowserSidebarActionOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let liveFolderManager = browserManager.liveFolderManager
        return Self(
            tabManager: { [weak browserManager, tabManager = browserManager.tabManager] in
                browserManager?.tabManager ?? tabManager
            },
            liveFolderManager: { liveFolderManager }
        )
    }
}
