import Foundation
import Navigation
import WebKit

extension WKFrameInfo {
    var sumiWebKitSafeRequest: URLRequest? {
        safeRequest
    }

    var sumiWebKitRequestURL: URL? {
        sumiWebKitSafeRequest?.url
    }
}

extension WKNavigationAction {
    var sumiWebKitSafeSourceFrame: WKFrameInfo? {
        safeSourceFrame
    }

    var sumiWebKitSourceURL: URL? {
        sumiWebKitSafeSourceFrame?.sumiWebKitRequestURL
    }
}
