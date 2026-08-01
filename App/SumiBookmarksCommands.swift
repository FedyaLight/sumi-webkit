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
        cancellable = bookmarkManager.$publicationRevision
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.snapshot = self.bookmarkManager.snapshot(sortMode: .manual)
            }
    }
}

struct SumiBookmarksCommands: Commands {
    let browserContext: SumiCommandsBrowserContext
    @ObservedObject private var snapshotStore: SumiBookmarkMenuSnapshotStore
    @ObservedObject private var menuFaviconInvalidator: SumiMenuFaviconInvalidator

    init(
        browserContext: SumiCommandsBrowserContext,
        menuFaviconInvalidator: SumiMenuFaviconInvalidator
    ) {
        self.browserContext = browserContext
        let bookmarkManager = browserContext.bookmarkManager
        self.snapshotStore = SumiBookmarkMenuSnapshotStore(bookmarkManager: bookmarkManager)
        self._menuFaviconInvalidator = ObservedObject(wrappedValue: menuFaviconInvalidator)
    }

    private var bookmarkMenuSnapshot: SumiBookmarksSnapshot {
        snapshotStore.snapshot
    }

    private var bookmarkMenuFaviconPartition: SumiFaviconPartition {
        let _ = menuFaviconInvalidator.revision
        return browserContext.faviconPartition
    }

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Import Bookmarks…") {
                browserContext.importBookmarksFromMenu()
            }

            Button("Export Bookmarks…") {
                browserContext.exportBookmarksFromMenu()
            }
            .disabled(!bookmarkMenuSnapshot.hasBookmarks)
        }

        CommandMenu("Bookmarks") {
            let bookmarkSnapshot = bookmarkMenuSnapshot
            let faviconPartition = bookmarkMenuFaviconPartition

            Button("Show Bookmarks") {
                browserContext.manageBookmarksFromMenu()
            }
            .keyboardShortcut("b", modifiers: [.command, .option])

            Divider()

            Button("Add Bookmark…") {
                browserContext.requestBookmarkEditorForActiveWindowFromMenu()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!browserContext.canBookmarkActivePage)

            Button("Add Open Tabs to Bookmarks…") {
                browserContext.bookmarkAllTabsFromMenu()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(!browserContext.canBookmarkAllTabsInActiveWindow)

            Button("Add Bookmark Folder") {
                browserContext.createBookmarkFolderFromMenu()
            }

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
            let openableURLs = entity.openableURLs
            Menu {
                if entity.children.isEmpty {
                    Text("Folder Is Empty")
                        .disabled(true)
                } else {
                    SumiBookmarkCommandItems(
                        entities: entity.children,
                        browserContext: browserContext,
                        faviconPartition: faviconPartition
                    )
                }
                if !openableURLs.isEmpty {
                    Divider()
                    Button("Open in New Tabs") {
                        browserContext.openBookmarkURLsInNewTabsFromMenuItem(
                            openableURLs
                        )
                    }
                    Button("Replace Tabs") {
                        browserContext.replaceTabsWithBookmarkURLsFromMenuItem(
                            openableURLs
                        )
                    }
                }
            } label: {
                SumiCommandMenuLabels.system(
                    SumiCommandMenuLabels.bookmarkTitle(for: entity),
                    systemImage: entity.id == SumiBookmarkConstants.favoritesFolderID
                        ? "star"
                        : "folder"
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
                    partition: faviconPartition,
                    imageReader: browserContext.faviconImageReader
                )
            }
            .disabled(entity.url == nil)
        }
    }
}

private extension SumiBookmarkEntity {
    var openableURLs: [URL] {
        if let url { return [url] }
        return children.flatMap(\.openableURLs)
    }
}
