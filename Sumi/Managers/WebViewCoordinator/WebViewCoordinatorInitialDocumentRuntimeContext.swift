import Foundation

@MainActor
struct WebViewCoordinatorInitialDocumentRuntimeContext {
    let needsInitialDocumentExtensionContextLoad: (UUID) -> Bool
    let ensureInitialDocumentExtensionContextsLoaded: (UUID) async -> Void
    let refreshCompositorForWindow: (UUID) -> Void
}
