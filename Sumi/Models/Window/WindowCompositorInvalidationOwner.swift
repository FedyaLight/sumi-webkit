import Observation

/// Owns per-window compositor and native-surface invalidation counters.
@MainActor
@Observable
final class WindowCompositorInvalidationOwner {
    /// Compositor version counter for this window (incremented when tab ownership changes).
    private(set) var compositorVersion = 0

    /// Forces WebsiteView to re-evaluate whether the current tab is native or web-backed.
    private(set) var nativeSurfaceRoutingRevision: UInt64 = 0

    @ObservationIgnored private var isCompositorRefreshScheduled = false

    /// Coalesces repeated same-turn compositor invalidations into one UI update.
    func refresh() {
        guard !isCompositorRefreshScheduled else { return }
        isCompositorRefreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            isCompositorRefreshScheduled = false
            compositorVersion += 1
        }
    }

    func invalidateNativeSurfaceRouting() {
        nativeSurfaceRoutingRevision &+= 1
    }
}
