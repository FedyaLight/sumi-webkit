import Foundation

@MainActor
final class BrowserSidebarFolderCommandOwner {
    struct Dependencies {
        let spaceForSidebarActions: @MainActor (BrowserWindowState) -> Space?
        let createFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Void
        let createRSSLiveFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Void
        let createGitHubPRFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Void
        let createGitHubIssuesFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func canCreateFolderInCurrentSpace(in windowState: BrowserWindowState) -> Bool {
        dependencies.spaceForSidebarActions(windowState) != nil
    }

    func createFolderInCurrentSpace(in windowState: BrowserWindowState) {
        dependencies.createFolderInCurrentSpace(windowState)
    }

    func createRSSLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        dependencies.createRSSLiveFolderInCurrentSpace(windowState)
    }

    func createGitHubPRFolderInCurrentSpace(in windowState: BrowserWindowState) {
        dependencies.createGitHubPRFolderInCurrentSpace(windowState)
    }

    func createGitHubIssuesFolderInCurrentSpace(in windowState: BrowserWindowState) {
        dependencies.createGitHubIssuesFolderInCurrentSpace(windowState)
    }
}

extension BrowserSidebarFolderCommandOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            spaceForSidebarActions: { [weak browserManager] windowState in
                browserManager?.spaceForSidebarActions(in: windowState)
            },
            createFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.createFolderInCurrentSpace(in: windowState)
            },
            createRSSLiveFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.createRSSLiveFolderInCurrentSpace(in: windowState)
            },
            createGitHubPRFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.createGitHubPRFolderInCurrentSpace(in: windowState)
            },
            createGitHubIssuesFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.createGitHubIssuesFolderInCurrentSpace(in: windowState)
            }
        )
    }
}
