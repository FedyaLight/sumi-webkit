import Foundation
import SumiDomain
import WebKit

enum BrowserTabOpenActivationPolicy {
    case foreground(windowState: BrowserWindowState, loadPolicy: TabSelectionLoadPolicy)
    case background
}

struct BrowserTabOpenContext {
    let windowState: BrowserWindowState?
    let sourceTab: Tab?
    let preferredSpaceId: UUID?
    let regularInsertionIndex: Int?
    let activationPolicy: BrowserTabOpenActivationPolicy

    static func foreground(
        windowState: BrowserWindowState,
        sourceTab: Tab? = nil,
        preferredSpaceId: UUID? = nil,
        regularInsertionIndex: Int? = nil,
        loadPolicy: TabSelectionLoadPolicy = .deferred
    ) -> BrowserTabOpenContext {
        BrowserTabOpenContext(
            windowState: windowState,
            sourceTab: sourceTab,
            preferredSpaceId: preferredSpaceId,
            regularInsertionIndex: regularInsertionIndex,
            activationPolicy: .foreground(windowState: windowState, loadPolicy: loadPolicy)
        )
    }

    static func background(
        windowState: BrowserWindowState? = nil,
        sourceTab: Tab? = nil,
        preferredSpaceId: UUID? = nil,
        regularInsertionIndex: Int? = nil
    ) -> BrowserTabOpenContext {
        BrowserTabOpenContext(
            windowState: windowState,
            sourceTab: sourceTab,
            preferredSpaceId: preferredSpaceId,
            regularInsertionIndex: regularInsertionIndex,
            activationPolicy: .background
        )
    }
}

@MainActor
final class BrowserTabOpeningOwner {
    private let destinations: BrowserTabOpenDestinationResolver
    private let regularTabs: BrowserRegularTabOpeningTransaction
    private let ephemeralTabs: BrowserEphemeralTabOpeningTransaction
    private let activation: BrowserTabOpenActivation

    init(
        destinations: BrowserTabOpenDestinationResolver,
        regularTabs: BrowserRegularTabOpeningTransaction,
        ephemeralTabs: BrowserEphemeralTabOpeningTransaction,
        activation: BrowserTabOpenActivation
    ) {
        self.destinations = destinations
        self.regularTabs = regularTabs
        self.ephemeralTabs = ephemeralTabs
        self.activation = activation
    }

    @discardableResult
    func createNewTab() -> Tab {
        if let activeWindow = destinations.window(
            for: .background()
        ) {
            return openNewTab(context: .foreground(windowState: activeWindow))
        }
        return regularTabs.createDefaultTab()
    }

    @discardableResult
    func createNewTab(
        in windowState: BrowserWindowState,
        url: String = SumiSurface.emptyTabURL.absoluteString
    ) -> Tab {
        openNewTab(
            url: url,
            context: .foreground(windowState: windowState)
        )
    }

    @discardableResult
    func createNewTabAfterSidebarInsertion(
        in windowState: BrowserWindowState,
        url: String = SumiSurface.emptyTabURL.absoluteString
    ) -> Tab {
        guard !windowState.isIncognito else {
            return openNewTab(
                url: url,
                context: .foreground(windowState: windowState)
            )
        }

        let newTab = regularTabs.createForSidebarInsertion(
            url: url,
            in: windowState
        )
        activation.selectAfterSidebarInsertion(newTab, in: windowState)

        return newTab
    }

    @discardableResult
    func openNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        context: BrowserTabOpenContext
    ) -> Tab {
        let resolvedWindowState = resolvedWindowState(for: context)

        if let resolvedWindowState,
           resolvedWindowState.isIncognito,
           let profile = resolvedWindowState.ephemeralProfile {
            return ephemeralTabs.open(
                url: url,
                context: context,
                windowState: resolvedWindowState,
                profile: profile
            )
        }
        return regularTabs.open(url: url, context: context)
    }

    @discardableResult
    func openPreparedRegularTab(
        url: String,
        context: BrowserTabOpenContext,
        prepareBeforePublication: @MainActor (Tab) -> Void
    ) -> Tab {
        regularTabs.open(
            url: url,
            context: context,
            prepareBeforePublication: prepareBeforePublication
        )
    }

    func duplicateTab(_ tab: Tab, in windowState: BrowserWindowState) {
        regularTabs.duplicate(tab, in: windowState)
    }

    @discardableResult
    func createPopupTab(
        from sourceTab: Tab,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        activate: Bool = true
    ) -> Tab? {
        let context = BrowserTabOpenContext.background(sourceTab: sourceTab)
        let sourceWindowState = destinations.window(for: context)
        if sourceTab.isEphemeral || sourceWindowState?.isIncognito == true {
            guard let sourceWindowState,
                  let profile = sourceWindowState.ephemeralProfile
            else {
                return nil
            }
            return ephemeralTabs.createPopup(
                from: sourceTab,
                windowState: sourceWindowState,
                profile: profile,
                webViewConfigurationOverride: webViewConfigurationOverride,
                activate: activate
            )
        }
        return regularTabs.createPopup(
            from: sourceTab,
            windowState: sourceWindowState,
            webViewConfigurationOverride: webViewConfigurationOverride,
            activate: activate
        )
    }

    func resolvedTabOpenSpace(for context: BrowserTabOpenContext) -> Space? {
        destinations.space(for: context)
    }

    func prepareBackgroundTabIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState?
    ) {
        _ = windowState
        activation.prepareBackgroundTabIfNeeded(tab)
    }

    private func resolvedWindowState(for context: BrowserTabOpenContext) -> BrowserWindowState? {
        destinations.window(for: context)
    }
}
