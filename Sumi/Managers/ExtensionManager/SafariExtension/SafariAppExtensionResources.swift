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

    /// Uses the signed installed `.appex` for native Safari Web Extensions so WebKit can
    /// route appex-native features (e.g. native messaging defaults) through the bundle.
    /// Directory installs remain a separate developer/unpacked path.
    @available(macOS 15.5, *)
    static func makeWebExtension(
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String,
        packageRoot: URL,
        fileManager: FileManager = .default
    ) async throws -> (extension: WKWebExtension, loadSource: SafariAppExtensionRuntimeLoadSource) {
        if sourceKind == .safariAppExtension {
            guard let appexURL = installedAppexBundleURL(
                sourceKind: sourceKind,
                sourceBundlePath: sourceBundlePath,
                fileManager: fileManager
            ),
            let bundle = Bundle(url: appexURL)
            else {
                throw ExtensionError.installationFailed(
                    "Installed Safari app extension bundle is unavailable"
                )
            }

            let webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            return (webExtension, .originalAppexBundle)
        }

        let webExtension = try await WKWebExtension(resourceBaseURL: packageRoot)
        return (webExtension, .copiedPackage)
    }
}
