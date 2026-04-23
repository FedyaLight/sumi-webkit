import AppKit

@MainActor
final class SumiHistoryMenuInstaller {
    weak var browserManager: BrowserManager?
    weak var shortcutManager: KeyboardShortcutManager?
    weak var actionTarget: AnyObject?

    func installOrUpdateIfNeeded() {
        guard let mainMenu = NSApp.mainMenu else { return }

        let historyMenuItem: NSMenuItem
        let historyItems = mainMenu.items.filter { $0.title == "History" }
        if let existingAppKitItem = historyItems.first(where: { $0.submenu is SumiHistoryMenu }) {
            historyMenuItem = existingAppKitItem
        } else if let firstHistoryItem = historyItems.first {
            historyMenuItem = firstHistoryItem
        } else {
            historyMenuItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
            let insertionIndex = mainMenu.items.firstIndex(where: { $0.title == "Extensions" })
                ?? mainMenu.items.firstIndex(where: { $0.title == "Window" }).map { $0 + 1 }
                ?? mainMenu.items.count
            mainMenu.insertItem(historyMenuItem, at: insertionIndex)
        }

        for duplicate in historyItems where duplicate !== historyMenuItem {
            mainMenu.removeItem(duplicate)
        }

        if let menu = historyMenuItem.submenu as? SumiHistoryMenu {
            menu.browserManager = browserManager
            menu.shortcutManager = shortcutManager
            menu.actionTarget = actionTarget
            menu.update()
            return
        }

        historyMenuItem.submenu = SumiHistoryMenu(
            browserManager: browserManager,
            shortcutManager: shortcutManager,
            actionTarget: actionTarget
        )
    }
}

@MainActor
final class SumiHistoryMenu: NSMenu {
    weak var browserManager: BrowserManager?
    weak var shortcutManager: KeyboardShortcutManager?
    weak var actionTarget: AnyObject?

    private let backMenuItem = NSMenuItem(title: "Back", action: #selector(AppDelegate.historyGoBack(_:)), keyEquivalent: "")
    private let forwardMenuItem = NSMenuItem(title: "Forward", action: #selector(AppDelegate.historyGoForward(_:)), keyEquivalent: "")
    private let recentlyClosedMenuItem = NSMenuItem(title: "Recently Closed", action: nil, keyEquivalent: "")
    private let reopenLastClosedMenuItem = NSMenuItem(
        title: "Reopen Last Closed Tab",
        action: #selector(AppDelegate.reopenLastClosedTab(_:)),
        keyEquivalent: ""
    )
    private let reopenAllWindowsFromLastSessionMenuItem = NSMenuItem(
        title: "Reopen All Windows From Last Session",
        action: #selector(AppDelegate.reopenAllWindowsFromLastSession(_:)),
        keyEquivalent: ""
    )
    private let showHistoryMenuItem = NSMenuItem(
        title: "Show All History",
        action: #selector(AppDelegate.showHistory(_:)),
        keyEquivalent: ""
    )
    private let clearAllHistoryMenuItem = NSMenuItem(
        title: "Clear All History",
        action: #selector(AppDelegate.clearAllHistory(_:)),
        keyEquivalent: ""
    )

    private var recentlyVisitedMenuItems: [NSMenuItem] = []

    init(
        browserManager: BrowserManager?,
        shortcutManager: KeyboardShortcutManager?,
        actionTarget: AnyObject?
    ) {
        self.browserManager = browserManager
        self.shortcutManager = shortcutManager
        self.actionTarget = actionTarget
        super.init(title: "History")
        autoenablesItems = false
        buildFixedItems()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update() {
        super.update()

        applyTargets()
        updateNavigationState()
        updateRecentlyClosedMenu()
        updateReopenItems()
        clearVariableItems()
        addRecentlyVisitedItems()
        addBottomItems()
    }

    private func buildFixedItems() {
        items = [
            backMenuItem,
            forwardMenuItem,
            .separator(),
            reopenLastClosedMenuItem,
            recentlyClosedMenuItem,
            reopenAllWindowsFromLastSessionMenuItem,
            .separator(),
            showHistoryMenuItem,
            .separator(),
            clearAllHistoryMenuItem,
        ]
        applyTargets()
        update()
    }

    private func applyTargets() {
        let target = actionTarget
        [
            backMenuItem,
            forwardMenuItem,
            reopenLastClosedMenuItem,
            reopenAllWindowsFromLastSessionMenuItem,
            showHistoryMenuItem,
            clearAllHistoryMenuItem,
        ].forEach { $0.target = target }
    }

    private func updateNavigationState() {
        backMenuItem.isEnabled = browserManager?.canGoBackInActiveWindow == true
        forwardMenuItem.isEnabled = browserManager?.canGoForwardInActiveWindow == true
        applyShortcut(.goBack, to: backMenuItem, fallbackKey: "[", fallbackModifiers: [.command])
        applyShortcut(.goForward, to: forwardMenuItem, fallbackKey: "]", fallbackModifiers: [.command])
    }

    private func updateRecentlyClosedMenu() {
        let submenu = SumiRecentlyClosedMenu(
            recentlyClosedItems: browserManager?.recentlyClosedManager.items ?? [],
            actionTarget: actionTarget
        )
        recentlyClosedMenuItem.submenu = submenu
        recentlyClosedMenuItem.isEnabled = !submenu.items.isEmpty
    }

    private func updateReopenItems() {
        let mostRecentItem = browserManager?.recentlyClosedManager.mostRecentItem
        if case .window? = mostRecentItem {
            reopenLastClosedMenuItem.title = "Reopen Last Closed Window"
        } else {
            reopenLastClosedMenuItem.title = "Reopen Last Closed Tab"
        }

        reopenLastClosedMenuItem.isEnabled = browserManager?.recentlyClosedManager.canReopenRecentlyClosedItem == true
        reopenAllWindowsFromLastSessionMenuItem.isEnabled = browserManager?.canRestoreAnyLastSession == true

        if browserManager?.canOfferStartupLastSessionRestoreShortcut == true {
            clearShortcut(on: reopenLastClosedMenuItem)
            applyShortcut(.undoCloseTab, to: reopenAllWindowsFromLastSessionMenuItem, fallbackKey: "t", fallbackModifiers: [.command, .shift])
        } else {
            clearShortcut(on: reopenAllWindowsFromLastSessionMenuItem)
            applyShortcut(.undoCloseTab, to: reopenLastClosedMenuItem, fallbackKey: "t", fallbackModifiers: [.command, .shift])
        }
    }

    private func clearVariableItems() {
        let removableItems = items.filter { item in
            recentlyVisitedMenuItems.contains(item)
                || item === showHistoryMenuItem
                || item === clearAllHistoryMenuItem
        }
        removableItems.forEach(removeItem)
        recentlyVisitedMenuItems = []
    }

    private func addRecentlyVisitedItems() {
        let visits = browserManager?.historyManager.recentVisitedItems(maxCount: 12) ?? []
        let header = NSMenuItem(title: "Recently Visited", action: nil, keyEquivalent: "")
        header.isEnabled = false
        recentlyVisitedMenuItems = [header]

        if !visits.isEmpty {
            recentlyVisitedMenuItems.append(contentsOf: visits.map {
                SumiVisitMenuItem(visit: $0, actionTarget: actionTarget)
            })
        }

        for item in recentlyVisitedMenuItems {
            addItem(item)
        }
    }

    private func addBottomItems() {
        addItem(.separator())

        showHistoryMenuItem.isEnabled = true
        applyShortcut(.viewHistory, to: showHistoryMenuItem, fallbackKey: "y", fallbackModifiers: [.command])
        addItem(showHistoryMenuItem)

        addItem(.separator())

        clearAllHistoryMenuItem.isEnabled = browserManager?.historyManager.canClearHistory == true
        clearAllHistoryMenuItem.keyEquivalent = "\u{8}"
        clearAllHistoryMenuItem.keyEquivalentModifierMask = [.command, .shift]
        addItem(clearAllHistoryMenuItem)
    }

    private func applyShortcut(
        _ action: ShortcutAction,
        to item: NSMenuItem,
        fallbackKey: String,
        fallbackModifiers: NSEvent.ModifierFlags
    ) {
        guard let shortcutManager,
              let shortcut = shortcutManager.shortcut(for: action),
              shortcut.isEnabled,
              let keyEquivalent = keyEquivalent(for: shortcut.keyCombination.key)
        else {
            item.keyEquivalent = fallbackKey
            item.keyEquivalentModifierMask = fallbackModifiers
            return
        }

        item.keyEquivalent = keyEquivalent
        item.keyEquivalentModifierMask = shortcut.keyCombination.modifiers.nsEventModifierFlags
    }

    private func clearShortcut(on item: NSMenuItem) {
        item.keyEquivalent = ""
        item.keyEquivalentModifierMask = []
    }

    private func keyEquivalent(for key: String) -> String? {
        switch key.lowercased() {
        case "return", "enter":
            return "\r"
        case "delete", "backspace":
            return "\u{8}"
        case "tab":
            return "\t"
        case "space":
            return " "
        default:
            if key.count == 1 {
                return key.lowercased()
            }
            return nil
        }
    }
}

@MainActor
private final class SumiRecentlyClosedMenu: NSMenu {
    init(recentlyClosedItems: [RecentlyClosedItem], actionTarget: AnyObject?) {
        super.init(title: "Recently Closed")
        autoenablesItems = false
        items = recentlyClosedItems.prefix(30).map { item in
            let menuItem = NSMenuItem(
                title: Self.recentlyClosedTitle(for: item),
                action: #selector(AppDelegate.recentlyClosedAction(_:)),
                keyEquivalent: ""
            )
            menuItem.representedObject = item
            menuItem.target = actionTarget
            Self.applyRecentlyClosedImage(to: menuItem, for: item)
            menuItem.isEnabled = true
            return menuItem
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func recentlyClosedTitle(for item: RecentlyClosedItem) -> String {
        switch item {
        case .tab(let tab):
            return tab.title.isEmpty ? tab.url.absoluteString : tab.title
        case .window(let window):
            return window.title.isEmpty ? "Window" : window.title
        }
    }

    private static func applyRecentlyClosedImage(to menuItem: NSMenuItem, for item: RecentlyClosedItem) {
        switch item {
        case .tab(let tab):
            MenuFaviconResolver.apply(to: menuItem, for: tab.url)
        case .window:
            let image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
            image?.size = NSSize(width: 16, height: 16)
            menuItem.image = image
        }
    }
}

@MainActor
private final class SumiVisitMenuItem: NSMenuItem {
    init(visit: HistoryListItem, actionTarget: AnyObject?) {
        super.init(title: visit.displayTitle, action: #selector(AppDelegate.openHistoryEntryVisit(_:)), keyEquivalent: "")
        representedObject = visit
        target = actionTarget
        MenuFaviconResolver.apply(to: self, for: visit.url)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private enum MenuFaviconResolver {
    static func apply(to menuItem: NSMenuItem, for url: URL) {
        if let cacheKey = SumiFaviconResolver.cacheKey(for: url),
           let image = TabFaviconStore.getCachedImage(for: cacheKey) {
            menuItem.image = image.resizedToFaviconSize()
            return
        }

        let placeholder = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        placeholder?.size = NSSize(width: 16, height: 16)
        menuItem.image = placeholder

        Task { @MainActor [weak menuItem] in
            guard let menuItem,
                  let fetchedImage = await SumiFaviconResolver.shared.image(for: url)
            else {
                return
            }
            menuItem.image = fetchedImage.resizedToFaviconSize()
        }
    }
}

private extension NSImage {
    func resizedToFaviconSize() -> NSImage {
        let targetSize = NSSize(width: 16, height: 16)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        image.unlockFocus()
        return image
    }
}

private extension Modifiers {
    var nsEventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        return flags
    }
}
