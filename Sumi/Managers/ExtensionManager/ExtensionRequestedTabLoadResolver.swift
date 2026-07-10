import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabLoad {
    let url: URL?
    let extensionContext: WKWebExtensionContext?

    var requiresContentScriptPreload: Bool {
        guard extensionContext == nil,
              let scheme = url?.scheme?.lowercased()
        else {
            return false
        }
        return scheme == "http" || scheme == "https" || scheme == "file"
    }
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabLoadResolver {
    func resolve(
        _ requestedURL: URL?,
        controller: WKWebExtensionController
    ) -> ExtensionRequestedTabLoad {
        guard let requestedURL else {
            return ExtensionRequestedTabLoad(url: nil, extensionContext: nil)
        }

        guard ExtensionUtils.isExtensionOwnedURL(requestedURL) else {
            return ExtensionRequestedTabLoad(
                url: requestedURL,
                extensionContext: nil
            )
        }
        return ExtensionRequestedTabLoad(
            url: requestedURL,
            extensionContext: controller.extensionContext(for: requestedURL)
        )
    }
}
