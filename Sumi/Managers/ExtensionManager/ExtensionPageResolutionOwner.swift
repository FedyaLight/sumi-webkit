import Foundation
import WebKit

/// Resolves which installed extension owns a page or context.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPageResolutionOwner {
    private weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func ownerExtensionID(
        extensionContext: WKWebExtensionContext? = nil,
        openerTab: Tab? = nil,
        extensionOwnedSourceURL: URL? = nil
    ) -> String? {
        if let extensionContext,
           let extensionId = manager?.extensionID(for: extensionContext) {
            return extensionId
        }

        if let override = openerTab?.webExtensionContextOverride,
           let extensionId = manager?.extensionID(for: override) {
            return extensionId
        }

        for candidate in [extensionOwnedSourceURL, openerTab?.url] {
            guard let url = candidate,
                  ExtensionURLIdentity.isOwned(url),
                  let host = url.host,
                  host.isEmpty == false
            else {
                continue
            }
            return host
        }

        return nil
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func extensionID(
        for extensionContext: WKWebExtensionContext
    ) -> String? {
        profileRuntime.extensionId(for: extensionContext)
    }

    func ownerExtensionID(
        extensionContext: WKWebExtensionContext? = nil,
        openerTab: Tab? = nil,
        extensionOwnedSourceURL: URL? = nil
    ) -> String? {
        pageResolutionOwner.ownerExtensionID(
            extensionContext: extensionContext,
            openerTab: openerTab,
            extensionOwnedSourceURL: extensionOwnedSourceURL
        )
    }
}
