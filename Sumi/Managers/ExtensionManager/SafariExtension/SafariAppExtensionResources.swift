//
//  SafariAppExtensionResources.swift
//  Sumi
//
//  Locates and copies Safari Web Extension resources from `.appex` bundles.
//

import Foundation
import WebKit

enum SafariAppExtensionRuntimeLoadSource: String, Codable, Sendable, Equatable {
    case copiedPackage
    case originalAppexBundle
}

enum SafariAppExtensionResources {
    private static let manifestRelativeCandidates = [
        "Resources/manifest.json",
        "manifest.json",
    ]

    /// Directory inside the `.appex` bundle that contains `manifest.json`.
    static func resourcesRoot(in appexURL: URL, fileManager: FileManager = .default) throws -> URL {
        let contentsURL = appexURL.appendingPathComponent("Contents", isDirectory: true)
        guard fileManager.fileExists(atPath: contentsURL.path) else {
            throw ExtensionError.installationFailed(
                "Safari app extension bundle is missing Contents"
            )
        }

        for relative in manifestRelativeCandidates {
            let manifestURL = contentsURL.appendingPathComponent(relative)
            if fileManager.fileExists(atPath: manifestURL.path) {
                return manifestURL.deletingLastPathComponent()
            }
        }

        throw ExtensionError.installationFailed(
            "Safari app extension is missing manifest.json"
        )
    }

    /// Copies unpacked extension files into a flat directory for Sumi's managed store.
    ///
    /// `WKWebExtension(appExtensionBundle:)` reads the signed bundle directly; Sumi still
    /// copies resources so installs survive host-app updates and support manifest patching.
    static func copyResources(
        from sourceRoot: URL,
        to destinationDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.removeItem(at: destinationDirectory)
        }
        try fileManager.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        let items = try fileManager.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for item in items {
            let destination = destinationDirectory.appendingPathComponent(item.lastPathComponent)
            try fileManager.copyItem(at: item, to: destination)
        }
    }

    /// Resolved `.appex` on disk for a Safari import (`sourceBundlePath` stores the appex path).
    static func installedAppexBundleURL(
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String,
        fileManager: FileManager = .default
    ) -> URL? {
        guard sourceKind == .safariAppExtension else { return nil }

        let appexURL = URL(fileURLWithPath: sourceBundlePath, isDirectory: true)
            .standardizedFileURL
        guard fileManager.fileExists(atPath: appexURL.path),
              appexURL.pathExtension.lowercased() == "appex",
              Bundle(url: appexURL) != nil
        else {
            return nil
        }

        return appexURL
    }

    /// Prefers the signed installed `.appex` when still present so WebKit can route
    /// appex-native features (e.g. native messaging defaults); falls back to Sumi's
    /// copied package when the host app was removed or updated away.
    @available(macOS 15.5, *)
    static func makeWebExtension(
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String,
        packageRoot: URL,
        fileManager: FileManager = .default
    ) async throws -> (extension: WKWebExtension, loadSource: SafariAppExtensionRuntimeLoadSource) {
        if let appexURL = installedAppexBundleURL(
            sourceKind: sourceKind,
            sourceBundlePath: sourceBundlePath,
            fileManager: fileManager
        ),
           let bundle = Bundle(url: appexURL)
        {
            do {
                let webExtension = try await WKWebExtension(appExtensionBundle: bundle)
                return (webExtension, .originalAppexBundle)
            } catch {
                RuntimeDiagnostics.debug(
                    "WKWebExtension(appExtensionBundle:) failed for \(appexURL.path); falling back to copied package: \(error.localizedDescription)",
                    category: "SafariExtension"
                )
            }
        }

        let webExtension = try await WKWebExtension(resourceBaseURL: packageRoot)
        return (webExtension, .copiedPackage)
    }
}
