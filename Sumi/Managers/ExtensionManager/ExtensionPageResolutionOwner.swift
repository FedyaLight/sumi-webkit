import Foundation
import WebKit

/// Resolves which installed extension owns a page or context, and where that
/// extension's options page lives.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPageResolutionOwner {
    struct Dependencies {
        let extensionID: @MainActor (WKWebExtensionContext) -> String?
        let installedExtensions: @MainActor () -> [InstalledExtension]
        let loadedExtensionManifests: @MainActor () -> [String: [String: Any]]
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func ownerExtensionID(
        extensionContext: WKWebExtensionContext? = nil,
        openerTab: Tab? = nil,
        extensionOwnedSourceURL: URL? = nil
    ) -> String? {
        if let extensionContext,
           let extensionId = dependencies.extensionID(extensionContext) {
            return extensionId
        }

        if let override = openerTab?.webExtensionContextOverride,
           let extensionId = dependencies.extensionID(override) {
            return extensionId
        }

        for candidate in [extensionOwnedSourceURL, openerTab?.url] {
            guard let url = candidate,
                  ExtensionUtils.isExtensionOwnedURL(url),
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
        guard let extensionId = dependencies.extensionID(extensionContext),
              let installedExtension = dependencies.installedExtensions()
              .first(where: { $0.id == extensionId })
        else {
            return nil
        }

        let extensionRoot = URL(
            fileURLWithPath: installedExtension.packagePath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let manifest = dependencies.loadedExtensionManifests()[extensionId]
            ?? installedExtension.manifest

        let pagePath: String?
        if let persistedPath = installedExtension.optionsPagePath,
           let normalizedPath = ExtensionUtils.existingValidatedOptionsPagePath(
               persistedPath,
               in: extensionRoot
           ) {
            pagePath = normalizedPath
        } else if let declaredPath = ExtensionUtils.optionsPagePath(from: manifest),
                  let normalizedPath = ExtensionUtils.existingValidatedOptionsPagePath(
                      declaredPath,
                      in: extensionRoot
                  ) {
            pagePath = normalizedPath
        } else {
            pagePath = ExtensionUtils.storedOptionsPagePath(
                from: manifest,
                in: extensionRoot
            )
        }

        guard let pagePath else { return nil }
        return ExtensionUtils.url(
            extensionContext.baseURL,
            appendingManifestRelativePath: pagePath
        )
    }
}

@available(macOS 15.5, *)
extension ExtensionPageResolutionOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            extensionID: { [weak manager] extensionContext in
                manager?.extensionID(for: extensionContext)
            },
            installedExtensions: { [weak manager] in manager?.installedExtensions ?? [] },
            loadedExtensionManifests: { [weak manager] in
                manager?.loadedExtensionManifests ?? [:]
            }
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
        profileRuntimeOwner.extensionId(for: extensionContext)
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
