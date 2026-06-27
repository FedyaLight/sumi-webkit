import AppKit

/// Owns policy for mutating WebKit-provided context menu items while preserving
/// their native action targets for replay and request capture.
@MainActor
struct SumiWebPageNativeMenuComposer {
    let menu: NSMenu
    let context: SumiWebPageMenuContext
    let actionTarget: SumiWebPageMenuController

    private let snapshot: SumiWebPageMenuSnapshot

    init(
        menu: NSMenu,
        context: SumiWebPageMenuContext,
        actionTarget: SumiWebPageMenuController
    ) {
        self.menu = menu
        self.context = context
        self.actionTarget = actionTarget
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

    func replaceAmbiguousItems() {
        for (index, item) in menu.items.enumerated().reversed() {
            guard let identifier = SumiWebKitMenuItemIdentifier(item.identifier) else {
                continue
            }

            switch identifier {
            case .openLinkInNewWindow:
                replaceOpenItem(
                    at: index,
                    originalItem: item,
                    newTabTitle: "Open Link in New Tab",
                    tabCommand: .openLinkInNewTab,
                    windowCommand: .openLinkInNewWindow,
                    symbolName: "link"
                )
            case .openImageInNewWindow:
                replaceOpenItem(
                    at: index,
                    originalItem: item,
                    newTabTitle: "Open Image in New Tab",
                    tabCommand: .openImageInNewTab,
                    windowCommand: context.hasLinkContext ? nil : .openImageInNewWindow,
                    symbolName: "photo"
                )
                menu.insertItem(
                    makeNativeItem(
                        title: "Copy Image Address",
                        command: .copyImageAddress,
                        action: #selector(SumiWebPageMenuController.copyNativeImageAddress(_:)),
                        symbolName: "link",
                        primaryItem: item
                    ),
                    at: context.hasLinkContext ? index + 1 : index + 2
                )
            case .openMediaInNewWindow:
                replaceOpenItem(
                    at: index,
                    originalItem: item,
                    newTabTitle: item.title.sumiReplacingNewWindowWithNewTab(
                        fallback: "Open Media in New Tab"
                    ),
                    tabCommand: .openMediaInNewTab,
                    windowCommand: context.hasLinkContext ? nil : .openMediaInNewWindow,
                    symbolName: "play.rectangle"
                )
            case .openFrameInNewWindow:
                menu.removeItem(at: index)
                menu.insertItem(
                    makeNativeItem(
                        title: item.title,
                        command: .openFrameInNewWindow,
                        action: #selector(SumiWebPageMenuController.openNativeContextItemInNewWindow(_:)),
                        symbolName: "macwindow",
                        primaryItem: item
                    ),
                    at: index
                )
            case .downloadLinkedFile:
                replaceDownloadItem(
                    at: index,
                    originalItem: item,
                    command: .downloadLinkedFile,
                    requestItem: snapshot.item(for: .openLinkInNewWindow),
                    symbolName: "arrow.down.circle"
                )
            case .downloadImage:
                replaceDownloadItem(
                    at: index,
                    originalItem: item,
                    command: .downloadImage,
                    requestItem: snapshot.item(for: .openImageInNewWindow),
                    symbolName: "arrow.down.circle"
                )
            case .downloadMedia:
                replaceDownloadItem(
                    at: index,
                    originalItem: item,
                    command: .downloadMedia,
                    requestItem: snapshot.item(for: .openMediaInNewWindow),
                    symbolName: "arrow.down.circle"
                )
            default:
                continue
            }
        }
    }

    func decorateRemainingWebKitItems() {
        decorateWebKitItems(in: menu)
    }

    private func removeSuppressedWebKitItems(in menu: NSMenu) {
        for item in menu.items.reversed() {
            if let identifier = SumiWebKitMenuItemIdentifier(item.identifier),
               identifier.isSuppressedBySumi
            {
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

    private func replaceOpenItem(
        at index: Int,
        originalItem: NSMenuItem,
        newTabTitle: String,
        tabCommand: SumiWebPageMenuCommand,
        windowCommand: SumiWebPageMenuCommand?,
        symbolName: String
    ) {
        menu.removeItem(at: index)
        menu.insertItem(
            makeNativeItem(
                title: newTabTitle,
                command: tabCommand,
                action: #selector(SumiWebPageMenuController.openNativeContextItemInNewTab(_:)),
                symbolName: symbolName,
                primaryItem: originalItem
            ),
            at: index
        )
        guard let windowCommand else { return }
        menu.insertItem(
            makeNativeItem(
                title: originalItem.title,
                command: windowCommand,
                action: #selector(SumiWebPageMenuController.openNativeContextItemInNewWindow(_:)),
                symbolName: "macwindow",
                primaryItem: originalItem
            ),
            at: index + 1
        )
    }

    private func replaceDownloadItem(
        at index: Int,
        originalItem: NSMenuItem,
        command: SumiWebPageMenuCommand,
        requestItem: NSMenuItem?,
        symbolName: String
    ) {
        menu.removeItem(at: index)
        menu.insertItem(
            makeNativeItem(
                title: originalItem.title,
                command: command,
                action: #selector(SumiWebPageMenuController.downloadNativeContextResource(_:)),
                symbolName: symbolName,
                primaryItem: originalItem,
                requestItem: requestItem,
                fallbackItem: originalItem
            ),
            at: index
        )
    }

    private func decorateWebKitItems(in menu: NSMenu) {
        for item in menu.items {
            if let identifier = SumiWebKitMenuItemIdentifier(item.identifier),
               item.image == nil,
               let symbolName = identifier.symbolName
            {
                item.image = SumiWebPageMenuIcon.make(symbolName, title: item.title)
            }

            if let submenu = item.submenu {
                decorateWebKitItems(in: submenu)
            }
        }
    }

    private func makeItem(
        title: String,
        command: SumiWebPageMenuCommand,
        action: Selector,
        symbolName: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = actionTarget
        item.identifier = command.itemIdentifier
        item.image = SumiWebPageMenuIcon.make(symbolName, title: title)
        return item
    }

    private func makeNativeItem(
        title: String,
        command: SumiWebPageMenuCommand,
        action: Selector,
        symbolName: String,
        primaryItem: NSMenuItem,
        requestItem: NSMenuItem? = nil,
        fallbackItem: NSMenuItem? = nil
    ) -> NSMenuItem {
        let item = makeItem(
            title: title,
            command: command,
            action: action,
            symbolName: symbolName
        )
        item.isEnabled = primaryItem.isEnabled
        item.representedObject = SumiWebPageMenuNativeReference(
            primaryItem: primaryItem,
            requestItem: requestItem,
            fallbackItem: fallbackItem ?? primaryItem
        )
        return item
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

final class SumiWebPageMenuNativeReference: NSObject {
    let primaryItem: NSMenuItem
    let requestItem: NSMenuItem?
    let fallbackItem: NSMenuItem

    init(primaryItem: NSMenuItem, requestItem: NSMenuItem?, fallbackItem: NSMenuItem) {
        self.primaryItem = primaryItem
        self.requestItem = requestItem
        self.fallbackItem = fallbackItem
    }

    convenience init?(_ item: NSMenuItem) {
        guard let reference = item.representedObject as? SumiWebPageMenuNativeReference else {
            return nil
        }
        self.init(
            primaryItem: reference.primaryItem,
            requestItem: reference.requestItem,
            fallbackItem: reference.fallbackItem
        )
    }
}

private extension NSMenuItem {
    // WKMenuTarget keeps the legacy WebKit context action tag on action items.
    var sumiIsWebKitStopItem: Bool {
        identifier == nil && tag == 11
    }
}

private extension String {
    func sumiReplacingNewWindowWithNewTab(fallback: String) -> String {
        guard contains("New Window") else { return fallback }
        return replacingOccurrences(of: "New Window", with: "New Tab")
    }
}
