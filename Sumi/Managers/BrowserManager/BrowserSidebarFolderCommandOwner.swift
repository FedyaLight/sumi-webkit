import Foundation

@MainActor
final class BrowserSidebarFolderCommandOwner {
    private let spaceForSidebarActions: @MainActor (BrowserWindowState) -> Space?
    private let createFolderInCurrentSpaceAction: @MainActor (BrowserWindowState) -> Void
    private let createRSSLiveFolderInCurrentSpaceAction: @MainActor (BrowserWindowState) -> Void
    private let createGitHubPRFolderInCurrentSpaceAction: @MainActor (BrowserWindowState) -> Void
    private let createGitHubIssuesFolderInCurrentSpaceAction: @MainActor (BrowserWindowState) -> Void

    init(
        spaceForSidebarActions: @escaping @MainActor (BrowserWindowState) -> Space?,
        createFolderInCurrentSpace: @escaping @MainActor (BrowserWindowState) -> Void,
        createRSSLiveFolderInCurrentSpace: @escaping @MainActor (BrowserWindowState) -> Void,
        createGitHubPRFolderInCurrentSpace: @escaping @MainActor (BrowserWindowState) -> Void,
        createGitHubIssuesFolderInCurrentSpace: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.spaceForSidebarActions = spaceForSidebarActions
        self.createFolderInCurrentSpaceAction = createFolderInCurrentSpace
        self.createRSSLiveFolderInCurrentSpaceAction = createRSSLiveFolderInCurrentSpace
        self.createGitHubPRFolderInCurrentSpaceAction = createGitHubPRFolderInCurrentSpace
        self.createGitHubIssuesFolderInCurrentSpaceAction = createGitHubIssuesFolderInCurrentSpace
    }

    func canCreateFolderInCurrentSpace(in windowState: BrowserWindowState) -> Bool {
        spaceForSidebarActions(windowState) != nil
    }

    func createFolderInCurrentSpace(in windowState: BrowserWindowState) {
        createFolderInCurrentSpaceAction(windowState)
    }

    func createRSSLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        createRSSLiveFolderInCurrentSpaceAction(windowState)
    }

    func createGitHubPRFolderInCurrentSpace(in windowState: BrowserWindowState) {
        createGitHubPRFolderInCurrentSpaceAction(windowState)
    }

    func createGitHubIssuesFolderInCurrentSpace(in windowState: BrowserWindowState) {
        createGitHubIssuesFolderInCurrentSpaceAction(windowState)
    }
}
