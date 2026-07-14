import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabLoad {
    enum Ownership {
        case ordinaryBrowser
        case extensionOwned(WKWebExtensionContext)
        case unresolvedExtensionOwned
    }

    let url: URL?
    let ownership: Ownership

    var extensionContext: WKWebExtensionContext? {
        guard case .extensionOwned(let context) = ownership else { return nil }
        return context
    }

    var isOrdinaryBrowserRequest: Bool {
        if case .ordinaryBrowser = ownership { return true }
        return false
    }

    var hasUnresolvedExtensionOwnership: Bool {
        if case .unresolvedExtensionOwned = ownership { return true }
        return false
    }

    var requiresContentScriptPreload: Bool {
        guard isOrdinaryBrowserRequest,
              let scheme = url?.scheme?.lowercased()
        else {
            return false
        }
        return scheme == "http" || scheme == "https" || scheme == "file"
    }

    func shouldOpenTransientInternalTab(
        shouldBeActive: Bool,
        shouldBePinned: Bool
    ) -> Bool {
        guard shouldBeActive == false,
              shouldBePinned == false,
              extensionContext != nil,
              let url
        else {
            return false
        }
        return ExtensionURLIdentity.isOwned(url)
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
            return ExtensionRequestedTabLoad(
                url: nil,
                ownership: .ordinaryBrowser
            )
        }

        guard ExtensionURLIdentity.isOwned(requestedURL) else {
            return ExtensionRequestedTabLoad(
                url: requestedURL,
                ownership: .ordinaryBrowser
            )
        }
        guard let context = controller.extensionContext(for: requestedURL)
        else {
            return ExtensionRequestedTabLoad(
                url: requestedURL,
                ownership: .unresolvedExtensionOwned
            )
        }
        return ExtensionRequestedTabLoad(
            url: requestedURL,
            ownership: .extensionOwned(context)
        )
    }
}
