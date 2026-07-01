import Foundation

@MainActor
struct InitialDocumentWebViewRuntimeContext {
    let needsInitialDocumentExtensionContextLoad: (UUID) -> Bool
    let ensureInitialExtensionContextsLoaded: (UUID) async -> Void
    let refreshCompositorForWindow: (UUID) -> Void
}
