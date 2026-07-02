import AppKit

@MainActor
struct SumiWebPageMenuItemFactory {
    let actionTarget: SumiWebPageMenuController

    func makeItem(
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
}

enum SumiWebPageMenuIcon {
    static func make(_ symbolName: String, title: String) -> NSImage? {
        guard let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: title
        ) else {
            return nil
        }

        return image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        )
    }
}
