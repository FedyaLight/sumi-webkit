import Foundation
import WebKit

@MainActor
public struct WebViewCoordinatorShutdownRuntimeContext {
    public let cleanupUserScripts: (WKUserContentController, UUID) -> Void

    public init(cleanupUserScripts: @escaping (WKUserContentController, UUID) -> Void) {
        self.cleanupUserScripts = cleanupUserScripts
    }
}
