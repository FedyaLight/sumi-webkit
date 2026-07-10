import Foundation

/// Shared lifetime boundary for ports owned by `TabManager` but implemented by
/// the enclosing browser session. Losing the session while retaining and using
/// its ports is a graph violation, not an inactive/no-op runtime state.
@MainActor
final class BrowserManagerRuntimeReference {
    private weak var browserManager: BrowserManager?

    init(_ browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func require() -> BrowserManager {
        guard let browserManager else {
            preconditionFailure("Tab runtime port used after BrowserManager deallocation")
        }
        return browserManager
    }
}
