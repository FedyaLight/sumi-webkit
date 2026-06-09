//
//  ExtensionManager+ManifestPatching.swift
//  Sumi
//
//  Install-source resolution for Safari Web Extensions.
//  Sumi does not rewrite manifests or inject compatibility JavaScript into
//  imported Safari `.appex` packages — runtime loads the signed bundle through
//  `WKWebExtension(appExtensionBundle:)` when possible.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
extension ExtensionManager {
    struct ResolvedInstallSource {
        let sourceKind: WebExtensionSourceKind
        /// Unpacked resources root (directory install) or in-bundle resources root (appex).
        let resourcesURL: URL
        let sourceBundlePath: URL
        let sourceFingerprintURL: URL
        /// Non-nil when `sourceKind` is `.safariAppExtension`.
        let appexBundleURL: URL?
    }

    func validateMV3Requirements(
        manifest: [String: Any],
        baseURL: URL
    ) throws {
        guard manifest["manifest_version"] as? Int == 3 else {
            return
        }

        guard
            let background = manifest["background"] as? [String: Any],
            let serviceWorker = background["service_worker"] as? String,
            serviceWorker.isEmpty == false
        else {
            return
        }

        guard let serviceWorkerURL = ExtensionUtils.url(
            baseURL,
            appendingManifestRelativePath: serviceWorker
        ) else {
            throw ExtensionError.installationFailed(
                "MV3 service worker path is invalid: \(serviceWorker)"
            )
        }
        guard FileManager.default.fileExists(atPath: serviceWorkerURL.path) else {
            throw ExtensionError.installationFailed(
                "MV3 service worker not found: \(serviceWorker)"
            )
        }
    }

    nonisolated static func resolveInstallSource(at url: URL) throws -> ResolvedInstallSource {
        let standardized = url.standardizedFileURL
        switch standardized.pathExtension.lowercased() {
        case "appex":
            return try resolveSafariAppExtensionInstallSource(at: standardized)
        case "app":
            return try resolveContainingAppInstallSource(at: standardized)
        default:
            return try resolveDirectoryInstallSource(at: standardized)
        }
    }

    private nonisolated static func resolveDirectoryInstallSource(at url: URL) throws -> ResolvedInstallSource {
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExtensionError.installationFailed(
                "Sumi accepts unpacked extension directories, Safari app extensions (.appex), or containing apps (.app)"
            )
        }

        let manifestURL = url.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw ExtensionError.installationFailed(
                "The selected directory does not contain a manifest.json"
            )
        }

        return ResolvedInstallSource(
            sourceKind: .directory,
            resourcesURL: url,
            sourceBundlePath: url,
            sourceFingerprintURL: url,
            appexBundleURL: nil
        )
    }

    private nonisolated static func resolveSafariAppExtensionInstallSource(
        at appexURL: URL
    ) throws -> ResolvedInstallSource {
        var issues: [SafariExtensionScannerIssue] = []
        let scanner = SafariExtensionScanner()
        guard let candidate = scanner.inspectAppexBundle(at: appexURL, issues: &issues) else {
            if let issue = issues.first {
                throw ExtensionError.installationFailed(
                    safariExtensionScannerIssueDescription(issue)
                )
            }
            throw ExtensionError.installationFailed(
                "The selected bundle is not a Safari Web Extension"
            )
        }

        let resourcesURL = try SafariAppExtensionResources.resourcesRoot(in: appexURL)
        return ResolvedInstallSource(
            sourceKind: .safariAppExtension,
            resourcesURL: resourcesURL,
            sourceBundlePath: appexURL,
            sourceFingerprintURL: appexURL,
            appexBundleURL: candidate.appexURL
        )
    }

    private nonisolated static func resolveContainingAppInstallSource(at appURL: URL) throws -> ResolvedInstallSource {
        var issues: [SafariExtensionScannerIssue] = []
        let scanner = SafariExtensionScanner()
        let candidates = scanner.inspectContainingAppBundle(at: appURL, issues: &issues)

        guard candidates.isEmpty == false else {
            if let issue = issues.first {
                throw ExtensionError.installationFailed(
                    safariExtensionScannerIssueDescription(issue)
                )
            }
            throw ExtensionError.installationFailed(
                "The selected app does not contain a Safari Web Extension"
            )
        }

        guard candidates.count == 1, let candidate = candidates.first else {
            let names = candidates.map(\.displayName).joined(separator: ", ")
            throw ExtensionError.installationFailed(
                "The selected app contains multiple Safari Web Extensions (\(names)). Select a specific .appex bundle instead."
            )
        }

        let resourcesURL = try SafariAppExtensionResources.resourcesRoot(in: candidate.appexURL)
        return ResolvedInstallSource(
            sourceKind: .safariAppExtension,
            resourcesURL: resourcesURL,
            sourceBundlePath: candidate.appexURL,
            sourceFingerprintURL: candidate.appexURL,
            appexBundleURL: candidate.appexURL
        )
    }

    private nonisolated static func safariExtensionScannerIssueDescription(
        _ issue: SafariExtensionScannerIssue
    ) -> String {
        switch issue {
        case .unreadableBundle(let url):
            return "Safari extension bundle is not readable: \(url.lastPathComponent)"
        case .invalidExtensionPoint(let url, let found):
            if let found {
                return "\(url.lastPathComponent) is not a Safari Web Extension (found \(found))"
            }
            return "\(url.lastPathComponent) is not a Safari Web Extension"
        case .missingManifest(let url):
            return "Safari extension bundle is missing manifest.json: \(url.lastPathComponent)"
        case .duplicateExtensionIdentifier(let identifier):
            return "Duplicate Safari extension identifier: \(identifier)"
        }
    }

    nonisolated static func manifestDeclaresWebKitBrowserTarget(
        for manifest: [String: Any]
    ) -> Bool {
        guard let browserSpecificSettings = manifest["browser_specific_settings"] as? [String: Any] else {
            return false
        }

        return browserSpecificSettings["safari"] != nil
            || browserSpecificSettings["webkit"] != nil
            || browserSpecificSettings["WebKit"] != nil
    }
}
