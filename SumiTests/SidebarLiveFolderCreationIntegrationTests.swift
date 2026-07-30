@testable import Sumi
import XCTest

final class SidebarLiveFolderCreationTests: XCTestCase {
    func testSidebarBackgroundMatchesZenLiveFolderCreationMenu() {
        let entries = makeSidebarShellContextMenuEntries(
            isCompactModeEnabled: true,
            actions: .init(
                newTab: Self.noop,
                newFolder: Self.noop,
                newRSSLiveFolder: Self.noop,
                newGitHubPullRequestsLiveFolder: Self.noop,
                newGitHubIssuesLiveFolder: Self.noop,
                changeTheme: Self.noop,
                toggleCompactMode: Self.noop,
                openSettings: Self.noop
            )
        )

        XCTAssertEqual(
            Self.snapshot(entries),
            [
                "New Tab",
                "New Folder",
                "> Live Folder",
                "  Pull Requests",
                "  Issues",
                "  RSS Feed",
                "---",
                "Change Theme",
                "Toggle Compact Mode",
                "Sidebar Settings…",
            ]
        )

        guard case let .submenu(_, systemImage, children) = entries[2] else {
            return XCTFail("Expected Live Folder submenu after New Folder")
        }
        XCTAssertNil(systemImage)
        XCTAssertEqual(
            children.compactMap(\.actionIcon),
            [
                .folderIcon(SumiZenFolderIconCatalog.storageValue(for: "logo-github")),
                .folderIcon(SumiZenFolderIconCatalog.storageValue(for: "logo-github")),
                .folderIcon(SumiZenFolderIconCatalog.storageValue(for: "logo-rss")),
            ]
        )
    }

    func testLiveFolderOptionsExtendTheNormalFolderMenuLikeZen() {
        let folderEntries = makeFolderHeaderContextMenuEntries(
            actions: .init(
                edit: Self.noop,
                alphabetize: Self.noop,
                unloadActiveTabs: Self.noop,
                ungroup: Self.noop,
                delete: Self.noop
            )
        )
        let entries = makeLiveFolderHeaderContextMenuEntries(
            options: [
                .action(.init(
                    title: "Refresh Now",
                    classification: .stateMutationNonStructural,
                    onAction: Self.noop
                )),
            ],
            folderEntries: folderEntries
        )

        XCTAssertEqual(
            Self.snapshot(entries),
            [
                "> Live Folder Options",
                "  Refresh Now",
                "---",
                "Edit",
                "---",
                "Sort by Name",
                "Unload Active Tabs in Folder",
                "---",
                "Ungroup Folder",
                "Delete Folder",
            ]
        )
    }

    private static func snapshot(
        _ entries: [SidebarContextMenuEntry],
        level: Int = 0
    ) -> [String] {
        let prefix = String(repeating: "  ", count: level)
        return entries.flatMap { entry in
            switch entry {
            case .separator:
                return ["\(prefix)---"]
            case let .action(action):
                return ["\(prefix)\(action.title)"]
            case let .submenu(title, _, children):
                return ["\(prefix)> \(title)"]
                    + snapshot(children, level: level + 1)
            }
        }
    }

    private static func noop() { /* no-op */ }
}

private extension SidebarContextMenuEntry {
    var actionIcon: SidebarContextMenuIcon? {
        guard case let .action(action) = self else { return nil }
        return action.icon
    }
}
