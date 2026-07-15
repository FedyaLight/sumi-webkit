#if DEBUG
import Foundation
import WebKit

/// Exact construction-time substitutions for adversarial tests. Production
/// assembly never mutates after initialization, and no override is retained by
/// `ExtensionManager` itself.
@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerTestAssemblyOverrides {
    struct ActionFinalization {
        let backgroundWake: @MainActor (
            WKWebExtension,
            WKWebExtensionContext,
            ExtensionManager.ExtensionBackgroundWakeReason,
            @escaping @MainActor () -> Bool
        ) async throws -> Void
        let reconcile: @MainActor (String) -> Void
    }

    let unloadContext: (@MainActor (
        WKWebExtensionController,
        WKWebExtensionContext
    ) throws -> Void)?
    let isLoadedContext: (@MainActor (
        WKWebExtensionController,
        WKWebExtensionContext
    ) -> Bool)?
    let actionFinalization: ActionFinalization?

    init(
        unloadContext: (@MainActor (
            WKWebExtensionController,
            WKWebExtensionContext
        ) throws -> Void)? = nil,
        isLoadedContext: (@MainActor (
            WKWebExtensionController,
            WKWebExtensionContext
        ) -> Bool)? = nil,
        actionFinalization: ActionFinalization? = nil
    ) {
        self.unloadContext = unloadContext
        self.isLoadedContext = isLoadedContext
        self.actionFinalization = actionFinalization
    }
}
#endif
