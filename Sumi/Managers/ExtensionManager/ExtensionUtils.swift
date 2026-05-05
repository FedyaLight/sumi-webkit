//
//  ExtensionUtils.swift
//  Sumi
//
//  Shared Safari/WebExtension helpers used by Sumi's native WebKit runtime.
//

import CryptoKit
import Foundation
import WebKit

struct ExtensionUtils {
    static let commonOptionsPageRelativePaths = [
        "ui/options/index.html",
        "options/index.html",
        "options.html",
        "settings.html",
    ]

    /// Joins `base` with a manifest-relative path using `/` as hierarchy (unlike `appendingPathComponent`,
    /// which encodes `/` as a single segment). Rejects absolute paths and `..` / `.` segments.
    static func url(
        _ base: URL,
        appendingManifestRelativePath relative: String
    ) -> URL? {
        var path = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.isEmpty == false else { return nil }
        if path.hasPrefix("/") {
            return nil
        }
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        guard path.isEmpty == false else { return nil }
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            if segment == ".." || segment == "." {
                return nil
            }
        }
        return base.appending(path: path)
    }

    static var isExtensionSupportAvailable: Bool {
        true
    }

    static func applicationSupportRoot() -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent(
            SumiAppIdentity.runtimeBundleIdentifier,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    static func extensionsDirectory() -> URL {
        let directory = applicationSupportRoot()
            .appendingPathComponent("Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    static func validateManifest(at url: URL) throws -> [String: Any] {
        let manifest = try loadJSONObject(at: url)

        guard let manifestVersion = manifest["manifest_version"] as? Int else {
            throw ExtensionError.invalidManifest("Missing manifest_version")
        }

        guard manifestVersion == 2 || manifestVersion == 3 else {
            throw ExtensionError.unsupportedManifest(
                "Sumi supports manifest_version 2 and 3 only"
            )
        }

        guard let name = manifest["name"] as? String, name.isEmpty == false else {
            throw ExtensionError.invalidManifest("Missing name")
        }

        guard
            let version = manifest["version"] as? String,
            version.isEmpty == false
        else {
            throw ExtensionError.invalidManifest("Missing version")
        }

        return manifest
    }

    static func loadJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard
            let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            throw ExtensionError.invalidManifest("Invalid JSON structure")
        }
        return object
    }

    @discardableResult
    static func writeJSONObjectIfChanged(_ object: [String: Any], to url: URL) throws -> Bool {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ExtensionError.invalidManifest("Manifest is not a valid JSON object")
        }
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        if let existing = try? Data(contentsOf: url), existing == data {
            return false
        }
        try data.write(to: url, options: [.atomic])
        return true
    }

    static func localizedString(
        _ rawValue: String?,
        in extensionRoot: URL
    ) -> String? {
        guard let rawValue, rawValue.hasPrefix("__MSG_"), rawValue.hasSuffix("__") else {
            return rawValue
        }

        let key = String(rawValue.dropFirst(6).dropLast(2))
        let localesRoot = extensionRoot.appendingPathComponent("_locales", isDirectory: true)
        guard FileManager.default.fileExists(atPath: localesRoot.path) else {
            return nil
        }

        let preferredLocales = preferredLocaleDirectoryNames()
        let candidateDirectories = (try? FileManager.default.contentsOfDirectory(
            at: localesRoot,
            includingPropertiesForKeys: nil
        )) ?? []

        let localeDirectory = preferredLocales.lazy.compactMap { candidate in
            candidateDirectories.first {
                $0.lastPathComponent.caseInsensitiveCompare(candidate) == .orderedSame
            }
        }.first

        guard let directory = localeDirectory else { return nil }
        let messagesURL = directory.appendingPathComponent("messages.json")
        guard let messages = try? loadJSONObject(at: messagesURL) else {
            return nil
        }

        return (messages[key] as? [String: Any])?["message"] as? String
    }

    static func preferredLocaleDirectoryNames() -> [String] {
        var values: [String] = []
        let locale = Locale.current
        if let language = locale.language.languageCode?.identifier {
            if let region = locale.language.region?.identifier {
                values.append("\(language)_\(region)")
                values.append("\(language)-\(region)")
            }
            values.append(language)
        }
        values.append("en")
        return Array(NSOrderedSet(array: values)) as? [String] ?? values
    }

    static func fingerprint(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func fingerprint(string: String) -> String {
        fingerprint(data: Data(string.utf8))
    }

    static func fingerprint(fileAt url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return fingerprint(string: url.path)
        }
        return fingerprint(data: data)
    }

    static func normalizePathFingerprint(_ url: URL) -> String {
        fingerprint(string: url.standardizedFileURL.path)
    }

    static func iconPath(
        in extensionRoot: URL,
        manifest: [String: Any]
    ) -> String? {
        let candidates = iconCandidates(from: manifest)

        for relativePath in candidates {
            guard let candidate = url(
                extensionRoot,
                appendingManifestRelativePath: relativePath
            ) else {
                continue
            }
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }

        return nil
    }

    private static func iconCandidates(from manifest: [String: Any]) -> [String] {
        var candidates: [String] = []

        func appendIconMap(_ value: Any?) {
            guard let map = value as? [String: Any] else { return }
            for key in map.keys.sorted(by: >) {
                if let path = map[key] as? String, path.isEmpty == false {
                    candidates.append(path)
                }
            }
        }

        appendIconMap(manifest["icons"])

        if let action = manifest["action"] as? [String: Any] {
            appendIconMap(action["default_icon"])
            if let path = action["default_icon"] as? String, path.isEmpty == false {
                candidates.append(path)
            }
        }

        if let browserAction = manifest["browser_action"] as? [String: Any] {
            appendIconMap(browserAction["default_icon"])
            if let path = browserAction["default_icon"] as? String, path.isEmpty == false {
                candidates.append(path)
            }
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    static func defaultPopupPath(from manifest: [String: Any]) -> String? {
        if let action = manifest["action"] as? [String: Any],
           let popup = action["default_popup"] as? String,
           popup.isEmpty == false
        {
            return popup
        }

        if let browserAction = manifest["browser_action"] as? [String: Any],
           let popup = browserAction["default_popup"] as? String,
           popup.isEmpty == false
        {
            return popup
        }

        return nil
    }

    static func optionsPagePath(from manifest: [String: Any]) -> String? {
        if let options = manifest["options_ui"] as? [String: Any],
           let page = options["page"] as? String,
           page.isEmpty == false
        {
            return page
        }

        if let page = manifest["options_page"] as? String, page.isEmpty == false {
            return page
        }

        if let overrides = manifest["chrome_url_overrides"] as? [String: Any],
           let page = overrides["options"] as? String,
           page.isEmpty == false
        {
            return page
        }

        return nil
    }

    static func storedOptionsPagePath(
        from manifest: [String: Any],
        in extensionRoot: URL
    ) -> String? {
        if let declaredPath = optionsPagePath(from: manifest),
           let normalizedPath = existingValidatedOptionsPagePath(
               declaredPath,
               in: extensionRoot
           )
        {
            return normalizedPath
        }

        for candidate in commonOptionsPageRelativePaths {
            if let normalizedPath = existingValidatedOptionsPagePath(
                candidate,
                in: extensionRoot
            ) {
                return normalizedPath
            }
        }

        return nil
    }

    static func resolvedOptionsPageURL(
        sdkURL: URL?,
        persistedPath: String?,
        manifest: [String: Any],
        extensionRoot: URL
    ) throws -> URL {
        if let sdkURL {
            if sdkURL.isFileURL {
                return try validatedExtensionPageURL(
                    sdkURL,
                    within: extensionRoot
                )
            }

            return sdkURL
        }

        if let persistedPath {
            guard let candidate = url(
                extensionRoot,
                appendingManifestRelativePath: persistedPath
            ) else {
                throw optionsPageNotFoundError()
            }
            return try validatedExtensionPageURL(candidate, within: extensionRoot)
        }

        if let declaredPath = optionsPagePath(from: manifest) {
            guard let candidate = url(
                extensionRoot,
                appendingManifestRelativePath: declaredPath
            ) else {
                throw optionsPageNotFoundError()
            }
            return try validatedExtensionPageURL(candidate, within: extensionRoot)
        }

        if let fallbackPath = storedOptionsPagePath(
            from: manifest,
            in: extensionRoot
        ) {
            guard let candidate = url(
                extensionRoot,
                appendingManifestRelativePath: fallbackPath
            ) else {
                throw optionsPageNotFoundError()
            }
            return try validatedExtensionPageURL(candidate, within: extensionRoot)
        }

        throw optionsPageNotFoundError()
    }

    static func validatedExtensionPageURL(
        _ candidateURL: URL,
        within extensionRoot: URL
    ) throws -> URL {
        let normalizedRoot = extensionRoot.resolvingSymlinksInPath().standardizedFileURL
        let normalizedCandidate = candidateURL.resolvingSymlinksInPath().standardizedFileURL

        let rootPath = normalizedRoot.path.hasSuffix("/")
            ? normalizedRoot.path
            : normalizedRoot.path + "/"

        guard
            normalizedCandidate.path == normalizedRoot.path
                || normalizedCandidate.path.hasPrefix(rootPath)
        else {
            throw NSError(
                domain: "ExtensionManager",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Options URL outside extension directory"]
            )
        }

        return normalizedCandidate
    }

    static func existingValidatedOptionsPagePath(
        _ relativePath: String,
        in extensionRoot: URL
    ) -> String? {
        let trimmedPath = relativePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else { return nil }

        guard let candidateURL = url(
            extensionRoot,
            appendingManifestRelativePath: trimmedPath
        ) else {
            return nil
        }
        guard
            let validatedURL = try? validatedExtensionPageURL(
                candidateURL,
                within: extensionRoot
            ),
            FileManager.default.fileExists(atPath: validatedURL.path)
        else {
            return nil
        }

        return relativeExtensionPath(
            for: validatedURL,
            within: extensionRoot
        )
    }

    static func relativeExtensionPath(
        for pageURL: URL,
        within extensionRoot: URL
    ) -> String? {
        let normalizedRoot = extensionRoot.resolvingSymlinksInPath().standardizedFileURL
        let normalizedPageURL = pageURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = normalizedRoot.path.hasSuffix("/")
            ? normalizedRoot.path
            : normalizedRoot.path + "/"

        guard normalizedPageURL.path.hasPrefix(rootPath) else {
            return nil
        }

        let relativePath = String(normalizedPageURL.path.dropFirst(rootPath.count))
        guard relativePath.isEmpty == false else {
            return nil
        }

        return relativePath
    }

    static func optionsPageNotFoundError() -> NSError {
        NSError(
            domain: "ExtensionManager",
            code: 6,
            userInfo: [NSLocalizedDescriptionKey: "No options page was found for this extension"]
        )
    }

    static func hasContentScripts(in manifest: [String: Any]) -> Bool {
        (manifest["content_scripts"] as? [[String: Any]])?.isEmpty == false
    }

    static func backgroundModel(from manifest: [String: Any]) -> SafariExtensionBackgroundModel {
        guard let background = manifest["background"] as? [String: Any] else {
            return .none
        }

        if background["service_worker"] as? String != nil {
            return .serviceWorker
        }

        if background["page"] as? String != nil {
            let persistent = background["persistent"] as? Bool ?? true
            return persistent ? .backgroundPage : .eventPage
        }

        if (background["scripts"] as? [String])?.isEmpty == false {
            let persistent = background["persistent"] as? Bool ?? true
            return persistent ? .backgroundPage : .eventPage
        }

        return .none
    }

    static func activationSummary(from manifest: [String: Any]) -> ExtensionActivationSummary {
        let requestedMatches = (
            manifest["host_permissions"] as? [String]
            ?? []
        ) + (((manifest["content_scripts"] as? [[String: Any]]) ?? []).flatMap {
            $0["matches"] as? [String] ?? []
        })

        let normalizedMatches = Array(NSOrderedSet(array: requestedMatches)) as? [String] ?? requestedMatches
        let broadScope = normalizedMatches.contains(where: {
            $0 == "<all_urls>" || $0 == "*://*/*" || $0.contains("://*")
        })

        return ExtensionActivationSummary(
            matchPatternStrings: normalizedMatches.sorted(),
            broadScope: broadScope,
            hasContentScripts: hasContentScripts(in: manifest),
            hasAction: defaultPopupPath(from: manifest) != nil
                || manifest["action"] != nil
                || manifest["browser_action"] != nil,
            hasOptionsPage: optionsPagePath(from: manifest) != nil,
            hasExtensionPages: hasExtensionPages(in: manifest)
        )
    }

    static func hasExtensionPages(in manifest: [String: Any]) -> Bool {
        optionsPagePath(from: manifest) != nil || defaultPopupPath(from: manifest) != nil
    }
}
