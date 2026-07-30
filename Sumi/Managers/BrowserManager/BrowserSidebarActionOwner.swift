import AppKit
import Foundation

@MainActor
final class BrowserSidebarActionOwner {
    private let spaces: TabSpaceCollectionStateOwner
    private let folderCommands: SidebarFolderCommands
    private let liveFolderManager: SumiLiveFolderManager
    private let settings: BrowserSettingsState

    init(
        spaces: TabSpaceCollectionStateOwner,
        folderCommands: SidebarFolderCommands,
        liveFolderManager: SumiLiveFolderManager,
        settings: BrowserSettingsState
    ) {
        self.spaces = spaces
        self.folderCommands = folderCommands
        self.liveFolderManager = liveFolderManager
        self.settings = settings
    }

    func spaceForSidebarActions(in windowState: BrowserWindowState) -> Space? {
        if let windowSpaceId = windowState.currentSpaceId,
           let windowSpace = spaces.spaces.first(where: { $0.id == windowSpaceId }) {
            return windowSpace
        }

        return nil
    }

    func createFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        _ = folderCommands.createFolder(
            in: space.id,
            name: "New Folder"
        )
    }

    func canCreateFolderInCurrentSpace(in windowState: BrowserWindowState) -> Bool {
        spaceForSidebarActions(in: windowState) != nil
    }

    func createRSSLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState),
              let feedURLString = promptForLiveFolderFeedURL(
                  in: windowState,
                  initialValue: "",
                  title: "New RSS Live Folder"
              )
        else {
            return
        }
        Task { [liveFolderManager] in
            await liveFolderManager.createRSSFolder(
                in: space.id,
                feedURLString: feedURLString
            )
        }
    }

    func editRSSLiveFolder(_ folderId: UUID, in windowState: BrowserWindowState) {
        guard let source = liveFolderManager.source(for: folderId),
              source.kind == .rss,
              let feedURLString = promptForLiveFolderFeedURL(
                  in: windowState,
                  initialValue: source.urlString,
                  title: "RSS Feed URL"
              ) else {
            return
        }
        liveFolderManager.setRSSFeedURL(
            folderId: folderId,
            urlString: feedURLString
        )
    }

    func createGitHubPRFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        liveFolderManager.createGitHubFolder(in: space.id, kind: .githubPullRequests)
    }

    func createGitHubIssuesFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        liveFolderManager.createGitHubFolder(in: space.id, kind: .githubIssues)
    }

    private func promptForLiveFolderFeedURL(
        in windowState: BrowserWindowState,
        initialValue: String,
        title: String
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter an RSS or Atom feed URL."
        alert.alertStyle = .informational
        alert.addButton(withTitle: initialValue.isEmpty ? "Create" : "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://example.com/feed.xml"
        field.stringValue = initialValue
        alert.accessoryView = field
        alert.sumiApplyNativeSurfaceAppearance(
            windowState: windowState,
            settings: settings.settings
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
