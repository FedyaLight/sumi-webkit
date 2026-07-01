import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
struct BookmarksPageBrowserContext {
    let bookmarkManager: SumiBookmarkManager
    let faviconService: any BrowserFaviconServicing
    let currentProfile: () -> Profile?
    let currentProfileUpdates: AnyPublisher<Profile?, Never>
    let currentTab: (BrowserWindowState) -> Tab?
    let openHistoryURLsInNewTabs: ([URL], BrowserWindowState) -> Void
    let openHistoryURLsInNewWindow: ([URL]) -> Void
    let openBookmarkURL: (URL, BrowserWindowState, HistoryOpenMode) -> Void
    let importBookmarksFromMenu: () -> Void
    let exportBookmarksFromMenu: () -> Void
    let scheduleRuntimeStatePersistence: (Tab) -> Void
}

@MainActor
final class SumiBookmarksPageViewModel: ObservableObject {
    @Published var selectedFolderID: String
    @Published var searchText = "" {
        didSet { rebuildVisibleEntities() }
    }
    @Published var sortMode: SumiBookmarkSortMode = .manual {
        didSet { rebuildVisibleEntities() }
    }
    @Published private(set) var folders: [SumiBookmarkFolder] = []
    @Published private(set) var visibleEntities: [SumiBookmarkEntity] = []
    @Published private(set) var selectedEntityIDs: Set<String> = []
    @Published var statusMessage: String?

    private weak var windowState: BrowserWindowState?
    private let browserContext: BookmarksPageBrowserContext
    private let bookmarkManager: SumiBookmarkManager
    private let faviconService: any BrowserFaviconServicing
    private var revisionCancellable: AnyCancellable?
    private var currentProfileCancellable: AnyCancellable?
    private(set) var draggedEntityIDs: Set<String> = []

    init(
        browserContext: BookmarksPageBrowserContext,
        windowState: BrowserWindowState?
    ) {
        self.windowState = windowState
        self.browserContext = browserContext
        self.bookmarkManager = browserContext.bookmarkManager
        self.faviconService = browserContext.faviconService
        let selected = windowState
            .flatMap { browserContext.currentTab($0) }
            .flatMap { SumiSurface.bookmarksSelectedFolderID(from: $0.url) }
        self.selectedFolderID = selected ?? SumiBookmarkConstants.rootFolderID

        revisionCancellable = bookmarkManager.$revision
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildVisibleEntities()
                }
            }
        currentProfileCancellable = browserContext.currentProfileUpdates
            .dropFirst()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        rebuildVisibleEntities()
    }

    isolated deinit {
        revisionCancellable?.cancel()
        currentProfileCancellable?.cancel()
    }

    var hasSelection: Bool {
        !selectedEntityIDs.isEmpty
    }

    var faviconPartition: SumiFaviconPartition {
        faviconService.partition(profile: browserContext.currentProfile())
    }

    var selectionCount: Int {
        selectedEntityIDs.count
    }

    var canDeleteSelection: Bool {
        selectedEntityIDs.contains(SumiBookmarkConstants.rootFolderID) == false && !selectedEntityIDs.isEmpty
    }

    var canDragAndDrop: Bool {
        sortMode.allowsManualMove && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func appear() {
        rebuildVisibleEntities()
    }

    func selectFolder(_ folderID: String) {
        selectedFolderID = folderID
        selectedEntityIDs.removeAll()
        syncSelectedFolderToActiveTab()
        rebuildVisibleEntities()
    }

    func showInFolder(_ entity: SumiBookmarkEntity) {
        guard let parentID = entity.parentID else { return }
        searchText = ""
        selectFolder(parentID)
        selectedEntityIDs = [entity.id]
    }

    func handleRowClick(_ entity: SumiBookmarkEntity, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        if modifiers.contains(.command) {
            if selectedEntityIDs.contains(entity.id) {
                selectedEntityIDs.remove(entity.id)
            } else {
                selectedEntityIDs.insert(entity.id)
            }
            return
        }
        selectedEntityIDs = [entity.id]
    }

    func clearSelection() {
        selectedEntityIDs.removeAll()
    }

    func openFromRow(_ entity: SumiBookmarkEntity, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        if entity.isFolder {
            selectFolder(entity.id)
            return
        }
        let mode: HistoryOpenMode = modifiers.contains(.command) ? .newTab : .currentTab
        open(entity, mode: mode)
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

    func openSelected() {
        guard let windowState else { return }
        browserContext.openHistoryURLsInNewTabs(
            bookmarkManager.openableURLs(for: selectedEntityIDs),
            windowState
        )
    }

    func copyLink(_ entity: SumiBookmarkEntity) {
        guard let url = entity.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func deleteSelected() {
        guard canDeleteSelection else { return }
        delete(ids: selectedEntityIDs)
    }

    func delete(_ entity: SumiBookmarkEntity) {
        delete(ids: [entity.id])
    }

    func createBookmark(title: String, urlString: String, parentID: String?) {
        do {
            guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw SumiBookmarkError.invalidURL
            }
            _ = try bookmarkManager.createBookmark(url: url, title: title, folderID: parentID)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateBookmark(id: String, title: String, urlString: String, parentID: String?) {
        do {
            guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw SumiBookmarkError.invalidURL
            }
            _ = try bookmarkManager.updateBookmark(id: id, title: title, url: url, folderID: parentID)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createFolder(title: String, parentID: String?) {
        do {
            _ = try bookmarkManager.createFolder(title: title, parentID: parentID)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateFolder(id: String, title: String, parentID: String?) {
        do {
            _ = try bookmarkManager.updateFolder(id: id, title: title, parentID: parentID)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func beginDragging(_ entity: SumiBookmarkEntity) {
        if selectedEntityIDs.contains(entity.id) {
            draggedEntityIDs = selectedEntityIDs
        } else {
            draggedEntityIDs = [entity.id]
            selectedEntityIDs = [entity.id]
        }
    }

    func dropDraggedItems(toParentID parentID: String, at index: Int? = nil) -> Bool {
        guard canDragAndDrop, !draggedEntityIDs.isEmpty else { return false }
        do {
            let orderedIDs = visibleEntities
                .map(\.id)
                .filter { draggedEntityIDs.contains($0) }
            try bookmarkManager.moveEntities(
                ids: orderedIDs.isEmpty ? Array(draggedEntityIDs) : orderedIDs,
                toParentID: parentID,
                atIndex: index
            )
            draggedEntityIDs.removeAll()
            return true
        } catch {
            statusMessage = error.localizedDescription
            draggedEntityIDs.removeAll()
            return false
        }
    }

    func bookmarkDraft(for entity: SumiBookmarkEntity? = nil) -> SumiBookmarkFormDraft {
        if let entity, let url = entity.url {
            return SumiBookmarkFormDraft(
                editingID: entity.id,
                title: entity.title,
                urlString: url.absoluteString,
                parentID: entity.parentID ?? selectedFolderID
            )
        }
        return SumiBookmarkFormDraft(
            editingID: nil,
            title: "",
            urlString: "https://",
            parentID: selectedFolderID
        )
    }

    func folderDraft(for entity: SumiBookmarkEntity? = nil) -> SumiFolderFormDraft {
        if let entity {
            return SumiFolderFormDraft(
                editingID: entity.id,
                title: entity.title,
                parentID: entity.parentID ?? SumiBookmarkConstants.rootFolderID
            )
        }
        return SumiFolderFormDraft(
            editingID: nil,
            title: "",
            parentID: selectedFolderID
        )
    }

    func folderPickerFolders(excluding folderID: String? = nil) -> [SumiBookmarkFolder] {
        guard let folderID else { return folders }
        let excludedPrefix = Set(descendantFolderIDs(of: folderID) + [folderID])
        return folders.filter { !excludedPrefix.contains($0.id) }
    }

    func folderDraft(forFolderID folderID: String) -> SumiFolderFormDraft? {
        bookmarkManager.entity(id: folderID).map { folderDraft(for: $0) }
    }

    func deleteFolder(id folderID: String) {
        guard let entity = bookmarkManager.entity(id: folderID) else { return }
        delete(entity)
    }

    func importBookmarksFromMenu() {
        browserContext.importBookmarksFromMenu()
    }

    func exportBookmarksFromMenu() {
        browserContext.exportBookmarksFromMenu()
    }

    private func delete(ids: Set<String>) {
        let alert = NSAlert()
        alert.messageText = ids.count > 1 ? "Delete Bookmarks" : "Delete Bookmark"
        alert.informativeText = "This will permanently remove the selected bookmark items."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try bookmarkManager.removeEntities(ids: ids)
            selectedEntityIDs.removeAll()
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func rebuildVisibleEntities() {
        let snapshot = bookmarkManager.snapshot(sortMode: sortMode)
        folders = snapshot.flattenedFolders
        if !folders.contains(where: { $0.id == selectedFolderID }) {
            selectedFolderID = SumiBookmarkConstants.rootFolderID
        }
        visibleEntities = bookmarkManager.visibleEntities(
            in: selectedFolderID,
            query: searchText,
            sortMode: sortMode
        )
        selectedEntityIDs = selectedEntityIDs.intersection(Set(visibleEntities.map(\.id)))
    }

    private func syncSelectedFolderToActiveTab() {
        guard let windowState,
              let tab = browserContext.currentTab(windowState),
              tab.representsSumiBookmarksSurface
        else { return }
        tab.url = SumiSurface.bookmarksSurfaceURL(selecting: selectedFolderID)
        tab.name = "Bookmarks"
        tab.favicon = Image(systemName: SumiSurface.bookmarksTabFaviconSystemImageName)
        tab.faviconIsTemplateGlobePlaceholder = false
        browserContext.scheduleRuntimeStatePersistence(tab)
    }

    private func descendantFolderIDs(of folderID: String) -> [String] {
        guard let entity = bookmarkManager.entity(id: folderID) else { return [] }
        return entity.children.flatMap { child -> [String] in
            guard child.isFolder else { return [] }
            return [child.id] + descendantFolderIDs(of: child.id)
        }
    }
}

enum SumiBookmarkConstants {
    static let rootFolderID = "bookmarks_root"
}

struct SumiBookmarkFormDraft: Identifiable, Equatable {
    let id = UUID()
    var editingID: String?
    var title: String
    var urlString: String
    var parentID: String
}

struct SumiFolderFormDraft: Identifiable, Equatable {
    let id = UUID()
    var editingID: String?
    var title: String
    var parentID: String
}
