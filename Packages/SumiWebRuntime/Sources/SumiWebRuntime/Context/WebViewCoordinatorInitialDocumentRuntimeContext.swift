import Foundation

@MainActor
public struct InitialDocumentWebViewRuntimeContext {
    public let needsInitialDocumentExtensionContextLoad: (UUID) -> Bool
    public let ensureInitialExtensionContextsLoaded: (UUID) async -> Void
    public let refreshCompositorForWindow: (UUID) -> Void

    public init(
        needsInitialDocumentExtensionContextLoad: @escaping (UUID) -> Bool,
        ensureInitialExtensionContextsLoaded: @escaping (UUID) async -> Void,
        refreshCompositorForWindow: @escaping (UUID) -> Void
    ) {
        self.needsInitialDocumentExtensionContextLoad = needsInitialDocumentExtensionContextLoad
        self.ensureInitialExtensionContextsLoaded = ensureInitialExtensionContextsLoaded
        self.refreshCompositorForWindow = refreshCompositorForWindow
    }
}
