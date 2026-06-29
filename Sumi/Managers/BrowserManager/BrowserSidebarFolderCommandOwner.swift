import Foundation

@MainActor
final class BrowserSidebarFolderCommandOwner {
    struct Dependencies {
        let spaceForSidebarActions: @MainActor (BrowserWindowState) -> Space?
        let createFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Void
        let createRSSLiveFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Void
        let createGitHubPullRequestsLiveFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Void
        let createGitHubIssuesLiveFolderInCurrentSpace: @MainActor (BrowserWindowState) -> Void
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

    func createGitHubPullRequestsLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        dependencies.createGitHubPullRequestsLiveFolderInCurrentSpace(windowState)
    }

    func createGitHubIssuesLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        dependencies.createGitHubIssuesLiveFolderInCurrentSpace(windowState)
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
            createGitHubPullRequestsLiveFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.createGitHubPullRequestsLiveFolderInCurrentSpace(in: windowState)
            },
            createGitHubIssuesLiveFolderInCurrentSpace: { [weak browserManager] windowState in
                browserManager?.createGitHubIssuesLiveFolderInCurrentSpace(in: windowState)
            }
        )
    }
}
