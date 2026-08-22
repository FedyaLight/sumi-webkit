//
//  SumiWebPageMenuModel.swift
//  Sumi
//
//  Value model for the web page contextual menu: the resolved menu context,
//  Sumi-owned command identity, and the known WebKit menu item identifiers.
//

import AppKit
import WebKit

/// Resolved facts for one web page menu presentation. Built once per rewrite
/// from the live `NSMenu` and the trusted DOM snapshot (when one arrived).
struct SumiWebPageMenuContext {
    let identifiers: Set<SumiWebKitMenuItemIdentifier>
    let targetHint: SumiWebPageContextMenuTargetKind?
    let selectedText: String?
    let linkURL: URL?
    let linkText: String?
    let imageURL: URL?
    let mediaURL: URL?
    let mediaDownloadTitle: String?
    let searchProviderName: String
    let isLoading: Bool
    let isDeveloperInspectionEnabled: Bool

    init(
        menu: NSMenu,
        snapshot: SumiWebPageContextMenuTargetSnapshot?,
        searchProviderName: String,
        isLoading: Bool,
        isDeveloperInspectionEnabled: Bool
    ) {
        identifiers = Set(menu.items.compactMap {
            SumiWebKitMenuItemIdentifier($0.identifier)
        })
        targetHint = snapshot?.kind
        selectedText = snapshot?.selectedText
        linkURL = snapshot?.linkHref.flatMap(URL.init(string:))
        linkText = snapshot?.linkText
        imageURL = snapshot?.imageSrc.flatMap(URL.init(string:))
        mediaURL = snapshot?.mediaSrc.flatMap(URL.init(string:))
        mediaDownloadTitle = menu.items.first {
            SumiWebKitMenuItemIdentifier($0.identifier) == .downloadMedia
        }?.title
        self.searchProviderName = searchProviderName
        self.isLoading = isLoading
        self.isDeveloperInspectionEnabled = isDeveloperInspectionEnabled
    }

    var hasLinkContext: Bool {
        identifiers.contains(where: \.belongsToLinkContext)
    }

    var hasImageContext: Bool {
        identifiers.contains(where: \.belongsToImageContext)
    }

    var isMailtoLink: Bool {
        linkURL?.scheme?.lowercased() == "mailto"
    }

    var isWebSchemeLink: Bool {
        isWebScheme(linkURL)
    }

    var isWebSchemeImage: Bool {
        isWebScheme(imageURL)
    }

    var isWebSchemeMedia: Bool {
        isWebScheme(mediaURL)
    }

    /// Recipients of a `mailto:` link: the path list plus any `to=` query
    /// values, comma-separated per RFC 6068.
    var mailtoAddresses: [String] {
        guard isMailtoLink,
              let linkURL,
              let components = URLComponents(url: linkURL, resolvingAgainstBaseURL: false)
        else { return [] }

        var rawLists = [components.path]
        for query in components.queryItems ?? [] where query.name.lowercased() == "to" {
            rawLists.append(query.value ?? "")
        }
        return rawLists
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var isPageBackground: Bool {
        if targetHint == .interactiveElement || targetHint == .editable {
            return false
        }
        if selectedText != nil {
            return false
        }
        return identifiers.contains(where: \.isPageBackgroundSignal)
            && !identifiers.contains(where: \.belongsToElementContext)
    }

    var canCopyLinkToSelectedText: Bool {
        targetHint != .editable
    }

    private func isWebScheme(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
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
    case openLinkInNewTab = "SumiWebPageMenu.OpenLinkInNewTab"
    case openLinkInNewWindow = "SumiWebPageMenu.OpenLinkInNewWindow"
    case openLinkInSplitView = "SumiWebPageMenu.OpenLinkInSplitView"
    case addLinkToBookmarks = "SumiWebPageMenu.AddLinkToBookmarks"
    case downloadLinkedFile = "SumiWebPageMenu.DownloadLinkedFile"
    case copyLink = "SumiWebPageMenu.CopyLink"
    case copyEmailAddress = "SumiWebPageMenu.CopyEmailAddress"
    case openImageInNewTab = "SumiWebPageMenu.OpenImageInNewTab"
    case openImageInNewWindow = "SumiWebPageMenu.OpenImageInNewWindow"
    case saveImageAs = "SumiWebPageMenu.SaveImageAs"
    case copyImageAddress = "SumiWebPageMenu.CopyImageAddress"
    case copyImage = "SumiWebPageMenu.CopyImage"
    case downloadMedia = "SumiWebPageMenu.DownloadMedia"

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
        !isPageBackgroundCommand
    }

    var symbolName: String {
        switch self {
        case .back:
            return "chevron.left"
        case .forward:
            return "chevron.right"
        case .reload:
            return "arrow.clockwise"
        case .stop:
            return "xmark"
        case .bookmarkPage, .addLinkToBookmarks:
            return "bookmark"
        case .copyPageAddress, .copyLink, .copyImageAddress:
            return "link"
        case .printPage:
            return "printer"
        case .copySelection, .copyImage:
            return "doc.on.doc"
        case .copyLinkToSelectedText:
            return "quote.bubble"
        case .searchSelection:
            return "magnifyingglass"
        case .openLinkInNewTab, .openImageInNewTab:
            return "plus.square.on.square"
        case .openLinkInNewWindow, .openImageInNewWindow:
            return "macwindow.badge.plus"
        case .openLinkInSplitView:
            return "rectangle.split.2x1"
        case .copyEmailAddress:
            return "envelope"
        case .downloadLinkedFile, .saveImageAs, .downloadMedia:
            return "arrow.down.circle"
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

    // `copyLinkWithHighlight` is deliberately absent: WebKit adds it for text
    // selections (Copy Link with Highlight), not for anchor elements.
    var belongsToLinkContext: Bool {
        switch self {
        case .copyLink,
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
        case .goBack, .goForward, .inspectElement, .openFrameInNewWindow, .reload, .shareMenu:
            // A subframe hit is still a page-background menu: it keeps the
            // owned page section alongside the native frame item.
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
