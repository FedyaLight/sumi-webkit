import AppKit
@testable import Sumi
import WebKit
import XCTest

/// Pure blueprint assertions: given a resolved context, the declarative spec
/// must produce the DDG-parity rule set (plus Sumi extras) for each context.
@MainActor
final class SumiWebPageMenuBlueprintTests: XCTestCase {
    typealias Rule = SumiWebPageMenuBlueprint.Rule

    // MARK: - Link

    func testWebLinkRulesReplaceOpenDownloadAndCopy() {
        let blueprint = makeBlueprint(
            identifiers: [.openLink, .openLinkInNewWindow, .downloadLinkedFile, .copyLink],
            kind: .link,
            linkHref: "https://example.com/page"
        )

        let rules = blueprint.rules()

        XCTAssertEqual(rules[0], Rule(
            anchor: .openLink,
            operations: [
                .replace([
                    .command(.openLinkInNewTab),
                    .command(.openLinkInSplitView),
                ])
            ]
        ))
        XCTAssertEqual(rules[1], Rule(
            anchor: .openLinkInNewWindow,
            operations: [.replace([.command(.openLinkInNewWindow)])]
        ))
        XCTAssertEqual(rules[2], Rule(
            anchor: .downloadLinkedFile,
            operations: [.replace([.command(.downloadLinkedFile)])]
        ))
        XCTAssertEqual(rules[3], Rule(
            anchor: .copyLink,
            operations: [
                .insertBefore([.command(.addLinkToBookmarks)]),
                .replace([.command(.copyLink)]),
            ]
        ))
    }

    func testMailtoLinkRulesReduceToCopyEmailAddress() {
        let blueprint = makeBlueprint(
            identifiers: [.openLink, .openLinkInNewWindow, .downloadLinkedFile, .copyLink],
            kind: .link,
            linkHref: "mailto:someone@example.com"
        )

        let rules = blueprint.rules()

        XCTAssertEqual(rules, [
            Rule(anchor: .openLink, operations: [.remove]),
            Rule(anchor: .openLinkInNewWindow, operations: [.remove]),
            Rule(anchor: .downloadLinkedFile, operations: [.remove]),
            Rule(anchor: .copyLink, operations: [.replace([.command(.copyEmailAddress)])]),
        ])
    }

    func testNonWebSchemeLinkRulesRemoveOpenAndDownloadButKeepCopy() {
        let blueprint = makeBlueprint(
            identifiers: [.openLink, .openLinkInNewWindow, .downloadLinkedFile, .copyLink],
            kind: .link,
            linkHref: "sumi-custom://internal/thing"
        )

        let rules = blueprint.rules()

        XCTAssertEqual(rules, [
            Rule(anchor: .openLink, operations: [.remove]),
            Rule(anchor: .openLinkInNewWindow, operations: [.remove]),
            Rule(anchor: .downloadLinkedFile, operations: [.remove]),
            Rule(anchor: .copyLink, operations: [.replace([.command(.copyLink)])]),
        ])
    }

    func testLinkWithoutSnapshotOnlyRemovesOpenLink() {
        let blueprint = makeBlueprint(
            identifiers: [.openLink, .openLinkInNewWindow, .downloadLinkedFile, .copyLink]
        )

        XCTAssertEqual(blueprint.rules(), [
            Rule(anchor: .openLink, operations: [.remove]),
        ])
    }

    func testLinkWithSelectionAppendsSelectionBlockAfterCopyLink() throws {
        let blueprint = makeBlueprint(
            identifiers: [
                .openLink,
                .openLinkInNewWindow,
                .downloadLinkedFile,
                .copyLink,
                .searchWeb,
            ],
            kind: .link,
            selectedText: "Chicken Curry Live",
            linkHref: "https://example.com/page"
        )

        let copyLinkRule = try XCTUnwrap(
            blueprint.rules().first { $0.anchor == .copyLink }
        )

        XCTAssertEqual(copyLinkRule.operations, [
            .insertBefore([.command(.addLinkToBookmarks)]),
            .replace([.command(.copyLink)]),
            .insertAfter([
                .separator,
                .command(.copySelection),
                .command(.copyLinkToSelectedText),
                .command(.searchSelection),
                .separator,
            ]),
        ])
        XCTAssertEqual(
            blueprint.rules().first { $0.anchor == .searchWeb },
            Rule(anchor: .searchWeb, operations: [.remove])
        )
    }

    // MARK: - Image

    func testImageRulesInsertOpenInNewTabAndCopyAddress() {
        let blueprint = makeBlueprint(
            identifiers: [.openImageInNewWindow, .downloadImage, .copyImage],
            kind: .image,
            imageSrc: "https://example.com/cat.png"
        )

        XCTAssertEqual(blueprint.rules(), [
            Rule(anchor: .downloadImage, operations: [.replace([.command(.saveImageAs)])]),
            Rule(anchor: .copyImage, operations: [
                .insertBefore([.separator, .command(.copyImageAddress)]),
                .replace([.command(.copyImage)]),
            ]),
            Rule(anchor: .openImageInNewWindow, operations: [
                .insertBefore([.command(.openImageInNewTab)]),
                .replace([.command(.openImageInNewWindow)]),
            ]),
        ])
    }

    func testNonWebImageSourceReplacesDownloadAndCopyImage() {
        let blueprint = makeBlueprint(
            identifiers: [.openImageInNewWindow, .downloadImage, .copyImage],
            kind: .image,
            imageSrc: "data:image/png;base64,AAAA"
        )

        XCTAssertEqual(blueprint.rules(), [
            Rule(anchor: .downloadImage, operations: [.replace([.command(.saveImageAs)])]),
            Rule(anchor: .copyImage, operations: [.replace([.command(.copyImage)])]),
        ])
    }

    func testImageWithoutSnapshotKeepsNativeActions() {
        let blueprint = makeBlueprint(
            identifiers: [.openImageInNewWindow, .downloadImage, .copyImage]
        )

        XCTAssertEqual(blueprint.rules(), [])
    }

    // MARK: - Selection

    func testSelectionReplacesSearchWebInPlaceAndInsertsCopyLinkAfterCopy() {
        let blueprint = makeBlueprint(
            identifiers: [.lookUp, .translate, .searchWeb, .copy],
            kind: .otherElement,
            selectedText: "Chicken Curry Live"
        )

        XCTAssertEqual(blueprint.rules(), [
            Rule(anchor: .searchWeb, operations: [.replace([.command(.searchSelection)])]),
            Rule(anchor: .copy, operations: [
                .insertAfter([.command(.copyLinkToSelectedText)]),
            ]),
        ])
    }

    func testEditableSelectionSuppressesCopyLinkToSelectedTextButKeepsSearch() {
        let blueprint = makeBlueprint(
            identifiers: [.copy, .paste, .searchWeb, .spellingMenu],
            kind: .editable,
            selectedText: "typed text"
        )

        XCTAssertEqual(blueprint.rules(), [
            Rule(anchor: .searchWeb, operations: [.replace([.command(.searchSelection)])]),
        ])
    }

    func testNativeCopyLinkWithHighlightSuppressesOwnedEquivalent() {
        let blueprint = makeBlueprint(
            identifiers: [.copy, .copyLinkWithHighlight, .searchWeb],
            kind: .otherElement,
            selectedText: "highlighted"
        )

        XCTAssertEqual(blueprint.rules(), [
            Rule(anchor: .searchWeb, operations: [.replace([.command(.searchSelection)])]),
        ])
    }

    func testSelectionFallbackSectionWhenNoNativeCopy() {
        let blueprint = makeBlueprint(
            identifiers: [.goBack, .reload],
            kind: .interactiveElement,
            selectedText: "selected words"
        )

        XCTAssertEqual(blueprint.selectionFallbackSection(), [
            .command(.copySelection),
            .command(.copyLinkToSelectedText),
            .command(.searchSelection),
        ])
        XCTAssertEqual(blueprint.pageBackgroundSection(), [])
    }

    // MARK: - Page background

    func testPageBackgroundSectionOrderAndReload() {
        let blueprint = makeBlueprint(identifiers: [.reload], kind: .page)

        XCTAssertEqual(blueprint.pageBackgroundSection(), [
            .command(.back),
            .command(.forward),
            .command(.reload),
            .separator,
            .command(.bookmarkPage),
            .command(.copyPageAddress),
            .command(.printPage),
        ])
    }

    func testPageBackgroundSectionUsesStopWhenLoading() {
        let blueprint = makeBlueprint(
            identifiers: [.reload],
            kind: .page,
            isLoading: true
        )

        XCTAssertTrue(blueprint.pageBackgroundSection().contains(.command(.stop)))
        XCTAssertFalse(blueprint.pageBackgroundSection().contains(.command(.reload)))
    }

    func testPageBackgroundSectionAbsentForElementAndSelectionContexts() {
        XCTAssertEqual(
            makeBlueprint(identifiers: [.reload], kind: .interactiveElement)
                .pageBackgroundSection(),
            []
        )
        XCTAssertEqual(
            makeBlueprint(identifiers: [.reload], kind: .page, selectedText: "text")
                .pageBackgroundSection(),
            []
        )
        XCTAssertEqual(
            makeBlueprint(identifiers: [.reload, .writingTools], kind: .page)
                .pageBackgroundSection(),
            []
        )
    }

    func testFrameMenuGetsPageBackgroundSection() {
        let blueprint = makeBlueprint(
            identifiers: [.reload, .openFrameInNewWindow],
            kind: .page
        )

        XCTAssertFalse(blueprint.pageBackgroundSection().isEmpty)
        XCTAssertTrue(blueprint.rules().isEmpty)
    }

    // MARK: - Inspect Element

    func testInspectElementRetitledWhenDeveloperInspectionEnabled() {
        let blueprint = makeBlueprint(
            identifiers: [.reload, .inspectElement],
            kind: .page,
            isDeveloperInspectionEnabled: true
        )

        XCTAssertEqual(blueprint.rules(), [
            Rule(anchor: .inspectElement, operations: [
                .retitle(SumiWebPageMenuStrings.inspectElement),
            ]),
        ])
    }

    func testInspectElementRemovedWhenDeveloperInspectionDisabled() {
        let blueprint = makeBlueprint(
            identifiers: [.reload, .inspectElement],
            kind: .page
        )

        XCTAssertEqual(blueprint.rules(), [
            Rule(anchor: .inspectElement, operations: [.remove]),
        ])
    }

    // MARK: - Context facts

    func testMailtoAddressesParsePathAndToQueryRecipients() {
        let context = makeContext(
            identifiers: [.copyLink],
            kind: .link,
            linkHref: "mailto:a@example.com,b@example.com?to=c@example.com&subject=Hi"
        )

        XCTAssertEqual(context.mailtoAddresses, [
            "a@example.com",
            "b@example.com",
            "c@example.com",
        ])
    }

    func testMediaMenuOwnsWebMediaDownloadAndPreservesOtherNativeActions() {
        let blueprint = makeBlueprint(
            identifiers: [
                .copyMediaLink,
                .downloadMedia,
                .openMediaInNewWindow,
                .toggleFullScreen,
                .togglePictureInPicture,
            ],
            kind: .media,
            mediaSrc: "https://example.com/video.mp4"
        )

        XCTAssertEqual(blueprint.rules(), [
            Rule(
                anchor: .downloadMedia,
                operations: [.replace([.command(.downloadMedia)])]
            )
        ])
        XCTAssertEqual(blueprint.pageBackgroundSection(), [])
    }

    func testBlobMediaDownloadRemainsNative() {
        let blueprint = makeBlueprint(
            identifiers: [.downloadMedia],
            kind: .media,
            mediaSrc: "blob:https://example.com/asset"
        )

        XCTAssertTrue(blueprint.rules().isEmpty)
    }

    // MARK: - Helpers

    private func makeBlueprint(
        identifiers: [SumiWebKitMenuItemIdentifier],
        kind: SumiWebPageContextMenuTargetKind? = nil,
        selectedText: String? = nil,
        linkHref: String? = nil,
        imageSrc: String? = nil,
        mediaSrc: String? = nil,
        isLoading: Bool = false,
        isDeveloperInspectionEnabled: Bool = false
    ) -> SumiWebPageMenuBlueprint {
        SumiWebPageMenuBlueprint(context: makeContext(
            identifiers: identifiers,
            kind: kind,
            selectedText: selectedText,
            linkHref: linkHref,
            imageSrc: imageSrc,
            mediaSrc: mediaSrc,
            isLoading: isLoading,
            isDeveloperInspectionEnabled: isDeveloperInspectionEnabled
        ))
    }

    private func makeContext(
        identifiers: [SumiWebKitMenuItemIdentifier],
        kind: SumiWebPageContextMenuTargetKind? = nil,
        selectedText: String? = nil,
        linkHref: String? = nil,
        imageSrc: String? = nil,
        mediaSrc: String? = nil,
        isLoading: Bool = false,
        isDeveloperInspectionEnabled: Bool = false
    ) -> SumiWebPageMenuContext {
        let menu = NSMenu()
        for identifier in identifiers {
            let item = NSMenuItem(title: identifier.rawValue, action: nil, keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
            menu.addItem(item)
        }
        let snapshot = kind.map {
            SumiWebPageContextMenuTargetSnapshot(
                kind: $0,
                selectedText: selectedText,
                linkHref: linkHref,
                imageSrc: imageSrc,
                mediaSrc: mediaSrc
            )
        }
        return SumiWebPageMenuContext(
            menu: menu,
            snapshot: snapshot,
            searchProviderName: "DuckDuckGo",
            isLoading: isLoading,
            isDeveloperInspectionEnabled: isDeveloperInspectionEnabled
        )
    }
}
