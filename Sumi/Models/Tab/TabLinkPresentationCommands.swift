import AppKit
import Foundation
import SumiWebRuntime

@MainActor
enum TabLinkDisposition: Equatable {
    case newTab(selected: Bool)
    case newWindow(selected: Bool)
    case splitView
}

/// Browser-chrome presentation commands whose destination must be derived from
/// the exact physical WebView that initiated them.
@MainActor
struct TabLinkPresentationCommands {
    typealias OpenTab = @MainActor (
        _ url: URL,
        _ source: PhysicalWebViewSourceReceipt,
        _ selected: Bool
    ) -> Bool
    typealias OpenWindow = @MainActor (
        _ url: URL,
        _ source: PhysicalWebViewSourceReceipt,
        _ selected: Bool
    ) -> Bool
    typealias OpenSplit = @MainActor (
        _ url: URL,
        _ source: PhysicalWebViewSourceReceipt
    ) -> Bool
    typealias PresentGlance = @MainActor (
        _ url: URL,
        _ source: PhysicalWebViewSourceReceipt,
        _ originRectInWindow: CGRect?
    ) -> Bool
    typealias ActivateSource = @MainActor (
        _ source: PhysicalWebViewSourceReceipt
    ) -> Bool

    private let openAction: @MainActor (
        URL,
        FocusableWKWebView,
        TabLinkDisposition
    ) -> Bool
    private let presentGlanceAction: @MainActor (
        URL,
        FocusableWKWebView,
        CGRect?
    ) -> Bool
    private let activateAction: @MainActor (FocusableWKWebView) -> Bool

    init(
        resolveSource: @escaping @MainActor (
            FocusableWKWebView
        ) -> PhysicalWebViewSourceReceipt?,
        openTab: @escaping OpenTab,
        openWindow: @escaping OpenWindow,
        openSplit: @escaping OpenSplit,
        activateSource: @escaping ActivateSource,
        presentGlance: @escaping PresentGlance
    ) {
        openAction = { url, sourceWebView, disposition in
            guard let source = resolveSource(sourceWebView) else {
                return false
            }

            switch disposition {
            case .newTab(let selected):
                return openTab(url, source, selected)
            case .newWindow(let selected):
                return openWindow(url, source, selected)
            case .splitView:
                return openSplit(url, source)
            }
        }
        activateAction = { sourceWebView in
            guard let source = resolveSource(sourceWebView) else {
                return false
            }
            return activateSource(source)
        }
        presentGlanceAction = { url, sourceWebView, originRectInWindow in
            guard let source = resolveSource(sourceWebView) else {
                return false
            }
            guard activateSource(source) else {
                return false
            }
            return presentGlance(
                url,
                source,
                originRectInWindow
            )
        }
    }

    @discardableResult
    func activateSource(of sourceWebView: FocusableWKWebView) -> Bool {
        activateAction(sourceWebView)
    }

    @discardableResult
    func open(
        _ url: URL,
        from sourceWebView: FocusableWKWebView,
        disposition: TabLinkDisposition
    ) -> Bool {
        openAction(url, sourceWebView, disposition)
    }

    @discardableResult
    func presentInGlance(
        _ url: URL,
        from sourceWebView: FocusableWKWebView,
        originRectInWindow: CGRect? = nil
    ) -> Bool {
        presentGlanceAction(url, sourceWebView, originRectInWindow)
    }

    static let inactive = Self(
        resolveSource: { _ in nil },
        openTab: { _, _, _ in false },
        openWindow: { _, _, _ in false },
        openSplit: { _, _ in false },
        activateSource: { _ in false },
        presentGlance: { _, _, _ in false }
    )
}
