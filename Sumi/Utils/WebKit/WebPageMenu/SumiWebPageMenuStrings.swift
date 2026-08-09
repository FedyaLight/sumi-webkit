import Foundation

/// Single home for every user-visible string in the web page context menu.
/// Keys are the English strings; Xcode extracts them into
/// `Sumi/Resources/Localizable.xcstrings` at build time.
enum SumiWebPageMenuStrings {
    static var back: String { String(localized: "Back") }
    static var forward: String { String(localized: "Forward") }
    static var reloadPage: String { String(localized: "Reload Page") }
    static var stopLoading: String { String(localized: "Stop Loading") }
    static var bookmarkPage: String { String(localized: "Bookmark This Page…") }
    static var copyPageAddress: String { String(localized: "Copy Page Address") }
    static var printPage: String { String(localized: "Print Page…") }

    static var openLinkInNewTab: String { String(localized: "Open Link in New Tab") }
    static var openLinkInSplitView: String { String(localized: "Open Link in Split View") }
    static var openLinkInNewWindow: String { String(localized: "Open Link in New Window") }
    static var downloadLinkedFileAs: String { String(localized: "Download Linked File As…") }
    static var addLinkToBookmarks: String { String(localized: "Add Link to Bookmarks") }
    static var copyLink: String { String(localized: "Copy Link") }
    static var copyEmailAddress: String { String(localized: "Copy Email Address") }
    static var copyEmailAddresses: String { String(localized: "Copy Email Addresses") }

    static var openImageInNewTab: String { String(localized: "Open Image in New Tab") }
    static var openImageInNewWindow: String { String(localized: "Open Image in New Window") }
    static var saveImageAs: String { String(localized: "Save Image As…") }
    static var copyImageAddress: String { String(localized: "Copy Image Address") }
    static var downloadMedia: String { String(localized: "Download Media") }

    static var copySelection: String { String(localized: "Copy") }
    static var copyLinkToSelectedText: String { String(localized: "Copy Link to Selected Text") }
    static var inspectElement: String { String(localized: "Inspect Element") }

    static func searchItemTitle(provider: String, snippet: String) -> String {
        String(localized: "Search \(provider) for \"\(snippet)\"")
    }
}
