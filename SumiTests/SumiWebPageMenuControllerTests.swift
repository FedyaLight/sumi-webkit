import AppKit
import WebKit
import XCTest
@testable import Sumi

@MainActor
final class SumiWebPageMenuControllerTests: XCTestCase {
    func testPageBackgroundMenuGetsBrowserSectionAndRemovesWebKitNavigation() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))
        menu.addItem(.separator())
        let inspectElement = webKitItem(title: "Inspect", identifier: .inspectElement)
        inspectElement.target = self
        inspectElement.action = #selector(noop(_:))
        menu.addItem(inspectElement)

        prepare(menu)

        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.reload.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue)?.image)
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.forward.rawValue)?.image)
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.reload.rawValue)?.image)
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.bookmarkPage.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.copyPageAddress.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.printPage.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.inspectElement.rawValue))
    }

    func testInteractiveElementMenuKeepsNativePageItemsWithoutSumiPageSection() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Back", identifier: .goBack))
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))
        let inspectElement = webKitItem(title: "Inspect", identifier: .inspectElement)
        inspectElement.target = self
        inspectElement.action = #selector(noop(_:))
        menu.addItem(inspectElement)

        prepare(menu, targetHint: .interactiveElement)

        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.goBack.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.reload.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.bookmarkPage.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.copyPageAddress.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.printPage.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.inspectElement.rawValue))
    }

    func testLinkMenuRemovesCurrentOpenAndSplitsNewTabFromNewWindow() {
        let menu = NSMenu()
        let openLink = webKitItem(title: "Open Link", identifier: .openLink)
        openLink.target = self
        openLink.action = #selector(noop(_:))
        menu.addItem(openLink)
        menu.addItem(webKitItem(title: "Open Link in New Window", identifier: .openLinkInNewWindow))
        menu.addItem(webKitItem(title: "Copy Link", identifier: .copyLink))
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))

        prepare(menu)

        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.openLink.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.reload.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.openLinkInNewWindow.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.openLinkInNewTab.rawValue)?.image)
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.openLinkInNewWindow.rawValue)?.image)
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.bookmarkPage.rawValue))
    }

    func testSelectedLinkMenuKeepsLinkCommandsAndAddsSelectionFallbacks() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Open Link in New Window", identifier: .openLinkInNewWindow))
        menu.addItem(webKitItem(title: "Download Linked File", identifier: .downloadLinkedFile))
        menu.addItem(webKitItem(title: "Copy Link", identifier: .copyLink))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Services", action: nil, keyEquivalent: ""))

        prepare(menu, targetHint: .link, selectedText: "Chicken Curry Live")

        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.openLinkInNewTab.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.openLinkInNewWindow.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.downloadLinkedFile.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.copyLink.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.copySelection.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.copyLinkToSelectedText.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.searchSelection.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.printPage.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.bookmarkPage.rawValue))
        XCTAssertLessThan(
            menu.indexOfItem(identifier: SumiWebPageMenuCommand.searchSelection.rawValue),
            menu.indexOfItem(withTitle: "Services")
        )
    }

    func testImageMenuUsesSumiDownloadPathAndAddsImageAddressCommand() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Open Image in New Window", identifier: .openImageInNewWindow))
        menu.addItem(webKitItem(title: "Save Image", identifier: .downloadImage))
        menu.addItem(webKitItem(title: "Copy Image", identifier: .copyImage))

        prepare(menu)

        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.openImageInNewWindow.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.downloadImage.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.openImageInNewTab.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.openImageInNewWindow.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.copyImageAddress.rawValue))
        XCTAssertEqual(
            menu.item(identifier: SumiWebPageMenuCommand.downloadImage.rawValue)?.action,
            #selector(SumiWebPageMenuController.downloadNativeContextResource(_:))
        )
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
    }

    func testLinkedImageMenuPrefersImageDownloadAndAvoidsRedundantPageItems() {
        let menu = NSMenu()
        let disabledLookUp = webKitItem(title: "Look Up", identifier: .lookUp)
        disabledLookUp.isEnabled = false
        menu.addItem(webKitItem(title: "Open Link", identifier: .openLink))
        menu.addItem(webKitItem(title: "Open Link in New Window", identifier: .openLinkInNewWindow))
        menu.addItem(webKitItem(title: "Download Linked File", identifier: .downloadLinkedFile))
        menu.addItem(webKitItem(title: "Copy Link", identifier: .copyLink))
        menu.addItem(.separator())
        menu.addItem(webKitItem(title: "Open Image in New Window", identifier: .openImageInNewWindow))
        menu.addItem(webKitItem(title: "Download Image", identifier: .downloadImage))
        menu.addItem(webKitItem(title: "Copy Image", identifier: .copyImage))
        menu.addItem(disabledLookUp)
        menu.addItem(.separator())
        menu.addItem(webKitItem(title: "Share...", identifier: .shareMenu))

        prepare(menu)

        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.openLink.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.downloadLinkedFile.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.openImageInNewWindow.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.openImageInNewWindow.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.lookUp.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.shareMenu.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.openLinkInNewTab.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.openLinkInNewWindow.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.copyLink.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.openImageInNewTab.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.copyImageAddress.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.downloadImage.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.copyImage.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.inspectElement.rawValue))
    }

    func testEditableMenuDropsWebKitSpellingFamilyWithoutPageCommands() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Paste", identifier: .paste))
        menu.addItem(webKitItem(title: "Spelling and Grammar", identifier: .spellingMenu))
        menu.addItem(webKitItem(title: "Show Spelling", identifier: .showSpellingPanel))
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))

        prepare(menu)

        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.paste.rawValue)?.image)
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.spellingMenu.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.showSpellingPanel.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
    }

    func testCurrentWritingToolsIdentifierPreventsPageCommands() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Writing Tools", identifier: .writingTools))
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))

        prepare(menu)

        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.writingTools.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.bookmarkPage.rawValue))
    }

    func testReusedPageMenuDoesNotDuplicateSumiSection() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))
        let webView = FocusableWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let controller = SumiWebPageMenuController()

        controller.prepare(menu, for: webView)
        controller.prepare(menu, for: webView)

        XCTAssertEqual(menu.items.count {
            $0.identifier?.rawValue == SumiWebPageMenuCommand.back.rawValue
        }, 1)
        XCTAssertEqual(menu.items.count {
            $0.identifier?.rawValue == SumiWebPageMenuCommand.bookmarkPage.rawValue
        }, 1)
    }

    @objc private func noop(_: Any?) {}

    private func prepare(
        _ menu: NSMenu,
        targetHint: SumiWebPageContextMenuTargetKind? = nil,
        selectedText: String? = nil
    ) {
        let webView = FocusableWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        SumiWebPageMenuController().prepare(
            menu,
            for: webView,
            targetHint: targetHint,
            selectedText: selectedText
        )
    }

    private func webKitItem(
        title: String,
        identifier: SumiWebKitMenuItemIdentifier
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        return item
    }
}

private extension NSMenu {
    func item(identifier rawValue: String) -> NSMenuItem? {
        items.first { $0.identifier?.rawValue == rawValue }
    }

    func indexOfItem(identifier rawValue: String) -> Int {
        items.firstIndex { $0.identifier?.rawValue == rawValue } ?? -1
    }
}
