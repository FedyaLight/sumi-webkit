//
//  SumiWebPageMenuModel.swift
//  Sumi
//
//  Value model for the web page contextual menu: the resolved menu context,
//  Sumi-owned command identity, and the known WebKit menu item identifiers.
//

import AppKit
import WebKit

struct SumiWebPageMenuContext {
    let identifiers: Set<SumiWebKitMenuItemIdentifier>
    let hasOwnedPageCommands: Bool
    let hasOwnedElementCommands: Bool
    let targetHint: SumiWebPageContextMenuTargetKind?
    let selectedText: String?
    let hasLinkContext: Bool
    let hasImageContext: Bool
    let hasMediaContext: Bool
    let searchProviderName: String

    init(
        menu: NSMenu,
        targetHint: SumiWebPageContextMenuTargetKind?,
        selectedText: String?,
        searchProviderName: String
    ) {
        identifiers = Set(menu.items.compactMap {
            SumiWebKitMenuItemIdentifier($0.identifier)
        })
        self.targetHint = targetHint
        self.selectedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        hasOwnedPageCommands = menu.items.contains {
            SumiWebPageMenuCommand($0.identifier)?.isPageBackgroundCommand == true
        }
        hasOwnedElementCommands = menu.items.contains {
            SumiWebPageMenuCommand($0.identifier)?.belongsToElementContext == true
        }
        hasLinkContext = identifiers.contains(where: \.belongsToLinkContext)
        hasImageContext = identifiers.contains(where: \.belongsToImageContext)
        hasMediaContext = identifiers.contains(where: \.belongsToMediaContext)
        self.searchProviderName = searchProviderName
    }

    var hasElementContext: Bool {
        hasOwnedElementCommands
            || identifiers.contains(where: \.belongsToElementContext)
            || targetHint?.isWebPageElement == true
            || selectedText != nil
    }

    var isPageBackground: Bool {
        if targetHint == .interactiveElement || targetHint == .editable {
            return false
        }
        if selectedText != nil {
            return false
        }

        return hasOwnedPageCommands
            || (
                !hasOwnedElementCommands
                && identifiers.contains(where: \.isPageBackgroundSignal)
                && !identifiers.contains(where: \.belongsToElementContext)
            )
    }

    var canCopyLinkToSelectedText: Bool {
        targetHint != .editable
    }

    func selectionFallbackInsertionIndex(in menu: NSMenu) -> Int {
        let elementIdentifiers = Set(identifiers.filter(\.belongsToElementContext))
        guard !elementIdentifiers.isEmpty else { return 0 }

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

    func hasPrintCommand(in menu: NSMenu) -> Bool {
        menu.items.contains {
            SumiWebPageMenuCommand($0.identifier) == .printPage
                || $0.title.localizedCaseInsensitiveContains("Print")
                || $0.title.localizedCaseInsensitiveContains("Печать")
        }
    }
}

private extension SumiWebPageContextMenuTargetKind {
    var isWebPageElement: Bool {
        switch self {
        case .editable, .interactiveElement, .link, .image, .media:
            return true
        case .page, .otherElement:
            return false
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum SumiWebPageMenuCommand: String, CaseIterable {
    case back = "SumiWebPageMenu.Back"
    case forward = "SumiWebPageMenu.Forward"
    case reload = "SumiWebPageMenu.Reload"
    case stop = "SumiWebPageMenu.Stop"
    case bookmarkPage = "SumiWebPageMenu.BookmarkPage"
    case copyPageAddress = "SumiWebPageMenu.CopyPageAddress"
    case printPage = "SumiWebPageMenu.PrintPage"
    case copySelection = "SumiWebPageMenu.CopySelection"
    case copyLinkToSelectedText = "SumiWebPageMenu.CopyLinkToSelectedText"
    case searchSelection = "SumiWebPageMenu.SearchSelection"

    init?(_ identifier: NSUserInterfaceItemIdentifier?) {
        guard let identifier else { return nil }
        self.init(rawValue: identifier.rawValue)
    }

    var itemIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(rawValue)
    }

    var isPageBackgroundCommand: Bool {
        switch self {
        case .back,
             .forward,
             .reload,
             .stop,
             .bookmarkPage,
             .copyPageAddress,
             .printPage:
            return true
        default:
            return false
        }
    }

    var belongsToElementContext: Bool {
        switch self {
        case .copySelection, .copyLinkToSelectedText, .searchSelection:
            return true
        default:
            return !isPageBackgroundCommand
        }
    }
}

enum SumiWebKitMenuItemIdentifier: String, CaseIterable {
    case addHighlightToCurrentQuickNote = "WKMenuItemIdentifierAddHighlightToCurrentQuickNote"
    case addHighlightToNewQuickNote = "WKMenuItemIdentifierAddHighlightToNewQuickNote"
    case checkGrammarWithSpelling = "WKMenuItemIdentifierCheckGrammarWithSpelling"
    case checkSpelling = "WKMenuItemIdentifierCheckSpelling"
    case checkSpellingWhileTyping = "WKMenuItemIdentifierCheckSpellingWhileTyping"
    case copy = "WKMenuItemIdentifierCopy"
    case copyImage = "WKMenuItemIdentifierCopyImage"
    case copyLink = "WKMenuItemIdentifierCopyLink"
    case copyLinkWithHighlight = "WKMenuItemIdentifierCopyLinkWithHighlight"
    case copyMediaLink = "WKMenuItemIdentifierCopyMediaLink"
    case copySubject = "WKMenuItemIdentifierCopySubject"
    case downloadImage = "WKMenuItemIdentifierDownloadImage"
    case downloadLinkedFile = "WKMenuItemIdentifierDownloadLinkedFile"
    case downloadMedia = "WKMenuItemIdentifierDownloadMedia"
    case goBack = "WKMenuItemIdentifierGoBack"
    case goForward = "WKMenuItemIdentifierGoForward"
    case inspectElement = "WKMenuItemIdentifierInspectElement"
    case lookUp = "WKMenuItemIdentifierLookUp"
    case openFrameInNewWindow = "WKMenuItemIdentifierOpenFrameInNewWindow"
    case openImageInNewWindow = "WKMenuItemIdentifierOpenImageInNewWindow"
    case openLink = "WKMenuItemIdentifierOpenLink"
    case openLinkInNewWindow = "WKMenuItemIdentifierOpenLinkInNewWindow"
    case openMediaInNewWindow = "WKMenuItemIdentifierOpenMediaInNewWindow"
    case paste = "WKMenuItemIdentifierPaste"
    case pauseAllAnimations = "WKMenuItemIdentifierPauseAllAnimations"
    case pauseAnimation = "WKMenuItemIdentifierPauseAnimation"
    case playAllAnimations = "WKMenuItemIdentifierPlayAllAnimations"
    case playAnimation = "WKMenuItemIdentifierPlayAnimation"
    case proofread = "WKMenuItemIdentifierProofread"
    case reload = "WKMenuItemIdentifierReload"
    case revealImage = "WKMenuItemIdentifierRevealImage"
    case rewrite = "WKMenuItemIdentifierRewrite"
    case searchWeb = "WKMenuItemIdentifierSearchWeb"
    case shareMenu = "WKMenuItemIdentifierShareMenu"
    case showHideMediaControls = "WKMenuItemIdentifierShowHideMediaControls"
    case showHideMediaStats = "WKMenuItemIdentifierShowHideMediaStats"
    case showSpellingPanel = "WKMenuItemIdentifierShowSpellingPanel"
    case speechMenu = "WKMenuItemIdentifierSpeechMenu"
    case spellingMenu = "WKMenuItemIdentifierSpellingMenu"
    case summarize = "WKMenuItemIdentifierSummarize"
    case toggleEnhancedFullScreen = "WKMenuItemIdentifierToggleEnhancedFullScreen"
    case toggleFullScreen = "WKMenuItemIdentifierToggleFullScreen"
    case togglePictureInPicture = "WKMenuItemIdentifierTogglePictureInPicture"
    case toggleVideoViewer = "WKMenuItemIdentifierToggleVideoViewer"
    case translate = "WKMenuItemIdentifierTranslate"
    case writingTools = "WKMenuItemIdentifierWritingTools"

    init?(_ identifier: NSUserInterfaceItemIdentifier?) {
        guard let identifier else { return nil }
        self.init(rawValue: identifier.rawValue)
    }

    var isPageNavigation: Bool {
        switch self {
        case .goBack, .goForward, .reload:
            return true
        default:
            return false
        }
    }

    var isPageBackgroundSignal: Bool {
        switch self {
        case .goBack, .goForward, .inspectElement, .reload, .shareMenu:
            return true
        default:
            return false
        }
    }

    var belongsToLinkContext: Bool {
        switch self {
        case .copyLink,
             .copyLinkWithHighlight,
             .downloadLinkedFile,
             .openLink,
             .openLinkInNewWindow:
            return true
        default:
            return false
        }
    }

    var belongsToImageContext: Bool {
        switch self {
        case .copyImage,
             .copySubject,
             .downloadImage,
             .openImageInNewWindow,
             .revealImage:
            return true
        default:
            return false
        }
    }

    var belongsToMediaContext: Bool {
        switch self {
        case .copyMediaLink,
             .downloadMedia,
             .openMediaInNewWindow,
             .showHideMediaControls,
             .showHideMediaStats,
             .toggleEnhancedFullScreen,
             .toggleFullScreen,
             .togglePictureInPicture,
             .toggleVideoViewer:
            return true
        default:
            return false
        }
    }

    var belongsToElementContext: Bool {
        switch self {
        case .addHighlightToCurrentQuickNote,
             .addHighlightToNewQuickNote,
             .checkGrammarWithSpelling,
             .checkSpelling,
             .checkSpellingWhileTyping,
             .copy,
             .copyImage,
             .copyLink,
             .copyLinkWithHighlight,
             .copyMediaLink,
             .copySubject,
             .downloadImage,
             .downloadLinkedFile,
             .downloadMedia,
             .lookUp,
             .openFrameInNewWindow,
             .openImageInNewWindow,
             .openLink,
             .openLinkInNewWindow,
             .openMediaInNewWindow,
             .paste,
             .pauseAllAnimations,
             .pauseAnimation,
             .playAllAnimations,
             .playAnimation,
             .proofread,
             .revealImage,
             .rewrite,
             .searchWeb,
             .showHideMediaControls,
             .showHideMediaStats,
             .showSpellingPanel,
             .speechMenu,
             .spellingMenu,
             .summarize,
             .toggleEnhancedFullScreen,
             .toggleFullScreen,
             .togglePictureInPicture,
             .toggleVideoViewer,
             .translate,
             .writingTools:
            return true
        case .goBack, .goForward, .inspectElement, .reload, .shareMenu:
            return false
        }
    }

    var isSuppressedBySumi: Bool {
        switch self {
        case .checkGrammarWithSpelling,
             .checkSpelling,
             .checkSpellingWhileTyping,
             .showSpellingPanel,
             .spellingMenu:
            return true
        default:
            return false
        }
    }

    var symbolName: String? {
        switch self {
        case .addHighlightToCurrentQuickNote, .addHighlightToNewQuickNote:
            return "note.text"
        case .checkGrammarWithSpelling,
             .checkSpelling,
             .checkSpellingWhileTyping,
             .showSpellingPanel,
             .spellingMenu:
            return "textformat.abc"
        case .copy, .copyImage, .copySubject:
            return "doc.on.doc"
        case .copyLink, .copyLinkWithHighlight, .copyMediaLink:
            return "link"
        case .downloadImage, .downloadLinkedFile, .downloadMedia:
            return "arrow.down.circle"
        case .goBack:
            return "chevron.left"
        case .goForward:
            return "chevron.right"
        case .inspectElement:
            return "hammer"
        case .lookUp:
            return "book.closed"
        case .openFrameInNewWindow,
             .openImageInNewWindow,
             .openLink,
             .openLinkInNewWindow,
             .openMediaInNewWindow:
            return "arrow.up.right.square"
        case .paste:
            return "clipboard"
        case .pauseAllAnimations, .pauseAnimation:
            return "pause.circle"
        case .playAllAnimations, .playAnimation:
            return "play.circle"
        case .proofread:
            return "checkmark.bubble"
        case .reload:
            return "arrow.clockwise"
        case .revealImage:
            return "viewfinder"
        case .rewrite:
            return "pencil.and.scribble"
        case .searchWeb:
            return "magnifyingglass"
        case .shareMenu:
            return "square.and.arrow.up"
        case .showHideMediaControls:
            return "play.rectangle"
        case .showHideMediaStats:
            return "chart.bar"
        case .speechMenu:
            return "waveform"
        case .summarize:
            return "text.redaction"
        case .toggleEnhancedFullScreen, .toggleFullScreen:
            return "arrow.up.left.and.arrow.down.right"
        case .togglePictureInPicture:
            return "pip"
        case .toggleVideoViewer:
            return "rectangle.inset.filled"
        case .translate:
            return "character.book.closed"
        case .writingTools:
            return "wand.and.stars"
        }
    }
}
