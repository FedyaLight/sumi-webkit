import AppKit

/// Builds Sumi-owned menu items: title (static or context-derived), action
/// selector, identifier, and SF Symbol icon.
@MainActor
struct SumiWebPageMenuItemFactory {
    let actionTarget: SumiWebPageMenuActionOwner

    func makeItem(
        for command: SumiWebPageMenuCommand,
        context: SumiWebPageMenuContext
    ) -> NSMenuItem {
        let title = title(for: command, context: context)
        let item = NSMenuItem(
            title: title,
            action: SumiWebPageMenuActionOwner.action(for: command),
            keyEquivalent: ""
        )
        item.target = actionTarget
        item.identifier = command.itemIdentifier
        item.image = SumiWebPageMenuIcon.make(command.symbolName, title: title)
        return item
    }

    private func title(
        for command: SumiWebPageMenuCommand,
        context: SumiWebPageMenuContext
    ) -> String {
        switch command {
        case .back:
            return SumiWebPageMenuStrings.back
        case .forward:
            return SumiWebPageMenuStrings.forward
        case .reload:
            return SumiWebPageMenuStrings.reloadPage
        case .stop:
            return SumiWebPageMenuStrings.stopLoading
        case .bookmarkPage:
            return SumiWebPageMenuStrings.bookmarkPage
        case .copyPageAddress:
            return SumiWebPageMenuStrings.copyPageAddress
        case .printPage:
            return SumiWebPageMenuStrings.printPage
        case .copySelection:
            return SumiWebPageMenuStrings.copySelection
        case .copyLinkToSelectedText:
            return SumiWebPageMenuStrings.copyLinkToSelectedText
        case .searchSelection:
            return SumiWebPageMenuStrings.searchItemTitle(
                provider: context.searchProviderName,
                snippet: SumiWebPageMenuTextFormatter.menuSnippet(
                    for: context.selectedText ?? ""
                )
            )
        case .openLinkInNewTab:
            return SumiWebPageMenuStrings.openLinkInNewTab
        case .openLinkInSplitView:
            return SumiWebPageMenuStrings.openLinkInSplitView
        case .openLinkInNewWindow:
            return SumiWebPageMenuStrings.openLinkInNewWindow
        case .addLinkToBookmarks:
            return SumiWebPageMenuStrings.addLinkToBookmarks
        case .copyLink:
            return SumiWebPageMenuStrings.copyLink
        case .copyEmailAddress:
            return context.mailtoAddresses.count > 1
                ? SumiWebPageMenuStrings.copyEmailAddresses
                : SumiWebPageMenuStrings.copyEmailAddress
        case .openImageInNewTab:
            return SumiWebPageMenuStrings.openImageInNewTab
        case .openImageInNewWindow:
            return SumiWebPageMenuStrings.openImageInNewWindow
        case .copyImageAddress:
            return SumiWebPageMenuStrings.copyImageAddress
        }
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
