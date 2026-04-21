//
//  ExtensionManager+ManifestPatching.swift
//  Sumi
//
//  Install-source resolution and manifest patching for Sumi's WebExtension runtime.
//
//  On-disk JS files written here are referenced by manifest.json and loaded by
//  WebKit's extension system. They cannot be replaced by WKUserScript injection
//  because WebKit resolves content_scripts and background.service_worker paths
//  from the manifest at load time. The page-world externally_connectable bridge
//  is already injected via WKUserScript from the externally_connectable runtime.
//  All writes are idempotent: existing content is checked before writing.
//
//  (Hardening “no disk writes” goal): scripts that the manifest names by path must
//  continue to exist on disk; only bridge pieces that are not manifest-referenced
//  should avoid package writes (the page-world bridge already follows that rule).
//

import Foundation
import WebKit

@available(macOS 15.5, *)
extension ExtensionManager {
    struct ResolvedInstallSource {
        let sourceKind: SafariExtensionSourceKind
        let resourcesURL: URL
        let sourceBundlePath: URL
        let sourceFingerprintURL: URL
        let appBundleID: String?
        let appexBundleID: String?
    }

    private struct ManifestPatchCacheEntry: Codable {
        let manifestFingerprint: String
        let artifactFingerprints: [String: String]
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

    nonisolated static func isSafariWebExtensionBundle(_ appexURL: URL) -> Bool {
        let infoPlistURL = appexURL.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoPlistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any],
            let extensionDictionary = plist["NSExtension"] as? [String: Any],
            let pointIdentifier = extensionDictionary["NSExtensionPointIdentifier"] as? String
        else {
            return false
        }

        return pointIdentifier == "com.apple.Safari.web-extension"
    }

    nonisolated static func resolveSafariResources(in appexURL: URL) throws -> URL {
        let resourcesURL = appexURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let manifestURL = resourcesURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ExtensionError.installationFailed(
                "No manifest.json was found in \(appexURL.lastPathComponent)"
            )
        }
        return resourcesURL
    }

    static func resolveInstallSource(at url: URL) throws -> ResolvedInstallSource {
        let fileManager = FileManager.default
        let pathExtension = url.pathExtension.lowercased()

        if pathExtension == "app" {
            let pluginsDirectory = url.appendingPathComponent("Contents/PlugIns", isDirectory: true)
            guard let appexURLs = try? fileManager.contentsOfDirectory(
                at: pluginsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                throw ExtensionError.installationFailed(
                    "No Safari extension plug-ins were found inside \(url.lastPathComponent)"
                )
            }

            for appexURL in appexURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where appexURL.pathExtension.lowercased() == "appex" {
                guard isSafariWebExtensionBundle(appexURL) else { continue }
                let resourcesURL = try resolveSafariResources(in: appexURL)
                return ResolvedInstallSource(
                    sourceKind: .app,
                    resourcesURL: resourcesURL,
                    sourceBundlePath: url,
                    sourceFingerprintURL: url,
                    appBundleID: Bundle(url: url)?.bundleIdentifier,
                    appexBundleID: Bundle(url: appexURL)?.bundleIdentifier
                )
            }

            throw ExtensionError.installationFailed(
                "Sumi could not find a Safari Web Extension inside \(url.lastPathComponent)"
            )
        }

        if pathExtension == "appex" {
            guard isSafariWebExtensionBundle(url) else {
                throw ExtensionError.installationFailed(
                    "\(url.lastPathComponent) is not a Safari Web Extension"
                )
            }
            return ResolvedInstallSource(
                sourceKind: .appex,
                resourcesURL: try resolveSafariResources(in: url),
                sourceBundlePath: url,
                sourceFingerprintURL: url,
                appBundleID: Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())?.bundleIdentifier,
                appexBundleID: Bundle(url: url)?.bundleIdentifier
            )
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExtensionError.installationFailed(
                "Sumi installs Safari extensions from .app, .appex, or unpacked directories only"
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
            appBundleID: nil,
            appexBundleID: nil
        )
    }

    private nonisolated static func patchExternallyConnectableBackgroundSupport(
        in manifest: inout [String: Any],
        extensionRoot: URL
    ) -> Bool {
        guard var background = manifest["background"] as? [String: Any] else {
            return false
        }

        var changed = false
        let helperFilename = externallyConnectableBackgroundHelperFilename

        if var scripts = background["scripts"] as? [String], scripts.isEmpty == false {
            if scripts.contains(helperFilename) == false {
                scripts.insert(helperFilename, at: 0)
                background["scripts"] = scripts
                changed = true
            }
        }

        if let configuredServiceWorker = background["service_worker"] as? String,
           configuredServiceWorker.isEmpty == false
        {
            let originalServiceWorker: String
            if configuredServiceWorker == externallyConnectableServiceWorkerWrapperFilename,
               let existingOriginal = externallyConnectableOriginalServiceWorkerPath(
                   in: extensionRoot
               )
            {
                originalServiceWorker = existingOriginal
            } else {
                originalServiceWorker = configuredServiceWorker
            }

            if background["service_worker"] as? String != externallyConnectableServiceWorkerWrapperFilename {
                background["service_worker"] = externallyConnectableServiceWorkerWrapperFilename
                changed = true
            }

            let wrapperURL = ExtensionUtils.url(
                extensionRoot,
                appendingManifestRelativePath: externallyConnectableServiceWorkerWrapperFilename
            ) ?? extensionRoot.appendingPathComponent(
                externallyConnectableServiceWorkerWrapperFilename
            )
            let wrapperSource = externallyConnectableServiceWorkerWrapperScript(
                originalServiceWorker: originalServiceWorker,
                backgroundType: background["type"] as? String
            )
            let existingWrapperSource = try? String(contentsOf: wrapperURL, encoding: .utf8)
            if existingWrapperSource != wrapperSource {
                try? wrapperSource.write(to: wrapperURL, atomically: true, encoding: .utf8)
                changed = true
            }
        }

        if let backgroundPagePath = background["page"] as? String,
           backgroundPagePath.isEmpty == false,
           let backgroundPageURL = ExtensionUtils.url(
               extensionRoot,
               appendingManifestRelativePath: backgroundPagePath
           )
        {
            if let existingHTML = try? String(contentsOf: backgroundPageURL, encoding: .utf8) {
                let injectedHTML = injectExternallyConnectableHelper(
                    intoBackgroundPageHTML: existingHTML,
                    helperFilename: helperFilename
                )
                if injectedHTML != existingHTML {
                    try? injectedHTML.write(
                        to: backgroundPageURL,
                        atomically: true,
                        encoding: .utf8
                    )
                    changed = true
                }
            }
        }

        if changed {
            manifest["background"] = background
        }

        return changed
    }

    private nonisolated static func patchWebKitRuntimeCompatibilityPrelude(
        in manifest: inout [String: Any],
        extensionRoot: URL
    ) -> Bool {
        guard shouldInstallWebKitRuntimeCompatibilityPrelude(for: manifest),
              var background = manifest["background"] as? [String: Any]
        else {
            return false
        }

        var changed = false
        let preludeFilename = webKitRuntimeCompatibilityPreludeFilename
        let preludeURL = ExtensionUtils.url(
            extensionRoot,
            appendingManifestRelativePath: preludeFilename
        ) ?? extensionRoot.appendingPathComponent(preludeFilename)
        let preludeSource = webKitRuntimeCompatibilityPreludeScript(
            browserSpecificSettings: manifest["browser_specific_settings"] as? [String: Any]
        )
        let existingPreludeSource = try? String(contentsOf: preludeURL, encoding: .utf8)
        if existingPreludeSource != preludeSource {
            try? preludeSource.write(to: preludeURL, atomically: true, encoding: .utf8)
            changed = true
        }

        if var scripts = background["scripts"] as? [String], scripts.isEmpty == false {
            if scripts.first != preludeFilename {
                scripts.removeAll { $0 == preludeFilename }
                scripts.insert(preludeFilename, at: 0)
                background["scripts"] = scripts
                manifest["background"] = background
                changed = true
            }
        }

        if let backgroundPagePath = background["page"] as? String,
           backgroundPagePath.isEmpty == false,
           let backgroundPageURL = ExtensionUtils.url(
               extensionRoot,
               appendingManifestRelativePath: backgroundPagePath
           )
        {
            if let existingHTML = try? String(contentsOf: backgroundPageURL, encoding: .utf8) {
                let injectedHTML = injectScriptsIntoBackgroundPageHTML(
                    existingHTML,
                    scriptFilenames: [preludeFilename]
                )
                if injectedHTML != existingHTML {
                    try? injectedHTML.write(
                        to: backgroundPageURL,
                        atomically: true,
                        encoding: .utf8
                    )
                    changed = true
                }
            }
        }

        if let configuredServiceWorker = background["service_worker"] as? String,
           configuredServiceWorker.isEmpty == false
        {
            let originalServiceWorker: String
            if configuredServiceWorker == webKitRuntimeCompatibilityServiceWorkerWrapperFilename,
               let existingOriginal = webKitRuntimeCompatibilityOriginalServiceWorkerPath(
                   in: extensionRoot
               )
            {
                originalServiceWorker = existingOriginal
            } else {
                originalServiceWorker = configuredServiceWorker
            }

            if background["service_worker"] as? String != webKitRuntimeCompatibilityServiceWorkerWrapperFilename {
                background["service_worker"] = webKitRuntimeCompatibilityServiceWorkerWrapperFilename
                manifest["background"] = background
                changed = true
            }

            let wrapperURL = ExtensionUtils.url(
                extensionRoot,
                appendingManifestRelativePath: webKitRuntimeCompatibilityServiceWorkerWrapperFilename
            ) ?? extensionRoot.appendingPathComponent(
                webKitRuntimeCompatibilityServiceWorkerWrapperFilename
            )
            let wrapperSource = webKitRuntimeCompatibilityServiceWorkerWrapperScript(
                originalServiceWorker: originalServiceWorker,
                backgroundType: background["type"] as? String
            )
            let existingWrapperSource = try? String(contentsOf: wrapperURL, encoding: .utf8)
            if existingWrapperSource != wrapperSource {
                try? wrapperSource.write(to: wrapperURL, atomically: true, encoding: .utf8)
                changed = true
            }
        }

        return changed
    }

    nonisolated static func shouldInstallWebKitRuntimeCompatibilityPrelude(
        for manifest: [String: Any]
    ) -> Bool {
        guard let browserSpecificSettings = manifest["browser_specific_settings"] as? [String: Any] else {
            return false
        }

        return browserSpecificSettings["safari"] != nil
            || browserSpecificSettings["webkit"] != nil
            || browserSpecificSettings["WebKit"] != nil
    }

    private nonisolated static func webKitRuntimeCompatibilityOriginalServiceWorkerPath(
        in extensionRoot: URL
    ) -> String? {
        let wrapperURL = ExtensionUtils.url(
            extensionRoot,
            appendingManifestRelativePath: webKitRuntimeCompatibilityServiceWorkerWrapperFilename
        ) ?? extensionRoot.appendingPathComponent(
            webKitRuntimeCompatibilityServiceWorkerWrapperFilename
        )
        guard let wrapperSource = try? String(contentsOf: wrapperURL, encoding: .utf8) else {
            return nil
        }

        let marker = "// SUMI_WEBKIT_RUNTIME_COMPAT_ORIGINAL_SERVICE_WORKER:"
        guard let line = wrapperSource.split(separator: "\n").first(where: {
            $0.hasPrefix(marker)
        }) else {
            return nil
        }

        return line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
    }

    private nonisolated static func externallyConnectableOriginalServiceWorkerPath(
        in extensionRoot: URL
    ) -> String? {
        let wrapperURL = ExtensionUtils.url(
            extensionRoot,
            appendingManifestRelativePath: externallyConnectableServiceWorkerWrapperFilename
        ) ?? extensionRoot.appendingPathComponent(
            externallyConnectableServiceWorkerWrapperFilename
        )
        guard let wrapperSource = try? String(contentsOf: wrapperURL, encoding: .utf8) else {
            return nil
        }

        let marker = "// SUMI_EC_ORIGINAL_SERVICE_WORKER:"
        guard let line = wrapperSource.split(separator: "\n").first(where: {
            $0.hasPrefix(marker)
        }) else {
            return nil
        }

        return line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
    }

    private nonisolated static func injectExternallyConnectableHelper(
        intoBackgroundPageHTML html: String,
        helperFilename: String
    ) -> String {
        let scriptTag = #"<script src="\#(helperFilename)"></script>"#
        guard html.contains(helperFilename) == false else {
            return html
        }

        if let headRange = html.range(
            of: "<head[^>]*>",
            options: [.regularExpression, .caseInsensitive]
        ) {
            return html.replacingCharacters(
                in: headRange,
                with: "\(html[headRange])\n\(scriptTag)"
            )
        }

        if let bodyRange = html.range(
            of: "<body[^>]*>",
            options: [.regularExpression, .caseInsensitive]
        ) {
            return html.replacingCharacters(
                in: bodyRange,
                with: "\(html[bodyRange])\n\(scriptTag)"
            )
        }

        return "\(scriptTag)\n\(html)"
    }

    private nonisolated static func injectScriptsIntoBackgroundPageHTML(
        _ html: String,
        scriptFilenames: [String]
    ) -> String {
        let uniqueFilenames = scriptFilenames.reduce(into: [String]()) { partialResult, filename in
            guard partialResult.contains(filename) == false else { return }
            partialResult.append(filename)
        }
        let missingFilenames = uniqueFilenames.filter { html.contains($0) == false }
        guard missingFilenames.isEmpty == false else { return html }

        let scriptTags = missingFilenames
            .map { #"<script src="\#($0)"></script>"# }
            .joined(separator: "\n")

        if let headRange = html.range(
            of: "<head[^>]*>",
            options: [.regularExpression, .caseInsensitive]
        ) {
            return html.replacingCharacters(
                in: headRange,
                with: "\(html[headRange])\n\(scriptTags)"
            )
        }

        if let bodyRange = html.range(
            of: "<body[^>]*>",
            options: [.regularExpression, .caseInsensitive]
        ) {
            return html.replacingCharacters(
                in: bodyRange,
                with: "\(html[bodyRange])\n\(scriptTags)"
            )
        }

        return "\(scriptTags)\n\(html)"
    }

    private nonisolated static func selectiveContentScriptGuardTargets() -> Set<String> {
        guard RuntimeDiagnostics.hasExplicitDebugLaunchIntent
            || RuntimeDiagnostics.allowsPersistedDebugDefaults
            || RuntimeDiagnostics.isRunningTests
        else {
            return []
        }

        let defaults = UserDefaults.standard

        if let rawTargets = defaults.array(forKey: selectiveContentScriptGuardTargetsKey) as? [String] {
            return Set(
                rawTargets
                    .map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    }
                    .filter { $0.isEmpty == false }
            )
        }

        guard let rawValue = defaults.string(forKey: selectiveContentScriptGuardTargetsKey) else {
            return []
        }

        return Set(
            rawValue
                .split(separator: ",")
                .map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                .filter { $0.isEmpty == false }
        )
    }

    private nonisolated static func shouldInstallSelectiveContentScriptGuard(
        for manifest: [String: Any],
        manifestURL: URL
    ) -> Bool {
        let targets = selectiveContentScriptGuardTargets()
        guard targets.isEmpty == false else { return false }

        var candidates: Set<String> = [ExtensionUtils.fingerprint(fileAt: manifestURL)]
        let candidateKeys = ["name", "short_name", "homepage_url"]

        for key in candidateKeys {
            if let value = manifest[key] as? String {
                let normalized = value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if normalized.isEmpty == false {
                    candidates.insert(normalized)
                }
            }
        }

        if let browserSpecificSettings = manifest["browser_specific_settings"] as? [String: Any] {
            for browser in browserSpecificSettings.values {
                guard let settings = browser as? [String: Any] else { continue }
                for key in ["id", "strict_min_version"] {
                    guard let value = settings[key] as? String else { continue }
                    let normalized = value
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    if normalized.isEmpty == false {
                        candidates.insert(normalized)
                    }
                }
            }
        }

        return candidates.contains { targets.contains($0) }
    }

    private nonisolated static func selectiveContentScriptGuardFilename(
        manifestURL: URL,
        scriptIndex: Int
    ) -> String {
        let fingerprint = ExtensionUtils.fingerprint(fileAt: manifestURL)
        let prefix = String(fingerprint.prefix(12))
        return "sumi_content_guard_\(prefix)_\(scriptIndex).js"
    }

    private nonisolated static func selectiveContentScriptGuardMarkerAttribute(
        manifestURL: URL,
        scriptIndex: Int
    ) -> String {
        let fingerprint = ExtensionUtils.fingerprint(fileAt: manifestURL)
        return "data-sumi-cs-guard-\(String(fingerprint.prefix(12)))_\(scriptIndex)"
    }

    private nonisolated static func patchSelectiveContentScriptGuard(
        in manifest: inout [String: Any],
        manifestURL: URL,
        extensionRoot: URL
    ) -> Bool {
        guard shouldInstallSelectiveContentScriptGuard(for: manifest, manifestURL: manifestURL),
              var contentScripts = manifest["content_scripts"] as? [[String: Any]]
        else {
            return false
        }

        var changed = false

        for index in contentScripts.indices {
            let jsFiles = contentScripts[index]["js"] as? [String] ?? []
            guard jsFiles.isEmpty == false else { continue }

            let guardFilename = selectiveContentScriptGuardFilename(
                manifestURL: manifestURL,
                scriptIndex: index
            )
            let guardURL = ExtensionUtils.url(
                extensionRoot,
                appendingManifestRelativePath: guardFilename
            ) ?? extensionRoot.appendingPathComponent(guardFilename)
            let guardSource = selectiveContentScriptGuardScript(
                markerAttribute: selectiveContentScriptGuardMarkerAttribute(
                    manifestURL: manifestURL,
                    scriptIndex: index
                ),
                originalScriptFilenames: jsFiles
            )
            let existingGuardSource = try? String(contentsOf: guardURL, encoding: .utf8)
            if existingGuardSource != guardSource {
                try? guardSource.write(to: guardURL, atomically: true, encoding: .utf8)
                changed = true
            }

            if jsFiles != [guardFilename] {
                contentScripts[index]["js"] = [guardFilename]
                changed = true
            }
        }

        if changed {
            manifest["content_scripts"] = contentScripts
        }

        return changed
    }

    private nonisolated static func shouldSkipManifestPatch(
        manifestURL: URL,
        extensionRoot: URL
    ) -> Bool {
        guard RuntimeDiagnostics.hasExplicitDebugLaunchIntent == false,
              RuntimeDiagnostics.allowsPersistedDebugDefaults == false
        else {
            return false
        }

        let cacheKey = manifestPatchCacheKey(for: manifestURL)
        guard let entry = manifestPatchCache()[cacheKey] else { return false }
        guard entry.manifestFingerprint == ExtensionUtils.fingerprint(fileAt: manifestURL) else {
            return false
        }

        return entry.artifactFingerprints == manifestPatchArtifactFingerprints(
            in: extensionRoot
        )
    }

    private nonisolated static func updateManifestPatchCache(
        manifestURL: URL,
        extensionRoot: URL
    ) {
        var cache = manifestPatchCache()
        cache[manifestPatchCacheKey(for: manifestURL)] = ManifestPatchCacheEntry(
            manifestFingerprint: ExtensionUtils.fingerprint(fileAt: manifestURL),
            artifactFingerprints: manifestPatchArtifactFingerprints(in: extensionRoot)
        )

        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: manifestPatchCacheStorageKey)
    }

    private nonisolated static func manifestPatchCache()
        -> [String: ManifestPatchCacheEntry]
    {
        guard let data = UserDefaults.standard.data(
            forKey: manifestPatchCacheStorageKey
        ) else {
            return [:]
        }

        return (try? JSONDecoder().decode(
            [String: ManifestPatchCacheEntry].self,
            from: data
        )) ?? [:]
    }

    private nonisolated static func manifestPatchCacheKey(for manifestURL: URL) -> String {
        ExtensionUtils.fingerprint(
            string: manifestURL.standardizedFileURL.path
        )
    }

    private nonisolated static func manifestPatchArtifactFingerprints(
        in extensionRoot: URL
    ) -> [String: String] {
        let staticFilenames = [
            externallyConnectableBridgeFilename,
            externallyConnectableBackgroundHelperFilename,
            externallyConnectableServiceWorkerWrapperFilename,
            webKitRuntimeCompatibilityPreludeFilename,
            webKitRuntimeCompatibilityServiceWorkerWrapperFilename,
        ]

        var filenames = Set(staticFilenames)
        if let packageURLs = try? FileManager.default.contentsOfDirectory(
            at: extensionRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in packageURLs {
                let filename = url.lastPathComponent
                if filename.hasPrefix("sumi_content_guard_"),
                   filename.hasSuffix(".js")
                {
                    filenames.insert(filename)
                }
            }
        }

        var fingerprints: [String: String] = [:]
        for filename in filenames.sorted() {
            let url = extensionRoot.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            fingerprints[filename] = ExtensionUtils.fingerprint(fileAt: url)
        }
        return fingerprints
    }

    nonisolated func patchManifestForWebKit(at manifestURL: URL) {
        let extensionRoot = manifestURL.deletingLastPathComponent()
        guard Self.shouldSkipManifestPatch(
            manifestURL: manifestURL,
            extensionRoot: extensionRoot
        ) == false else {
            return
        }

        guard var manifest = try? ExtensionUtils.loadJSONObject(at: manifestURL) else { return }

        var changed = false

        if var contentScripts = manifest["content_scripts"] as? [[String: Any]] {
            for index in contentScripts.indices {
                guard let world = contentScripts[index]["world"] as? String, world == "MAIN" else {
                    continue
                }
                guard let matches = contentScripts[index]["matches"] as? [String] else {
                    continue
                }
                let jsFiles = contentScripts[index]["js"] as? [String] ?? []

                if jsFiles.contains(Self.externallyConnectableBridgeFilename) {
                    continue
                }

                let allDomainSpecific = matches.allSatisfy { pattern in
                    guard let schemeEnd = pattern.range(of: "://") else { return false }
                    let afterScheme = pattern[schemeEnd.upperBound...]
                    guard let slashIndex = afterScheme.firstIndex(of: "/") else { return false }
                    let host = String(afterScheme[afterScheme.startIndex..<slashIndex])
                    return host != "*" && host.hasPrefix("*.") == false
                }

                if allDomainSpecific {
                    contentScripts[index].removeValue(forKey: "world")
                    changed = true
                }
            }
            manifest["content_scripts"] = contentScripts
        }

        if let externallyConnectable = manifest["externally_connectable"] as? [String: Any],
           let matches = externallyConnectable["matches"] as? [String],
           matches.isEmpty == false
        {
            var contentScripts = manifest["content_scripts"] as? [[String: Any]] ?? []
            let bridgeScript = Self.externallyConnectableBridgeFilename
            let existingBridgeIndexes = contentScripts.indices.filter {
                (($0 < contentScripts.count ? contentScripts[$0]["js"] as? [String] : nil) ?? [])
                    .contains(bridgeScript)
            }

            var canonicalBridgeEntry: [String: Any]
            if let firstIndex = existingBridgeIndexes.first {
                canonicalBridgeEntry = contentScripts[firstIndex]
            } else {
                canonicalBridgeEntry = [:]
            }
            canonicalBridgeEntry["all_frames"] = true
            canonicalBridgeEntry["js"] = [bridgeScript]
            canonicalBridgeEntry["matches"] = matches
            canonicalBridgeEntry["run_at"] = "document_start"

            if existingBridgeIndexes.isEmpty == false {
                let firstIndex = existingBridgeIndexes[0]
                let firstEntryBefore = contentScripts[firstIndex]
                let beforeCount = contentScripts.count
                contentScripts = contentScripts.enumerated().compactMap { index, entry in
                    if existingBridgeIndexes.contains(index) {
                        return index == firstIndex ? canonicalBridgeEntry : nil
                    }
                    return entry
                }
                if beforeCount != contentScripts.count
                    || NSDictionary(dictionary: firstEntryBefore).isEqual(to: canonicalBridgeEntry) == false
                {
                    contentScripts[firstIndex] = canonicalBridgeEntry
                    changed = true
                }
            } else {
                contentScripts.append(canonicalBridgeEntry)
                changed = true
            }

            manifest["content_scripts"] = contentScripts

            let bridgeURL = ExtensionUtils.url(
                extensionRoot,
                appendingManifestRelativePath: bridgeScript
            ) ?? extensionRoot.appendingPathComponent(bridgeScript)
            let bridgeSource = Self.isolatedWorldExternallyConnectableBridgeScript()
            let existingSource = try? String(contentsOf: bridgeURL, encoding: .utf8)
            if existingSource != bridgeSource {
                try? bridgeSource.write(to: bridgeURL, atomically: true, encoding: .utf8)
                changed = true
            }

            let backgroundHelperURL = ExtensionUtils.url(
                extensionRoot,
                appendingManifestRelativePath: Self.externallyConnectableBackgroundHelperFilename
            ) ?? extensionRoot.appendingPathComponent(
                Self.externallyConnectableBackgroundHelperFilename
            )
            let backgroundHelperSource = Self.externallyConnectableBackgroundHelperScript()
            let existingBackgroundHelperSource = try? String(
                contentsOf: backgroundHelperURL,
                encoding: .utf8
            )
            if existingBackgroundHelperSource != backgroundHelperSource {
                try? backgroundHelperSource.write(
                    to: backgroundHelperURL,
                    atomically: true,
                    encoding: .utf8
                )
                changed = true
            }

            if Self.patchExternallyConnectableBackgroundSupport(
                in: &manifest,
                extensionRoot: extensionRoot
            ) {
                changed = true
            }
        }

        if Self.patchWebKitRuntimeCompatibilityPrelude(
            in: &manifest,
            extensionRoot: manifestURL.deletingLastPathComponent()
        ) {
            changed = true
        }

        let selectiveContentGuardChanged = Self.patchSelectiveContentScriptGuard(
            in: &manifest,
            manifestURL: manifestURL,
            extensionRoot: extensionRoot
        )
        if selectiveContentGuardChanged {
            changed = true
        }

        if changed {
            _ = try? ExtensionUtils.writeJSONObjectIfChanged(manifest, to: manifestURL)
        }
        Self.updateManifestPatchCache(
            manifestURL: manifestURL,
            extensionRoot: extensionRoot
        )
    }
}
