import Foundation
import WebKit

/// Owns ordered publication of exact normal-window projections. Model/profile
/// resolution is delegated to `ExtensionNormalWindowProjectionResolver`; this
/// type owns only lifecycle state, reentrancy barriers, and WebKit event order.
#if DEBUG
    @available(macOS 15.5, *)
    @MainActor
    enum ExtensionNormalWindowLifecycleDebugEvent {
        case didOpenWindow(UUID)
        case didFocusWindow(UUID)
    }
#endif

@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowLifecycle {
    private typealias PublishedWindow =
        ExtensionNormalWindowPublicationLedger.Publication

    private final class PublicationLease:
        BrowserWindowExtensionPublication {
        private weak var lifecycle: ExtensionNormalWindowLifecycle?
        private weak var window: BrowserWindowState?
        let windowID: UUID
        let windowIdentity: ObjectIdentifier
        let lifecycleEpoch: UInt64
        let adapter: ExtensionWindowAdapter

        init(
            lifecycle: ExtensionNormalWindowLifecycle,
            window: BrowserWindowState,
            publication: PublishedWindow
        ) {
            self.lifecycle = lifecycle
            self.window = window
            self.windowID = window.id
            self.windowIdentity = publication.projection.windowIdentity
            self.lifecycleEpoch = publication.lifecycleEpoch
            self.adapter = publication.projection.windowAdapter
        }

        func isCurrent() -> Bool {
            guard let lifecycle, let window else { return false }
            return lifecycle.isCurrent(self, window: window)
        }

        func revokeIfCurrent() {
            guard let lifecycle, let window else { return }
            lifecycle.revoke(self, window: window)
        }

        func revokeIfCurrent(
            closingPublishedTabs: @MainActor () -> Void
        ) {
            guard let lifecycle, let window else {
                closingPublishedTabs()
                return
            }
            lifecycle.revoke(
                self,
                window: window,
                closingPublishedTabs: closingPublishedTabs
            )
        }
    }

    struct RuntimeReconciliationToken: Equatable {
        fileprivate let epoch: UInt64
        fileprivate let publicationStage: ExtensionRuntimePublicationStage
    }

    private enum Phase: Equatable {
        case active
        case reconciling(RuntimeReconciliationToken)
        case retiring(UInt64)
        case runtimeUnavailable(UInt64)
    }

    private let resolver: ExtensionNormalWindowProjectionResolver
    private let validator: ExtensionNormalWindowPublicationValidator
    private let ledger: ExtensionNormalWindowPublicationLedger
    private let publicationQuery: ExtensionNormalWindowPublicationQuery
    private let adapterStore: ExtensionBrowserAdapterStore
    private let preparedTabVisibility: ExtensionPreparedTabVisibility
    #if DEBUG
        private let debugEvent:
            @MainActor (ExtensionNormalWindowLifecycleDebugEvent) -> Void
    #endif
    private var phase = Phase.active {
        didSet { synchronizeLedgerReadPolicy() }
    }
    private var lifecycleEpoch: UInt64 = 0
    private var activePublicationStage = ExtensionRuntimePublicationStage
        .loadedRuntime {
        didSet { synchronizeLedgerReadPolicy() }
    }
    private var closingWindowIdentityByID: [UUID: ObjectIdentifier] = [:]

    var acceptsNewPublications: Bool {
        phase == .active
    }

    #if DEBUG
        init(
            resolver: ExtensionNormalWindowProjectionResolver,
            validator: ExtensionNormalWindowPublicationValidator,
            ledger: ExtensionNormalWindowPublicationLedger,
            adapterStore: ExtensionBrowserAdapterStore,
            preparedTabVisibility: ExtensionPreparedTabVisibility,
            debugEvent: @escaping @MainActor (
                ExtensionNormalWindowLifecycleDebugEvent
            ) -> Void = { _ in }
        ) {
            self.resolver = resolver
            self.validator = validator
            self.ledger = ledger
            self.publicationQuery = ExtensionNormalWindowPublicationQuery(
                ledger: ledger,
                validator: validator
            )
            self.adapterStore = adapterStore
            self.preparedTabVisibility = preparedTabVisibility
            self.debugEvent = debugEvent
            synchronizeLedgerReadPolicy()
        }
    #else
        init(
            resolver: ExtensionNormalWindowProjectionResolver,
            validator: ExtensionNormalWindowPublicationValidator,
            ledger: ExtensionNormalWindowPublicationLedger,
            adapterStore: ExtensionBrowserAdapterStore,
            preparedTabVisibility: ExtensionPreparedTabVisibility
        ) {
            self.resolver = resolver
            self.validator = validator
            self.ledger = ledger
            self.publicationQuery = ExtensionNormalWindowPublicationQuery(
                ledger: ledger,
                validator: validator
            )
            self.adapterStore = adapterStore
            self.preparedTabVisibility = preparedTabVisibility
            synchronizeLedgerReadPolicy()
        }
    #endif

    @discardableResult
    func opened(_ window: BrowserWindowState) -> Bool {
        publication(for: window) != nil
    }

    func publication(
        for window: BrowserWindowState
    ) -> (any BrowserWindowExtensionPublication)? {
        guard let published = reconcile(window) else { return nil }
        return PublicationLease(
            lifecycle: self,
            window: window,
            publication: published
        )
    }

    func closed(_ window: BrowserWindowState) {
        guard case .active = phase else { return }
        guard let published = ledger.publication(for: window.id) else {
            removeUnpublishedAdapter(for: window)
            return
        }
        guard published.projection.windowIdentity
                == ObjectIdentifier(window)
        else {
            return
        }
        close(published, windowID: window.id)
    }

    func focused(_ window: BrowserWindowState) {
        guard validator.isExactRegistered(window) else { return }
        resolver.switchToWindowProfile(window)
        guard let published = reconcile(window) else { return }
        published.projection.controller.didFocusWindow(
            published.projection.windowAdapter
        )
        #if DEBUG
            debugEvent(.didFocusWindow(window.id))
        #endif
    }

    /// A normal Tab can cross WebKit's didOpenTab boundary only after its exact
    /// containing window projection has crossed didOpenWindow for the same
    /// profile and generation. Transient/mini-window Tabs use their own ledger.
    func prepareTabOpen(_ tab: Tab) -> Bool {
        if validator.canPublishWithoutNormalWindow(tab) {
            return true
        }
        guard case .active = phase,
              let window = validator.preferredWindow(for: tab),
              let published = reconcile(window),
              validator.profileID(for: tab)
                == published.projection.profileID
        else {
            return false
        }
        return true
    }

    /// Reconciles the containing window before a Tab activation event. `false`
    /// means the physical window currently has no honest extension projection.
    func prepareTabActivation(_ tab: Tab) -> Bool {
        prepareTabOpen(tab)
    }

    func tabPublicationIsCurrent(_ tab: Tab, profileID: UUID) -> Bool {
        publicationQuery.tabPublicationIsCurrent(tab, profileID: profileID)
    }

    func windowPublicationIsCurrent(
        _ window: BrowserWindowState,
        selectedTab: Tab,
        profileID: UUID
    ) -> Bool {
        publicationQuery.windowPublicationIsCurrent(
            window,
            selectedTab: selectedTab,
            profileID: profileID
        )
    }

    func publishedAdapter(
        for window: BrowserWindowState,
        profileID: UUID
    ) -> ExtensionWindowAdapter? {
        publicationQuery.publishedAdapter(for: window, profileID: profileID)
    }

    /// Begins a generation-wide replacement. Existing projections leave the
    /// ledger before callbacks, and no reentrant Tab/window event can reopen a
    /// normal projection until the exact token is finished.
    func beginRuntimeReconciliation(
        publicationStage: ExtensionRuntimePublicationStage = .loadedRuntime,
        closePublishedTabs: @MainActor () -> Void = {}
    ) -> RuntimeReconciliationToken? {
        guard closingWindowIdentityByID.isEmpty else { return nil }
        let closesExistingProjection: Bool
        switch phase {
        case .active:
            closesExistingProjection = true
        case .runtimeUnavailable:
            closesExistingProjection = false
        case .reconciling, .retiring:
            return nil
        }
        lifecycleEpoch &+= 1
        let token = RuntimeReconciliationToken(
            epoch: lifecycleEpoch,
            publicationStage: publicationStage
        )
        phase = .reconciling(token)

        if closesExistingProjection {
            // WebKit tracks openTabs independently from openWindows. While the
            // exact old projection is still readable, balance old-generation
            // Tabs; only then detach and close the window projection.
            closePublishedTabs()

            // A synchronous WebKit callback may tear the runtime down. Its
            // retirement phase owns the remaining close sequence and this
            // now-stale reload token must never resume publication.
            guard phase == .reconciling(token) else { return nil }

            for entry in ledger.takeAll() {
                closeDetached(
                    entry.publication,
                    windowID: entry.windowID
                )
            }
        }
        activePublicationStage = .loadedRuntime
        return token
    }

    /// Resumes publication only for the token that suspended it. Windows are
    /// republished from exact current state before callers emit prepared Tab
    /// events. `false` means a synchronous WebKit callback invalidated the batch.
    @discardableResult
    func finishRuntimeReconciliation(
        _ token: RuntimeReconciliationToken,
        republishing windows: [BrowserWindowState]
    ) -> Bool {
        guard phase == .reconciling(token) else { return false }
        lifecycleEpoch &+= 1
        let resumedEpoch = lifecycleEpoch
        phase = .active
        activePublicationStage = token.publicationStage

        for window in windows {
            guard phase == .active,
                  lifecycleEpoch == resumedEpoch
            else {
                return false
            }
            _ = reconcile(window)
        }
        return phase == .active && lifecycleEpoch == resumedEpoch
    }

    /// Balances every open while its exact controller still exists. The short
    /// reconciliation phase suppresses reentrant reopen during didCloseWindow.
    @discardableResult
    func closeAllForRuntimeTeardown(
        closePublishedTabs: @MainActor () -> Void = {}
    ) -> Bool {
        switch phase {
        case .runtimeUnavailable, .retiring:
            return false
        case .active:
            if closingWindowIdentityByID.isEmpty == false {
                lifecycleEpoch &+= 1
                let retirementEpoch = lifecycleEpoch
                phase = .retiring(retirementEpoch)
                closePublishedTabs()

                for entry in ledger.takeAll() {
                    closeDetached(
                        entry.publication,
                        windowID: entry.windowID
                    )
                }
                phase = .runtimeUnavailable(retirementEpoch)
                activePublicationStage = .loadedRuntime
                return true
            }
            guard let token = beginRuntimeReconciliation(
                closePublishedTabs: closePublishedTabs
            ) else {
                return false
            }
            guard phase == .reconciling(token) else {
                return false
            }
            lifecycleEpoch &+= 1
            phase = .runtimeUnavailable(lifecycleEpoch)
            activePublicationStage = .loadedRuntime
            return true
        case .reconciling:
            // Invalidate the in-flight reload token before crossing another
            // WebKit callback boundary, while keeping old projections readable
            // until their Tab close events have been balanced.
            lifecycleEpoch &+= 1
            let retirementEpoch = lifecycleEpoch
            phase = .retiring(retirementEpoch)
            closePublishedTabs()

            for entry in ledger.takeAll() {
                closeDetached(
                    entry.publication,
                    windowID: entry.windowID
                )
            }
            phase = .runtimeUnavailable(retirementEpoch)
            activePublicationStage = .loadedRuntime
            return true
        }
    }

    @discardableResult
    private func reconcile(
        _ window: BrowserWindowState
    ) -> PublishedWindow? {
        guard case .active = phase else { return nil }
        let windowID = window.id
        let identity = ObjectIdentifier(window)
        guard closingWindowIdentityByID[windowID] == nil else {
            return nil
        }

        if let existing = ledger.publication(for: windowID) {
            guard existing.projection.windowIdentity == identity else {
                return nil
            }
            if validator.validate(
                existing.projection,
                for: window,
                publicationStage: activePublicationStage
            ) {
                return existing
            }

            // Selecting another already-published Tab in the same physical
            // window does not close and reopen that window in WebKit. Refresh
            // the exact selected-Tab proof while preserving the publication
            // lease and adapter identity. Profile, controller, runtime
            // generation, or physical-window changes still take the full
            // close/open path below.
            if let refreshedProjection = resolver.resolve(
                window,
                publicationStage: activePublicationStage
            ), refreshedProjection.belongsToSameWindowPublication(
                as: existing.projection
            ) {
                let refreshed = PublishedWindow(
                    lifecycleEpoch: existing.lifecycleEpoch,
                    projection: refreshedProjection
                )
                ledger.set(refreshed, for: windowID)
                return refreshed
            }

            close(existing, windowID: windowID)
            guard case .active = phase else { return nil }
            if let reentrant = ledger.publication(for: windowID) {
                return validator.validate(
                    reentrant.projection,
                    for: window,
                    publicationStage: activePublicationStage
                )
                    ? reentrant
                    : nil
            }
        }

        guard let projection = resolver.resolve(
            window,
            publicationStage: activePublicationStage
        ) else {
            return nil
        }
        let publicationEpoch = lifecycleEpoch
        let published = PublishedWindow(
            lifecycleEpoch: publicationEpoch,
            projection: projection
        )
        ledger.set(published, for: windowID)
        preparedTabVisibility.withWindowOpenCallback(
            window: window,
            adapter: projection.windowAdapter,
            controller: projection.controller
        ) {
            projection.controller.didOpenWindow(projection.windowAdapter)
            #if DEBUG
                debugEvent(.didOpenWindow(windowID))
            #endif
        }

        guard case .active = phase,
              lifecycleEpoch == publicationEpoch,
              let current = ledger.publication(for: windowID),
              current.lifecycleEpoch == publicationEpoch,
              current.projection.windowAdapter
                === projection.windowAdapter,
              validator.validate(
                  current.projection,
                  for: window,
                  publicationStage: activePublicationStage
              )
        else {
            if let current = ledger.publication(for: windowID),
               current.lifecycleEpoch == publicationEpoch,
               current.projection.windowAdapter === projection.windowAdapter {
                close(current, windowID: windowID)
            }
            return nil
        }
        return current
    }

    private func close(
        _ published: PublishedWindow,
        windowID: UUID
    ) {
        guard let current = ledger.publication(for: windowID),
              current.lifecycleEpoch == published.lifecycleEpoch,
              current.projection.windowIdentity
                == published.projection.windowIdentity,
              current.projection.windowAdapter
                === published.projection.windowAdapter
        else {
            return
        }
        _ = ledger.remove(for: windowID)
        closeDetached(published, windowID: windowID)
    }

    private func closeDetached(
        _ published: PublishedWindow,
        windowID: UUID
    ) {
        let windowIdentity = published.projection.windowIdentity
        guard closingWindowIdentityByID[windowID] == nil else { return }
        closingWindowIdentityByID[windowID] = windowIdentity
        _ = adapterStore.removeWindowAdapter(
            for: windowID,
            ifIdenticalTo: published.projection.windowAdapter
        )
        published.projection.controller.didCloseWindow(
            published.projection.windowAdapter
        )
        if closingWindowIdentityByID[windowID] == windowIdentity {
            closingWindowIdentityByID.removeValue(forKey: windowID)
        }
    }

    private func removeUnpublishedAdapter(for window: BrowserWindowState) {
        guard closingWindowIdentityByID[window.id] == nil else { return }
        guard let adapter = adapterStore.existingWindowAdapter(for: window.id),
              adapter.represents(window)
        else {
            return
        }
        _ = adapterStore.removeWindowAdapter(
            for: window.id,
            ifIdenticalTo: adapter
        )
    }

    private func isCurrent(
        _ lease: PublicationLease,
        window: BrowserWindowState
    ) -> Bool {
        guard case .active = phase,
              let published = exactPublication(
                  for: lease,
                  window: window
              ),
              validator.validate(
                  published.projection,
                  for: window,
                  publicationStage: activePublicationStage
              )
        else {
            return false
        }
        return true
    }

    private func revoke(
        _ lease: PublicationLease,
        window: BrowserWindowState
    ) {
        revoke(
            lease,
            window: window,
            closingPublishedTabs: {}
        )
    }

    private func revoke(
        _ lease: PublicationLease,
        window: BrowserWindowState,
        closingPublishedTabs: @MainActor () -> Void
    ) {
        guard let published = exactPublication(
            for: lease,
            window: window
        )
        else {
            closingPublishedTabs()
            return
        }
        let windowID = window.id
        let windowIdentity = published.projection.windowIdentity
        guard closingWindowIdentityByID[windowID] == nil else {
            closingPublishedTabs()
            return
        }

        // Keep the exact old projection queryable while its Tab close is
        // emitted, but tombstone reconciliation before crossing WebKit. This
        // preserves didCloseTab -> didCloseWindow ordering without allowing a
        // synchronous callback to reopen either projection.
        closingWindowIdentityByID[windowID] = windowIdentity
        closingPublishedTabs()
        if let current = ledger.publication(for: windowID),
           current.lifecycleEpoch == published.lifecycleEpoch,
           current.projection.windowIdentity == windowIdentity,
           current.projection.windowAdapter
            === published.projection.windowAdapter {
            _ = ledger.remove(for: windowID)
        }
        _ = adapterStore.removeWindowAdapter(
            for: windowID,
            ifIdenticalTo: published.projection.windowAdapter
        )
        published.projection.controller.didCloseWindow(
            published.projection.windowAdapter
        )
        if closingWindowIdentityByID[windowID] == windowIdentity {
            closingWindowIdentityByID.removeValue(forKey: windowID)
        }
    }

    private func exactPublication(
        for lease: PublicationLease,
        window: BrowserWindowState
    ) -> PublishedWindow? {
        guard lease.windowID == window.id,
              lease.windowIdentity == ObjectIdentifier(window),
              let published = ledger.publication(for: window.id),
              published.lifecycleEpoch == lease.lifecycleEpoch,
              published.projection.windowIdentity == lease.windowIdentity,
              published.projection.windowAdapter === lease.adapter
        else {
            return nil
        }
        return published
    }

    private var phaseAllowsPublishedReads: Bool {
        switch phase {
        case .active, .reconciling, .retiring:
            return true
        case .runtimeUnavailable:
            return false
        }
    }

    private func synchronizeLedgerReadPolicy() {
        ledger.updateReadPolicy(
            acceptsPublishedReads: phaseAllowsPublishedReads,
            publicationStage: activePublicationStage
        )
    }
}
