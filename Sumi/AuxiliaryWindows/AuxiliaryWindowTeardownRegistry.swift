import Foundation

/// Keeps shutdown access to an auxiliary-window runtime only after that
/// runtime has actually been materialized. The empty registry is the
/// zero-cost path for browser sessions that never open an auxiliary window.
@MainActor
final class AuxiliaryWindowTeardownRegistry {
    private var teardown: AuxiliaryWindowTeardownService?

    var hasLoadedRuntime: Bool { teardown != nil }

    func register(_ teardown: AuxiliaryWindowTeardownService) {
        if let existing = self.teardown {
            precondition(
                existing === teardown,
                "An auxiliary-window teardown runtime cannot be replaced"
            )
            return
        }
        self.teardown = teardown
    }

    func closeAllIfLoaded(reason: AuxiliaryWindowCloseReason) {
        teardown?.closeAll(reason: reason)
    }

    func closeAllAfterBrowserRuntimeDeallocationIfLoaded() {
        teardown?.closeAllAfterBrowserRuntimeDeallocation()
    }
}
