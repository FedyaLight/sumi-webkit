import AppKit
@testable import Sumi
import SumiWebRuntime
import WebKit
import XCTest

/// NSMenu-level integration of the web page menu system: presenter lifecycle,
/// rewrite results per context, deferral, and native action identity.
@MainActor
final class SumiWebPageMenuPresenterTests: XCTestCase {
    // MARK: - Page background

    func testPageBackgroundMenuGetsOwnedSectionAndRemovesWebKitNavigation() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))
        menu.addItem(.separator())
        let inspectElement = webKitItem(title: "Inspect", identifier: .inspectElement)
        inspectElement.target = self
        inspectElement.action = #selector(noop(_:))
        menu.addItem(inspectElement)

        prepare(menu, kind: .page)

        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.reload.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue)?.image)
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.forward.rawValue)?.image)
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.reload.rawValue)?.image)
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.bookmarkPage.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.copyPageAddress.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.printPage.rawValue))
        let survivingInspect = menu.item(
            identifier: SumiWebKitMenuItemIdentifier.inspectElement.rawValue
        )
        XCTAssertIdentical(survivingInspect, inspectElement)
        XCTAssertIdentical(survivingInspect?.target as AnyObject?, self)
        XCTAssertEqual(survivingInspect?.action, #selector(noop(_:)))
    }

    func testInteractiveElementMenuKeepsNativePageItemsWithoutOwnedSection() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Back", identifier: .goBack))
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))

        prepare(menu, kind: .interactiveElement)

        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.goBack.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.reload.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.bookmarkPage.rawValue))
    }

    func testFrameMenuKeepsNativeFrameItemAndAddsPageSection() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))
        let frameItem = webKitItem(
            title: "Open Frame in New Window",
            identifier: .openFrameInNewWindow
        )
        frameItem.target = self
        frameItem.action = #selector(noop(_:))
        menu.addItem(frameItem)

        prepare(menu, kind: .page)

        XCTAssertIdentical(
            menu.item(identifier: SumiWebKitMenuItemIdentifier.openFrameInNewWindow.rawValue),
            frameItem
        )
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.bookmarkPage.rawValue))
    }

    // MARK: - Link

    func testWebLinkMenuBuildsParityItemSet() throws {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Open Link", identifier: .openLink))
        menu.addItem(webKitItem(title: "Open Link in New Window", identifier: .openLinkInNewWindow))
        let nativeDownload = webKitItem(title: "Download Linked File", identifier: .downloadLinkedFile)
        nativeDownload.target = self
        nativeDownload.action = #selector(noop(_:))
        menu.addItem(nativeDownload)
        menu.addItem(webKitItem(title: "Copy Link", identifier: .copyLink))

        prepare(menu, kind: .link, linkHref: "https://example.com/page")

        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.openLink.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.copyLink.rawValue))

        let openInNewTab = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.openLinkInNewTab.rawValue)
        )
        XCTAssertEqual(openInNewTab.title, "Open Link in New Tab")
        XCTAssertEqual(menu.index(of: openInNewTab), 0)

        let openInNewWindow = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.openLinkInNewWindow.rawValue)
        )
        XCTAssertEqual(openInNewWindow.title, "Open Link in New Window")

        let download = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.downloadLinkedFile.rawValue)
        )
        XCTAssertFalse(download === nativeDownload)
        XCTAssertEqual(download.title, "Download Linked File As…")

        let addToBookmarks = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.addLinkToBookmarks.rawValue)
        )
        let ownedCopyLink = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.copyLink.rawValue)
        )
        XCTAssertEqual(menu.index(of: addToBookmarks), menu.index(of: ownedCopyLink) - 1)
    }

    func testMailtoLinkMenuReducesToCopyEmailAddressWithPluralTitle() throws {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Open Link", identifier: .openLink))
        menu.addItem(webKitItem(title: "Open Link in New Window", identifier: .openLinkInNewWindow))
        menu.addItem(webKitItem(title: "Download Linked File", identifier: .downloadLinkedFile))
        menu.addItem(webKitItem(title: "Copy Link", identifier: .copyLink))

        prepare(menu, kind: .link, linkHref: "mailto:a@example.com,b@example.com")

        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.openLink.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.openLinkInNewWindow.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.downloadLinkedFile.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.openLinkInNewTab.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.addLinkToBookmarks.rawValue))

        let copyEmail = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.copyEmailAddress.rawValue)
        )
        XCTAssertEqual(copyEmail.title, "Copy Email Addresses")
    }

    func testLinkMenuWithSelectionInsertsSelectionBlockAfterCopyLink() throws {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Open Link", identifier: .openLink))
        menu.addItem(webKitItem(title: "Open Link in New Window", identifier: .openLinkInNewWindow))
        menu.addItem(webKitItem(title: "Download Linked File", identifier: .downloadLinkedFile))
        menu.addItem(webKitItem(title: "Copy Link", identifier: .copyLink))
        menu.addItem(webKitItem(title: "Search the Web", identifier: .searchWeb))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Services", action: nil, keyEquivalent: ""))

        prepare(
            menu,
            kind: .link,
            selectedText: "Chicken Curry Live",
            linkHref: "https://example.com/page"
        )

        let copyLinkIndex = menu.indexOfItem(identifier: SumiWebPageMenuCommand.copyLink.rawValue)
        let copyIndex = menu.indexOfItem(identifier: SumiWebPageMenuCommand.copySelection.rawValue)
        let copyFragmentIndex = menu.indexOfItem(
            identifier: SumiWebPageMenuCommand.copyLinkToSelectedText.rawValue
        )
        let searchIndex = menu.indexOfItem(identifier: SumiWebPageMenuCommand.searchSelection.rawValue)

        XCTAssertGreaterThan(copyIndex, copyLinkIndex)
        XCTAssertEqual(copyFragmentIndex, copyIndex + 1)
        XCTAssertEqual(searchIndex, copyFragmentIndex + 1)
        XCTAssertLessThan(searchIndex, menu.indexOfItem(withTitle: "Services"))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.searchWeb.rawValue))
        let searchItem = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.searchSelection.rawValue)
        )
        XCTAssertTrue(searchItem.title.contains("Chicken Curry Live"))
    }

    func testLinkMenuWithoutSnapshotKeepsNativeResourceItemsAfterTimeout() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Open Link", identifier: .openLink))
        let nativeNewWindow = webKitItem(
            title: "Open Link in New Window",
            identifier: .openLinkInNewWindow
        )
        nativeNewWindow.target = self
        nativeNewWindow.action = #selector(noop(_:))
        menu.addItem(nativeNewWindow)
        menu.addItem(webKitItem(title: "Copy Link", identifier: .copyLink))

        let webView = makeWebView()
        let presenter = SumiWebPageMenuPresenter()
        presenter.menuWillOpen(menu, for: webView)

        // No snapshot yet: the rewrite is deferred and the menu is untouched.
        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.openLink.rawValue))

        let timeout = expectation(description: "fallback rewrite")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + SumiWebPageMenuPresenter.deferredSnapshotTimeout + 0.2
        ) { timeout.fulfill() }
        wait(for: [timeout], timeout: 2)

        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.openLink.rawValue))
        XCTAssertIdentical(
            menu.item(identifier: SumiWebKitMenuItemIdentifier.openLinkInNewWindow.rawValue),
            nativeNewWindow
        )
        XCTAssertIdentical(nativeNewWindow.target as AnyObject?, self)
        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.copyLink.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.openLinkInNewTab.rawValue))
    }

    // MARK: - Image

    func testImageMenuBuildsParityItemSet() throws {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Open Image in New Window", identifier: .openImageInNewWindow))
        let nativeDownload = webKitItem(title: "Download Image", identifier: .downloadImage)
        nativeDownload.target = self
        nativeDownload.action = #selector(noop(_:))
        menu.addItem(nativeDownload)
        menu.addItem(webKitItem(title: "Copy Image", identifier: .copyImage))

        let webView = makeWebView()
        webView.contextMenu.record(
            SumiWebPageContextMenuTargetSnapshot(
                kind: .image,
                imageSrc: "https://example.com/cat.png"
            )
        )
        let presenter = SumiWebPageMenuPresenter()
        presenter.menuWillOpen(menu, for: webView)

        let openInNewTab = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.openImageInNewTab.rawValue)
        )
        XCTAssertEqual(menu.index(of: openInNewTab), 0)
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.openImageInNewWindow.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.openImageInNewWindow.rawValue))

        let download = try XCTUnwrap(
            menu.items.first { $0.title == "Save Image As…" }
        )
        XCTAssertFalse(download === nativeDownload)
        XCTAssertTrue(download.target is SumiWebPageMenuActionOwner)
        XCTAssertEqual(download.title, "Save Image As…")

        let copyAddress = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.copyImageAddress.rawValue)
        )
        let copyImageIndex = menu.indexOfItem(identifier: SumiWebPageMenuCommand.copyImage.rawValue)
        XCTAssertEqual(menu.index(of: copyAddress), copyImageIndex - 1)
        withExtendedLifetime(presenter) {}
    }

    func testLinkedImageMenuKeepsBothDownloadItems() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Open Link", identifier: .openLink))
        menu.addItem(webKitItem(title: "Open Link in New Window", identifier: .openLinkInNewWindow))
        menu.addItem(webKitItem(title: "Download Linked File", identifier: .downloadLinkedFile))
        menu.addItem(webKitItem(title: "Copy Link", identifier: .copyLink))
        menu.addItem(.separator())
        menu.addItem(webKitItem(title: "Open Image in New Window", identifier: .openImageInNewWindow))
        menu.addItem(webKitItem(title: "Download Image", identifier: .downloadImage))
        menu.addItem(webKitItem(title: "Copy Image", identifier: .copyImage))

        prepare(
            menu,
            kind: .link,
            linkHref: "https://example.com/page",
            imageSrc: "https://example.com/cat.png"
        )

        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.downloadLinkedFile.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.saveImageAs.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.openLinkInNewTab.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.openImageInNewTab.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.copyImageAddress.rawValue))
    }

    func testImageMenuWithoutSnapshotKeepsNativeDownload() {
        let menu = NSMenu()
        let nativeDownload = webKitItem(title: "Save Image As…", identifier: .downloadImage)
        nativeDownload.target = self
        nativeDownload.action = #selector(noop(_:))
        menu.addItem(nativeDownload)
        let webView = makeWebView()
        let presenter = SumiWebPageMenuPresenter()

        presenter.menuWillOpen(menu, for: webView)

        let timeout = expectation(description: "fallback rewrite")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + SumiWebPageMenuPresenter.deferredSnapshotTimeout + 0.2
        ) { timeout.fulfill() }
        wait(for: [timeout], timeout: 2)

        XCTAssertIdentical(
            menu.item(identifier: SumiWebKitMenuItemIdentifier.downloadImage.rawValue),
            nativeDownload
        )
        XCTAssertIdentical(nativeDownload.target as AnyObject?, self)
        XCTAssertEqual(nativeDownload.action, #selector(noop(_:)))
        withExtendedLifetime((presenter, webView)) {}
    }

    // MARK: - Media

    func testMediaDownloadUsesSumiOwnedAction() throws {
        let menu = NSMenu()
        let nativeDownload = webKitItem(title: "Download Video", identifier: .downloadMedia)
        nativeDownload.target = self
        nativeDownload.action = #selector(noop(_:))
        menu.addItem(nativeDownload)

        let webView = makeWebView()
        webView.contextMenu.record(
            SumiWebPageContextMenuTargetSnapshot(
                kind: .media,
                mediaSrc: "https://example.com/video.mp4"
            )
        )
        let presenter = SumiWebPageMenuPresenter()
        presenter.menuWillOpen(menu, for: webView)

        let download = try XCTUnwrap(
            menu.items.first { $0.title == "Download Video" }
        )
        XCTAssertFalse(download === nativeDownload)
        XCTAssertTrue(download.target is SumiWebPageMenuActionOwner)
        XCTAssertNotNil(download.action)
    }

    // MARK: - Selection

    func testSelectionMenuReplacesSearchWebInPlaceAndPreservesNatives() throws {
        let menu = NSMenu()
        let lookUp = webKitItem(title: "Look Up", identifier: .lookUp)
        lookUp.target = self
        lookUp.action = #selector(noop(_:))
        menu.addItem(lookUp)
        menu.addItem(webKitItem(title: "Translate", identifier: .translate))
        menu.addItem(webKitItem(title: "Search the Web", identifier: .searchWeb))
        menu.addItem(.separator())
        let copy = webKitItem(title: "Copy", identifier: .copy)
        copy.target = self
        copy.action = #selector(noop(_:))
        menu.addItem(copy)

        prepare(menu, kind: .otherElement, selectedText: "Chicken Curry Live")

        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.searchWeb.rawValue))
        let search = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.searchSelection.rawValue)
        )
        XCTAssertEqual(menu.index(of: search), 2)
        XCTAssertIdentical(
            menu.item(identifier: SumiWebKitMenuItemIdentifier.lookUp.rawValue),
            lookUp
        )
        XCTAssertIdentical(lookUp.target as AnyObject?, self)

        let copyFragment = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.copyLinkToSelectedText.rawValue)
        )
        XCTAssertEqual(menu.index(of: copyFragment), menu.index(of: copy) + 1)
    }

    func testEditableMenuKeepsSpellingFamilyAndSuppressesTextFragmentCopy() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Copy", identifier: .copy))
        menu.addItem(webKitItem(title: "Paste", identifier: .paste))
        menu.addItem(webKitItem(title: "Spelling and Grammar", identifier: .spellingMenu))
        menu.addItem(webKitItem(title: "Show Spelling", identifier: .showSpellingPanel))

        prepare(menu, kind: .editable, selectedText: "typed text")

        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.spellingMenu.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.showSpellingPanel.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.paste.rawValue)?.image)
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.copyLinkToSelectedText.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
    }

    func testInteractiveElementSelectionGetsFallbackSection() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))

        prepare(menu, kind: .interactiveElement, selectedText: "first clone selection")

        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.copySelection.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.copyLinkToSelectedText.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.searchSelection.rawValue))
    }

    // MARK: - Deferral lifecycle

    func testDeferredRewriteRunsWhenSnapshotArrives() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))
        let webView = makeWebView()
        let presenter = SumiWebPageMenuPresenter()

        presenter.menuWillOpen(menu, for: webView)
        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.reload.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue))

        webView.contextMenu.record(SumiWebPageContextMenuTargetSnapshot(kind: .page))

        XCTAssertNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.reload.rawValue))
        XCTAssertNotNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
    }

    func testMenuDidCloseCancelsDeferredRewrite() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))
        let webView = makeWebView()
        let presenter = SumiWebPageMenuPresenter()

        presenter.menuWillOpen(menu, for: webView)
        presenter.menuDidClose(menu)
        webView.contextMenu.record(SumiWebPageContextMenuTargetSnapshot(kind: .page))

        XCTAssertNotNil(menu.item(identifier: SumiWebKitMenuItemIdentifier.reload.rawValue))
        XCTAssertNil(menu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
    }

    func testLaterSnapshotCannotRewritePreparedMenuAgain() throws {
        let menu = NSMenu()
        let nativeOpen = webKitItem(
            title: "Open Image in New Window",
            identifier: .openImageInNewWindow
        )
        nativeOpen.target = self
        nativeOpen.action = #selector(noop(_:))
        menu.addItem(nativeOpen)
        let webView = makeWebView()
        webView.contextMenu.record(SumiWebPageContextMenuTargetSnapshot(kind: .image))
        let presenter = SumiWebPageMenuPresenter()

        presenter.menuWillOpen(menu, for: webView)
        let preparedItem = try XCTUnwrap(
            menu.item(identifier: SumiWebKitMenuItemIdentifier.openImageInNewWindow.rawValue)
        )

        webView.contextMenu.record(SumiWebPageContextMenuTargetSnapshot(kind: .link))

        XCTAssertIdentical(preparedItem, nativeOpen)
        XCTAssertIdentical(preparedItem.target as AnyObject?, self)
        XCTAssertEqual(preparedItem.action, #selector(noop(_:)))
    }

    func testReusedMenuDoesNotDuplicateOwnedSection() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))
        let webView = makeWebView()
        webView.contextMenu.record(SumiWebPageContextMenuTargetSnapshot(kind: .page))
        let presenter = SumiWebPageMenuPresenter()

        presenter.menuWillOpen(menu, for: webView)
        presenter.menuWillOpen(menu, for: webView)

        XCTAssertEqual(menu.items.count {
            $0.identifier?.rawValue == SumiWebPageMenuCommand.back.rawValue
        }, 1)
        XCTAssertEqual(menu.items.count {
            $0.identifier?.rawValue == SumiWebPageMenuCommand.bookmarkPage.rawValue
        }, 1)
    }

    func testContextMenuSnapshotsRemainScopedToPhysicalWebViewClones() {
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            loadsCachedFaviconOnInit: false
        )
        let elementWebView = makeWebView()
        let pageWebView = makeWebView()
        elementWebView.owningTab = tab
        pageWebView.owningTab = tab
        elementWebView.contextMenu.record(
            SumiWebPageContextMenuTargetSnapshot(
                kind: .interactiveElement,
                selectedText: "first clone selection"
            )
        )
        pageWebView.contextMenu.record(
            SumiWebPageContextMenuTargetSnapshot(kind: .page)
        )

        let elementMenu = NSMenu()
        elementMenu.addItem(webKitItem(title: "Reload", identifier: .reload))
        let pageMenu = NSMenu()
        pageMenu.addItem(webKitItem(title: "Reload", identifier: .reload))

        SumiWebPageMenuPresenter().menuWillOpen(elementMenu, for: elementWebView)
        SumiWebPageMenuPresenter().menuWillOpen(pageMenu, for: pageWebView)

        XCTAssertNil(elementMenu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
        XCTAssertNotNil(elementMenu.item(identifier: SumiWebPageMenuCommand.copySelection.rawValue))
        XCTAssertNotNil(pageMenu.item(identifier: SumiWebPageMenuCommand.back.rawValue))
        XCTAssertNil(pageMenu.item(identifier: SumiWebPageMenuCommand.copySelection.rawValue))
    }

    // MARK: - Extension items

    func testWebKitHostedExtensionItemsRemainSingle() {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Reload", identifier: .reload))
        let webKitHostedItem = NSMenuItem(
            title: "Extension Item",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(webKitHostedItem)
        let webView = makeWebView()
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            loadsCachedFaviconOnInit: false
        )
        webView.owningTab = tab
        webView.contextMenu.record(SumiWebPageContextMenuTargetSnapshot(kind: .editable))

        SumiWebPageMenuPresenter().menuWillOpen(menu, for: webView)

        XCTAssertEqual(
            menu.items.filter { $0.title == "Extension Item" }.count,
            1
        )
        XCTAssertTrue(menu.items.contains { $0 === webKitHostedItem })
    }

    func testEveryUnownedWebKitCommandPreservesNativeTargetAndAction() {
        let menu = NSMenu()
        var nativeItems: [SumiWebKitMenuItemIdentifier: NSMenuItem] = [:]
        for identifier in SumiWebKitMenuItemIdentifier.allCases {
            let item = webKitItem(title: identifier.rawValue, identifier: identifier)
            item.target = self
            item.action = #selector(noop(_:))
            menu.addItem(item)
            nativeItems[identifier] = item
        }

        prepare(menu, kind: .editable)

        for (identifier, originalItem) in nativeItems {
            if identifier == .openLink {
                XCTAssertNil(menu.item(identifier: identifier.rawValue), "\(identifier) should be removed")
                continue
            }
            let survivingItem = menu.item(identifier: identifier.rawValue)
            XCTAssertIdentical(survivingItem, originalItem, "\(identifier) was replaced")
            XCTAssertIdentical(survivingItem?.target as AnyObject?, self, "\(identifier) lost its target")
            XCTAssertEqual(survivingItem?.action, #selector(noop(_:)), "\(identifier) lost its action")
        }
    }

    // MARK: - Validation and commands

    func testLinkCommandsDisabledWithoutOwningTab() throws {
        let menu = NSMenu()
        menu.addItem(webKitItem(title: "Open Link", identifier: .openLink))
        menu.addItem(webKitItem(title: "Open Link in New Window", identifier: .openLinkInNewWindow))
        menu.addItem(webKitItem(title: "Copy Link", identifier: .copyLink))

        prepare(menu, kind: .link, linkHref: "https://example.com/page")

        let openInNewTab = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.openLinkInNewTab.rawValue)
        )
        XCTAssertFalse(openInNewTab.isEnabled)
        let copyLink = try XCTUnwrap(
            menu.item(identifier: SumiWebPageMenuCommand.copyLink.rawValue)
        )
        XCTAssertTrue(copyLink.isEnabled)
    }

    func testBookmarkLinkCommandForwardsURLAndTitle() {
        var received: (url: URL, title: String?)?
        let commands = TabWebPageMenuCommands(
            appearance: { _, fallback in fallback },
            canBookmark: { _ in true },
            requestBookmarkEditor: { _ in true },
            bookmarkLink: { _, url, title in
                received = (url, title)
                return true
            },
            download: { _, _ in false }
        )

        let webView = makeWebView()
        let url = URL(string: "https://example.com/page")!
        XCTAssertTrue(commands.bookmarkLink(from: webView, url: url, title: "Example"))
        XCTAssertEqual(received?.url, url)
        XCTAssertEqual(received?.title, "Example")
    }

    func testDownloadCommandForwardsPhysicalWebViewAndURL() {
        let webView = makeWebView()
        let url = URL(string: "https://example.com/video.mp4")!
        var received: (webView: FocusableWKWebView, url: URL)?
        let commands = TabWebPageMenuCommands(
            appearance: { _, fallback in fallback },
            canBookmark: { _ in false },
            requestBookmarkEditor: { _ in false },
            bookmarkLink: { _, _, _ in false },
            download: { sourceWebView, sourceURL in
                received = (sourceWebView, sourceURL)
                return true
            }
        )

        XCTAssertTrue(commands.download(from: webView, url: url))
        XCTAssertTrue(received?.webView === webView)
        XCTAssertEqual(received?.url, url)
    }

    func testMediaDownloadActionDispatchesSnapshotURL() {
        let url = URL(string: "https://example.com/video.mp4")!
        assertDownloadAction(
            url: url,
            snapshot: SumiWebPageContextMenuTargetSnapshot(
                kind: .media,
                mediaSrc: url.absoluteString
            )
        ) { $0.downloadMedia(nil) }
    }

    func testLinkedFileDownloadActionDispatchesSnapshotURL() {
        let url = URL(string: "https://example.com/archive.zip")!
        assertDownloadAction(
            url: url,
            snapshot: SumiWebPageContextMenuTargetSnapshot(
                kind: .link,
                linkHref: url.absoluteString
            )
        ) { $0.downloadLinkedFile(nil) }
    }

    func testImageDownloadActionDispatchesSnapshotURL() {
        let url = URL(string: "https://example.com/cat.png")!
        assertDownloadAction(
            url: url,
            snapshot: SumiWebPageContextMenuTargetSnapshot(
                kind: .image,
                imageSrc: url.absoluteString
            )
        ) { $0.saveImageAs(nil) }
    }

    private func assertDownloadAction(
        url: URL,
        snapshot: SumiWebPageContextMenuTargetSnapshot,
        perform: (SumiWebPageMenuActionOwner) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let webView = makeWebView()
        let tab = Tab(url: URL(string: "https://example.com")!)
        var receivedURL: URL?
        var runtime = TabBrowserRuntime.inactive
        runtime.webPageMenuCommands = TabWebPageMenuCommands(
            appearance: { _, fallback in fallback },
            canBookmark: { _ in false },
            requestBookmarkEditor: { _ in false },
            bookmarkLink: { _, _, _ in false },
            download: { _, sourceURL in
                receivedURL = sourceURL
                return true
            }
        )
        tab.attachBrowserRuntime(runtime)
        webView.owningTab = tab
        let context = SumiWebPageMenuContext(
            menu: NSMenu(),
            snapshot: snapshot,
            searchProviderName: "DuckDuckGo",
            isLoading: false,
            isDeveloperInspectionEnabled: false
        )
        let owner = SumiWebPageMenuActionOwner()
        owner.prepare(webView: webView, context: context)

        perform(owner)

        XCTAssertEqual(receivedURL, url, file: file, line: line)
    }

    func testFactoryProducesNonEmptyTitleAndIconForEveryCommand() {
        let context = SumiWebPageMenuContext(
            menu: NSMenu(),
            snapshot: SumiWebPageContextMenuTargetSnapshot(
                kind: .link,
                selectedText: "text",
                linkHref: "mailto:a@example.com"
            ),
            searchProviderName: "DuckDuckGo",
            isLoading: false,
            isDeveloperInspectionEnabled: false
        )
        let actionTarget = SumiWebPageMenuActionOwner()
        let factory = SumiWebPageMenuItemFactory(actionTarget: actionTarget)

        for command in SumiWebPageMenuCommand.allCases {
            let item = factory.makeItem(for: command, context: context)
            XCTAssertFalse(item.title.isEmpty, "\(command) has an empty title")
            XCTAssertNotNil(item.image, "\(command) has no icon")
            XCTAssertEqual(item.identifier, command.itemIdentifier)
            XCTAssertNotNil(item.action, "\(command) has no action")
            if let action = item.action {
                XCTAssertTrue(
                    actionTarget.responds(to: action),
                    "\(command) points to an unavailable action"
                )
            }
        }
    }

    func testOpenActionsRouteExactURLsAndDispositions() {
        let pageURL = URL(string: "https://source.example/article")!
        let linkURL = URL(string: "https://target.example/page")!
        let imageURL = URL(string: "https://target.example/image.png")!
        let webView = makeWebView()
        let tab = Tab(url: pageURL)
        let window = BrowserWindowState()
        let profile = Profile(
            name: "Menu Actions",
            dataStore: webView.configuration.websiteDataStore
        )
        let space = Space(name: "Menu Actions", profileId: profile.id)
        let receipt = PhysicalWebViewSourceReceipt(
            webView: webView,
            trackedWebView: TrackedWebViewOwner(tabID: tab.id, windowID: window.id),
            tab: tab,
            window: window,
            residence: .regularSpaceMember,
            presentationSpace: space,
            presentationProfile: profile,
            executionProfile: profile,
            dataStore: profile.dataStore,
            appKitWindow: nil
        )
        var routes: [(URL, TabLinkDisposition)] = []
        var runtime = TabBrowserRuntime.inactive
        runtime.linkPresentationCommands = TabLinkPresentationCommands(
            resolveSource: { $0 === webView ? receipt : nil },
            openTab: { url, _, selected in
                routes.append((url, .newTab(selected: selected)))
                return true
            },
            openWindow: { url, _, selected in
                routes.append((url, .newWindow(selected: selected)))
                return true
            },
            openSplit: { url, _ in
                routes.append((url, .splitView))
                return true
            },
            activateSource: { _ in true },
            presentGlance: { _, _, _ in true }
        )
        tab.attachBrowserRuntime(runtime)
        webView.owningTab = tab
        let owner = makeActionOwner(
            webView: webView,
            snapshot: SumiWebPageContextMenuTargetSnapshot(
                kind: .link,
                selectedText: "context search",
                linkHref: linkURL.absoluteString,
                imageSrc: imageURL.absoluteString
            )
        )

        owner.openLinkInNewTab(nil)
        owner.openLinkInNewWindow(nil)
        owner.openLinkInSplitView(nil)
        owner.openImageInNewTab(nil)
        owner.openImageInNewWindow(nil)
        owner.searchSelection(nil)

        XCTAssertEqual(routes.map(\.0), [
            linkURL,
            linkURL,
            linkURL,
            imageURL,
            imageURL,
            URL(string: "https://duckduckgo.com/?q=context+search")!,
        ])
        XCTAssertEqual(routes.map(\.1), [
            .newTab(selected: true),
            .newWindow(selected: true),
            .splitView,
            .newTab(selected: true),
            .newWindow(selected: true),
            .newTab(selected: true),
        ])
    }

    func testCopyAndBookmarkActionsUseExactContextValues() {
        let pageURL = URL(string: "https://source.example/article")!
        let linkURL = URL(string: "https://target.example/page")!
        let imageURL = URL(string: "https://target.example/image.png")!
        let webView = makeWebView()
        let tab = Tab(url: pageURL)
        var bookmarkPageRequests = 0
        var bookmarkedLink: (URL, String?)?
        var runtime = TabBrowserRuntime.inactive
        runtime.webPageMenuCommands = TabWebPageMenuCommands(
            appearance: { _, fallback in fallback },
            canBookmark: { _ in true },
            requestBookmarkEditor: { _ in
                bookmarkPageRequests += 1
                return true
            },
            bookmarkLink: { _, url, title in
                bookmarkedLink = (url, title)
                return true
            },
            download: { _, _ in true }
        )
        tab.attachBrowserRuntime(runtime)
        webView.owningTab = tab
        let owner = makeActionOwner(
            webView: webView,
            snapshot: SumiWebPageContextMenuTargetSnapshot(
                kind: .link,
                selectedText: "selected words",
                linkHref: linkURL.absoluteString,
                linkText: "Target title",
                imageSrc: imageURL.absoluteString
            )
        )

        owner.bookmarkPage(nil)
        owner.addLinkToBookmarks(nil)
        XCTAssertEqual(bookmarkPageRequests, 1)
        XCTAssertEqual(bookmarkedLink?.0, linkURL)
        XCTAssertEqual(bookmarkedLink?.1, "Target title")

        assertPasteboard(after: { owner.copyPageAddress(nil) }, equals: pageURL.absoluteString)
        assertPasteboard(after: { owner.copySelection(nil) }, equals: "selected words")
        assertPasteboard(after: { owner.copyLink(nil) }, equals: linkURL.absoluteString)
        assertPasteboard(after: { owner.copyImageAddress(nil) }, equals: imageURL.absoluteString)
        assertPasteboard(
            after: { owner.copyLinkToSelectedText(nil) },
            equals: "https://source.example/article#:~:text=selected%20words"
        )

        let mailOwner = makeActionOwner(
            webView: webView,
            snapshot: SumiWebPageContextMenuTargetSnapshot(
                kind: .link,
                linkHref: "mailto:a@example.com,b@example.com"
            )
        )
        assertPasteboard(
            after: { mailOwner.copyEmailAddress(nil) },
            equals: "a@example.com, b@example.com"
        )
    }

    @objc private func noop(_: Any?) { /* no-op */ }

    // MARK: - Harness

    private func makeWebView() -> FocusableWKWebView {
        FocusableWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    }

    private func makeActionOwner(
        webView: FocusableWKWebView,
        snapshot: SumiWebPageContextMenuTargetSnapshot
    ) -> SumiWebPageMenuActionOwner {
        let context = SumiWebPageMenuContext(
            menu: NSMenu(),
            snapshot: snapshot,
            searchProviderName: "DuckDuckGo",
            isLoading: false,
            isDeveloperInspectionEnabled: false
        )
        let owner = SumiWebPageMenuActionOwner()
        owner.prepare(webView: webView, context: context)
        return owner
    }

    private func assertPasteboard(
        after action: () -> Void,
        equals expectedValue: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        NSPasteboard.general.clearContents()
        action()
        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            expectedValue,
            file: file,
            line: line
        )
    }

    private func prepare(
        _ menu: NSMenu,
        kind: SumiWebPageContextMenuTargetKind,
        selectedText: String? = nil,
        linkHref: String? = nil,
        imageSrc: String? = nil
    ) {
        let webView = makeWebView()
        webView.contextMenu.record(
            SumiWebPageContextMenuTargetSnapshot(
                kind: kind,
                selectedText: selectedText,
                linkHref: linkHref,
                imageSrc: imageSrc
            )
        )
        SumiWebPageMenuPresenter().menuWillOpen(menu, for: webView)
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
