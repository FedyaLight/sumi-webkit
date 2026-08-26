import AppKit
import Combine
import Foundation
import SumiDomain

@MainActor
struct BookmarksPageBrowserContext {
    let bookmarkManager: SumiBookmarkManager
    let faviconService: any BrowserFaviconServicing
    let faviconImageReader: any BrowserFaviconImageReading
    let currentProfile: () -> Profile?
    let currentProfileUpdates: AnyPublisher<Profile?, Never>
    let currentTab: (BrowserWindowState) -> Tab?
    let openHistoryURLsInNewTabs: ([URL], BrowserWindowState) -> Void
    let openHistoryURLsInNewWindow: ([URL]) -> Void
    let openBookmarkURL: (URL, BrowserWindowState, HistoryOpenMode) -> Void
    let scheduleRuntimeStatePersistence: (Tab) -> Void
    let sumiSettings: () -> SumiSettingsService?
}

/// Prepares the bookmark tree for the AppKit outline view and owns bookmark
/// mutations. Selection, expansion, and drag state belong to NSOutlineView.
@MainActor
final class SumiBookmarksPageViewModel: ObservableObject {
    var searchText = "" {
        didSet { rebuildOutline() }
    }
    @Published var sortMode: SumiBookmarkSortMode = .manual {
        didSet { rebuildOutline() }
    }
    @Published private(set) var outlineRoots: [SumiBookmarkEntity] = []
    private(set) var statusMessage: String?

    let initiallySelectedFolderID: String?

    private weak var windowState: BrowserWindowState?
    private let browserContext: BookmarksPageBrowserContext
    private let bookmarkManager: SumiBookmarkManager
    private let faviconService: any BrowserFaviconServicing
    private var publicationCancellable: AnyCancellable?
    private var currentProfileCancellable: AnyCancellable?

    init(
        browserContext: BookmarksPageBrowserContext,
        windowState: BrowserWindowState?
    ) {
        self.windowState = windowState
        self.browserContext = browserContext
        self.bookmarkManager = browserContext.bookmarkManager
        self.faviconService = browserContext.faviconService
        self.initiallySelectedFolderID = windowState
            .flatMap { browserContext.currentTab($0) }
            .flatMap { SumiSurface.bookmarksSelectedFolderID(from: $0.url) }

        publicationCancellable = bookmarkManager.$publicationRevision
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebuildOutline()
            }
        currentProfileCancellable = browserContext.currentProfileUpdates
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebuildOutline()
            }
        rebuildOutline()
    }

    isolated deinit {
        publicationCancellable?.cancel()
        currentProfileCancellable?.cancel()
    }

    var faviconPartition: SumiFaviconPartition {
        faviconService.partition(profile: browserContext.currentProfile())
    }

    var faviconImageReader: any BrowserFaviconImageReading {
        browserContext.faviconImageReader
    }

    var canDragAndDrop: Bool {
        sortMode.allowsManualMove
            && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func appear() {
        rebuildOutline()
    }

    func openFromRow(
        _ entity: SumiBookmarkEntity,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) {
        open(
            entity,
            mode: .libraryDefault(
                modifiers: modifiers,
                openInNewTab: browserContext.sumiSettings()?.openBookmarksAndHistoryInNewTab == true
            )
        )
    }

    func open(_ entity: SumiBookmarkEntity, mode: HistoryOpenMode) {
        guard let windowState else { return }
        if entity.isFolder {
            let urls = bookmarkManager.openableURLs(for: [entity.id])
            switch mode {
            case .currentTab, .newTab:
                browserContext.openHistoryURLsInNewTabs(urls, windowState)
            case .newWindow:
                browserContext.openHistoryURLsInNewWindow(urls)
            }
            return
        }

        guard let url = entity.url else { return }
        browserContext.openBookmarkURL(url, windowState, mode)
    }

    func open(_ entities: [SumiBookmarkEntity]) {
        guard let windowState else { return }
        let ids = entities.map(\.id)
        let urls = bookmarkManager.openableURLs(for: ids)
        browserContext.openHistoryURLsInNewTabs(urls, windowState)
    }

    func copyLink(_ entity: SumiBookmarkEntity) {
        guard let url = entity.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func delete(_ entities: [SumiBookmarkEntity]) {
        let ids = Set(entities.map(\.id))
        guard !ids.isEmpty,
              !ids.contains(where: SumiBookmarkConstants.isProtectedFolderID)
        else { return }

        let alert = NSAlert()
        alert.messageText = ids.count > 1 ? "Delete Bookmark Items?" : "Delete Bookmark Item?"
        alert.informativeText = "This permanently removes the selected bookmarks and folders."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.sumiApplyNativeSurfaceAppearance(
            windowState: windowState,
            settings: browserContext.sumiSettings()
        )
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try bookmarkManager.removeEntities(ids: ids)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateBookmark(
        id: String,
        title: String,
        urlString: String,
        parentID: String?
    ) -> Bool {
        do {
            guard let url = URL(
                string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            ) else {
                throw SumiBookmarkError.invalidURL
            }
            _ = try bookmarkManager.updateBookmark(
                id: id,
                title: title,
                url: url,
                folderID: parentID
            )
            statusMessage = nil
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func createFolder(title: String, parentID: String?) -> SumiBookmarkEntity? {
        do {
            let folder = try bookmarkManager.createFolder(title: title, parentID: parentID)
            statusMessage = nil
            return folder
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func rename(_ entity: SumiBookmarkEntity, title: String) -> Bool {
        if entity.isFolder {
            return updateFolder(
                id: entity.id,
                title: title,
                parentID: entity.parentID
            )
        }
        guard let url = entity.url else { return false }
        return updateBookmark(
            id: entity.id,
            title: title,
            urlString: url.absoluteString,
            parentID: entity.parentID
        )
    }

    func updateAddress(_ entity: SumiBookmarkEntity, urlString: String) -> Bool {
        guard entity.isBookmark else { return false }
        return updateBookmark(
            id: entity.id,
            title: entity.title,
            urlString: urlString,
            parentID: entity.parentID
        )
    }

    func updateFolder(id: String, title: String, parentID: String?) -> Bool {
        do {
            _ = try bookmarkManager.updateFolder(id: id, title: title, parentID: parentID)
            statusMessage = nil
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func moveEntities(ids: [String], toParentID parentID: String, at index: Int?) -> Bool {
        guard canDragAndDrop, !ids.isEmpty else { return false }
        do {
            try bookmarkManager.moveEntities(ids: ids, toParentID: parentID, atIndex: index)
            statusMessage = nil
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func rebuildOutline() {
        let snapshot = bookmarkManager.snapshot(sortMode: sortMode)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            outlineRoots = snapshot.root.children
        } else {
            outlineRoots = flattenedDescendants(of: snapshot.root)
                .filter { $0.matchesSearch(query) }
                .map { entity in
                    var result = entity
                    result.children = []
                    return result
                }
        }
    }

    private func flattenedDescendants(
        of entity: SumiBookmarkEntity
    ) -> [SumiBookmarkEntity] {
        entity.children.flatMap { child in
            [child] + flattenedDescendants(of: child)
        }
    }

}
