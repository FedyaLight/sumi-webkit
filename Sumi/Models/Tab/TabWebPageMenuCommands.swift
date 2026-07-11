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

    init(
        appearance: @escaping @MainActor (
            FocusableWKWebView,
            NSAppearance?
        ) -> NSAppearance?,
        canBookmark: @escaping @MainActor (FocusableWKWebView) -> Bool,
        requestBookmarkEditor: @escaping @MainActor (
            FocusableWKWebView
        ) -> Bool
    ) {
        appearanceAction = appearance
        canBookmarkAction = canBookmark
        requestBookmarkEditorAction = requestBookmarkEditor
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

    static let inactive = Self(
        appearance: { _, fallback in fallback },
        canBookmark: { _ in false },
        requestBookmarkEditor: { _ in false }
    )
}
