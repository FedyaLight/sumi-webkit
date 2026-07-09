import Foundation

public enum SumiPopupNavigationOrigin {
    nonisolated public static func isExtensionOriginatedPopupNavigation(
        sourceURL: URL?,
        requestURL: URL?
    ) -> Bool {
        SumiExtensionOwnedURL.isExtensionOwnedURL(sourceURL)
            || SumiExtensionOwnedURL.isExtensionOwnedURL(requestURL)
    }

    nonisolated public static func isExtensionOriginatedExternalPopupNavigation(
        sourceURL: URL?,
        requestURL: URL?
    ) -> Bool {
        let requestScheme = requestURL?.scheme?.lowercased()

        return SumiExtensionOwnedURL.isExtensionOwnedURL(sourceURL)
            && (requestScheme == "http" || requestScheme == "https")
    }
}
