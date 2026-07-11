import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit

/// Creates an extension-requested normal window as one reversible model, shell,
/// WebView, and extension-publication transaction. No observer can see an empty
/// intermediate window.
@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionRequestedWindowTransaction:
    ExtensionRequestedWindowCreating {
    private struct PreparedWindow {
        let window: BrowserWindowState
        let tab: Tab
        let webView: FocusableWKWebView
        let seed: ExtensionRequestedWindowSeed
        var isPresented: Bool
    }

    private weak var commands: BrowserWindowCommands?
    private weak var restoration: WindowSessionRestoreService?
    private weak var extensionPublication:
        WindowExtensionPublicationTransaction?
    private weak var tabs: TabManager?
    private weak var webViews: WebViewLifecycleService?
    private let ownership: WebViewOwnershipQuery
    private let registeredWindow: @MainActor (UUID) -> BrowserWindowState?
    private let materialize: @MainActor (
        Tab,
        BrowserWindowState
    ) -> FocusableWKWebView?
    private let rollbackRegisteredWindow: @MainActor (
        BrowserWindowState
    ) -> Bool
    private let persistWindow: @MainActor (BrowserWindowState) -> Void
    private var preparedByToken: [UUID: PreparedWindow] = [:]

    init(
        commands: BrowserWindowCommands,
        restoration: WindowSessionRestoreService,
        extensionPublication: WindowExtensionPublicationTransaction,
        tabs: TabManager,
        webViews: WebViewLifecycleService,
        ownership: WebViewOwnershipQuery,
        registeredWindow: @escaping @MainActor (
            UUID
        ) -> BrowserWindowState?,
        materialize: @escaping @MainActor (
            Tab,
            BrowserWindowState
        ) -> FocusableWKWebView?,
        rollbackRegisteredWindow: @escaping @MainActor (
            BrowserWindowState
        ) -> Bool,
        persistWindow: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.commands = commands
        self.restoration = restoration
        self.extensionPublication = extensionPublication
        self.tabs = tabs
        self.webViews = webViews
        self.ownership = ownership
        self.registeredWindow = registeredWindow
        self.materialize = materialize
        self.rollbackRegisteredWindow = rollbackRegisteredWindow
        self.persistWindow = persistWindow
    }

    func prepareExtensionRequestedWindow(
        _ seed: ExtensionRequestedWindowSeed
    ) -> (any PreparedExtensionRequestedWindow)? {
        guard let commands,
              let restoration,
              let extensionPublication,
              let tabs,
              seed.space.profileId == seed.profileID,
              tabs.spaceStateOwner.space(with: seed.space.id) === seed.space
        else {
            return nil
        }

        var initialTab: Tab?
        var initialWebView: FocusableWKWebView?
        var preparedContext = false
        var stagedExtensionPublication = false

        let window = commands.createPreparedWindow(
            initialize: { target in
                guard tabs.spaceStateOwner.space(with: seed.space.id)
                        === seed.space,
                      seed.space.profileId == seed.profileID
                else {
                    return
                }
                let tab = tabs.regularTabLifecycleOwner.createNewTab(
                    url: (seed.url ?? SumiSurface.emptyTabURL).absoluteString,
                    in: seed.space,
                    activate: false,
                    webExtensionContextOverride: seed.webExtensionContext
                )
                initialTab = tab
                guard restoration.prepareContextualWindowWithInitialTab(
                    profileID: seed.profileID,
                    spaceID: seed.space.id,
                    initialTabExecutionProfileID: tab.profileId
                        ?? seed.profileID,
                    forRegistration: target
                ) else {
                    return
                }
                preparedContext = true
                _ = WindowTabSelectionStateApplicator.apply(
                    tab,
                    to: target,
                    updateSpaceFromTab: true,
                    rememberSelection: true
                )
            },
            validateBeforeShell: { target in
                guard let initialTab else { return false }
                return Self.validate(
                    initialTab,
                    seed: seed,
                    in: target,
                    tabs: tabs,
                    webView: nil,
                    ownership: self.ownership
                )
            },
            validateBeforePublication: { target in
                guard target.isAwaitingInitialSessionResolution == false,
                      let initialTab,
                      Self.validate(
                          initialTab,
                          seed: seed,
                          in: target,
                          tabs: tabs,
                          webView: initialWebView,
                          ownership: self.ownership
                      )
                else {
                    return false
                }

                if initialWebView == nil {
                    initialWebView = self.materialize(initialTab, target)
                }
                guard let initialWebView,
                      initialWebView.owningTab === initialTab,
                      Self.hasExactTrackedWebView(
                          initialWebView,
                          tab: initialTab,
                          window: target,
                          ownership: self.ownership
                      )
                else {
                    return false
                }

                if stagedExtensionPublication == false {
                    guard extensionPublication.stageInitialTab(
                        initialTab,
                        webView: initialWebView,
                        in: target,
                        reason: "BrowserExtensionRequestedWindowTransaction.create"
                    ) == .extensionPrepared else {
                        return false
                    }
                    stagedExtensionPublication = true
                }
                return extensionPublication.validateStagedInitialTab(
                    initialTab,
                    webView: initialWebView,
                    in: target
                )
            },
            validateCommittedRegistration: { target in
                guard self.registeredWindow(target.id) === target,
                      extensionPublication.initialPublicationResult(
                          for: target
                      ) == .extensionPublished,
                      let initialTab,
                      let initialWebView
                else {
                    extensionPublication.revokeCommittedPublicationIfNeeded(
                        for: target
                    )
                    return false
                }
                let isValid = Self.validate(
                    initialTab,
                    seed: seed,
                    in: target,
                    tabs: tabs,
                    webView: initialWebView,
                    ownership: self.ownership
                )
                if isValid == false {
                    extensionPublication.revokeCommittedPublicationIfNeeded(
                        for: target
                    )
                }
                return isValid
            },
            discardPreparedState: { [weak self] target in
                guard let initialTab else {
                    if preparedContext {
                        restoration.cancelPreparedWindowRegistration(target)
                    }
                    return
                }
                self?.discard(
                    initialTab,
                    from: target,
                    spaceID: seed.space.id
                )
            },
            presentAfterRegistration: false
        )

        guard let window else {
            return nil
        }
        guard let initialTab,
              let initialWebView,
              registeredWindow(window.id) === window,
              extensionPublication.initialPublicationResult(for: window)
                == .extensionPublished,
              Self.validate(
                  initialTab,
                  seed: seed,
                  in: window,
                  tabs: tabs,
                  webView: initialWebView,
                  ownership: ownership
              )
        else {
            extensionPublication.revokeCommittedPublicationIfNeeded(for: window)
            _ = rollbackRegisteredWindow(window)
            if let initialTab {
                discard(
                    initialTab,
                    from: window,
                    spaceID: seed.space.id
                )
            }
            return nil
        }

        let token = UUID()
        preparedByToken[token] = PreparedWindow(
            window: window,
            tab: initialTab,
            webView: initialWebView,
            seed: seed,
            isPresented: false
        )
        return BrowserPreparedExtensionRequestedWindow(
            transaction: self,
            token: token,
            window: window
        )
    }

    fileprivate func presentPreparedWindow(
        token: UUID,
        window: BrowserWindowState
    ) -> Bool {
        guard var prepared = currentPreparedWindow(
            token: token,
            window: window,
            requiresPresented: false
        ), prepared.isPresented == false,
           let commands,
           commands.presentPreparedWindow(window, activate: true),
           let current = currentPreparedWindow(
               token: token,
               window: window,
               requiresPresented: false
           ), current.isPresented == false
        else {
            cancelPreparedWindow(token: token, window: window)
            return false
        }

        prepared.isPresented = true
        preparedByToken[token] = prepared
        return true
    }

    fileprivate func acceptPreparedWindow(
        token: UUID,
        window: BrowserWindowState
    ) -> Bool {
        guard let prepared = currentPreparedWindow(
            token: token,
            window: window,
            requiresPresented: true
        ) else {
            cancelPreparedWindow(token: token, window: window)
            return false
        }

        preparedByToken.removeValue(forKey: token)
        persistWindow(prepared.window)
        prepared.window.compositorInvalidation.refresh()
        return true
    }

    fileprivate func cancelPreparedWindow(
        token: UUID,
        window: BrowserWindowState
    ) {
        guard let prepared = preparedByToken[token],
              prepared.window === window
        else {
            return
        }
        preparedByToken.removeValue(forKey: token)
        extensionPublication?.revokeCommittedPublicationIfNeeded(
            for: prepared.window
        )
        _ = rollbackRegisteredWindow(prepared.window)
        discard(
            prepared.tab,
            from: prepared.window,
            spaceID: prepared.seed.space.id
        )
    }

    private func currentPreparedWindow(
        token: UUID,
        window: BrowserWindowState,
        requiresPresented: Bool
    ) -> PreparedWindow? {
        guard let prepared = preparedByToken[token],
              prepared.window === window,
              prepared.isPresented == requiresPresented,
              registeredWindow(window.id) === window,
              extensionPublication?.initialPublicationResult(for: window)
                == .extensionPublished,
              let tabs,
              Self.validate(
                  prepared.tab,
                  seed: prepared.seed,
                  in: window,
                  tabs: tabs,
                  webView: prepared.webView,
                  ownership: ownership
              )
        else {
            return nil
        }
        return prepared
    }

    private static func validate(
        _ tab: Tab,
        seed: ExtensionRequestedWindowSeed,
        in window: BrowserWindowState,
        tabs: TabManager,
        webView: FocusableWKWebView?,
        ownership: WebViewOwnershipQuery
    ) -> Bool {
        guard window.isIncognito == false,
              window.currentProfileId == seed.profileID,
              window.currentSpaceId == seed.space.id,
              window.currentTabId == tab.id,
              tab.spaceId == seed.space.id,
              (tab.profileId ?? seed.space.profileId) == seed.profileID,
              tab.webExtensionContextOverride === seed.webExtensionContext,
              tabs.spaceStateOwner.space(with: seed.space.id) === seed.space
        else {
            return false
        }
        guard tabs.regularTabCollectionOwner
            .tabs(in: seed.space.id)
            .contains(where: { $0 === tab })
        else {
            return false
        }
        guard let webView else { return true }
        return hasExactTrackedWebView(
            webView,
            tab: tab,
            window: window,
            ownership: ownership
        )
    }

    private static func hasExactTrackedWebView(
        _ webView: FocusableWKWebView,
        tab: Tab,
        window: BrowserWindowState,
        ownership: WebViewOwnershipQuery
    ) -> Bool {
        ownership.trackedOwner(containing: webView) == TrackedWebViewOwner(
            tabID: tab.id,
            windowID: window.id
        ) && ownership.webView(
            for: tab.id,
            in: window.id
        ) === webView
    }

    private func discard(
        _ tab: Tab,
        from window: BrowserWindowState,
        spaceID: UUID
    ) {
        guard let tabs else { return }
        webViews?.removeAllWebViews(
            for: tab,
            closeActiveFullscreenMedia: true
        )
        tab.performComprehensiveWebViewCleanup()
        tabs.structuralPersistence.cancelRuntimeStatePersistence(for: tab.id)
        window.currentTabId = nil
        if tabs.regularTabCollectionOwner.remove(
            tab.id,
            from: spaceID,
            currentSpaceId: window.currentSpaceId
        ) != nil {
            tabs.tabCollectionMembershipOwner.detach(tab)
            tabs.structuralPersistence.scheduleStructuralPersistence()
        }
        restoration?.cancelPreparedWindowRegistration(window)
    }
}

@available(macOS 15.5, *)
@MainActor
private final class BrowserPreparedExtensionRequestedWindow:
    PreparedExtensionRequestedWindow {
    let window: BrowserWindowState

    private let transaction: BrowserExtensionRequestedWindowTransaction
    private let token: UUID

    init(
        transaction: BrowserExtensionRequestedWindowTransaction,
        token: UUID,
        window: BrowserWindowState
    ) {
        self.transaction = transaction
        self.token = token
        self.window = window
    }

    func present() -> Bool {
        transaction.presentPreparedWindow(token: token, window: window)
    }

    func accept() -> Bool {
        transaction.acceptPreparedWindow(token: token, window: window)
    }

    func cancel() {
        transaction.cancelPreparedWindow(token: token, window: window)
    }
}
