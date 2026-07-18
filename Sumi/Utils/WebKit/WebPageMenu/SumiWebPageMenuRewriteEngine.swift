import AppKit

/// Applies a `SumiWebPageMenuBlueprint` to the live `NSMenu`: pure mechanics,
/// no per-context policy. Items are visited in reverse so earlier indices
/// stay valid while rules mutate the menu. Native WebKit items keep their
/// original targets and actions unless a rule removes or replaces them.
@MainActor
struct SumiWebPageMenuRewriteEngine {
    let menu: NSMenu
    let context: SumiWebPageMenuContext
    let itemFactory: SumiWebPageMenuItemFactory

    func apply(_ blueprint: SumiWebPageMenuBlueprint) {
        applyRules(blueprint.rules())
        insertPageBackgroundSection(blueprint.pageBackgroundSection())
        insertSelectionFallbackSection(blueprint.selectionFallbackSection())
        decorateNativeItems(in: menu)
        menu.sumiNormalizeSeparators()
        menu.sumiForceRelayout()
    }

    // MARK: - Rules

    private func applyRules(_ rules: [SumiWebPageMenuBlueprint.Rule]) {
        let rulesByAnchor = Dictionary(
            rules.map { ($0.anchor, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for item in menu.items.reversed() {
            guard let identifier = SumiWebKitMenuItemIdentifier(item.identifier),
                  let rule = rulesByAnchor[identifier]
            else { continue }
            let index = menu.index(of: item)
            guard index != -1 else { continue }
            apply(rule, to: item, at: index)
        }
    }

    private func apply(
        _ rule: SumiWebPageMenuBlueprint.Rule,
        to item: NSMenuItem,
        at index: Int
    ) {
        var anchorIndex = index
        var afterIndex = index + 1

        for operation in rule.operations {
            switch operation {
            case .remove:
                menu.removeItem(at: anchorIndex)
                afterIndex = anchorIndex

            case .retitle(let title):
                item.title = title

            case .replace(let entries):
                menu.removeItem(at: anchorIndex)
                var insertion = anchorIndex
                for entry in entries {
                    menu.insertItem(makeItem(entry), at: insertion)
                    insertion += 1
                }
                afterIndex = insertion

            case .insertBefore(let entries):
                var insertion = anchorIndex
                for entry in entries {
                    menu.insertItem(makeItem(entry), at: insertion)
                    insertion += 1
                }
                anchorIndex = insertion
                afterIndex = anchorIndex + 1

            case .insertAfter(let entries):
                var insertion = afterIndex
                for entry in entries {
                    menu.insertItem(makeItem(entry), at: insertion)
                    insertion += 1
                }
            }
        }
    }

    // MARK: - Owned sections

    private func insertPageBackgroundSection(_ entries: [SumiWebPageMenuBlueprint.Entry]) {
        guard !entries.isEmpty else { return }

        removeNativePageNavigationItems()
        var insertion = 0
        for entry in entries {
            menu.insertItem(makeItem(entry), at: insertion)
            insertion += 1
        }
        if insertion < menu.items.count, !menu.items[insertion].isSeparatorItem {
            menu.insertItem(.separator(), at: insertion)
        }
    }

    private func removeNativePageNavigationItems() {
        for item in menu.items.reversed() {
            guard SumiWebKitMenuItemIdentifier(item.identifier)?.isPageNavigation == true
                || item.sumiIsWebKitStopItem
            else { continue }
            menu.removeItem(item)
        }
    }

    private func insertSelectionFallbackSection(_ entries: [SumiWebPageMenuBlueprint.Entry]) {
        guard !entries.isEmpty else { return }

        var insertion = selectionFallbackInsertionIndex()
        if insertion > 0, !menu.items[insertion - 1].isSeparatorItem {
            menu.insertItem(.separator(), at: insertion)
            insertion += 1
        }
        for entry in entries {
            menu.insertItem(makeItem(entry), at: insertion)
            insertion += 1
        }
        if insertion < menu.items.count, !menu.items[insertion].isSeparatorItem {
            menu.insertItem(.separator(), at: insertion)
        }
    }

    private func selectionFallbackInsertionIndex() -> Int {
        var lastElementIndex = -1
        for (index, item) in menu.items.enumerated() {
            if let identifier = SumiWebKitMenuItemIdentifier(item.identifier),
               identifier.belongsToElementContext {
                lastElementIndex = index
            }
            if SumiWebPageMenuCommand(item.identifier)?.belongsToElementContext == true {
                lastElementIndex = index
            }
        }
        return lastElementIndex >= 0 ? lastElementIndex + 1 : 0
    }

    // MARK: - Decoration

    private func decorateNativeItems(in menu: NSMenu) {
        for item in menu.items {
            if let identifier = SumiWebKitMenuItemIdentifier(item.identifier),
               item.image == nil,
               let symbolName = identifier.symbolName {
                item.image = SumiWebPageMenuIcon.make(symbolName, title: item.title)
            }

            if let submenu = item.submenu {
                decorateNativeItems(in: submenu)
            }
        }
    }

    private func makeItem(_ entry: SumiWebPageMenuBlueprint.Entry) -> NSMenuItem {
        switch entry {
        case .separator:
            return .separator()
        case .command(let command):
            return itemFactory.makeItem(for: command, context: context)
        }
    }
}

@MainActor
extension NSMenu {
    func sumiNormalizeSeparators() {
        while items.first?.isSeparatorItem == true {
            removeItem(at: 0)
        }
        while items.last?.isSeparatorItem == true {
            removeItem(at: numberOfItems - 1)
        }

        var previousWasSeparator = false
        for index in items.indices.reversed() {
            let item = items[index]
            if item.isSeparatorItem, previousWasSeparator {
                removeItem(at: index)
                continue
            }
            previousWasSeparator = item.isSeparatorItem
        }
    }

    /// Menus mutated after presentation (the deferred rewrite path) keep
    /// stale layout metrics unless the item list is rebuilt.
    func sumiForceRelayout() {
        let currentItems = items
        removeAllItems()
        for item in currentItems {
            addItem(item)
        }
    }
}

private extension NSMenuItem {
    // WKMenuTarget keeps the legacy WebKit context action tag on the
    // identifier-less Stop item.
    var sumiIsWebKitStopItem: Bool {
        identifier == nil && tag == 11
    }
}
