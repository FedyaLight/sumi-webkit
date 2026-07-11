import Foundation
import SumiWebRuntime
import WebKit

/// One synchronous transaction from WebKit's child configuration to a fully
/// owned browser window. No window is published until its exact Tab, WebView,
/// profile partition, tracked slot, and initial selection all agree.
@MainActor
final class WebKitChildWindowOpeningService: WebKitChildWindowOpening {
    private enum ChildResidence {
        case regular(spaceID: UUID)
        case ephemeral
    }

    private struct Child {
        let tab: Tab
        let webView: FocusableWKWebView
        let residence: ChildResidence
    }

    private let windowTransaction: WebKitChildWindowShellTransaction
    private weak var tabs: TabManager?
    private weak var ownership: WebViewOwnershipService?
    private weak var ownershipQuery: WebViewOwnershipQuery?
    private let sourceResolver: PhysicalWebViewSourceResolver
    private weak var lifecycle: WebViewLifecycleService?
    private weak var extensionPublication:
        WindowExtensionPublicationTransaction?
    private let persistWindowSession: @MainActor (BrowserWindowState) -> Void

    init(
        windowTransaction: WebKitChildWindowShellTransaction,
        tabs: TabManager,
        ownership: WebViewOwnershipService,
        ownershipQuery: WebViewOwnershipQuery,
        sourceResolver: PhysicalWebViewSourceResolver,
        lifecycle: WebViewLifecycleService,
        extensionPublication: WindowExtensionPublicationTransaction,
        persistWindowSession: @escaping @MainActor (
            BrowserWindowState
        ) -> Void
    ) {
        self.windowTransaction = windowTransaction
        self.tabs = tabs
        self.ownership = ownership
        self.ownershipQuery = ownershipQuery
        self.sourceResolver = sourceResolver
        self.lifecycle = lifecycle
        self.extensionPublication = extensionPublication
        self.persistWindowSession = persistWindowSession
    }

    func open(
        configuration: WKWebViewConfiguration,
        requestURL: URL?,
        from sourceWebView: FocusableWKWebView,
        activate: Bool,
        isExtensionOriginated: Bool
    ) -> WKWebView? {
        guard let source = sourceResolver.resolve(sourceWebView),
              extensionPublication != nil
        else {
            return nil
        }
        return open(
            configuration: configuration,
            requestURL: requestURL,
            source: source,
            activate: activate,
            isExtensionOriginated: isExtensionOriginated
        )
    }

    /// Exact-receipt entry point retained for the shell/extension publication
    /// transaction. It revalidates immediately before any child mutation.
    func open(
        configuration: WKWebViewConfiguration,
        requestURL: URL?,
        source: PhysicalWebViewSourceReceipt,
        activate: Bool,
        isExtensionOriginated: Bool
    ) -> WKWebView? {
        guard sourceResolver.isCurrent(source),
              source.dataStore === source.executionProfile.dataStore,
              configuration.websiteDataStore === source.dataStore,
              let extensionPublication
        else {
            return nil
        }
        if isExtensionOriginated,
           source.usesPresentationProfileForExecution == false {
            return nil
        }

        var child: Child?
        var didStageExtensionPublication = false
        let targetWindow = windowTransaction.create(
            source: source,
            activate: activate,
            installChild: { [weak self] targetWindow in
                guard let self,
                      let created = self.makeChild(
                          configuration: configuration,
                          requestURL: requestURL,
                          source: source,
                          targetWindow: targetWindow,
                          isExtensionOriginated: isExtensionOriginated
                      )
                else {
                    return false
                }
                child = created
                return self.validate(
                    created,
                    source: source,
                    targetWindow: targetWindow
                )
            },
            validateChildBeforePublication: { [weak self, weak extensionPublication]
                targetWindow in
                guard let self,
                      let extensionPublication,
                      let child,
                      self.validate(
                          child,
                          source: source,
                          targetWindow: targetWindow
                      )
                else {
                    return false
                }
                if didStageExtensionPublication == false {
                    switch extensionPublication.stageInitialTab(
                        child.tab,
                        webView: child.webView,
                        in: targetWindow,
                        reason: "WebKitChildWindowOpeningService.open"
                    ) {
                    case .extensionPrepared:
                        didStageExtensionPublication = true
                    case .nativeOnly:
                        guard isExtensionOriginated == false else {
                            return false
                        }
                        didStageExtensionPublication = true
                    case .suppressed:
                        guard isExtensionOriginated == false else {
                            return false
                        }
                        didStageExtensionPublication = true
                    case .rejected:
                        return false
                    }
                }
                return extensionPublication.validateStagedInitialTab(
                    child.tab,
                    webView: child.webView,
                    in: targetWindow
                )
            },
            discardChild: { [weak self] targetWindow in
                extensionPublication.discardRegistration(targetWindow)
                guard let self, let child else { return }
                self.discard(child, from: targetWindow)
            }
        )
        guard let targetWindow, let child else { return nil }

        persistWindowSession(targetWindow)
        targetWindow.compositorInvalidation.refresh()
        return child.webView
    }

    private func makeChild(
        configuration: WKWebViewConfiguration,
        requestURL: URL?,
        source: PhysicalWebViewSourceReceipt,
        targetWindow: BrowserWindowState,
        isExtensionOriginated: Bool
    ) -> Child? {
        guard let tabs, let ownership else { return nil }
        let childTab: Tab
        let residence: ChildResidence
        if source.residence == .privateEphemeral {
            guard targetWindow.isIncognito,
                  targetWindow.ephemeralProfile === source.executionProfile,
                  targetWindow.currentProfileId
                    == source.executionProfile.id,
                  let blankURL = URL(string: "about:blank")
            else {
                return nil
            }
            childTab = tabs.ephemeralLifecycleOwner.createEphemeralTab(
                url: requestURL ?? blankURL,
                in: targetWindow,
                profile: source.executionProfile
            )
            residence = .ephemeral
        } else {
            guard targetWindow.isIncognito == false,
                  targetWindow.currentSpaceId
                    == source.presentationSpace.id,
                  targetWindow.currentProfileId
                    == source.presentationProfile.id,
                  source.presentationSpace.profileId
                    == source.presentationProfile.id
            else {
                return nil
            }
            let insertionIndex = tabs.regularTabCollectionOwner
                .childInsertionIndex(
                    openedFrom: source.tab,
                    in: source.presentationSpace
                )
            childTab = tabs.regularTabLifecycleOwner.createPopupTab(
                in: source.presentationSpace,
                activate: false,
                executionProfileID: source.executionProfile.id,
                regularInsertionIndex: insertionIndex
            )
            residence = .regular(spaceID: source.presentationSpace.id)
        }
        if source.residence == .privateEphemeral {
            childTab.profileId = source.executionProfile.id
        }
        childTab.isPopupHost = true

        childTab.visitedLinkStore.applyStore(
            to: configuration,
            for: source.executionProfile
        )
        let childWebView = childTab.createPopupWebViewFromWebKitConfiguration(
            configuration,
            currentURL: requestURL,
            isExtensionOriginated: isExtensionOriginated,
            reason: "WebKitChildWindowOpeningService.makeChild"
        )
        ownership.registerTrackedWebView(
            childWebView,
            for: childTab,
            in: targetWindow.id
        )
        _ = WindowTabSelectionStateApplicator.apply(
            childTab,
            to: targetWindow,
            updateSpaceFromTab: source.window.isIncognito == false,
            rememberSelection: true
        )
        targetWindow.webKitChildWindowIdentity = WebKitChildWindowIdentity(
            initialTabID: childTab.id
        )
        return Child(
            tab: childTab,
            webView: childWebView,
            residence: residence
        )
    }

    private func validate(
        _ child: Child,
        source: PhysicalWebViewSourceReceipt,
        targetWindow: BrowserWindowState
    ) -> Bool {
        guard let ownershipQuery,
              child.webView.configuration.websiteDataStore
                === source.executionProfile.dataStore,
              child.tab.profileId == source.executionProfile.id,
              targetWindow.currentTabId == child.tab.id,
              ownershipQuery.trackedOwner(containing: child.webView)
                == TrackedWebViewOwner(
                    tabID: child.tab.id,
                    windowID: targetWindow.id
                ),
              ownershipQuery.webView(
                  for: child.tab.id,
                  in: targetWindow.id
              ) === child.webView
        else {
            return false
        }

        switch child.residence {
        case .regular(let spaceID):
            return child.tab.spaceId == spaceID
                && targetWindow.currentSpaceId == spaceID
        case .ephemeral:
            return child.tab.spaceId == nil
                && targetWindow.ephemeralProfile
                    === source.executionProfile
                && targetWindow.ephemeralTabs.contains {
                    $0 === child.tab
                }
        }
    }

    private func discard(
        _ child: Child,
        from targetWindow: BrowserWindowState
    ) {
        guard let lifecycle, let tabs else { return }
        lifecycle.cleanupTrackedWebView(
            child.webView,
            owner: TrackedWebViewOwner(
                tabID: child.tab.id,
                windowID: targetWindow.id
            )
        )
        tabs.structuralPersistence.cancelRuntimeStatePersistence(
            for: child.tab.id
        )
        targetWindow.currentTabId = nil
        if targetWindow.webKitChildWindowIdentity?.initialTabID
            == child.tab.id {
            targetWindow.webKitChildWindowIdentity = nil
        }

        switch child.residence {
        case .regular(let spaceID):
            if tabs.regularTabCollectionOwner.remove(
                child.tab.id,
                from: spaceID,
                currentSpaceId: targetWindow.currentSpaceId
            ) != nil {
                tabs.tabCollectionMembershipOwner.detach(child.tab)
                tabs.structuralPersistence.scheduleStructuralPersistence()
            }
        case .ephemeral:
            targetWindow.ephemeralTabs.removeAll { $0 === child.tab }
        }
    }
}
