import Foundation
import WebKit

/// Resolves which installed extension owns a page or context, and where that
/// extension's options page lives.
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

    func computeOptionsPageURL(
        for extensionContext: WKWebExtensionContext
    ) -> URL? {
        guard let manager,
              let extensionId = manager.extensionID(for: extensionContext),
              let installedExtension = manager.installedExtensionCollection.records
              .first(where: { $0.id == extensionId })
        else {
            return nil
        }

        let extensionRoot = URL(
            fileURLWithPath: installedExtension.packagePath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let manifest = manager.runtimeCatalog.manifest(for: extensionId)
            ?? installedExtension.manifest

        let pagePath: String?
        if let persistedPath = installedExtension.optionsPagePath,
           let normalizedPath = ExtensionOptionsPageResolution.existingValidatedPath(
               persistedPath,
               in: extensionRoot
           ) {
            pagePath = normalizedPath
        } else if let declaredPath = ExtensionManifestSemantics.optionsPagePath(from: manifest),
                  let normalizedPath = ExtensionOptionsPageResolution.existingValidatedPath(
                      declaredPath,
                      in: extensionRoot
                  ) {
            pagePath = normalizedPath
        } else {
            pagePath = ExtensionOptionsPageResolution.storedPath(
                from: manifest,
                in: extensionRoot
            )
        }

        guard let pagePath else { return nil }
        return ExtensionPathSafety.manifestRelativeURL(
            extensionContext.baseURL,
            path: pagePath
        )
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

    func computeOptionsPageURL(
        for extensionContext: WKWebExtensionContext
    ) -> URL? {
        pageResolutionOwner.computeOptionsPageURL(for: extensionContext)
    }
}
