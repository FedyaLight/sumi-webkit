//
//  Tab.swift
//  Sumi
//
//

import AppKit
import Combine
import Foundation
import Navigation
import SumiDomain
import WebKit
import SumiWebRuntime

@MainActor
public class Tab: NSObject, Identifiable, ObservableObject {
    public typealias LoadingState = TabLoadingState
    public let id: UUID
    /// Presentation/persistence URL. Navigation authority is advanced only by
    /// explicit commands or exact WebKit lifecycle identities, never by an
    /// incidental model assignment.
    public var url: URL
    @Published var name: String
    /// Model-neutral favicon representation; the UI layer maps this to `SwiftUI.Image`
    /// (see `Sumi/Components/TabFaviconPresentation+Image.swift`).
    @Published var faviconPresentation: TabFaviconPresentation
    /// True while the tab shows the SF Symbol ``globe`` fallback (no bitmap favicon yet / resolver miss).
    @Published var faviconIsTemplateGlobePlaceholder: Bool = false
    private let placementStateOwner = TabPlacementStateOwner()
    private let surfaceStateOwner = TabSurfaceStateOwner()
    var spaceId: UUID? {
        get { placementStateOwner.spaceId }
        set { placementStateOwner.spaceId = newValue }
    }
    var index: Int {
        get { placementStateOwner.index }
        set { placementStateOwner.index = newValue }
    }
    var profileId: UUID?
    private var profileAssignmentIntentRevision: UInt64 = 0
    private var pendingProfileAssignmentIntent:
        DeferredWebViewProfileAssignmentIntent?
    private var settlingProfileAssignmentIntent:
        DeferredWebViewProfileAssignmentIntent?
    // If true, this tab is created to host a popup window; do not perform initial load.
    var isPopupHost: Bool {
        get { surfaceStateOwner.isPopupHost }
        set { surfaceStateOwner.isPopupHost = newValue }
    }
    // If true, this tab hosts content in a compact auxiliary mini-window (not in sidebar).
    var isAuxiliaryMiniWindow: Bool {
        get { surfaceStateOwner.isAuxiliaryMiniWindow }
        set { surfaceStateOwner.isAuxiliaryMiniWindow = newValue }
    }

    let stateChangeEmitter = TabStateChangeEmitter()
    let navigationRuntime = TabNavigationRuntime()
    let mediaRuntime = TabMediaRuntime()
    let faviconRuntime = TabFaviconRuntime()
    let profileResolutionOwner = TabProfileResolutionOwner()
    let extensionPageRuntimeOwner = TabExtensionPageRuntimeOwner()
    public let webViewSession: WebViewSessionHandle
    private let mainFrameRuntimeTransaction: TabMainFrameRuntimeTransaction
    let webViewConfigurationOwner = TabWebViewConfigurationOwner()
    let normalWebViewSetupOwner = TabNormalWebViewSetupOwner()
    let webViewProvisioningOwner = TabWebViewProvisioningOwner()
    lazy var normalWebViewRuntimeContextOwner = TabNormalWebViewRuntimeContextOwner(tab: self)
    private let closeLifecycleOwner = TabCloseLifecycleOwner()
    let webViewReplacementContextOwner =
        TabWebViewReplacementContextOwner()
    let navigationCommandOwner = TabNavigationCommandOwner()
    lazy var profileWebViewCreationGate = TabProfileWebViewCreationGate(
        tab: self,
        currentProfileUpdates: { [weak self] in
            self?.browserRuntime.currentProfileUpdates()
        }
    )
    lazy var ownedWebViewPreparationOwner = TabOwnedWebViewPreparationOwner(
        dependencies: .live(tab: self)
    )
    var suspensionState = TabSuspensionState()
    var lastSelectedAt: Date?
    lazy var permissionSurfaceOwner = TabPermissionSurfaceOwner(context: .live(tab: self))
    lazy var webKitUIDelegateOwner = TabWebKitUIDelegateOwner(tab: self)
    lazy var webKitPermissionUIDelegateOwner = TabWebKitPermissionUIDelegateOwner(tab: self)
    private var browserRuntime = TabBrowserRuntime.inactive
    private var browserRuntimeAttached = false
    private(set) var linkPresentationCommands =
        TabLinkPresentationCommands.inactive
    private(set) var webPageMenuCommands = TabWebPageMenuCommands.inactive
    private let dependencyStateOwner: TabDependencyStateOwner

    // MARK: - Pin State
    var isPinned: Bool {
        get { placementStateOwner.isPinned }
        set { placementStateOwner.isPinned = newValue }
    }
    var isSpacePinned: Bool {
        get { placementStateOwner.isSpacePinned }
        set { placementStateOwner.isSpacePinned = newValue }
    }
    var folderId: UUID? {
        get { placementStateOwner.folderId }
        set { placementStateOwner.folderId = newValue }
    }
    var shortcutPinId: UUID? {
        get { placementStateOwner.shortcutPinId }
        set { placementStateOwner.shortcutPinId = newValue }
    }
    var shortcutPinRole: ShortcutPinRole? {
        get { placementStateOwner.shortcutPinRole }
        set { placementStateOwner.shortcutPinRole = newValue }
    }
    var isShortcutLiveInstance: Bool {
        get { placementStateOwner.isShortcutLiveInstance }
        set { placementStateOwner.isShortcutLiveInstance = newValue }
    }

    // MARK: - Ephemeral State
    /// Whether this tab belongs to an ephemeral/incognito session
    public var isEphemeral: Bool {
        resolveProfile()?.isEphemeral ?? false
    }

    var loadingState: LoadingState {
        get { navigationRuntime.loadingState }
        set {
            guard navigationRuntime.loadingState != newValue else { return }
            let oldIsLoading = navigationRuntime.loadingState.isLoading
            objectWillChange.send()
            navigationRuntime.loadingState = newValue
            if !newValue.isLoading {
                self.estimatedProgress = 1.0
            }
            guard oldIsLoading != newValue.isLoading else { return }
            stateChangeEmitter.postLoadingStateDidChange(for: self)
        }
    }

    func beginLoadingPresentationIfNeeded() {
        guard !loadingState.isLoading else { return }
        estimatedProgress = 0.05
        loadingState = .didStartProvisionalNavigation
    }

    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    /// Owns page-load progress. Kept off `Tab`'s own `@Published` graph so its
    /// high-frequency ticks don't invalidate sidebar rows that observe the whole
    /// `Tab`; only the chrome loading bar subscribes to it. See ``TabLoadingProgress``.
    let loadingProgress = TabLoadingProgress()
    var estimatedProgress: Double {
        get { loadingProgress.estimatedProgress }
        set { loadingProgress.estimatedProgress = newValue }
    }

    // Restored navigation state from undo/session restoration (applied when web view is created)
    var restoredCanGoBack: Bool? {
        get { navigationRuntime.restoredCanGoBack }
        set { navigationRuntime.restoredCanGoBack = newValue }
    }
    var restoredCanGoForward: Bool? {
        get { navigationRuntime.restoredCanGoForward }
        set { navigationRuntime.restoredCanGoForward = newValue }
    }

    // MARK: - Audio State
    @Published var audioState: SumiWebViewAudioState = .unmuted(isPlayingAudio: false)
    // MARK: - Rename State
    @Published var isRenaming: Bool = false
    @Published var editingName: String = ""

    var profileAwaitCancellable: AnyCancellable?
    let findInPage = FindInPageTabExtension()

    // MARK: - Tab State
    var isUnloaded: Bool {
        resolvedCurrentWebView() == nil
    }

    /// True when the tab row should show the web-content-unloaded favicon affordance.
    /// Sumi-native tabs (settings UI, empty new-tab surface) never host a primary-frame WKWebView for that UI, so they must not look “unloaded”.
    var showsWebViewUnloadedIndicator: Bool {
        requiresPrimaryWebView && isUnloaded
    }

    var webViewConfigurationOverride: WKWebViewConfiguration? {
        get { webViewConfigurationOwner.webViewConfigurationOverride }
        set { webViewConfigurationOwner.webViewConfigurationOverride = newValue }
    }
    var webExtensionContextOverride: WKWebExtensionContext? {
        get { webViewConfigurationOwner.webExtensionContextOverride }
        set { webViewConfigurationOwner.webExtensionContextOverride = newValue }
    }
    let reloadPolicyStateOwner = TabReloadPolicyStateOwner()

    func beginWebViewRebuildIntent() -> UInt64 {
        mainFrameRuntimeTransaction.beginRebuildIntent()
    }

    var currentWebViewRebuildIntentRevision: UInt64 {
        mainFrameRuntimeTransaction.rebuildIntentRevision
    }

    func isCurrentWebViewRebuildIntent(_ revision: UInt64) -> Bool {
        mainFrameRuntimeTransaction.rebuildIntentRevision == revision
    }

    @discardableResult
    func beginMainFrameNavigationIntent(to targetURL: URL) -> TabMainFrameNavigationIntent {
        let intent = mainFrameRuntimeTransaction.beginExplicitIntent(to: targetURL)
        for webView in webViewSession.allKnownWebViews {
            guard let host = webView.sumiReaderPresentationHost,
                  host.tabID == id,
                  host.webView === webView else {
                continue
            }
            host.dismissReader()
        }
        return intent
    }

    func currentMainFrameNavigationIntent(
        matching targetURL: URL
    ) -> TabMainFrameNavigationIntent? {
        mainFrameRuntimeTransaction.currentIntent(matching: targetURL)
    }

    func currentMainFrameNavigationIntent() -> TabMainFrameNavigationIntent {
        mainFrameRuntimeTransaction.currentIntent
    }

    func currentMainFrameNavigationIntent(
        revision: UInt64
    ) -> TabMainFrameNavigationIntent? {
        mainFrameRuntimeTransaction.currentIntent(revision: revision)
    }

    func isCurrentMainFrameNavigationIntent(
        _ intent: TabMainFrameNavigationIntent
    ) -> Bool {
        mainFrameRuntimeTransaction.isCurrentIntent(intent)
    }

    func submittedMainFrameSemanticRevision(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> UInt64? {
        mainFrameRuntimeTransaction.semanticRevision(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime
        )
    }

    func isCurrentMainFrameNavigationIntent(
        revision: UInt64,
        targetURL: URL
    ) -> Bool {
        mainFrameRuntimeTransaction.isCurrentIntent(
            revision: revision,
            targetURL: targetURL
        )
    }

    @discardableResult
    func claimDirectMainFrameLoad(on webView: WKWebView) -> Bool {
        mainFrameRuntimeTransaction.claimDirectSubmission(on: webView) != nil
    }

    func claimDirectMainFrameLoadLease(
        on webView: WKWebView
    ) -> TabMainFrameSubmissionLease? {
        mainFrameRuntimeTransaction.claimDirectSubmission(on: webView)
    }

    func claimDeferredMainFrameLoad(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL
    ) -> TabDeferredMainFrameLoadClaim {
        mainFrameRuntimeTransaction.claimDeferredSubmission(
            on: webView,
            revision: revision,
            targetURL: targetURL
        )
    }

    func submittedMainFrameLoadLease(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL
    ) -> TabMainFrameSubmissionLease? {
        mainFrameRuntimeTransaction.submittedLease(
            on: webView,
            revision: revision,
            targetURL: targetURL
        )
    }

    @discardableResult
    func bindSubmittedMainFrameLoad(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        matching lease: TabMainFrameSubmissionLease? = nil
    ) -> Bool {
        mainFrameRuntimeTransaction.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            matching: lease
        )
    }

    @discardableResult
    func failSubmittedMainFrameLoad(
        on webView: WKWebView,
        matching lease: TabMainFrameSubmissionLease? = nil
    ) -> TabMainFrameNavigationAbortResult {
        mainFrameRuntimeTransaction.failSubmittedLoad(
            on: webView,
            matching: lease
        )
    }

    func restoreDeferredMainFrameLoadAfterFailedSubmission(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL,
        matching lease: TabMainFrameSubmissionLease? = nil
    ) {
        mainFrameRuntimeTransaction.restoreDeferredLoadAfterFailedSubmission(
            on: webView,
            revision: revision,
            targetURL: targetURL,
            matching: lease
        )
    }

    @discardableResult
    func webViewDidLeaveNavigationRuntime(
        _ webView: WKWebView
    ) -> TabMainFrameRuntimeDepartureResult {
        let preferredWebView = resolvedCurrentWebView().flatMap {
            $0 === webView ? nil : $0
        }
        return webViewsDidLeaveNavigationRuntime(
            [webView],
            preferredAuthorityWebView: preferredWebView
        )
    }

    /// Retires a complete physical generation before any member is destroyed.
    /// Authority is reduced and replayed once after the whole set has departed.
    @discardableResult
    func webViewsDidLeaveNavigationRuntime(
        _ webViews: [WKWebView],
        preferredAuthorityWebView: WKWebView?
    ) -> TabMainFrameRuntimeDepartureResult {
        let previousSuspensionDecision = documentSuspensionDecision
        var seen: Set<ObjectIdentifier> = []
        let departingWebViews = webViews.filter {
            seen.insert(ObjectIdentifier($0)).inserted
        }
        departingWebViews.forEach {
            navigationRuntime.webViewRouting.cancelWebContentProcessRecovery($0)
        }
        let result = mainFrameRuntimeTransaction.webViewsDidLeaveRuntime(
            departingWebViews,
            preferredAuthorityWebView: preferredAuthorityWebView
        )
        if let continuation = result.continuation {
            TabMainFrameLifecycleReducer.replayIfNeeded(
                continuation,
                tab: self
            )
        }
        reconcileDocumentSuspensionStateIfChanged(
            from: previousSuspensionDecision,
            reason: "document-replica-departure"
        )
        return result
    }

    func abortMainFrameNavigation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        rollsBackWhenUnreplaced: Bool = true
    ) -> TabMainFrameNavigationAbortResult {
        let previousSuspensionDecision = documentSuspensionDecision
        let result = mainFrameRuntimeTransaction.abortNavigation(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            survivingCommittedURL: webView.committedURL,
            rollsBackWhenUnreplaced: rollsBackWhenUnreplaced
        )
        if case .authoritativeRollback(let rollbackURL) = result {
            _ = beginWebViewRebuildIntent()
            url = rollbackURL
            activatePendingDocumentSuspensionReports()
        }
        reconcileDocumentSuspensionStateIfChanged(
            from: previousSuspensionDecision,
            reason: "document-navigation-abort"
        )
        return result
    }

    func beginWebContentProcessRecovery(
        on webView: WKWebView
    ) -> TabWebContentProcessRecoveryPlan {
        mainFrameRuntimeTransaction.beginWebContentProcessRecovery(on: webView)
    }

    func requiresWebContentProcessRecovery(on webView: WKWebView) -> Bool {
        mainFrameRuntimeTransaction.requiresWebContentProcessRecovery(on: webView)
    }

    func mainFrameDocumentLease(
        for webView: WKWebView
    ) -> TabMainFrameDocumentLease? {
        mainFrameRuntimeTransaction.documentLease(for: webView)
    }

    var documentSuspensionDecision: TabDocumentSuspensionDecision {
        mainFrameRuntimeTransaction.documentSuspensionDecision()
    }

    @discardableResult
    func recordDocumentSuspensionReport(
        _ report: TabDocumentSuspensionReport,
        from webView: WKWebView,
        matching lease: TabMainFrameDocumentLease
    ) -> Bool {
        mainFrameRuntimeTransaction.recordSuspensionReport(
            report,
            from: webView,
            matching: lease
        )
    }

    @discardableResult
    func recordSubframePictureInPictureReport(
        _ report: TabSubframePictureInPictureReport,
        from webView: WKWebView,
        matching lease: TabMainFrameDocumentLease
    ) -> Bool {
        mainFrameRuntimeTransaction.recordSubframePictureInPictureReport(
            report,
            from: webView,
            matching: lease
        )
    }

    func documentSuspensionActivationToken(
        for webView: WKWebView
    ) -> String? {
        mainFrameRuntimeTransaction.documentSuspensionToken(for: webView)
    }

    func beginPreparedMainFrameLoad(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) -> TabMainFramePreparedLoadTicket? {
        mainFrameRuntimeTransaction.beginPreparedLoad(
            on: webView,
            intent: intent
        )
    }

    func finishPreparedMainFrameLoad(
        _ ticket: TabMainFramePreparedLoadTicket
    ) {
        mainFrameRuntimeTransaction.finishPreparedLoad(ticket)
    }

    @discardableResult
    func markDeferredMainFrameLoad(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) -> Bool {
        mainFrameRuntimeTransaction.markDeferredLoad(
            on: webView,
            intent: intent
        )
    }

    func clearDeferredMainFrameLoad(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) {
        mainFrameRuntimeTransaction.clearDeferredLoad(
            on: webView,
            intent: intent
        )
    }

    func hasOutstandingMainFrameLoad(on webView: WKWebView, targetURL: URL) -> Bool {
        mainFrameRuntimeTransaction.hasOutstandingLoad(
            on: webView,
            targetURL: targetURL
        )
    }

    func mainFrameLoadingWebViews() -> [WKWebView] {
        mainFrameRuntimeTransaction.loadingWebViews()
    }

    func beginMainFrameLifecycle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        navigationLifetime: AnyObject,
        targetURL: URL?,
        allowsUserInitiatedSupersession: Bool,
        continuationKind: TabMainFrameContinuationKind?
    ) -> TabMainFrameLifecycleRole {
        let acceptance = mainFrameRuntimeTransaction.beginLifecycle(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            targetURL: targetURL,
            allowsUserInitiatedSupersession: allowsUserInitiatedSupersession,
            continuationKind: continuationKind
        )
        if acceptance.beganNewIntent {
            _ = beginWebViewRebuildIntent()
        }
        return acceptance.role
    }

    func mainFrameLifecycleRole(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        isCurrent: Bool?
    ) -> TabMainFrameLifecycleRole {
        mainFrameRuntimeTransaction.lifecycleRole(
            from: webView,
            navigationID: navigationID,
            isCurrent: isCurrent
        )
    }

    func shouldAcceptMainFrameLifecycle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        isCurrent: Bool?
    ) -> Bool {
        mainFrameRuntimeTransaction.lifecycleRole(
            from: webView,
            navigationID: navigationID,
            isCurrent: isCurrent
        ).isAuthority
    }

    func prepareMainFrameAuthorityForCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameLifecycleRole {
        mainFrameRuntimeTransaction.prepareAuthorityForCommit(
            from: webView,
            navigationID: navigationID
        )
    }

    func recordMainFrameCommitSnapshot(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        committedURL: URL,
        isPDF: Bool
    ) -> TabMainFrameCommitSnapshotClaim {
        let previousSuspensionDecision = documentSuspensionDecision
        let claim = mainFrameRuntimeTransaction.recordCommit(
            from: webView,
            navigationID: navigationID,
            committedURL: committedURL,
            isPDF: isPDF
        )
        activatePendingDocumentSuspensionReports()
        reconcileDocumentSuspensionStateIfChanged(
            from: previousSuspensionDecision,
            reason: "document-commit"
        )
        return claim
    }

    func claimMainFrameTransactionStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool {
        mainFrameRuntimeTransaction.claimTransactionStartEffects(
            from: webView,
            navigationID: navigationID
        )
    }

    func claimMainFrameAuthorityTargetPreparation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool {
        mainFrameRuntimeTransaction.claimAuthorityTargetPreparation(
            from: webView,
            navigationID: navigationID
        )
    }

    func claimMainFrameLocalStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool {
        mainFrameRuntimeTransaction.claimLocalStartEffects(
            from: webView,
            navigationID: navigationID
        )
    }

    func claimMainFrameAuthorityForTerminalSuccess(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        terminalURL: URL?,
        completesDocumentNavigation: Bool
    ) -> TabMainFrameLifecycleRole {
        mainFrameRuntimeTransaction.claimAuthorityForTerminalSuccess(
            from: webView,
            navigationID: navigationID,
            terminalURL: terminalURL,
            completesDocumentNavigation: completesDocumentNavigation
        )
    }

    func claimSharedMainFrameFinishEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool {
        mainFrameRuntimeTransaction.claimSharedFinishEffects(
            from: webView,
            navigationID: navigationID
        )
    }

    func claimPromotedSharedCommitEffects(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool {
        let previousSuspensionDecision = documentSuspensionDecision
        let claimed = mainFrameRuntimeTransaction.claimPromotedSharedCommitEffects(
            matching: continuation
        )
        if claimed {
            activatePendingDocumentSuspensionReports()
            reconcileDocumentSuspensionStateIfChanged(
                from: previousSuspensionDecision,
                reason: "document-authority-promotion"
            )
        }
        return claimed
    }

    func claimPromotedSharedFinishEffects(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool {
        mainFrameRuntimeTransaction.claimPromotedSharedFinishEffects(
            matching: continuation
        )
    }

    func applyPromotedAuthorityURL(
        _ targetURL: URL,
        matching continuation: TabMainFrameAuthorityContinuation
    ) {
        guard mainFrameRuntimeTransaction.acceptPromotedAuthorityTarget(
            targetURL,
            matching: continuation
        ) else { return }
        url = targetURL
    }

    @discardableResult
    func recordMainFrameResponse(
        isPDF: Bool,
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameLifecycleRole {
        mainFrameRuntimeTransaction.recordResponse(
            isPDF: isPDF,
            from: webView,
            navigationID: navigationID
        )
    }

    func mainFrameResponseIsPDF(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool? {
        mainFrameRuntimeTransaction.responseIsPDF(
            from: webView,
            navigationID: navigationID
        )
    }

    func applyAcceptedMainFrameLifecycleURL(
        _ targetURL: URL,
        from webView: WKWebView,
        navigationID: ObjectIdentifier?
    ) {
        guard mainFrameRuntimeTransaction.acceptLifecycleTarget(
            targetURL,
            from: webView,
            navigationID: navigationID
        ) else { return }
        url = targetURL
    }

    func finishMainFrameLifecycle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?
    ) {
        mainFrameRuntimeTransaction.finishLifecycle(
            from: webView,
            navigationID: navigationID
        )
    }

    func cancelMainFrameNavigationIntent() {
        let previousSuspensionDecision = documentSuspensionDecision
        _ = mainFrameRuntimeTransaction.rollbackToDurableDocument()
        activatePendingDocumentSuspensionReports()
        reconcileDocumentSuspensionStateIfChanged(
            from: previousSuspensionDecision,
            reason: "document-navigation-cancel"
        )
    }

    func rollbackMainFrameNavigationAfterFailedSubmission(
        on webView: WKWebView?
    ) {
        let previousSuspensionDecision = documentSuspensionDecision
        var survivingWebViews = webViewSession.allKnownWebViews
        if let webView,
           survivingWebViews.contains(where: { $0 === webView }) == false {
            survivingWebViews.append(webView)
        }
        let rollback = mainFrameRuntimeTransaction.rollbackAfterFailedSubmission(
            survivingWebViews: survivingWebViews
        )
        activatePendingDocumentSuspensionReports()
        reconcileDocumentSuspensionStateIfChanged(
            from: previousSuspensionDecision,
            reason: "document-submission-rollback"
        )
        let rollbackURL = rollback.targetURL
        _ = beginWebViewRebuildIntent()
        url = rollbackURL
        if loadingState.isLoading {
            loadingState = .idle
        }
        applyCachedFaviconOrPlaceholder(for: rollbackURL)
        refreshFaviconExtensionCache()
        if let navigationStateSource = rollback.navigationStateSource {
            updateNavigationState(from: navigationStateSource)
        } else if let webView,
                  let committedURL = webView.committedURL,
                  WebRuntimeNavigationIdentity(committedURL)
                    == WebRuntimeNavigationIdentity(rollbackURL) {
            updateNavigationState(from: webView)
        } else {
            updateNavigationState()
        }
        stateChangeEmitter.postNavigationStateDidChange(for: self)
        navigationRuntime.persistenceCallbacks.scheduleRuntimeStatePersistence(self)
        navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            self,
            [.URL, .loading]
        )
        mediaRuntime.callbacks.scheduleBackgroundMediaReconcile(
            "navigation-submission-failed"
        )
    }

    private func activatePendingDocumentSuspensionReports() {
        for activation in mainFrameRuntimeTransaction
            .takePendingDocumentSuspensionActivations() {
            let webView = activation.webView
            let token = activation.token
            SumiDocumentSuspensionSensorUserScript.activateCommittedDocument(
                on: webView,
                token: token,
                epoch: activation.epoch,
                completion: { [weak self, weak webView] activated in
                    guard activated == false,
                          let self,
                          let webView,
                          self.mainFrameRuntimeTransaction
                            .documentSuspensionActivationDidFail(
                                for: webView,
                                token: token
                            ) else {
                        return
                    }
                    Task { @MainActor [weak self] in
                        await Task.yield()
                        self?.activatePendingDocumentSuspensionReports()
                    }
                }
            )
        }
    }

    private func reconcileDocumentSuspensionStateIfChanged(
        from previousDecision: TabDocumentSuspensionDecision,
        reason: String
    ) {
        guard documentSuspensionDecision != previousDecision else { return }
        navigationRuntime.lifecycleNavigationRuntime
            .reconcileDocumentSuspensionState(self)
        mediaRuntime.callbacks.scheduleBackgroundMediaReconcile(reason)
    }

    func isCurrentMainFrameNavigationRevision(_ revision: UInt64) -> Bool {
        mainFrameRuntimeTransaction.currentIntent.revision == revision
    }

    var hasBrowserRuntime: Bool {
        browserRuntimeAttached
    }

    func makeWebViewConfigurationContext() -> TabWebViewConfigurationContext {
        browserRuntime.webViewConfigurationContext()
    }

    func attachBrowserRuntime(_ runtime: TabBrowserRuntime) {
        browserRuntime = runtime
        browserRuntimeAttached = true
        linkPresentationCommands = runtime.linkPresentationCommands
        webPageMenuCommands = runtime.webPageMenuCommands
        navigationRuntime.webViewRouting = runtime.webViewRoutingRuntime
        navigationRuntime.persistenceCallbacks = runtime.persistenceRuntimeCallbacks
        mediaRuntime.callbacks = runtime.mediaRuntimeCallbacks
        navigationRuntime.navigationCommandRuntime = runtime.navigationCommandRuntime
        navigationRuntime.profileResolutionRuntime = runtime.profileResolutionRuntime
        navigationRuntime.reloadPolicyRuntime = runtime.reloadPolicyRuntime
        navigationRuntime.historySwipeRuntime = runtime.historySwipeRuntime
        navigationRuntime.historyRecordingRuntime = runtime.historyRecordingRuntime
        navigationRuntime.findInPageRuntime = runtime.findInPageRuntime
        navigationRuntime.extensionPropertiesRuntime = runtime.extensionPropertiesRuntime
        navigationRuntime.closeLifecycleRuntime = runtime.closeLifecycleRuntime
        navigationRuntime.lifecycleNavigationRuntime = runtime.lifecycleNavigationRuntime
        navigationRuntime.permissionRuntime = runtime.permissionRuntime
        navigationRuntime.webViewCleanupRuntime = runtime.webViewCleanupRuntime
        navigationRuntime.normalWebViewExtensionRuntime = runtime.normalWebViewExtensionRuntime
        navigationRuntime.navigationDelegateRuntime = runtime.navigationDelegateRuntime
        navigationRuntime.faviconExtensionRuntime = runtime.faviconExtensionRuntime
        navigationRuntime.popupPermissionEvaluator =
            runtime.popupPermissionEvaluator
        navigationRuntime.extensionPopupRequestConsumer =
            runtime.extensionPopupRequestConsumer
        navigationRuntime.extensionExternalTabOpening =
            runtime.extensionExternalTabOpening
        navigationRuntime.physicalWebPopupOpening =
            runtime.physicalWebPopupOpening
        navigationRuntime.webKitChildTabOpening =
            runtime.webKitChildTabOpening
        navigationRuntime.webKitChildWindowOpening =
            runtime.webKitChildWindowOpening
        navigationRuntime.installNavigationRuntime = runtime.installNavigationRuntime
        navigationRuntime.webKitUIRuntime = runtime.webKitUIRuntime
        navigationRuntime.webViewReplacementRuntime =
            runtime.webViewReplacementRuntime
        navigationRuntime.webViewRouting.bindWebViewSession(webViewSession)
        dependencyStateOwner.attachDataServicesProvider { [weak self] in
            self?.browserRuntime.dataServices()
        }
        sumiSettings = runtime.settings()
    }

    var sumiSettings: SumiSettingsService? {
        get { dependencyStateOwner.sumiSettings }
        set { dependencyStateOwner.sumiSettings = newValue }
    }

    var faviconService: any BrowserFaviconServicing {
        dependencyStateOwner.faviconService
    }

    var faviconCapabilities: BrowserFaviconCapabilities {
        dependencyStateOwner.faviconCapabilities
    }

    var visitedLinkStore: any BrowserVisitedLinkStoreManaging {
        dependencyStateOwner.visitedLinkStore
    }

    private var navigationStateController: TabNavigationStateController {
        navigationRuntime.navigationStateController
    }

    var isLoading: Bool {
        loadingState.isLoading
    }

    var representsSumiEmptySurface: Bool {
        surfaceStateOwner.representsSumiEmptySurface(for: url)
    }

    var representsSumiSettingsSurface: Bool {
        surfaceStateOwner.representsSumiSettingsSurface(for: url)
    }

    var representsSumiHistorySurface: Bool {
        surfaceStateOwner.representsSumiHistorySurface(for: url)
    }

    var representsSumiBookmarksSurface: Bool {
        surfaceStateOwner.representsSumiBookmarksSurface(for: url)
    }

    /// Native Sumi surfaces rendered outside WebKit.
    var representsSumiNativeSurface: Bool {
        surfaceStateOwner.representsSumiNativeSurface(for: url)
    }

    /// Internal Sumi surfaces that use chrome-template presentation.
    var representsSumiInternalSurface: Bool {
        surfaceStateOwner.representsSumiInternalSurface(for: url)
    }

    public var requiresPrimaryWebView: Bool {
        surfaceStateOwner.requiresPrimaryWebView(for: url)
    }

    /// Sidebar / split tab row: tint template SF Symbol favicons like `NavButtonStyle` (`tokens.primaryText`).
    /// Covers empty tab, internal Sumi surfaces, and the ordinary ``globe`` placeholder until a bitmap favicon loads.
    var usesChromeThemedTemplateFavicon: Bool {
        surfaceStateOwner.usesChromeThemedTemplateFavicon(
            for: url,
            faviconIsTemplateGlobePlaceholder: faviconIsTemplateGlobePlaceholder
        )
    }

    // MARK: - Initializers
    init(
        id: UUID = UUID(),
        url: URL = SumiSurface.emptyTabURL,
        name: String = "New Tab",
        favicon: String = "globe",
        spaceId: UUID? = nil,
        index: Int = 0,
        existingWebView: WKWebView? = nil,
        webViewSessions: WebViewSessionRepository? = nil,
        loadsCachedFaviconOnInit: Bool = true,
        faviconService: any BrowserFaviconServicing = TabDependencyIsolationDefaults.faviconService,
        faviconCapabilities: BrowserFaviconCapabilities = TabDependencyIsolationDefaults.faviconCapabilities,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = TabDependencyIsolationDefaults.visitedLinkStore
    ) {
        self.id = id
        self.url = url
        self.mainFrameRuntimeTransaction = TabMainFrameRuntimeTransaction(
            initialURL: url
        )
        self.name = name
        self.faviconPresentation = .systemSymbol(favicon)
        self.faviconIsTemplateGlobePlaceholder = (favicon == "globe")
        if let webViewSessions {
            self.webViewSession = WebViewSessionHandle(
                tabID: id,
                repository: webViewSessions
            )
        } else {
            self.webViewSession = WebViewSessionHandle(tabID: id)
        }
        self.dependencyStateOwner = TabDependencyStateOwner(
            faviconService: faviconService,
            faviconCapabilities: faviconCapabilities,
            visitedLinkStore: visitedLinkStore
        )
        super.init()
        self.spaceId = spaceId
        self.index = index
        navigationStateController.delegate = self
        parkExistingWebView(existingWebView)

        applyCachedFaviconOrPlaceholder(
            for: url,
            allowCacheLookup: loadsCachedFaviconOnInit
        )
    }

    func parkExistingWebView(_ webView: WKWebView?) {
        webViewSession.park(webView)
    }

    func clearParkedExistingWebView() {
        webViewSession.clearParked()
    }

    func adoptParkedWebViewAsCurrent(_ webView: WKWebView) {
        precondition(
            webViewSession.adoptParkedAsUntracked(webView),
            "Only this tab's parked WebView can be adopted"
        )
    }

    func replaceUntrackedWebView(_ webView: WKWebView) {
        webViewSession.replaceUntracked(with: webView)
    }

    func beginProfileAssignmentIntent(
        desiredProfileID: UUID?,
        resolvedProfileID: UUID,
        targetURL: URL,
        requiresStructuralPersistence: Bool
    ) -> DeferredWebViewProfileAssignmentIntent {
        precondition(
            settlingProfileAssignmentIntent == nil,
            "A profile transition must settle before another transition begins"
        )
        profileAssignmentIntentRevision &+= 1
        let intent = DeferredWebViewProfileAssignmentIntent(
            revision: profileAssignmentIntentRevision,
            expectedProfileID: profileId,
            desiredProfileID: desiredProfileID,
            resolvedProfileID: resolvedProfileID,
            targetURL: targetURL,
            requiresStructuralPersistence: requiresStructuralPersistence
        )
        pendingProfileAssignmentIntent = intent
        return intent
    }

    func isCurrentProfileAssignmentIntent(
        _ intent: DeferredWebViewProfileAssignmentIntent
    ) -> Bool {
        pendingProfileAssignmentIntent == intent
            && profileAssignmentIntentRevision == intent.revision
            && profileId == intent.expectedProfileID
    }

    func hasPendingProfileAssignment(to desiredProfileID: UUID?) -> Bool {
        let intent = pendingProfileAssignmentIntent
            ?? settlingProfileAssignmentIntent
        return intent?.desiredProfileID == desiredProfileID
    }

    var hasUnsettledProfileAssignment: Bool {
        pendingProfileAssignmentIntent != nil
            || settlingProfileAssignmentIntent != nil
    }

    @discardableResult
    func cancelPendingProfileAssignment() -> Bool {
        guard pendingProfileAssignmentIntent != nil else { return false }
        pendingProfileAssignmentIntent = nil
        return true
    }

    @discardableResult
    func commitProfileAssignmentIntent(
        _ intent: DeferredWebViewProfileAssignmentIntent
    ) -> Bool {
        guard isCurrentProfileAssignmentIntent(intent) else { return false }
        profileId = intent.desiredProfileID
        pendingProfileAssignmentIntent = nil
        return true
    }

    /// Applies the model half of a replacement transaction while retaining
    /// the exact intent until the repository retirement lease settles.
    @discardableResult
    func stageProfileAssignmentIntent(
        _ intent: DeferredWebViewProfileAssignmentIntent
    ) -> Bool {
        guard settlingProfileAssignmentIntent == nil,
              isCurrentProfileAssignmentIntent(intent) else {
            return false
        }
        profileId = intent.desiredProfileID
        pendingProfileAssignmentIntent = nil
        settlingProfileAssignmentIntent = intent
        return true
    }

    func isCurrentStagedProfileAssignmentIntent(
        _ intent: DeferredWebViewProfileAssignmentIntent
    ) -> Bool {
        settlingProfileAssignmentIntent == intent
            && profileAssignmentIntentRevision == intent.revision
            && profileId == intent.desiredProfileID
    }

    @discardableResult
    func finishStagedProfileAssignmentIntent(
        _ intent: DeferredWebViewProfileAssignmentIntent
    ) -> Bool {
        guard isCurrentStagedProfileAssignmentIntent(intent) else {
            return false
        }
        settlingProfileAssignmentIntent = nil
        return true
    }

    @discardableResult
    func rollbackStagedProfileAssignmentIntent(
        _ intent: DeferredWebViewProfileAssignmentIntent
    ) -> Bool {
        guard isCurrentStagedProfileAssignmentIntent(intent) else {
            return false
        }
        profileId = intent.expectedProfileID
        settlingProfileAssignmentIntent = nil
        return true
    }

    func abortProfileAssignmentIntent(
        _ intent: DeferredWebViewProfileAssignmentIntent
    ) {
        guard pendingProfileAssignmentIntent == intent else { return }
        pendingProfileAssignmentIntent = nil
    }

    public func clearCurrentWebViewOwnership() {
        webViewSession.clearUntracked()
    }

    public func clearAllWebViewOwnership() {
        webViewSession.clearDetachedOwnership()
    }

    @discardableResult
    func clearCurrentWebViewOwnershipIfIdentical(to webView: WKWebView) -> Bool {
        webViewSession.clearUntracked(ifIdenticalTo: webView)
    }

    func bindToShortcutPin(_ pin: ShortcutPin) {
        placementStateOwner.bindToShortcutPin(id: pin.id, role: pin.role)
    }

    func clearShortcutBinding() {
        placementStateOwner.clearShortcutBinding()
    }

    // MARK: - Tab Actions
    func closeTab() {
        closeLifecycleOwner.close(context: .live(tab: self))
    }

    deinit {
        // AnyCancellable cancels on deallocation, so deinit does not need to reach into
        // main-actor runtime buckets just to tear down deferred observers.
        RuntimeDiagnostics.debug("Tab deinit cleanup completed.", category: "Tab")
    }

    // MARK: - Rename Methods
    func startRenaming() {
        isRenaming = true
        editingName = name
    }

    func saveRename() {
        if !editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        isRenaming = false
        editingName = ""
    }

    func cancelRename() {
        isRenaming = false
        editingName = ""
    }

    func loadWebViewIfNeeded() {
        if !hasCurrentWebView {
            beginSuspendedRestoreIfNeeded()
            _ = ensureUntrackedNormalWebView(reason: "Tab.loadWebViewIfNeeded")
            finishSuspendedRestoreIfNeeded()
        }
    }

    func publishNavigationStateChangeIfNeeded(_ didChange: Bool) {
        guard didChange else { return }
        stateChangeEmitter.publishNavigationStateDidChange(for: self)
    }

    func noteAccess(at date: Date = Date()) {
        lastSelectedAt = date
    }

    func beginSuspendedRestoreIfNeeded() {
        suspensionState.beginRestoreIfNeeded()
    }

    func markSuspended(at date: Date = Date()) {
        objectWillChange.send()
        suspensionState.markSuspended(url: url)
        if lastSelectedAt == nil {
            lastSelectedAt = date
        }
        resetPlaybackActivity()
        loadingState = .idle
        stateChangeEmitter.postLifecycleDidChange(for: self)
    }

    func finishSuspendedRestoreIfNeeded() {
        guard suspensionState.isRestoreInProgress, hasCurrentWebView else { return }
        objectWillChange.send()
        suspensionState.finishRestore()
        stateChangeEmitter.postLifecycleDidChange(for: self)
    }

    // MARK: - Navigation State Observation

    /// Set up KVO observers for navigation state properties
    func setupNavigationStateObservers(for webView: WKWebView) {
        navigationStateController.observe(webView)
    }

    /// Remove KVO observers for navigation state properties
    func removeNavigationStateObservers(from webView: WKWebView) {
        navigationStateController.remove(webView)
    }

}

// MARK: - Hashable & Equatable
extension Tab {
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Tab else { return false }
        return self.id == other.id
    }

    public override var hash: Int {
        id.hashValue
    }
}
