import AppKit

/// Owns policy for minimally decorating WebKit-provided context menu items.
/// Resource actions and their targets remain wholly owned by WebKit.
@MainActor
struct SumiWebPageNativeMenuComposer {
    let menu: NSMenu
    let context: SumiWebPageMenuContext

    private let snapshot: SumiWebPageMenuSnapshot

    init(
        menu: NSMenu,
        context: SumiWebPageMenuContext
    ) {
        self.menu = menu
        self.context = context
        self.snapshot = SumiWebPageMenuSnapshot(menu: menu)
    }

    func removeSuppressedItems() {
        removeSuppressedWebKitItems(in: menu)
    }

    func removePageNavigationItems() {
        for item in menu.items.reversed() {
            guard SumiWebKitMenuItemIdentifier(item.identifier)?.isPageNavigation == true
                    || item.sumiIsWebKitStopItem
            else { continue }
            menu.removeItem(item)
        }
        menu.sumiNormalizeSeparators()
    }

    func removeContextuallyRedundantItems() {
        guard context.hasElementContext else { return }

        for item in menu.items.reversed() {
            guard let identifier = SumiWebKitMenuItemIdentifier(item.identifier) else {
                continue
            }

            let shouldRemove: Bool = switch identifier {
            case .openLink:
                true
            case .downloadLinkedFile:
                context.hasImageContext
            case .shareMenu:
                true
            case .lookUp:
                !item.isEnabled
            default:
                false
            }

            if shouldRemove {
                menu.removeItem(item)
            }
        }
        menu.sumiNormalizeSeparators()
    }

    func applyInspectElementPolicy(isDeveloperInspectionEnabled: Bool) {
        if isDeveloperInspectionEnabled {
            decorateNativeInspectElement()
        } else {
            removeNativeInspectElement()
        }
    }

    func decorateRemainingWebKitItems() {
        decorateWebKitItems(in: menu)
    }

    private func removeSuppressedWebKitItems(in menu: NSMenu) {
        for item in menu.items.reversed() {
            if let identifier = SumiWebKitMenuItemIdentifier(item.identifier),
               identifier.isSuppressedBySumi {
                menu.removeItem(item)
                continue
            }

            if let submenu = item.submenu {
                removeSuppressedWebKitItems(in: submenu)
                submenu.sumiNormalizeSeparators()
            }
        }
    }

    private func decorateNativeInspectElement() {
        guard let nativeInspectItem = snapshot.item(for: .inspectElement),
              menu.items.contains(where: { $0 === nativeInspectItem })
        else {
            return
        }

        nativeInspectItem.title = "Inspect Element"
        nativeInspectItem.image = SumiWebPageMenuIcon.make("hammer", title: nativeInspectItem.title)
    }

    private func removeNativeInspectElement() {
        guard let nativeInspectItem = snapshot.item(for: .inspectElement),
              menu.items.contains(where: { $0 === nativeInspectItem })
        else {
            return
        }
        menu.removeItem(nativeInspectItem)
    }

    private func decorateWebKitItems(in menu: NSMenu) {
        for item in menu.items {
            if let identifier = SumiWebKitMenuItemIdentifier(item.identifier),
               item.image == nil,
               let symbolName = identifier.symbolName {
                item.image = SumiWebPageMenuIcon.make(symbolName, title: item.title)
            }

            if let submenu = item.submenu {
                decorateWebKitItems(in: submenu)
            }
        }
    }

}

private struct SumiWebPageMenuSnapshot {
    private let webKitItems: [SumiWebKitMenuItemIdentifier: NSMenuItem]

    init(menu: NSMenu) {
        webKitItems = menu.items.reduce(into: [:]) { items, item in
            guard let identifier = SumiWebKitMenuItemIdentifier(item.identifier) else {
                return
            }
            items[identifier] = item
        }
    }

    func item(for identifier: SumiWebKitMenuItemIdentifier) -> NSMenuItem? {
        webKitItems[identifier]
    }
}

private extension NSMenuItem {
    // WKMenuTarget keeps the legacy WebKit context action tag on action items.
    var sumiIsWebKitStopItem: Bool {
        identifier == nil && tag == 11
    }
}
