import AppKit
import Foundation
import SumiDomain
import UniformTypeIdentifiers

struct BrowserBookmarkAllTabsPrompt: Equatable {
    var folderTitle: String
    var parentID: String?
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
protocol BrowserBookmarkCommandPresenting: BrowserBookmarkImportExportPresenting {
    func promptBookmarkAllTabs(
        defaultTitle: String,
        folders: [SumiBookmarkFolder]
    ) -> BrowserBookmarkAllTabsPrompt?
}

/// Bookmark command surface: open, bookmark-all, manage, editor presentation, menu commands.
/// Import/export pipeline lives on `BrowserBookmarkImportExportOwner`.
@MainActor
final class BrowserBookmarkCommandOwner {
    private typealias NewWindowRegistrationAwaiter = @MainActor () async -> BrowserWindowState?

    private let activeWindow: @MainActor @Sendable () -> BrowserWindowState?
    private let activePageTab: @MainActor @Sendable (BrowserWindowState) -> Tab?
    private let bookmarkManager: @MainActor @Sendable () -> SumiBookmarkManager?
    private let bookmarkEditorPresentationRequest: @MainActor @Sendable () -> SumiBookmarkEditorPresentationRequest?
    private let setBookmarkEditorPresentationRequest: @MainActor @Sendable (SumiBookmarkEditorPresentationRequest?) -> Void
    private let openNativeBrowserSurface: @MainActor @Sendable (
        SumiNativeBrowserSurfaceKind,
        URL,
        BrowserWindowState,
        UUID?
    ) -> Void
    private let openHistoryURL: @MainActor @Sendable (
        URL,
        BrowserWindowState,
        HistoryOpenMode
    ) -> Void
    private let openHistoryURLsInNewWindow: @MainActor @Sendable ([URL]) -> Void
    private let windowIds: @MainActor @Sendable () -> [UUID]
    private let createNewWindow: @MainActor @Sendable () -> Void
    private let awaitNextRegisteredWindow: @MainActor @Sendable (Set<UUID>) async -> BrowserWindowState?
    private let space: @MainActor @Sendable (UUID?) -> Space?
    private let tabsInSpace: @MainActor @Sendable (Space) -> [Tab]
    private let allTabs: @MainActor @Sendable () -> [Tab]
    private let presenter: any BrowserBookmarkCommandPresenting
    private let importExportOwner: BrowserBookmarkImportExportOwner
    private let date: @MainActor @Sendable () -> Date

    init(
        activeWindow: @escaping @MainActor @Sendable () -> BrowserWindowState?,
        activePageTab: @escaping @MainActor @Sendable (BrowserWindowState) -> Tab?,
        bookmarkManager: @escaping @MainActor @Sendable () -> SumiBookmarkManager?,
        bookmarkEditorPresentationRequest: @escaping @MainActor @Sendable () -> SumiBookmarkEditorPresentationRequest?,
        setBookmarkEditorPresentationRequest: @escaping @MainActor @Sendable (SumiBookmarkEditorPresentationRequest?) -> Void,
        openNativeBrowserSurface: @escaping @MainActor @Sendable (
            SumiNativeBrowserSurfaceKind,
            URL,
            BrowserWindowState,
            UUID?
        ) -> Void,
        openHistoryURL: @escaping @MainActor @Sendable (
            URL,
            BrowserWindowState,
            HistoryOpenMode
        ) -> Void,
        openHistoryURLsInNewWindow: @escaping @MainActor @Sendable ([URL]) -> Void,
        windowIds: @escaping @MainActor @Sendable () -> [UUID],
        createNewWindow: @escaping @MainActor @Sendable () -> Void,
        awaitNextRegisteredWindow: @escaping @MainActor @Sendable (Set<UUID>) async -> BrowserWindowState?,
        space: @escaping @MainActor @Sendable (UUID?) -> Space?,
        tabsInSpace: @escaping @MainActor @Sendable (Space) -> [Tab],
        allTabs: @escaping @MainActor @Sendable () -> [Tab],
        detectedImportSources: @escaping @MainActor @Sendable () -> [SumiBookmarkImportSource],
        readBookmarks: @escaping @MainActor @Sendable (SumiBookmarkImportSource) throws -> [SumiBookmarkImportNode],
        date: @escaping @MainActor @Sendable () -> Date,
        presenter: any BrowserBookmarkCommandPresenting
    ) {
        self.activeWindow = activeWindow
        self.activePageTab = activePageTab
        self.bookmarkManager = bookmarkManager
        self.bookmarkEditorPresentationRequest = bookmarkEditorPresentationRequest
        self.setBookmarkEditorPresentationRequest = setBookmarkEditorPresentationRequest
        self.openNativeBrowserSurface = openNativeBrowserSurface
        self.openHistoryURL = openHistoryURL
        self.openHistoryURLsInNewWindow = openHistoryURLsInNewWindow
        self.windowIds = windowIds
        self.createNewWindow = createNewWindow
        self.awaitNextRegisteredWindow = awaitNextRegisteredWindow
        self.space = space
        self.tabsInSpace = tabsInSpace
        self.allTabs = allTabs
        self.date = date
        self.presenter = presenter
        self.importExportOwner = BrowserBookmarkImportExportOwner(
            bookmarkManager: bookmarkManager,
            detectedImportSources: detectedImportSources,
            readBookmarks: readBookmarks,
            presenter: presenter
        )
    }

    @MainActor
    func requestBookmarkEditorForActiveWindowFromMenu() {
        guard let bookmarkManager = bookmarkManager(),
              let windowState = activeWindow(),
              let tab = activePageTab(windowState),
              bookmarkManager.canBookmark(tab)
        else {
            return
        }

        setBookmarkEditorPresentationRequest(
            SumiBookmarkEditorPresentationRequest(
                windowID: windowState.id,
                tabID: tab.id
            )
        )
    }

    @MainActor
    func clearBookmarkEditorPresentationRequest(_ request: SumiBookmarkEditorPresentationRequest) {
        guard bookmarkEditorPresentationRequest()?.id == request.id else { return }
        setBookmarkEditorPresentationRequest(nil)
    }

    @MainActor
    func openBookmarksTab(
        selecting folderID: String? = nil,
        in windowState: BrowserWindowState? = nil
    ) {
        if let targetWindow = windowState ?? activeWindow() {
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
        if let activeWindow = activeWindow() {
            openBookmarkURL(url, in: activeWindow, preferredOpenMode: .currentTab)
        } else {
            openHistoryURLsInNewWindow([url])
        }
    }

    @MainActor
    func openBookmarkURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        preferredOpenMode: HistoryOpenMode
    ) {
        openHistoryURL(url, windowState, preferredOpenMode)
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
        guard let activeWindow = activeWindow(),
              let bookmarkManager = bookmarkManager()
        else {
            return
        }

        let allRegularTabs = regularTabs(in: activeWindow)
        let bookmarkableTabs = allRegularTabs.filter { bookmarkManager.canBookmark($0) }
        guard !bookmarkableTabs.isEmpty else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let defaultTitle = "Bookmarked Tabs \(dateFormatter.string(from: date()))"

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
        guard let bookmarkManager = bookmarkManager() else {
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
        importExportOwner.importBookmarksFromMenu()
    }

    @MainActor
    func exportBookmarksFromMenu() {
        importExportOwner.exportBookmarksFromMenu()
    }

    @MainActor
    private func openBookmarksTab(
        inResolvedWindow targetWindow: BrowserWindowState,
        selecting folderID: String?
    ) {
        openNativeBrowserSurface(
            .bookmarks,
            SumiSurface.bookmarksSurfaceURL(selecting: folderID),
            targetWindow,
            nil
        )
    }

    @MainActor
    private func bookmarkableRegularTabsForActiveWindow() -> [Tab] {
        guard let activeWindow = activeWindow(),
              let bookmarkManager = bookmarkManager()
        else {
            return []
        }
        return regularTabs(in: activeWindow).filter { bookmarkManager.canBookmark($0) }
    }

    @MainActor
    private func regularTabs(in windowState: BrowserWindowState) -> [Tab] {
        guard !windowState.isIncognito else { return [] }
        if let currentSpace = space(windowState.currentSpaceId) {
            return tabsInSpace(currentSpace)
        }
        return allTabs()
    }

    @MainActor
    private func createNewWindowRegistrationAwaiter() -> NewWindowRegistrationAwaiter {
        let existingWindowIDs = Set(windowIds())
        createNewWindow()

        return { [awaitNextRegisteredWindow] in
            await awaitNextRegisteredWindow(existingWindowIDs)
        }
    }
}

final class BrowserBookmarkCommandAppKitPresenter: BrowserBookmarkCommandPresenting {
    /// Space-resolved appearance for the prompt windows; nil keeps the system
    /// appearance.
    private let nativeSurfaceAppearance: @MainActor () -> NSAppearance?

    init(nativeSurfaceAppearance: @escaping @MainActor () -> NSAppearance? = { nil }) {
        self.nativeSurfaceAppearance = nativeSurfaceAppearance
    }

    private func applyNativeSurfaceAppearance(to alert: NSAlert) {
        guard let appearance = nativeSurfaceAppearance() else { return }
        alert.window.appearance = appearance
    }

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
        applyNativeSurfaceAppearance(to: alert)
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
        applyNativeSurfaceAppearance(to: alert)
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
        applyNativeSurfaceAppearance(to: alert)
        alert.runModal()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
