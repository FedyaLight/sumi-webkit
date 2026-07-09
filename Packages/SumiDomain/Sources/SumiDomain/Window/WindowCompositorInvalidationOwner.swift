import Foundation
import Observation

/// Owns per-window compositor and native-surface invalidation counters.
@MainActor
@Observable
public final class WindowCompositorInvalidationOwner {
    public init() {}
    /// Compositor version counter for this window (incremented when tab ownership changes)
    public private(set) var compositorVersion: Int = 0

    /// Forces WebsiteView to re-evaluate whether the current tab is native or web-backed.
    public private(set) var nativeSurfaceRoutingRevision: UInt64 = 0

    @ObservationIgnored private var isCompositorRefreshScheduled: Bool = false

    /// Coalesce compositor invalidations so repeated same-turn calls trigger one UI update.
    public func refresh() {
        guard !isCompositorRefreshScheduled else { return }
        isCompositorRefreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isCompositorRefreshScheduled = false
            self.compositorVersion += 1
        }
    }

    public func invalidateNativeSurfaceRouting() {
        nativeSurfaceRoutingRevision &+= 1
    }
}
