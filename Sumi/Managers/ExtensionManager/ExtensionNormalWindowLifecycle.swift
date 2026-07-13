import Foundation
import WebKit

/// Owns ordered publication of exact normal-window projections. Model/profile
/// resolution is delegated to `ExtensionNormalWindowProjectionResolver`; this
/// type owns only lifecycle state, reentrancy barriers, and WebKit event order.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowLifecycle {
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
        fileprivate let allowsUnloadedRuntime: Bool
    }

    private enum Phase: Equatable {
        case active
        case reconciling(RuntimeReconciliationToken)
        case retiring(UInt64)
        case runtimeUnavailable(UInt64)
    }

    private struct PublishedWindow {
        let lifecycleEpoch: UInt64
        let projection: ExtensionNormalWindowProjection
    }

    private let resolver: ExtensionNormalWindowProjectionResolver
    private let adapterStore: ExtensionBrowserAdapterStore
    private let preparedTabVisibility: ExtensionPreparedTabVisibility
    #if DEBUG
        private let debugDidOpenWindow: @MainActor (UUID) -> Void
    #endif
    private var phase = Phase.active
    private var lifecycleEpoch: UInt64 = 0
    private var activeAllowsUnloadedRuntime = false
    private var publishedByWindowID: [UUID: PublishedWindow] = [:]
    private var closingWindowIdentityByID: [UUID: ObjectIdentifier] = [:]

    var acceptsNewPublications: Bool {
        phase == .active
    }

    #if DEBUG
        init(
            resolver: ExtensionNormalWindowProjectionResolver,
            adapterStore: ExtensionBrowserAdapterStore,
            preparedTabVisibility: ExtensionPreparedTabVisibility,
            debugDidOpenWindow: @escaping @MainActor (UUID) -> Void = { _ in }
        ) {
            self.resolver = resolver
            self.adapterStore = adapterStore
            self.preparedTabVisibility = preparedTabVisibility
            self.debugDidOpenWindow = debugDidOpenWindow
        }
    #else
        init(
            resolver: ExtensionNormalWindowProjectionResolver,
            adapterStore: ExtensionBrowserAdapterStore,
            preparedTabVisibility: ExtensionPreparedTabVisibility
        ) {
            self.resolver = resolver
            self.adapterStore = adapterStore
            self.preparedTabVisibility = preparedTabVisibility
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
        guard let published = publishedByWindowID[window.id] else {
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
        guard resolver.isExactRegistered(window) else { return }
        resolver.switchToWindowProfile(window)
        guard let published = reconcile(window) else { return }
        published.projection.controller.didFocusWindow(
            published.projection.windowAdapter
        )
    }

    /// A normal Tab can cross WebKit's didOpenTab boundary only after its exact
    /// containing window projection has crossed didOpenWindow for the same
    /// profile and generation. Transient/mini-window Tabs use their own ledger.
    func prepareTabOpen(_ tab: Tab) -> Bool {
        if resolver.canPublishWithoutNormalWindow(tab) {
            return true
        }
        guard case .active = phase,
              let window = resolver.preferredWindow(for: tab),
              let published = reconcile(window),
              resolver.profileID(for: tab)
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

    /// Read-only proof used after a Tab open callback. Unlike admission this
    /// never reconciles or closes a window, so validation cannot publish new
    /// state while checking whether the callback transaction stayed current.
    func tabPublicationIsCurrent(_ tab: Tab, profileID: UUID) -> Bool {
        if resolver.canPublishWithoutNormalWindow(tab) {
            return resolver.profileID(for: tab) == profileID
        }
        guard phaseAllowsPublishedReads,
              let window = resolver.preferredWindow(for: tab),
              let published = publishedByWindowID[window.id],
              published.projection.windowIdentity
                == ObjectIdentifier(window),
              published.projection.profileID == profileID,
              resolver.profileID(for: tab) == profileID
        else {
            return false
        }
        return resolver.validate(
            published.projection,
            for: window,
            allowWhenExtensionsNotLoaded: activeAllowsUnloadedRuntime
        )
    }

    func windowPublicationIsCurrent(
        _ window: BrowserWindowState,
        selectedTab: Tab,
        profileID: UUID
    ) -> Bool {
        guard phaseAllowsPublishedReads,
              let published = publishedByWindowID[window.id],
              published.projection.windowIdentity
                == ObjectIdentifier(window),
              published.projection.selectedTabIdentity
                == ObjectIdentifier(selectedTab),
              published.projection.selectedTabID == selectedTab.id,
              published.projection.profileID == profileID
        else {
            return false
        }
        return resolver.validate(
            published.projection,
            for: window,
            allowWhenExtensionsNotLoaded: activeAllowsUnloadedRuntime
        )
    }

    func publishedAdapter(
        for window: BrowserWindowState,
        profileID: UUID
    ) -> ExtensionWindowAdapter? {
        guard phaseAllowsPublishedReads,
              let published = publishedByWindowID[window.id],
              published.projection.windowIdentity
                == ObjectIdentifier(window),
              published.projection.profileID == profileID
        else {
            return nil
        }
        guard resolver.validate(
            published.projection,
            for: window,
            allowWhenExtensionsNotLoaded: activeAllowsUnloadedRuntime
        ) else {
            return nil
        }
        return published.projection.windowAdapter
    }

    /// Begins a generation-wide replacement. Existing projections leave the
    /// ledger before callbacks, and no reentrant Tab/window event can reopen a
    /// normal projection until the exact token is finished.
    func beginRuntimeReconciliation(
        allowWhenExtensionsNotLoaded: Bool = false,
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
            allowsUnloadedRuntime: allowWhenExtensionsNotLoaded
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

            let publications = Array(publishedByWindowID)
            publishedByWindowID.removeAll()
            for (windowID, published) in publications {
                closeDetached(published, windowID: windowID)
            }
        }
        activeAllowsUnloadedRuntime = false
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
        activeAllowsUnloadedRuntime = token.allowsUnloadedRuntime

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

                let publications = Array(publishedByWindowID)
                publishedByWindowID.removeAll()
                for (windowID, published) in publications {
                    closeDetached(published, windowID: windowID)
                }
                phase = .runtimeUnavailable(retirementEpoch)
                activeAllowsUnloadedRuntime = false
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
            activeAllowsUnloadedRuntime = false
            return true
        case .reconciling:
            // Invalidate the in-flight reload token before crossing another
            // WebKit callback boundary, while keeping old projections readable
            // until their Tab close events have been balanced.
            lifecycleEpoch &+= 1
            let retirementEpoch = lifecycleEpoch
            phase = .retiring(retirementEpoch)
            closePublishedTabs()

            let publications = Array(publishedByWindowID)
            publishedByWindowID.removeAll()
            for (windowID, published) in publications {
                closeDetached(published, windowID: windowID)
            }
            phase = .runtimeUnavailable(retirementEpoch)
            activeAllowsUnloadedRuntime = false
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

        if let existing = publishedByWindowID[windowID] {
            guard existing.projection.windowIdentity == identity else {
                return nil
            }
            if resolver.validate(
                existing.projection,
                for: window,
                allowWhenExtensionsNotLoaded: activeAllowsUnloadedRuntime
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
                allowWhenExtensionsNotLoaded: activeAllowsUnloadedRuntime
            ), refreshedProjection.belongsToSameWindowPublication(
                as: existing.projection
            ) {
                let refreshed = PublishedWindow(
                    lifecycleEpoch: existing.lifecycleEpoch,
                    projection: refreshedProjection
                )
                publishedByWindowID[windowID] = refreshed
                return refreshed
            }

            close(existing, windowID: windowID)
            guard case .active = phase else { return nil }
            if let reentrant = publishedByWindowID[windowID] {
                return resolver.validate(
                    reentrant.projection,
                    for: window,
                    allowWhenExtensionsNotLoaded:
                        activeAllowsUnloadedRuntime
                )
                    ? reentrant
                    : nil
            }
        }

        guard let projection = resolver.resolve(
            window,
            allowWhenExtensionsNotLoaded: activeAllowsUnloadedRuntime
        ) else {
            return nil
        }
        let publicationEpoch = lifecycleEpoch
        let published = PublishedWindow(
            lifecycleEpoch: publicationEpoch,
            projection: projection
        )
        publishedByWindowID[windowID] = published
        preparedTabVisibility.withWindowOpenCallback(
            window: window,
            adapter: projection.windowAdapter
        ) {
            projection.controller.didOpenWindow(projection.windowAdapter)
            #if DEBUG
                debugDidOpenWindow(windowID)
            #endif
        }

        guard case .active = phase,
              lifecycleEpoch == publicationEpoch,
              let current = publishedByWindowID[windowID],
              current.lifecycleEpoch == publicationEpoch,
              current.projection.windowAdapter
                === projection.windowAdapter,
              resolver.validate(
                  current.projection,
                  for: window,
                  allowWhenExtensionsNotLoaded:
                      activeAllowsUnloadedRuntime
              )
        else {
            if let current = publishedByWindowID[windowID],
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
        guard let current = publishedByWindowID[windowID],
              current.lifecycleEpoch == published.lifecycleEpoch,
              current.projection.windowIdentity
                == published.projection.windowIdentity,
              current.projection.windowAdapter
                === published.projection.windowAdapter
        else {
            return
        }
        publishedByWindowID.removeValue(forKey: windowID)
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
              resolver.validate(
                  published.projection,
                  for: window,
                  allowWhenExtensionsNotLoaded:
                      activeAllowsUnloadedRuntime
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
        if let current = publishedByWindowID[windowID],
           current.lifecycleEpoch == published.lifecycleEpoch,
           current.projection.windowIdentity == windowIdentity,
           current.projection.windowAdapter
            === published.projection.windowAdapter {
            publishedByWindowID.removeValue(forKey: windowID)
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
              let published = publishedByWindowID[window.id],
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
}
