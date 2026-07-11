import AppKit

/// Orchestrates full web page context menu composition across native WebKit
/// mutations and Sumi-owned menu sections.
@MainActor
struct SumiWebPageMenuComposer {
    let menu: NSMenu
    let webView: FocusableWKWebView
    let actionTarget: SumiWebPageMenuController
    let targetHint: SumiWebPageContextMenuTargetKind?
    let selectedText: String?

    func compose() {
        let context = SumiWebPageMenuContext(
            menu: menu,
            targetHint: targetHint,
            selectedText: selectedText,
            searchProviderName: searchProviderName
        )
        let nativeComposer = SumiWebPageNativeMenuComposer(
            menu: menu,
            context: context
        )
        let ownedComposer = SumiWebPageOwnedMenuComposer(
            menu: menu,
            context: context,
            actionTarget: actionTarget,
            isLoading: webView.isLoading
        )

        ownedComposer.removeOwnedPageItems()
        nativeComposer.removeSuppressedItems()
        nativeComposer.removeContextuallyRedundantItems()
        nativeComposer.applyInspectElementPolicy(
            isDeveloperInspectionEnabled: RuntimeDiagnostics.isDeveloperInspectionEnabled
        )

        if context.isPageBackground {
            nativeComposer.removePageNavigationItems()
            ownedComposer.insertPageBackgroundCommands()
        }

        ownedComposer.insertSelectionFallbackCommandsIfNeeded()
        nativeComposer.decorateRemainingWebKitItems()
        menu.sumiNormalizeSeparators()
    }

    private var searchProviderName: String {
        guard let settings = webView.owningTab?.sumiSettings else {
            return SearchProvider.duckDuckGo.displayName
        }
        return settings.resolvedSearchEngineDisplayName
    }
}
