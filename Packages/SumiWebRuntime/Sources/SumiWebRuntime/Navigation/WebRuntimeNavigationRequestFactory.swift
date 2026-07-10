import Foundation

public enum WebRuntimeNavigationRequestFactory {
    public static func navigationRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = cachePolicy(for: url)
        return request
    }

    private static func cachePolicy(for url: URL) -> URLRequest.CachePolicy {
        switch url.scheme?.lowercased() {
        case "webkit-extension", "safari-web-extension":
            return .reloadIgnoringLocalCacheData
        default:
            return .useProtocolCachePolicy
        }
    }
}
