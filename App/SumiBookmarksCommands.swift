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
    let browserContext: SumiCommandsBrowserContext
    @ObservedObject private var bookmarkManager: SumiBookmarkManager
    @ObservedObject private var snapshotStore: SumiBookmarkMenuSnapshotStore
    @ObservedObject private var menuFaviconInvalidator = SumiMenuFaviconInvalidator.shared

    init(
        browserContext: SumiCommandsBrowserContext
    ) {
        self.browserContext = browserContext
        let bookmarkManager = browserContext.bookmarkManager
        self.bookmarkManager = bookmarkManager
        self.snapshotStore = SumiBookmarkMenuSnapshotStore(bookmarkManager: bookmarkManager)
    }

    private var bookmarkMenuSnapshot: SumiBookmarksSnapshot {
        _ = bookmarkManager.revision
        return snapshotStore.snapshot
    }

    private var bookmarkMenuFaviconPartition: SumiFaviconPartition {
        _ = menuFaviconInvalidator.revision
        return browserContext.faviconPartition
    }

    var body: some Commands {
        CommandMenu("Bookmarks") {
            let bookmarkSnapshot = bookmarkMenuSnapshot
            let faviconPartition = bookmarkMenuFaviconPartition

            Button("Bookmark This Page…") {
                browserContext.requestBookmarkEditorForActiveWindowFromMenu()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!browserContext.canBookmarkActivePage)

            Button("Bookmark All Tabs…") {
                browserContext.bookmarkAllTabsFromMenu()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(!browserContext.canBookmarkAllTabsInActiveWindow)

            Button("Manage Bookmarks") {
                browserContext.manageBookmarksFromMenu()
            }
            .keyboardShortcut("b", modifiers: [.command, .option])

            Divider()

            Button("Import Bookmarks…") {
                browserContext.importBookmarksFromMenu()
            }

            Button("Export Bookmarks…") {
                browserContext.exportBookmarksFromMenu()
            }
            .disabled(!bookmarkSnapshot.hasBookmarks)

            Divider()

            let bookmarkChildren = bookmarkSnapshot.root.children
            if bookmarkChildren.isEmpty {
                Text("No Bookmarks")
                    .disabled(true)
            } else {
                SumiBookmarkCommandItems(
                    entities: bookmarkChildren,
                    browserContext: browserContext,
                    faviconPartition: faviconPartition
                )
            }
        }
    }
}

private struct SumiBookmarkCommandItems: View {
    let entities: [SumiBookmarkEntity]
    let browserContext: SumiCommandsBrowserContext
    let faviconPartition: SumiFaviconPartition

    var body: some View {
        ForEach(entities) { entity in
            SumiBookmarkCommandItem(
                entity: entity,
                browserContext: browserContext,
                faviconPartition: faviconPartition
            )
        }
    }
}

private struct SumiBookmarkCommandItem: View {
    let entity: SumiBookmarkEntity
    let browserContext: SumiCommandsBrowserContext
    let faviconPartition: SumiFaviconPartition

    var body: some View {
        if entity.isFolder {
            Menu {
                if entity.children.isEmpty {
                    Text("Empty")
                        .disabled(true)
                } else {
                    SumiBookmarkCommandItems(
                        entities: entity.children,
                        browserContext: browserContext,
                        faviconPartition: faviconPartition
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
                    browserContext.openBookmarkURLFromMenuItem(url)
                }
            } label: {
                SumiCommandMenuLabels.site(
                    SumiCommandMenuLabels.bookmarkTitle(for: entity),
                    url: entity.url,
                    partition: faviconPartition
                )
            }
            .disabled(entity.url == nil)
        }
    }
}
