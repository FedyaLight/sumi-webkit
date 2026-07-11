import Foundation
import WebKit

@MainActor
public struct WebViewShutdownRuntimeContext {
    public let cleanupUserScripts: (WKUserContentController, UUID) -> Void

    public init(cleanupUserScripts: @escaping (WKUserContentController, UUID) -> Void) {
        self.cleanupUserScripts = cleanupUserScripts
    }
}
