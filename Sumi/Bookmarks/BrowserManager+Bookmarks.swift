import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension BrowserManager {
    func requestBookmarkEditorForActiveWindowFromMenu() {
        guard let windowState = windowRegistry?.activeWindow,
              let tab = currentTab(for: windowState),
              bookmarkManager.canBookmark(tab)
        else {
            return
        }

        bookmarkEditorPresentationRequest = SumiBookmarkEditorPresentationRequest(
            windowID: windowState.id,
            tabID: tab.id
        )
    }

    func clearBookmarkEditorPresentationRequest(_ request: SumiBookmarkEditorPresentationRequest) {
        guard bookmarkEditorPresentationRequest?.id == request.id else { return }
        bookmarkEditorPresentationRequest = nil
    }

    func openBookmarksTab(
        selecting folderID: String? = nil,
        in windowState: BrowserWindowState? = nil
    ) {
        if let targetWindow = windowState ?? windowRegistry?.activeWindow {
            openBookmarksTab(inResolvedWindow: targetWindow, selecting: folderID)
            return
        }

        let existingWindowIDs = Set(windowRegistry?.windows.keys.map { $0 } ?? [])
        createNewWindow()
        Task { @MainActor [weak self] in
            guard let self,
                  let targetWindow = await self.windowRegistry?.awaitNextRegisteredWindow(
                    excluding: existingWindowIDs
                  )
            else {
                return
            }
            self.openBookmarksTab(inResolvedWindow: targetWindow, selecting: folderID)
        }
    }

    func openBookmarkURLFromMenuItem(_ url: URL) {
        if let activeWindow = windowRegistry?.activeWindow {
            openBookmarkURL(url, in: activeWindow, preferredOpenMode: .currentTab)
        } else {
            openHistoryURLsInNewWindow([url])
        }
    }

    func openBookmarkURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        preferredOpenMode: HistoryOpenMode
    ) {
        openHistoryURL(url, in: windowState, preferredOpenMode: preferredOpenMode)
    }

    func manageBookmarksFromMenu() {
        openBookmarksTab()
    }

    func canBookmarkAllTabsInActiveWindow() -> Bool {
        bookmarkableRegularTabsForActiveWindow().isEmpty == false
    }

    func bookmarkAllTabsFromMenu() {
        guard let activeWindow = windowRegistry?.activeWindow else { return }
        let allRegularTabs = regularTabs(in: activeWindow)
        let bookmarkableTabs = allRegularTabs.filter { bookmarkManager.canBookmark($0) }
        guard !bookmarkableTabs.isEmpty else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let defaultTitle = "Bookmarked Tabs \(dateFormatter.string(from: Date()))"

        let nameField = NSTextField(string: defaultTitle)
        nameField.placeholderString = "Folder name"
        let folderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for folder in bookmarkManager.folders() {
            let item = NSMenuItem(title: String(repeating: "  ", count: folder.depth) + folder.title, action: nil, keyEquivalent: "")
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
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let parentID = folderPopup.selectedItem?.representedObject as? String
        let folderTitle = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? defaultTitle
        do {
            let result = try bookmarkTabs(
                allRegularTabs,
                folderTitle: folderTitle,
                parentID: parentID
            )
            showBookmarkResultAlert(
                title: "Tabs Bookmarked",
                message: "\(result.created) added to “\(result.folderTitle)”. \(result.duplicates) duplicates skipped. \(result.skipped) unsupported tabs ignored."
            )
        } catch {
            showBookmarkResultAlert(title: "Bookmark All Tabs Failed", message: error.localizedDescription)
        }
    }

    func bookmarkTabs(
        _ tabs: [Tab],
        folderTitle: String,
        parentID: String?
    ) throws -> SumiBookmarkAllTabsResult {
        let folder = try bookmarkManager.createFolder(title: folderTitle, parentID: parentID)
        var created = 0
        var duplicates = 0
        var skipped = 0

        for tab in tabs {
            guard bookmarkManager.canBookmark(tab) else {
                skipped += 1
                continue
            }
            if bookmarkManager.isBookmarked(tab.url) {
                duplicates += 1
                continue
            }
            _ = try bookmarkManager.createBookmark(
                url: tab.url,
                title: tab.name,
                folderID: folder.id
            )
            created += 1
        }

        return SumiBookmarkAllTabsResult(
            created: created,
            duplicates: duplicates,
            skipped: skipped,
            folderTitle: folder.title
        )
    }

    func importBookmarksFromMenu() {
        let detectedSources = SumiBookmarkImportSource.detectedBrowserSources()
        guard !detectedSources.isEmpty else {
            importBookmarksFromHTMLFile()
            return
        }

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
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if popup.selectedItem?.representedObject as? String == "html" {
            importBookmarksFromHTMLFile()
            return
        }

        guard let sourceID = popup.selectedItem?.representedObject as? String,
              let source = detectedSources.first(where: { $0.id == sourceID })
        else { return }

        importBookmarks(from: source)
    }

    func exportBookmarksFromMenu() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Bookmarks.html"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK,
              let destination = panel.url
        else { return }

        do {
            try bookmarkManager.exportBookmarksHTML(to: destination)
            showBookmarkResultAlert(title: "Bookmarks Exported", message: "Bookmarks were exported to \(destination.lastPathComponent).")
        } catch {
            showBookmarkResultAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func openBookmarksTab(
        inResolvedWindow targetWindow: BrowserWindowState,
        selecting folderID: String?
    ) {
        let targetURL = SumiSurface.bookmarksSurfaceURL(selecting: folderID)

        if targetWindow.isIncognito, let profile = targetWindow.ephemeralProfile {
            if let existing = targetWindow.ephemeralTabs.first(where: { $0.representsSumiBookmarksSurface }) {
                configureBookmarksTab(existing, url: targetURL)
                selectTab(existing, in: targetWindow)
            } else {
                let newTab = tabManager.createEphemeralTab(
                    url: targetURL,
                    in: targetWindow,
                    profile: profile
                )
                configureBookmarksTab(newTab, url: targetURL)
                selectTab(newTab, in: targetWindow)
            }
            targetWindow.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let targetSpace =
            targetWindow.currentSpaceId.flatMap { id in
                tabManager.spaces.first(where: { $0.id == id })
            }
            ?? targetWindow.currentProfileId.flatMap { pid in
                tabManager.spaces.first(where: { $0.profileId == pid })
            }
            ?? tabManager.currentSpace

        let spaceIdForLookup = targetSpace?.id ?? tabManager.currentSpace?.id
        if let sid = spaceIdForLookup,
           let existing = (tabManager.tabsBySpace[sid] ?? []).first(where: { $0.representsSumiBookmarksSurface })
        {
            configureBookmarksTab(existing, url: targetURL)
            selectTab(existing, in: targetWindow)
            targetWindow.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newTab = openNewTab(
            url: targetURL.absoluteString,
            context: .foreground(
                windowState: targetWindow,
                preferredSpaceId: targetSpace?.id,
                loadPolicy: .deferred
            )
        )
        configureBookmarksTab(newTab, url: targetURL)
        targetWindow.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureBookmarksTab(_ tab: Tab, url: URL) {
        tab.url = url
        tab.name = "Bookmarks"
        tab.favicon = Image(systemName: SumiSurface.bookmarksTabFaviconSystemImageName)
        tab.faviconIsTemplateGlobePlaceholder = false
        tabManager.scheduleRuntimeStatePersistence(for: tab)
    }

    private func bookmarkableRegularTabsForActiveWindow() -> [Tab] {
        guard let activeWindow = windowRegistry?.activeWindow else { return [] }
        return regularTabs(in: activeWindow).filter { bookmarkManager.canBookmark($0) }
    }

    private func regularTabs(in windowState: BrowserWindowState) -> [Tab] {
        guard !windowState.isIncognito else { return [] }
        if let currentSpace = space(for: windowState.currentSpaceId) {
            return tabManager.tabs(in: currentSpace)
        }
        return tabManager.allTabs()
    }

    private func importBookmarksFromHTMLFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK,
              let fileURL = panel.url
        else { return }

        importBookmarks(
            from: SumiBookmarkImportSource(
                id: "html-\(fileURL.path)",
                title: fileURL.lastPathComponent,
                fileURL: fileURL,
                kind: .html
            )
        )
    }

    private func importBookmarks(from source: SumiBookmarkImportSource) {
        do {
            let nodes = try source.readBookmarks()
            let summary = try bookmarkManager.importBookmarks(nodes)
            showBookmarkResultAlert(
                title: "Bookmarks Imported",
                message: "\(source.title): \(summary.message)"
            )
        } catch {
            if source.kind == .safariPlist {
                importUnreadableSafariBookmarks(source: source, originalError: error)
            } else {
                showBookmarkResultAlert(title: "Import Failed", message: error.localizedDescription)
            }
        }
    }

    private func importUnreadableSafariBookmarks(source: SumiBookmarkImportSource, originalError: Error) {
        let panel = NSOpenPanel()
        panel.message = "Choose \(source.title)'s Bookmarks.plist file."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK,
              let fileURL = panel.url
        else {
            showBookmarkResultAlert(title: "Import Failed", message: originalError.localizedDescription)
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

    private func showBookmarkResultAlert(title: String, message: String) {
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
