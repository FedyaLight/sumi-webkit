import Combine
import SwiftUI

@MainActor
final class SumiBookmarkMenuSnapshotStore: ObservableObject {
    @Published private(set) var snapshot: SumiBookmarksSnapshot

    private let bookmarkManager: SumiBookmarkManager
    private var cancellable: AnyCancellable?

    init(bookmarkManager: SumiBookmarkManager) {
        self.bookmarkManager = bookmarkManager
        self.snapshot = bookmarkManager.snapshot(sortMode: .manual)
        cancellable = bookmarkManager.$revision
            .sink { [weak self] _ in
                guard let self else { return }
                self.snapshot = self.bookmarkManager.snapshot(sortMode: .manual)
            }
    }
}

struct SumiBookmarksCommands: Commands {
    let browserManager: BrowserManager
    @ObservedObject private var bookmarkManager: SumiBookmarkManager
    @ObservedObject private var snapshotStore: SumiBookmarkMenuSnapshotStore
    @ObservedObject private var menuFaviconInvalidator = SumiMenuFaviconInvalidator.shared

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
        let bookmarkManager = browserManager.bookmarkManager
        self.bookmarkManager = bookmarkManager
        self.snapshotStore = SumiBookmarkMenuSnapshotStore(bookmarkManager: bookmarkManager)
    }

    var body: some Commands {
        CommandMenu("Bookmarks") {
            let _ = bookmarkManager.revision
            let _ = menuFaviconInvalidator.revision
            let bookmarkSnapshot = snapshotStore.snapshot

            Button("Bookmark This Page…") {
                browserManager.requestBookmarkEditorForActiveWindowFromMenu()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(
                !bookmarkManager.canBookmark(browserManager.currentTabForActiveWindow())
            )

            Button("Bookmark All Tabs…") {
                browserManager.bookmarkAllTabsFromMenu()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(!browserManager.canBookmarkAllTabsInActiveWindow())

            Button("Manage Bookmarks") {
                browserManager.manageBookmarksFromMenu()
            }
            .keyboardShortcut("b", modifiers: [.command, .option])

            Divider()

            Button("Import Bookmarks…") {
                browserManager.importBookmarksFromMenu()
            }

            Button("Export Bookmarks…") {
                browserManager.exportBookmarksFromMenu()
            }
            .disabled(!bookmarkSnapshot.hasBookmarks)

            Divider()

            let bookmarkChildren = bookmarkSnapshot.root.children
            if bookmarkChildren.isEmpty {
                Button("No Bookmarks") {}
                    .disabled(true)
            } else {
                SumiBookmarkCommandItems(
                    entities: bookmarkChildren,
                    browserManager: browserManager
                )
            }
        }
    }
}

private struct SumiBookmarkCommandItems: View {
    let entities: [SumiBookmarkEntity]
    let browserManager: BrowserManager

    var body: some View {
        ForEach(entities) { entity in
            SumiBookmarkCommandItem(
                entity: entity,
                browserManager: browserManager
            )
        }
    }
}

private struct SumiBookmarkCommandItem: View {
    let entity: SumiBookmarkEntity
    let browserManager: BrowserManager

    var body: some View {
        if entity.isFolder {
            Menu {
                if entity.children.isEmpty {
                    Button("Empty") {}
                        .disabled(true)
                } else {
                    SumiBookmarkCommandItems(
                        entities: entity.children,
                        browserManager: browserManager
                    )
                }
            } label: {
                SumiCommandMenuLabels.system(
                    SumiCommandMenuLabels.bookmarkTitle(for: entity),
                    systemImage: "folder"
                )
            }
        } else {
            Button {
                if let url = entity.url {
                    browserManager.openBookmarkURLFromMenuItem(url)
                }
            } label: {
                SumiCommandMenuLabels.site(
                    SumiCommandMenuLabels.bookmarkTitle(for: entity),
                    url: entity.url
                )
            }
            .disabled(entity.url == nil)
        }
    }
}
