import AppKit

/// Browser-chrome commands emitted by a WebKit page menu. Every command is
/// authorized by the exact physical WebView that owns the presented menu.
@MainActor
struct TabWebPageMenuCommands {
    private let appearanceAction: @MainActor (
        FocusableWKWebView,
        NSAppearance?
    ) -> NSAppearance?
    private let canBookmarkAction: @MainActor (FocusableWKWebView) -> Bool
    private let requestBookmarkEditorAction: @MainActor (
        FocusableWKWebView
    ) -> Bool
    private let bookmarkLinkAction: @MainActor (
        FocusableWKWebView,
        URL,
        String?
    ) -> Bool
    private let downloadAction: @MainActor (FocusableWKWebView, URL) -> Bool

    init(
        appearance: @escaping @MainActor (
            FocusableWKWebView,
            NSAppearance?
        ) -> NSAppearance?,
        canBookmark: @escaping @MainActor (FocusableWKWebView) -> Bool,
        requestBookmarkEditor: @escaping @MainActor (
            FocusableWKWebView
        ) -> Bool,
        bookmarkLink: @escaping @MainActor (
            FocusableWKWebView,
            URL,
            String?
        ) -> Bool,
        download: @escaping @MainActor (FocusableWKWebView, URL) -> Bool
    ) {
        appearanceAction = appearance
        canBookmarkAction = canBookmark
        requestBookmarkEditorAction = requestBookmarkEditor
        bookmarkLinkAction = bookmarkLink
        downloadAction = download
    }

    func appearance(
        for sourceWebView: FocusableWKWebView,
        fallback: NSAppearance?
    ) -> NSAppearance? {
        appearanceAction(sourceWebView, fallback)
    }

    func canBookmark(_ sourceWebView: FocusableWKWebView) -> Bool {
        canBookmarkAction(sourceWebView)
    }

    @discardableResult
    func requestBookmarkEditor(
        from sourceWebView: FocusableWKWebView
    ) -> Bool {
        requestBookmarkEditorAction(sourceWebView)
    }

    /// Silently bookmarks a link from the page menu (no editor), DDG-style.
    @discardableResult
    func bookmarkLink(
        from sourceWebView: FocusableWKWebView,
        url: URL,
        title: String?
    ) -> Bool {
        bookmarkLinkAction(sourceWebView, url, title)
    }

    @discardableResult
    func download(
        from sourceWebView: FocusableWKWebView,
        url: URL
    ) -> Bool {
        downloadAction(sourceWebView, url)
    }

    static let inactive = Self(
        appearance: { _, fallback in fallback },
        canBookmark: { _ in false },
        requestBookmarkEditor: { _ in false },
        bookmarkLink: { _, _, _ in false },
        download: { _, _ in false }
    )
}
