import Foundation
import WebKit

extension WKError {
    var sumiIsContentPluginHandledLoad: Bool {
        let nsError = self as NSError
        return (nsError.domain == WKErrorDomain
                || nsError.domain == "WebKitErrorDomain")
            && nsError.code == 204
    }

    var sumiIsNavigationCancelled: Bool {
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
