import AppKit

@MainActor
final class SumiBookmarksMenuInstaller {
    weak var browserManager: BrowserManager?
    weak var actionTarget: AnyObject?

    func installOrUpdateIfNeeded() {
        guard let mainMenu = NSApp.mainMenu else { return }

        let bookmarksMenuItem: NSMenuItem
        let bookmarksItems = mainMenu.items.filter { $0.title == "Bookmarks" }
        if let existingAppKitItem = bookmarksItems.first(where: { $0.submenu is SumiBookmarksMenu }) {
            bookmarksMenuItem = existingAppKitItem
        } else if let firstBookmarksItem = bookmarksItems.first {
            bookmarksMenuItem = firstBookmarksItem
        } else {
            bookmarksMenuItem = NSMenuItem(title: "Bookmarks", action: nil, keyEquivalent: "")
            let insertionIndex = mainMenu.items.firstIndex(where: { $0.title == "History" }).map { $0 + 1 }
                ?? mainMenu.items.firstIndex(where: { $0.title == "Extensions" })
                ?? mainMenu.items.firstIndex(where: { $0.title == "Window" }).map { $0 + 1 }
                ?? mainMenu.items.count
            mainMenu.insertItem(bookmarksMenuItem, at: insertionIndex)
        }

        for duplicate in bookmarksItems where duplicate !== bookmarksMenuItem {
            mainMenu.removeItem(duplicate)
        }

        if let menu = bookmarksMenuItem.submenu as? SumiBookmarksMenu {
            menu.browserManager = browserManager
            menu.actionTarget = actionTarget
            menu.update()
            return
        }

        bookmarksMenuItem.submenu = SumiBookmarksMenu(
            browserManager: browserManager,
            actionTarget: actionTarget
        )
    }
}

@MainActor
final class SumiBookmarksMenu: NSMenu {
    weak var browserManager: BrowserManager?
    weak var actionTarget: AnyObject?

    init(
        browserManager: BrowserManager?,
        actionTarget: AnyObject?
    ) {
        self.browserManager = browserManager
        self.actionTarget = actionTarget
        super.init(title: "Bookmarks")
        autoenablesItems = false
        update()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update() {
        super.update()

        removeAllItems()
        addBookmarkThisPageItem()
        addBookmarkAllTabsItem()
        addManageBookmarksItem()
        addItem(.separator())
        addImportBookmarksItem()
        addExportBookmarksItem()
        addItem(.separator())
        addBookmarkTreeItems()
    }

    private func addBookmarkThisPageItem() {
        let item = NSMenuItem(
            title: "Bookmark This Page…",
            action: #selector(AppDelegate.bookmarkThisPageFromMenu(_:)),
            keyEquivalent: "d"
        )
        item.keyEquivalentModifierMask = [.command]
        item.target = actionTarget
        item.isEnabled = browserManager.map { manager in
            manager.bookmarkManager.canBookmark(manager.currentTabForActiveWindow())
        } ?? false
        addItem(item)
    }

    private func addBookmarkAllTabsItem() {
        let item = NSMenuItem(
            title: "Bookmark All Tabs…",
            action: #selector(AppDelegate.bookmarkAllTabsFromMenu(_:)),
            keyEquivalent: "d"
        )
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = actionTarget
        item.isEnabled = browserManager?.canBookmarkAllTabsInActiveWindow() ?? false
        addItem(item)
    }

    private func addManageBookmarksItem() {
        let item = NSMenuItem(
            title: "Manage Bookmarks",
            action: #selector(AppDelegate.manageBookmarksFromMenu(_:)),
            keyEquivalent: "b"
        )
        item.keyEquivalentModifierMask = [.command, .option]
        item.target = actionTarget
        item.isEnabled = true
        addItem(item)
    }

    private func addImportBookmarksItem() {
        let item = NSMenuItem(
            title: "Import Bookmarks…",
            action: #selector(AppDelegate.importBookmarksFromMenu(_:)),
            keyEquivalent: ""
        )
        item.target = actionTarget
        item.isEnabled = true
        addItem(item)
    }

    private func addExportBookmarksItem() {
        let item = NSMenuItem(
            title: "Export Bookmarks…",
            action: #selector(AppDelegate.exportBookmarksFromMenu(_:)),
            keyEquivalent: ""
        )
        item.target = actionTarget
        item.isEnabled = browserManager?.bookmarkManager.snapshot().hasBookmarks ?? false
        addItem(item)
    }

    private func addBookmarkTreeItems() {
        let rootChildren = browserManager?.bookmarkManager.snapshot(sortMode: .manual).root.children ?? []
        guard !rootChildren.isEmpty else {
            let emptyItem = NSMenuItem(title: "No Bookmarks", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            addItem(emptyItem)
            return
        }

        for entity in rootChildren {
            addItem(menuItem(for: entity))
        }
    }

    private func menuItem(for entity: SumiBookmarkEntity) -> NSMenuItem {
        if entity.isFolder {
            let item = NSMenuItem(title: menuTitle(for: entity), action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let submenu = NSMenu(title: entity.title)
            submenu.autoenablesItems = false
            if entity.children.isEmpty {
                let empty = NSMenuItem(title: "Empty", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                submenu.addItem(empty)
            } else {
                for child in entity.children {
                    submenu.addItem(menuItem(for: child))
                }
            }
            item.submenu = submenu
            return item
        }

        let item = NSMenuItem(
            title: menuTitle(for: entity),
            action: #selector(AppDelegate.openBookmarkFromMenu(_:)),
            keyEquivalent: ""
        )
        item.representedObject = entity.url
        item.target = actionTarget
        item.image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: nil)
        item.isEnabled = entity.url != nil
        return item
    }

    private func menuTitle(for entity: SumiBookmarkEntity) -> String {
        let displayTitle = entity.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? entity.displayURL
            : entity.title
        let maxLength = 80
        guard displayTitle.count > maxLength else { return displayTitle }
        return String(displayTitle.prefix(maxLength - 1)) + "…"
    }
}
