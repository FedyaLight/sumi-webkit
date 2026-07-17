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
    private let regularTabs: RegularTabCollectionOwner
    private let regularLifecycle: TabRegularLifecycleOwner
    private let ephemeralLifecycle: TabEphemeralLifecycleOwner
    private let residences: BrowserTabResidenceAuthority
    private weak var placement: (any AuxiliaryTrackedWebViewPlacing)?
    private weak var ownershipQuery: WebViewOwnershipQuery?
    private let sourceResolver: PhysicalWebViewSourceResolver
    private weak var lifecycle: WebViewLifecycleService?
    private weak var extensionPublication:
        WindowExtensionPublicationTransaction?
    private let persistWindowSession: @MainActor (BrowserWindowState) -> Void

    init(
        windowTransaction: WebKitChildWindowShellTransaction,
        regularTabs: RegularTabCollectionOwner,
        regularLifecycle: TabRegularLifecycleOwner,
        ephemeralLifecycle: TabEphemeralLifecycleOwner,
        residences: BrowserTabResidenceAuthority,
        placement: any AuxiliaryTrackedWebViewPlacing,
        ownershipQuery: WebViewOwnershipQuery,
        sourceResolver: PhysicalWebViewSourceResolver,
        lifecycle: WebViewLifecycleService,
        extensionPublication: WindowExtensionPublicationTransaction,
        persistWindowSession: @escaping @MainActor (
            BrowserWindowState
        ) -> Void
    ) {
        self.windowTransaction = windowTransaction
        self.regularTabs = regularTabs
        self.regularLifecycle = regularLifecycle
        self.ephemeralLifecycle = ephemeralLifecycle
        self.residences = residences
        self.placement = placement
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
                guard let self, let child else { return }
                self.discard(
                    child,
                    from: targetWindow,
                    extensionPublication: extensionPublication
                )
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
        guard let placement else { return nil }
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
            childTab = ephemeralLifecycle.createEphemeralTab(
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
            let insertionIndex = regularTabs.childInsertionIndex(
                openedFrom: source.tab,
                in: source.presentationSpace
            )
            childTab = regularLifecycle.createPopupTab(
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
        let child = Child(
            tab: childTab,
            webView: childWebView,
            residence: residence
        )
        let placementOutcome = placement.registerAuxiliaryTrackedWebView(
            childWebView,
            for: childTab,
            in: targetWindow.id
        )
        guard placementOutcome.isAccepted else {
            discardUnplaced(child, from: targetWindow)
            return nil
        }
        _ = WindowTabSelectionStateApplicator.apply(
            childTab,
            to: targetWindow,
            updateSpaceFromTab: source.window.isIncognito == false,
            rememberSelection: true
        )
        targetWindow.webKitChildWindowIdentity = WebKitChildWindowIdentity(
            initialTabID: childTab.id
        )
        return child
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
        from targetWindow: BrowserWindowState,
        extensionPublication: WindowExtensionPublicationTransaction
    ) {
        guard let lifecycle else { return }
        guard let admission = rollbackAdmission(
            for: child,
            in: targetWindow
        ) else {
            return
        }
        extensionPublication.discardRegistration(targetWindow)
        lifecycle.cleanupTrackedWebView(
            child.webView,
            owner: TrackedWebViewOwner(
                tabID: child.tab.id,
                windowID: targetWindow.id
            )
        )
        discardModel(
            child,
            admission: admission,
            from: targetWindow
        )
    }

    private func discardUnplaced(
        _ child: Child,
        from targetWindow: BrowserWindowState
    ) {
        guard let admission = rollbackAdmission(
            for: child,
            in: targetWindow
        ) else {
            return
        }
        child.tab.cleanupCloneWebView(child.webView)
        discardModel(
            child,
            admission: admission,
            from: targetWindow
        )
    }

    private func discardModel(
        _ child: Child,
        admission: BrowserTabResidenceAuthority.RemovalAdmission,
        from targetWindow: BrowserWindowState
    ) {
        guard residences.commitRemoval(
            admission,
            currentSpaceID: targetWindow.currentSpaceId
        ) else { return }

        switch child.residence {
        case .regular:
            clearChildWindowIdentity(child.tab, in: targetWindow)
        case .ephemeral:
            clearChildWindowIdentity(child.tab, in: targetWindow)
        }
    }

    private func rollbackAdmission(
        for child: Child,
        in targetWindow: BrowserWindowState
    ) -> BrowserTabResidenceAuthority.RemovalAdmission? {
        switch child.residence {
        case .regular(let spaceID):
            guard child.tab.spaceId == spaceID else { return nil }
        case .ephemeral:
            guard child.tab.spaceId == nil else { return nil }
        }
        return residences.admitRemoval(of: child.tab, from: targetWindow)
    }

    private func clearChildWindowIdentity(
        _ tab: Tab,
        in targetWindow: BrowserWindowState
    ) {
        if targetWindow.currentTabId == tab.id {
            targetWindow.currentTabId = nil
        }
        if targetWindow.webKitChildWindowIdentity?.initialTabID == tab.id {
            targetWindow.webKitChildWindowIdentity = nil
        }
    }
}
