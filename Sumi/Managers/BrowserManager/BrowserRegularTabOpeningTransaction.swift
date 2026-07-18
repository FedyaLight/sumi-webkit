import Foundation
import WebKit

@MainActor
final class BrowserRegularTabOpeningTransaction {
    private let lifecycle: TabRegularLifecycleOwner
    private let tabFactory: TabFactory
    private let destinations: BrowserTabOpenDestinationResolver
    private let activation: BrowserTabOpenActivation

    init(
        lifecycle: TabRegularLifecycleOwner,
        tabFactory: TabFactory,
        destinations: BrowserTabOpenDestinationResolver,
        activation: BrowserTabOpenActivation
    ) {
        self.lifecycle = lifecycle
        self.tabFactory = tabFactory
        self.destinations = destinations
        self.activation = activation
    }

    func createDefaultTab() -> Tab {
        lifecycle.createNewTab(in: destinations.firstSpace)
    }

    func open(
        url: String,
        context: BrowserTabOpenContext,
        prepareBeforePublication: @MainActor (Tab) -> Void = { _ in }
    ) -> Tab {
        let windowState = destinations.window(for: context)
        let space = destinations.space(for: context)
        let insertionIndex = context.regularInsertionIndex
            ?? destinations.insertionIndex(
                openedFrom: context.sourceTab,
                in: space
            )
        let tab = lifecycle.createNewTab(
            url: url,
            in: space,
            activate: false,
            regularInsertionIndex: insertionIndex,
            prepareBeforePublication: prepareBeforePublication
        )
        windowState?.markWebKitChildWindowAdopted(by: tab.id)
        activation.apply(
            context.activationPolicy,
            to: tab,
            resolvedWindow: windowState
        )
        return tab
    }

    func createForSidebarInsertion(
        url: String,
        in windowState: BrowserWindowState
    ) -> Tab {
        let context = BrowserTabOpenContext.background(
            windowState: windowState
        )
        let space = destinations.space(for: context)
        let tab = lifecycle.createNewTab(
            url: url,
            in: space,
            activate: false,
            regularInsertionIndex: destinations.insertionIndex(
                openedFrom: nil,
                in: space
            )
        )
        windowState.markWebKitChildWindowAdopted(by: tab.id)
        return tab
    }

    func duplicate(_ tab: Tab, in windowState: BrowserWindowState) {
        let context = BrowserTabOpenContext.background(
            windowState: windowState,
            sourceTab: tab
        )
        let space = destinations.space(for: context)
        let copy = tabFactory.makeTab(
            url: tab.url,
            name: tab.name,
            favicon: "globe",
            spaceId: space?.id,
            index: 0
        )
        copy.faviconPresentation = tab.faviconPresentation
        copy.faviconIsTemplateGlobePlaceholder =
            tab.faviconIsTemplateGlobePlaceholder
        copy.profileId = tab.profileId
        guard lifecycle.addTab(
            copy,
            regularInsertionIndex: destinations.insertionIndex(
                openedFrom: tab,
                in: space
            )
        ) else { return }
        activation.apply(
            .foreground(windowState: windowState, loadPolicy: .immediate),
            to: copy,
            resolvedWindow: windowState
        )
    }

    func createPopup(
        from sourceTab: Tab,
        windowState: BrowserWindowState?,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        activate: Bool
    ) -> Tab {
        let context = BrowserTabOpenContext.background(
            windowState: windowState,
            sourceTab: sourceTab,
            preferredSpaceId: sourceTab.spaceId
        )
        let space = destinations.space(for: context)
        let tab = lifecycle.createPopupTab(
            in: space,
            activate: activate,
            webViewConfigurationOverride: webViewConfigurationOverride,
            regularInsertionIndex: destinations.insertionIndex(
                openedFrom: sourceTab,
                in: space
            )
        )
        windowState?.markWebKitChildWindowAdopted(by: tab.id)
        return tab
    }
}
