import Foundation
import WebKit

@MainActor
struct WebViewCoordinatorShutdownRuntimeContext {
    let cleanupUserScripts: (WKUserContentController, UUID) -> Void
}
