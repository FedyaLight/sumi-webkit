import AppKit

/// Owns Sumi-created web page context menu sections. Native WebKit item
/// mutation stays in `SumiWebPageNativeMenuComposer`.
@MainActor
struct SumiWebPageOwnedMenuComposer {
    let menu: NSMenu
    let context: SumiWebPageMenuContext
    let actionTarget: SumiWebPageMenuController
    let isLoading: Bool

    private var itemFactory: SumiWebPageMenuItemFactory {
        SumiWebPageMenuItemFactory(actionTarget: actionTarget)
    }

    func removeOwnedPageItems() {
        for item in menu.items.reversed()
            where SumiWebPageMenuCommand(item.identifier)?.isPageBackgroundCommand == true {
            menu.removeItem(item)
        }
        menu.sumiNormalizeSeparators()
    }

    func insertSelectionFallbackCommandsIfNeeded() {
        guard let selectedText = context.selectedText else { return }

        var items: [NSMenuItem] = []
        if !context.identifiers.contains(.copy) {
            items.append(itemFactory.makeItem(
                title: "Copy",
                command: .copySelection,
                action: #selector(SumiWebPageMenuController.copySelection(_:)),
                symbolName: "doc.on.doc"
            ))
        }
        if context.canCopyLinkToSelectedText,
           !context.identifiers.contains(.copyLinkWithHighlight) {
            items.append(itemFactory.makeItem(
                title: "Copy Link to Selected Text",
                command: .copyLinkToSelectedText,
                action: #selector(SumiWebPageMenuController.copyLinkToSelectedText(_:)),
                symbolName: "quote.bubble"
            ))
        }
        if !context.identifiers.contains(.searchWeb) {
            items.append(itemFactory.makeItem(
                title: "Search \(context.searchProviderName) for \"\(SumiWebPageMenuTextFormatter.menuSnippet(for: selectedText))\"",
                command: .searchSelection,
                action: #selector(SumiWebPageMenuController.searchSelection(_:)),
                symbolName: "magnifyingglass"
            ))
        }

        if !context.hasPrintCommand(in: menu) {
            items.append(itemFactory.makeItem(
                title: "Print Page...",
                command: .printPage,
                action: #selector(SumiWebPageMenuController.printPage(_:)),
                symbolName: "printer"
            ))
        }

        guard !items.isEmpty else { return }
        var insertionIndex = context.selectionFallbackInsertionIndex(in: menu)
        if insertionIndex > 0, menu.items[insertionIndex - 1].isSeparatorItem == false {
            menu.insertItem(.separator(), at: insertionIndex)
            insertionIndex += 1
        }
        for item in items {
            menu.insertItem(item, at: insertionIndex)
            insertionIndex += 1
        }
        if insertionIndex < menu.items.count, menu.items[insertionIndex].isSeparatorItem == false {
            menu.insertItem(.separator(), at: insertionIndex)
        }
    }

    func insertPageBackgroundCommands() {
        let navigationItems = [
            itemFactory.makeItem(
                title: "Back",
                command: .back,
                action: #selector(SumiWebPageMenuController.goBack(_:)),
                symbolName: "chevron.left"
            ),
            itemFactory.makeItem(
                title: "Forward",
                command: .forward,
                action: #selector(SumiWebPageMenuController.goForward(_:)),
                symbolName: "chevron.right"
            ),
            loadingItem(),
        ]

        let pageItems = [
            itemFactory.makeItem(
                title: "Bookmark This Page...",
                command: .bookmarkPage,
                action: #selector(SumiWebPageMenuController.bookmarkPage(_:)),
                symbolName: "bookmark"
            ),
            itemFactory.makeItem(
                title: "Copy Page Address",
                command: .copyPageAddress,
                action: #selector(SumiWebPageMenuController.copyPageAddress(_:)),
                symbolName: "link"
            ),
            itemFactory.makeItem(
                title: "Print Page...",
                command: .printPage,
                action: #selector(SumiWebPageMenuController.printPage(_:)),
                symbolName: "printer"
            ),
        ]

        var insertionIndex = 0
        for item in navigationItems {
            menu.insertItem(item, at: insertionIndex)
            insertionIndex += 1
        }
        menu.insertItem(.separator(), at: insertionIndex)
        insertionIndex += 1
        for item in pageItems {
            menu.insertItem(item, at: insertionIndex)
            insertionIndex += 1
        }
        if insertionIndex < menu.items.count {
            menu.insertItem(.separator(), at: insertionIndex)
        }
    }

    private func loadingItem() -> NSMenuItem {
        if isLoading {
            return itemFactory.makeItem(
                title: "Stop Loading",
                command: .stop,
                action: #selector(SumiWebPageMenuController.stopLoading(_:)),
                symbolName: "xmark"
            )
        }

        return itemFactory.makeItem(
            title: "Reload Page",
            command: .reload,
            action: #selector(SumiWebPageMenuController.reloadPage(_:)),
            symbolName: "arrow.clockwise"
        )
    }
}
