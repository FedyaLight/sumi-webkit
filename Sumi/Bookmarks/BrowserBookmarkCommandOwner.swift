import AppKit
import Foundation
import UniformTypeIdentifiers

struct BrowserBookmarkAllTabsPrompt: Equatable {
    var folderTitle: String
    var parentID: String?
}

enum BrowserBookmarkImportSelection: Equatable {
    case htmlFile
    case source(SumiBookmarkImportSource)
}

enum BrowserBookmarkCommandOwnerError: LocalizedError {
    case bookmarkManagerUnavailable

    var errorDescription: String? {
        switch self {
        case .bookmarkManagerUnavailable:
            return "Bookmarks are unavailable."
        }
    }
}

@MainActor
protocol BrowserBookmarkCommandPresenting: AnyObject {
    func promptBookmarkAllTabs(
        defaultTitle: String,
        folders: [SumiBookmarkFolder]
    ) -> BrowserBookmarkAllTabsPrompt?
    func promptImportSource(
        detectedSources: [SumiBookmarkImportSource]
    ) -> BrowserBookmarkImportSelection?
    func promptHTMLImportFile() -> URL?
    func promptUnreadableSafariBookmarksReplacement(
        source: SumiBookmarkImportSource,
        originalError: Error
    ) -> URL?
    func promptExportDestination(defaultFileName: String) -> URL?
    func showBookmarkResultAlert(title: String, message: String)
}

final class BrowserBookmarkCommandOwner {
    private typealias NewWindowRegistrationAwaiter = @MainActor () async -> BrowserWindowState?

    struct Dependencies {
        let activeWindow: @MainActor @Sendable () -> BrowserWindowState?
        let activePageTab: @MainActor @Sendable (BrowserWindowState) -> Tab?
        let bookmarkManager: @MainActor @Sendable () -> SumiBookmarkManager?
        let bookmarkEditorPresentationRequest: @MainActor @Sendable () -> SumiBookmarkEditorPresentationRequest?
        let setBookmarkEditorPresentationRequest: @MainActor @Sendable (SumiBookmarkEditorPresentationRequest?) -> Void
        let openNativeBrowserSurface: @MainActor @Sendable (
            SumiNativeBrowserSurfaceKind,
            URL,
            BrowserWindowState,
            UUID?
        ) -> Void
        let openHistoryURL: @MainActor @Sendable (
            URL,
            BrowserWindowState,
            BrowserManager.HistoryOpenMode
        ) -> Void
        let openHistoryURLsInNewWindow: @MainActor @Sendable ([URL]) -> Void
        let windowIds: @MainActor @Sendable () -> [UUID]
        let createNewWindow: @MainActor @Sendable () -> Void
        let awaitNextRegisteredWindow: @MainActor @Sendable (Set<UUID>) async -> BrowserWindowState?
        let space: @MainActor @Sendable (UUID?) -> Space?
        let tabsInSpace: @MainActor @Sendable (Space) -> [Tab]
        let allTabs: @MainActor @Sendable () -> [Tab]
        let detectedImportSources: @MainActor @Sendable () -> [SumiBookmarkImportSource]
        let readBookmarks: @MainActor @Sendable (SumiBookmarkImportSource) throws -> [SumiBookmarkImportNode]
        let date: @MainActor @Sendable () -> Date
    }

    private let dependencies: Dependencies
    private let presenter: any BrowserBookmarkCommandPresenting

    init(
        dependencies: Dependencies,
        presenter: any BrowserBookmarkCommandPresenting
    ) {
        self.dependencies = dependencies
        self.presenter = presenter
    }

    @MainActor
    func requestBookmarkEditorForActiveWindowFromMenu() {
        guard let bookmarkManager = dependencies.bookmarkManager(),
              let windowState = dependencies.activeWindow(),
              let tab = dependencies.activePageTab(windowState),
              bookmarkManager.canBookmark(tab)
        else {
            return
        }

        dependencies.setBookmarkEditorPresentationRequest(
            SumiBookmarkEditorPresentationRequest(
                windowID: windowState.id,
                tabID: tab.id
            )
        )
    }

    @MainActor
    func clearBookmarkEditorPresentationRequest(_ request: SumiBookmarkEditorPresentationRequest) {
        guard dependencies.bookmarkEditorPresentationRequest()?.id == request.id else { return }
        dependencies.setBookmarkEditorPresentationRequest(nil)
    }

    @MainActor
    func openBookmarksTab(
        selecting folderID: String? = nil,
        in windowState: BrowserWindowState? = nil
    ) {
        if let targetWindow = windowState ?? dependencies.activeWindow() {
            openBookmarksTab(inResolvedWindow: targetWindow, selecting: folderID)
            return
        }

        let awaitNewWindow = createNewWindowRegistrationAwaiter()
        Task { @MainActor [weak self] in
            guard let self,
                  let targetWindow = await awaitNewWindow()
            else {
                return
            }
            self.openBookmarksTab(inResolvedWindow: targetWindow, selecting: folderID)
        }
    }

    @MainActor
    func openBookmarkURLFromMenuItem(_ url: URL) {
        if let activeWindow = dependencies.activeWindow() {
            openBookmarkURL(url, in: activeWindow, preferredOpenMode: .currentTab)
        } else {
            dependencies.openHistoryURLsInNewWindow([url])
        }
    }

    @MainActor
    func openBookmarkURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        preferredOpenMode: BrowserManager.HistoryOpenMode
    ) {
        dependencies.openHistoryURL(url, windowState, preferredOpenMode)
    }

    @MainActor
    func manageBookmarksFromMenu() {
        openBookmarksTab()
    }

    @MainActor
    func canBookmarkAllTabsInActiveWindow() -> Bool {
        bookmarkableRegularTabsForActiveWindow().isEmpty == false
    }

    @MainActor
    func bookmarkAllTabsFromMenu() {
        guard let activeWindow = dependencies.activeWindow(),
              let bookmarkManager = dependencies.bookmarkManager()
        else {
            return
        }

        let allRegularTabs = regularTabs(in: activeWindow)
        let bookmarkableTabs = allRegularTabs.filter { bookmarkManager.canBookmark($0) }
        guard !bookmarkableTabs.isEmpty else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let defaultTitle = "Bookmarked Tabs \(dateFormatter.string(from: dependencies.date()))"

        guard let prompt = presenter.promptBookmarkAllTabs(
            defaultTitle: defaultTitle,
            folders: bookmarkManager.folders()
        ) else {
            return
        }

        do {
            let result = try bookmarkTabs(
                allRegularTabs,
                folderTitle: prompt.folderTitle,
                parentID: prompt.parentID
            )
            presenter.showBookmarkResultAlert(
                title: "Tabs Bookmarked",
                message: "\(result.created) added to “\(result.folderTitle)”. \(result.duplicates) duplicates skipped. \(result.skipped) unsupported tabs ignored."
            )
        } catch {
            presenter.showBookmarkResultAlert(title: "Bookmark All Tabs Failed", message: error.localizedDescription)
        }
    }

    @MainActor
    func bookmarkTabs(
        _ tabs: [Tab],
        folderTitle: String,
        parentID: String?
    ) throws -> SumiBookmarkAllTabsResult {
        guard let bookmarkManager = dependencies.bookmarkManager() else {
            throw BrowserBookmarkCommandOwnerError.bookmarkManagerUnavailable
        }

        var bookmarkRequests: [SumiBookmarkCreateRequest] = []
        bookmarkRequests.reserveCapacity(tabs.count)
        var skipped = 0

        for tab in tabs {
            guard bookmarkManager.canBookmark(tab) else {
                skipped += 1
                continue
            }
            bookmarkRequests.append(
                SumiBookmarkCreateRequest(
                    url: tab.url,
                    title: tab.name
                )
            )
        }

        let result = try bookmarkManager.createFolderWithBookmarks(
            title: folderTitle,
            parentID: parentID,
            bookmarks: bookmarkRequests
        )

        return SumiBookmarkAllTabsResult(
            created: result.bookmarks.count,
            duplicates: result.duplicates,
            skipped: skipped,
            folderTitle: result.folder.title
        )
    }

    @MainActor
    func importBookmarksFromMenu() {
        let detectedSources = dependencies.detectedImportSources()
        guard !detectedSources.isEmpty else {
            importBookmarksFromHTMLFile()
            return
        }

        guard let selection = presenter.promptImportSource(detectedSources: detectedSources) else { return }
        switch selection {
        case .htmlFile:
            importBookmarksFromHTMLFile()
        case .source(let source):
            importBookmarks(from: source)
        }
    }

    @MainActor
    func exportBookmarksFromMenu() {
        guard let bookmarkManager = dependencies.bookmarkManager(),
              let destination = presenter.promptExportDestination(defaultFileName: "Bookmarks.html")
        else {
            return
        }

        do {
            try bookmarkManager.exportBookmarksHTML(to: destination)
            presenter.showBookmarkResultAlert(
                title: "Bookmarks Exported",
                message: "Bookmarks were exported to \(destination.lastPathComponent)."
            )
        } catch {
            presenter.showBookmarkResultAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    @MainActor
    private func openBookmarksTab(
        inResolvedWindow targetWindow: BrowserWindowState,
        selecting folderID: String?
    ) {
        dependencies.openNativeBrowserSurface(
            .bookmarks,
            SumiSurface.bookmarksSurfaceURL(selecting: folderID),
            targetWindow,
            nil
        )
    }

    @MainActor
    private func bookmarkableRegularTabsForActiveWindow() -> [Tab] {
        guard let activeWindow = dependencies.activeWindow(),
              let bookmarkManager = dependencies.bookmarkManager()
        else {
            return []
        }
        return regularTabs(in: activeWindow).filter { bookmarkManager.canBookmark($0) }
    }

    @MainActor
    private func regularTabs(in windowState: BrowserWindowState) -> [Tab] {
        guard !windowState.isIncognito else { return [] }
        if let currentSpace = dependencies.space(windowState.currentSpaceId) {
            return dependencies.tabsInSpace(currentSpace)
        }
        return dependencies.allTabs()
    }

    @MainActor
    private func importBookmarksFromHTMLFile() {
        guard let fileURL = presenter.promptHTMLImportFile() else { return }
        importBookmarks(
            from: SumiBookmarkImportSource(
                id: "html-\(fileURL.path)",
                title: fileURL.lastPathComponent,
                fileURL: fileURL,
                kind: .html
            )
        )
    }

    @MainActor
    private func importBookmarks(from source: SumiBookmarkImportSource) {
        guard let bookmarkManager = dependencies.bookmarkManager() else {
            presenter.showBookmarkResultAlert(
                title: "Import Failed",
                message: BrowserBookmarkCommandOwnerError.bookmarkManagerUnavailable.localizedDescription
            )
            return
        }

        do {
            let nodes = try dependencies.readBookmarks(source)
            let summary = try bookmarkManager.importBookmarks(nodes)
            presenter.showBookmarkResultAlert(
                title: "Bookmarks Imported",
                message: "\(source.title): \(summary.message)"
            )
        } catch {
            if source.kind == .safariPlist {
                importUnreadableSafariBookmarks(source: source, originalError: error)
            } else {
                presenter.showBookmarkResultAlert(title: "Import Failed", message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func importUnreadableSafariBookmarks(
        source: SumiBookmarkImportSource,
        originalError: Error
    ) {
        guard let fileURL = presenter.promptUnreadableSafariBookmarksReplacement(
            source: source,
            originalError: originalError
        ) else {
            presenter.showBookmarkResultAlert(title: "Import Failed", message: originalError.localizedDescription)
            return
        }

        let replacement = SumiBookmarkImportSource(
            id: "\(source.id)-manual",
            title: source.title,
            fileURL: fileURL,
            kind: source.kind
        )
        importBookmarks(from: replacement)
    }

    @MainActor
    private func createNewWindowRegistrationAwaiter() -> NewWindowRegistrationAwaiter {
        let existingWindowIDs = Set(dependencies.windowIds())
        dependencies.createNewWindow()

        return { [dependencies] in
            await dependencies.awaitNextRegisteredWindow(existingWindowIDs)
        }
    }
}

extension BrowserBookmarkCommandOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            activeWindow: { [weak browserManager] in browserManager?.windowRegistry?.activeWindow },
            activePageTab: { [weak browserManager] windowState in
                browserManager?.activePageTab(for: windowState)
            },
            bookmarkManager: { [weak browserManager] in browserManager?.bookmarkManager },
            bookmarkEditorPresentationRequest: { [weak browserManager] in
                browserManager?.bookmarkEditorPresentationRequest
            },
            setBookmarkEditorPresentationRequest: { [weak browserManager] request in
                browserManager?.bookmarkEditorPresentationRequest = request
            },
            openNativeBrowserSurface: { [weak browserManager] kind, url, windowState, preferredSpaceId in
                browserManager?.openNativeBrowserSurface(
                    kind,
                    url: url,
                    in: windowState,
                    preferredSpaceId: preferredSpaceId
                )
            },
            openHistoryURL: { [weak browserManager] url, windowState, preferredOpenMode in
                browserManager?.openHistoryURL(
                    url,
                    in: windowState,
                    preferredOpenMode: preferredOpenMode
                )
            },
            openHistoryURLsInNewWindow: { [weak browserManager] urls in
                browserManager?.openHistoryURLsInNewWindow(urls)
            },
            windowIds: { [weak browserManager] in
                browserManager?.windowRegistry.map { Array($0.windows.keys) } ?? []
            },
            createNewWindow: { [weak browserManager] in
                browserManager?.createNewWindow()
            },
            awaitNextRegisteredWindow: { [weak browserManager] existingWindowIDs in
                await browserManager?.windowRegistry?.awaitNextRegisteredWindow(
                    excluding: existingWindowIDs
                )
            },
            space: { [weak browserManager] spaceId in
                browserManager?.space(for: spaceId)
            },
            tabsInSpace: { [weak browserManager] space in
                browserManager?.tabManager.tabs(in: space) ?? []
            },
            allTabs: { [weak browserManager] in
                browserManager?.tabManager.allTabs() ?? []
            },
            detectedImportSources: {
                SumiBookmarkImportSource.detectedBrowserSources()
            },
            readBookmarks: { source in
                try source.readBookmarks()
            },
            date: {
                Date()
            }
        )
    }
}

final class BrowserBookmarkCommandAppKitPresenter: BrowserBookmarkCommandPresenting {
    func promptBookmarkAllTabs(
        defaultTitle: String,
        folders: [SumiBookmarkFolder]
    ) -> BrowserBookmarkAllTabsPrompt? {
        let nameField = NSTextField(string: defaultTitle)
        nameField.placeholderString = "Folder name"
        let folderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for folder in folders {
            let item = NSMenuItem(
                title: String(repeating: "  ", count: folder.depth) + folder.title,
                action: nil,
                keyEquivalent: ""
            )
            item.representedObject = folder.id
            folderPopup.menu?.addItem(item)
            if folder.id == SumiBookmarkConstants.rootFolderID {
                folderPopup.select(item)
            }
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(folderPopup)
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 54)

        let alert = NSAlert()
        alert.messageText = "Bookmark All Tabs"
        alert.informativeText = "Create a folder containing all bookmarkable tabs in the current window."
        alert.accessoryView = stack
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        return BrowserBookmarkAllTabsPrompt(
            folderTitle: nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? defaultTitle,
            parentID: folderPopup.selectedItem?.representedObject as? String
        )
    }

    func promptImportSource(
        detectedSources: [SumiBookmarkImportSource]
    ) -> BrowserBookmarkImportSelection? {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 28), pullsDown: false)
        let htmlItem = NSMenuItem(title: "HTML Bookmarks File…", action: nil, keyEquivalent: "")
        htmlItem.representedObject = "html"
        popup.menu?.addItem(htmlItem)
        popup.menu?.addItem(.separator())
        for source in detectedSources {
            let item = NSMenuItem(title: source.title, action: nil, keyEquivalent: "")
            item.representedObject = source.id
            popup.menu?.addItem(item)
        }

        let alert = NSAlert()
        alert.messageText = "Import Bookmarks"
        alert.informativeText = "Choose a browser profile or a Netscape bookmarks HTML file."
        alert.accessoryView = popup
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        if popup.selectedItem?.representedObject as? String == "html" {
            return .htmlFile
        }

        guard let sourceID = popup.selectedItem?.representedObject as? String,
              let source = detectedSources.first(where: { $0.id == sourceID })
        else {
            return nil
        }
        return .source(source)
    }

    func promptHTMLImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func promptUnreadableSafariBookmarksReplacement(
        source: SumiBookmarkImportSource,
        originalError _: Error
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose \(source.title)'s Bookmarks.plist file."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func promptExportDestination(defaultFileName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func showBookmarkResultAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
