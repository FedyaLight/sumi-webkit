import Foundation
import WebKit

/// Installs WebKit's exact child configuration into a new Tab in the physical
/// source window. Profile/data-store checks settle before structural mutation.
@MainActor
final class WebKitChildTabOpeningService: WebKitChildTabOpening {
    private let sources: PhysicalWebViewSourceResolver
    private weak var tabs: TabManager?
    private weak var placement: (any AuxiliaryTrackedWebViewPlacing)?
    private let selection: BrowserTabSelectionCommand
    private weak var notifications: (any BackgroundTabOpenedNotifying)?
    private weak var extensionTabs: (any ExtensionCreatedTabRegistering)?

    init(
        sources: PhysicalWebViewSourceResolver,
        tabs: TabManager,
        placement: any AuxiliaryTrackedWebViewPlacing,
        selection: BrowserTabSelectionCommand,
        notifications: any BackgroundTabOpenedNotifying,
        extensionTabs: any ExtensionCreatedTabRegistering
    ) {
        self.sources = sources
        self.tabs = tabs
        self.placement = placement
        self.selection = selection
        self.notifications = notifications
        self.extensionTabs = extensionTabs
    }

    func open(
        configuration: WKWebViewConfiguration,
        requestURL: URL?,
        from sourceWebView: FocusableWKWebView,
        selected: Bool,
        isExtensionOriginated: Bool
    ) -> WKWebView? {
        guard let source = sources.resolve(sourceWebView),
              configuration.websiteDataStore === source.dataStore,
              let tabs,
              let placement,
              isExtensionOriginated == false || extensionTabs != nil
        else {
            return nil
        }

        let child: Tab
        let residence: WebKitChildTabResidence
        if source.residence == .privateEphemeral {
            guard source.window.isIncognito,
                  source.window.ephemeralProfile === source.executionProfile,
                  let blankURL = URL(string: "about:blank")
            else {
                return nil
            }
            let previousTabID = source.window.currentTabId
            child = tabs.ephemeralLifecycleOwner.createEphemeralTab(
                url: requestURL ?? blankURL,
                in: source.window,
                profile: source.executionProfile
            )
            child.isPopupHost = true
            residence = .ephemeral(previousTabID: previousTabID)
            if selected == false {
                source.window.currentTabId = previousTabID
            }
        } else {
            guard source.window.isIncognito == false,
                  source.window.currentSpaceId == source.presentationSpace.id,
                  source.window.currentProfileId
                    == source.presentationProfile.id,
                  source.presentationSpace.profileId
                    == source.presentationProfile.id,
                  tabs.spaceStateOwner.space(
                      with: source.presentationSpace.id
                  ) === source.presentationSpace
            else {
                return nil
            }
            let insertionIndex = tabs.regularTabCollectionOwner
                .childInsertionIndex(
                    openedFrom: source.tab,
                    in: source.presentationSpace
                )
            child = tabs.regularTabLifecycleOwner.createPopupTab(
                in: source.presentationSpace,
                activate: false,
                executionProfileID: source.executionProfile.id,
                regularInsertionIndex: insertionIndex
            )
            residence = .regular(spaceID: source.presentationSpace.id)
        }

        if source.residence == .privateEphemeral {
            child.profileId = source.executionProfile.id
        }
        child.visitedLinkStore.applyStore(
            to: configuration,
            for: source.executionProfile
        )
        let childWebView = child.createPopupWebViewFromWebKitConfiguration(
            configuration,
            currentURL: requestURL,
            isExtensionOriginated: isExtensionOriginated,
            reason: "WebKitChildTabOpeningService.open"
        )
        let placementOutcome = placement.registerAuxiliaryTrackedWebView(
            childWebView,
            for: child,
            in: source.window.id
        )
        guard placementOutcome.isAccepted else {
            WebKitChildTabRollback.discard(
                child,
                webView: childWebView,
                residence: residence,
                sourceWindow: source.window,
                tabs: tabs
            )
            return nil
        }

        source.window.markWebKitChildWindowAdopted(by: child.id)

        if selected {
            selection.select(child, in: source.window, loadPolicy: .immediate)
        } else if isExtensionOriginated == false {
            notifications?.presentBackgroundTabOpenedNotification(
                tabId: child.id,
                in: source.window
            )
        }
        if isExtensionOriginated {
            extensionTabs?.registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
                child,
                reason: "WebKitChildTabOpeningService.open"
            )
        }
        return childWebView
    }
}
