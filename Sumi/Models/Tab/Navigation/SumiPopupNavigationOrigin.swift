import Foundation

enum SumiPopupNavigationOrigin {
    nonisolated static func isExtensionOriginatedPopupNavigation(
        sourceURL: URL?,
        requestURL: URL?
    ) -> Bool {
        ExtensionUtils.isExtensionOwnedURL(sourceURL)
            || ExtensionUtils.isExtensionOwnedURL(requestURL)
    }

    nonisolated static func isExtensionOriginatedExternalPopupNavigation(
        sourceURL: URL?,
        requestURL: URL?
    ) -> Bool {
        let requestScheme = requestURL?.scheme?.lowercased()

        return ExtensionUtils.isExtensionOwnedURL(sourceURL)
            && (requestScheme == "http" || requestScheme == "https")
    }
}
