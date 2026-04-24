//
//  UserScriptStore.swift
//  Sumi
//
//  File-system backed storage for userscripts.
//  Reads .user.js and .user.css files from a configurable directory,
//  tracks enabled/disabled state via manifest.json,
//  and supports @require resource caching.
//

import CryptoKit
import Foundation
import SwiftData

@MainActor
final class UserScriptStore {

    // MARK: - Manifest

    struct Manifest: Codable {
        var disabled: [String]
        var settings: [String: String]
        var require: [String: [String]]
        /// When missing in older `manifest.json`, treated as `alwaysMatch`.
        var runMode: UserScriptRunMode?
        /// Per-script allowlist of origin keys (`UserScriptOriginPolicy.originKey`) for `strictOrigin`.
        var originAllow: [String: [String]]?
        /// Per-script denylist applied in both modes before `@match`.
        var originDeny: [String: [String]]?

        static var `default`: Manifest {
            Manifest(
                disabled: [],
                settings: [
                    "active": "true",
                    "autoUpdateInterval": "off",
                    "lazyScriptBody": "false"
                ],
                require: [:],
                runMode: nil,
                originAllow: nil,
                originDeny: nil
            )
        }
    }

    // MARK: - Properties

    private(set) var scripts: [SumiInstalledUserScript] = []
    /// `internal` so zip backup/import in `UserScriptStore+Backup.swift` can merge manifest fields.
    internal var manifest: Manifest = .default
    /// `internal` for SwiftData persistence helpers in `UserScriptStore+SwiftData.swift`.
    internal let context: ModelContext?
    private let fileManager = FileManager.default
    private var dispatchSource: DispatchSourceFileSystemObject?

    /// Callback invoked when scripts change on disk (for hot-reload).
    var onScriptsChanged: (() -> Void)?

    var scriptsDirectory: URL {
        didSet {
            stopWatching()
            reload()
            startWatching()
        }
    }

    private var requireDirectory: URL {
        scriptsDirectory.appendingPathComponent("require")
    }

    private var manifestURL: URL {
        scriptsDirectory.appendingPathComponent("manifest.json")
    }

    // MARK: - Init

    init(directory: URL? = nil, context: ModelContext? = nil) {
        self.scriptsDirectory = directory ?? Self.defaultScriptsDirectory()
        self.context = context
        ensureDirectoryExists(scriptsDirectory)
        loadManifest()
        reload()
        startWatching()
    }

    deinit {
        dispatchSource?.cancel()
    }

    static func defaultScriptsDirectory() -> URL {
        let appSupport = fileManager_default_appSupportDir()
        return appSupport.appendingPathComponent("UserScripts")
    }

    private static func fileManager_default_appSupportDir() -> URL {
        let fm = FileManager.default
        let bundleComponent = SumiAppIdentity.runtimeBundleIdentifier
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Fallback to Documents
            return fm.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent(bundleComponent, isDirectory: true)
        }
        return appSupport.appendingPathComponent(bundleComponent, isDirectory: true)
    }

    // MARK: - Public API

    /// Reload all scripts from disk.
    func reload() {
        loadManifest()
        scripts = loadAllScripts()
    }

    /// Return only scripts that match the given URL, sorted by weight (heavier first).
    func scriptsForURL(_ url: URL) -> [SumiInstalledUserScript] {
        let originKey = UserScriptOriginPolicy.originKey(from: url)
        let mode = effectiveRunMode
        let allowMap = manifest.originAllow ?? [:]
        let denyMap = manifest.originDeny ?? [:]
        return scripts
            .filter { script in
                guard UserScriptOriginPolicy.passesOriginGate(
                    runMode: mode,
                    filename: script.filename,
                    originKey: originKey,
                    originAllow: allowMap,
                    originDeny: denyMap
                ) else { return false }
                return UserScriptMatchEngine.shouldInject(script: script, into: url)
            }
            .sorted { $0.effectiveWeight > $1.effectiveWeight }
    }

    // MARK: - Run mode & origin rules

    var effectiveRunMode: UserScriptRunMode {
        manifest.runMode ?? .alwaysMatch
    }

    var runMode: UserScriptRunMode {
        get { effectiveRunMode }
        set {
            manifest.runMode = newValue == .alwaysMatch ? nil : newValue
            saveManifest()
        }
    }

    var lazyScriptBodyEnabled: Bool {
        get { manifest.settings["lazyScriptBody"] == "true" }
        set {
            manifest.settings["lazyScriptBody"] = newValue ? "true" : "false"
            saveManifest()
        }
    }

    /// `off`, `startup`, `hourly`, `daily`
    var autoUpdateInterval: String {
        get { manifest.settings["autoUpdateInterval"] ?? "off" }
        set {
            manifest.settings["autoUpdateInterval"] = newValue
            saveManifest()
        }
    }

    func isOriginAllowed(filename: String, for url: URL) -> Bool {
        let key = UserScriptOriginPolicy.originKey(from: url)
        return manifest.originAllow?[filename]?.contains(key) == true
    }

    func isOriginDenied(filename: String, for url: URL) -> Bool {
        let key = UserScriptOriginPolicy.originKey(from: url)
        return manifest.originDeny?[filename]?.contains(key) == true
    }

    func setOriginAllow(_ allowed: Bool, filename: String, for url: URL) {
        let key = UserScriptOriginPolicy.originKey(from: url)
        guard !key.isEmpty else { return }
        if manifest.originAllow == nil { manifest.originAllow = [:] }
        if manifest.originDeny == nil { manifest.originDeny = [:] }
        var allow = manifest.originAllow![filename] ?? []
        var deny = manifest.originDeny![filename] ?? []
        if allowed {
            if !allow.contains(key) { allow.append(key) }
            deny.removeAll { $0 == key }
        } else {
            allow.removeAll { $0 == key }
        }
        if allow.isEmpty {
            manifest.originAllow!.removeValue(forKey: filename)
        } else {
            manifest.originAllow![filename] = allow
        }
        if deny.isEmpty {
            manifest.originDeny!.removeValue(forKey: filename)
        } else {
            manifest.originDeny![filename] = deny
        }
        pruneEmptyOriginMaps()
        saveManifest()
    }

    func setOriginDeny(_ denied: Bool, filename: String, for url: URL) {
        let key = UserScriptOriginPolicy.originKey(from: url)
        guard !key.isEmpty else { return }
        if manifest.originAllow == nil { manifest.originAllow = [:] }
        if manifest.originDeny == nil { manifest.originDeny = [:] }
        var allow = manifest.originAllow![filename] ?? []
        var deny = manifest.originDeny![filename] ?? []
        if denied {
            if !deny.contains(key) { deny.append(key) }
            allow.removeAll { $0 == key }
        } else {
            deny.removeAll { $0 == key }
        }
        if allow.isEmpty {
            manifest.originAllow!.removeValue(forKey: filename)
        } else {
            manifest.originAllow![filename] = allow
        }
        if deny.isEmpty {
            manifest.originDeny!.removeValue(forKey: filename)
        } else {
            manifest.originDeny![filename] = deny
        }
        pruneEmptyOriginMaps()
        saveManifest()
    }

    func pruneEmptyOriginMaps() {
        manifest.originAllow = manifest.originAllow?.filter { !$0.value.isEmpty }
        if manifest.originAllow?.isEmpty == true { manifest.originAllow = nil }
        manifest.originDeny = manifest.originDeny?.filter { !$0.value.isEmpty }
        if manifest.originDeny?.isEmpty == true { manifest.originDeny = nil }
    }

    private func removeOriginRules(for filename: String) {
        manifest.originAllow?[filename] = nil
        manifest.originDeny?[filename] = nil
        pruneEmptyOriginMaps()
    }

    /// Toggle a script's enabled state.
    func setEnabled(_ enabled: Bool, for filename: String) {
        if enabled {
            manifest.disabled.removeAll { $0 == filename }
        } else {
            if !manifest.disabled.contains(filename) {
                manifest.disabled.append(filename)
            }
        }
        saveManifest()

        if let idx = scripts.firstIndex(where: { $0.filename == filename }) {
            scripts[idx].isEnabled = enabled
            persist(script: scripts[idx], sourceURL: scriptsDirectory.appendingPathComponent(filename))
        }
    }

    /// Install or update a userscript from a remote `.user.js` / `.user.css` URL.
    /// This performs network and resource work asynchronously before atomically
    /// writing the compiled source into the scripts directory.
    @discardableResult
    func installScript(from url: URL) async throws -> SumiInstalledUserScript {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let content = String(data: data, encoding: .utf8),
              let parsedMetadata = UserScriptMetadataParser.parse(content)
        else {
            throw SumiUserScriptError.invalidMetadata
        }

        let metadata = parsedMetadata.resolvingInstallURLs(from: url)
        let fileExtension = metadata.fileType == .css ? "user.css" : "user.js"
        let filename = "\(Self.sanitizeFilename("\(metadata.namespace ?? "")-\(metadata.name)")).\(fileExtension)"
        let localSourceURL = scriptsDirectory.appendingPathComponent(filename)

        ensureDirectoryExists(scriptsDirectory)
        try content.write(to: localSourceURL, atomically: true, encoding: .utf8)

        let scriptId = existingEntity(namespace: metadata.namespace ?? "", name: metadata.name)?.id ?? UUID()
        clearPersistedResources(for: scriptId)
        clearCachedResources(for: filename)
        let compatPreludes = UserScriptCompatAssembly.preludeFragments(for: metadata)
        let requiredCode = try await cacheRequiredResources(
            for: filename,
            scriptId: scriptId,
            requires: metadata.requires,
            installURL: url
        )
        let resourceData = try await cacheResources(
            for: filename,
            scriptId: scriptId,
            resources: metadata.resources,
            installURL: url
        )

        let script = SumiInstalledUserScript(
            id: scriptId,
            filename: filename,
            metadata: metadata,
            sourceFileURL: nil,
            isEnabled: true,
            compatPreludeFragments: compatPreludes,
            requiredCode: requiredCode,
            resourceData: resourceData
        )

        persist(script: script, sourceURL: localSourceURL)
        reload()
        onScriptsChanged?()
        return scripts.first(where: { $0.id == scriptId }) ?? script
    }

    func updateInstalledScripts() async {
        let candidates = scripts.compactMap { script -> URL? in
            guard script.isEnabled else { return nil }
            let urlString = script.metadata.updateURL ?? script.metadata.downloadURL
            return urlString.flatMap(URL.init(string:))
        }

        for url in candidates {
            do {
                _ = try await installScript(from: url)
            } catch {
                RuntimeDiagnostics.debug(
                    "Userscript update failed for \(url.absoluteString): \(error.localizedDescription)",
                    category: "SumiScripts"
                )
            }
        }
    }

    func delete(filename: String) {
        let url = scriptsDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
        manifest.disabled.removeAll { $0 == filename }
        removeOriginRules(for: filename)
        saveManifest()
        if let entity = contextEntity(filename: filename) {
            context?.delete(entity)
            try? context?.save()
        }
        reload()
        onScriptsChanged?()
    }

    // MARK: - File Loading

    private func loadAllScripts() -> [SumiInstalledUserScript] {
        ensureDirectoryExists(scriptsDirectory)

        guard let urls = try? fileManager.contentsOfDirectory(
            at: scriptsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        var result: [SumiInstalledUserScript] = []

        for url in urls {
            let filename = url.lastPathComponent

            // Only process .user.js, .user.css, .js, .css files
            guard filename.hasSuffix(".js") || filename.hasSuffix(".css") else {
                continue
            }

            guard let content = try? String(contentsOf: url, encoding: .utf8),
                  let parsedMeta = UserScriptMetadataParser.parse(content)
            else {
                continue
            }

            let isEnabled = !manifest.disabled.contains(filename)

            let compatPreludes = UserScriptCompatAssembly.preludeFragments(for: parsedMeta)
            let requiredCode = loadRequiredResources(for: filename, requires: parsedMeta.requires)

            // Load @resource resources
            let resourceData = loadResourceData(for: filename, resources: parsedMeta.resources)
            let id = existingEntity(namespace: parsedMeta.namespace ?? "", name: parsedMeta.name)?.id ?? UUID()

            let useLazyBody = lazyScriptBodyEnabled && parsedMeta.fileType == .javascript
            let storedMetadata = useLazyBody ? parsedMeta.replacingCode("") : parsedMeta
            let deferredURL: URL? = useLazyBody ? url : nil

            let script = SumiInstalledUserScript(
                id: id,
                filename: filename,
                metadata: storedMetadata,
                sourceFileURL: deferredURL,
                isEnabled: isEnabled,
                compatPreludeFragments: compatPreludes,
                requiredCode: requiredCode,
                resourceData: resourceData
            )
            persist(script: script, sourceURL: url)
            result.append(script)
        }

        return result
    }

    // MARK: - @require Resources

    private func loadRequiredResources(for filename: String, requires: [String]) -> [String] {
        guard !requires.isEmpty else { return [] }

        let scriptRequireDir = requireDirectory.appendingPathComponent(filename).appendingPathComponent("requires")
        ensureDirectoryExists(scriptRequireDir)

        var results: [String] = []

        for urlString in requires {
            if let bundled = UserScriptInternalRequireURL.content(from: urlString) {
                results.append(bundled)
                continue
            }
            let sanitizedName = Self.sanitizeFilename(urlString)
            let localFile = scriptRequireDir.appendingPathComponent(sanitizedName)

            if fileManager.fileExists(atPath: localFile.path),
               let content = try? String(contentsOf: localFile, encoding: .utf8)
            {
                results.append(content)
            }
        }

        return results
    }

    // MARK: - @resource Data

    private func loadResourceData(for filename: String, resources: [String: String]) -> [String: String] {
        guard !resources.isEmpty else { return [:] }

        let scriptResourceDir = requireDirectory.appendingPathComponent(filename).appendingPathComponent("resources")
        ensureDirectoryExists(scriptResourceDir)

        var result: [String: String] = [:]

        for (name, _) in resources {
            let sanitizedName = Self.sanitizeFilename(name)
            let localFile = scriptResourceDir.appendingPathComponent(sanitizedName)

            if fileManager.fileExists(atPath: localFile.path),
               let content = try? String(contentsOf: localFile, encoding: .utf8)
            {
                result[name] = content
            }
        }

        return result
    }

    private func cacheRequiredResources(
        for filename: String,
        scriptId: UUID,
        requires: [String],
        installURL: URL
    ) async throws -> [String] {
        guard requires.isEmpty == false else { return [] }
        let scriptRequireDir = requireDirectory.appendingPathComponent(filename).appendingPathComponent("requires")
        ensureDirectoryExists(scriptRequireDir)

        var result: [String] = []
        for urlString in requires {
            if let bundled = UserScriptInternalRequireURL.content(from: urlString) {
                let sanitizedName = Self.sanitizeFilename(urlString)
                let localFile = scriptRequireDir.appendingPathComponent(sanitizedName)
                let data = Data(bundled.utf8)
                try data.write(to: localFile, options: .atomic)
                if let internalURL = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    persistResource(
                        scriptId: scriptId,
                        kind: "require",
                        name: urlString,
                        sourceURL: internalURL,
                        localFile: localFile,
                        mimeType: "text/javascript",
                        data: data
                    )
                }
                result.append(bundled)
                continue
            }
            let url = try resolvedResourceURL(urlString, baseURL: installURL)
            let (data, response) = try await URLSession.shared.data(from: url)
            let content = String(data: data, encoding: .utf8) ?? ""
            let localFile = scriptRequireDir.appendingPathComponent(Self.sanitizeFilename(url.absoluteString))
            try data.write(to: localFile, options: .atomic)
            persistResource(
                scriptId: scriptId,
                kind: "require",
                name: url.absoluteString,
                sourceURL: url,
                localFile: localFile,
                mimeType: response.mimeType,
                data: data
            )
            result.append(content)
        }
        return result
    }

    private func cacheResources(
        for filename: String,
        scriptId: UUID,
        resources: [String: String],
        installURL: URL
    ) async throws -> [String: String] {
        guard resources.isEmpty == false else { return [:] }
        let scriptResourceDir = requireDirectory.appendingPathComponent(filename).appendingPathComponent("resources")
        ensureDirectoryExists(scriptResourceDir)

        var result: [String: String] = [:]
        for (name, urlString) in resources {
            let url = try resolvedResourceURL(urlString, baseURL: installURL)
            let (data, response) = try await URLSession.shared.data(from: url)
            let content = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
            let localFile = scriptResourceDir.appendingPathComponent(Self.sanitizeFilename(name))
            try data.write(to: localFile, options: .atomic)
            persistResource(
                scriptId: scriptId,
                kind: "resource",
                name: name,
                sourceURL: url,
                localFile: localFile,
                mimeType: response.mimeType,
                data: data
            )
            result[name] = content
        }
        return result
    }

    private func resolvedResourceURL(_ raw: String, baseURL: URL) throws -> URL {
        guard let resolved = URL(string: raw, relativeTo: baseURL)?.absoluteURL else {
            throw SumiUserScriptError.invalidResourceURL(raw)
        }
        guard ["http", "https"].contains(resolved.scheme?.lowercased()) else {
            throw SumiUserScriptError.invalidResourceURL(raw)
        }
        return resolved
    }

    // MARK: - Manifest

    private func loadManifest() {
        guard fileManager.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode(Manifest.self, from: data)
        else {
            manifest = .default
            saveManifest()
            return
        }
        manifest = decoded
        mergeLegacyManifestDefaults()
    }

    private func mergeLegacyManifestDefaults() {
        var s = manifest.settings
        for (k, v) in Manifest.default.settings where s[k] == nil {
            s[k] = v
        }
        manifest.settings = s
    }

    func saveManifest() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    // MARK: - FSEvents Watcher

    private func startWatching() {
        let fd = open(scriptsDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.reload()
                self?.onScriptsChanged?()
            }
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        source.resume()
        dispatchSource = source
    }

    private func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    // MARK: - Helpers

    private func ensureDirectoryExists(_ url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func sanitizeFilename(_ str: String) -> String {
        var s = str
        if s.first == "." {
            s = "%2" + s.dropFirst()
        }
        s = s.replacingOccurrences(of: "/", with: "%2F")
        s = s.replacingOccurrences(of: ":", with: "%3A")
        s = s.replacingOccurrences(of: "\\", with: "%5C")
        return s
    }

    private func clearCachedResources(for filename: String) {
        let directory = requireDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: directory)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func metadataSnapshotJSON(_ metadata: UserScriptMetadata) -> String {
        let snapshot: [String: Any] = [
            "name": metadata.name,
            "namespace": metadata.namespace ?? "",
            "version": metadata.version ?? "",
            "match": metadata.matches,
            "excludeMatch": metadata.excludeMatches,
            "include": metadata.includes,
            "exclude": metadata.excludes,
            "grant": metadata.grants,
            "connect": metadata.connects,
            "sumiCompat": metadata.sumiCompat,
            "require": metadata.requires,
            "resource": metadata.resources,
            "runAt": metadata.runAt.rawValue,
            "injectInto": metadata.injectInto.rawValue,
            "noframes": metadata.noframes,
            "unwrap": metadata.unwrap,
            "topLevelAwait": metadata.topLevelAwait
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }
}

enum SumiUserScriptError: LocalizedError {
    case invalidMetadata
    case invalidResourceURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidMetadata:
            return "The file does not contain a valid userscript metadata block."
        case .invalidResourceURL(let url):
            return "Invalid userscript resource URL: \(url)"
        }
    }
}

private extension UserScriptMetadata {
    func resolvingInstallURLs(from installURL: URL) -> UserScriptMetadata {
        UserScriptMetadata(
            name: name,
            description: description,
            namespace: namespace,
            version: version,
            author: author,
            icon: icon,
            homepageURL: homepageURL,
            downloadURL: downloadURL ?? installURL.absoluteString,
            updateURL: updateURL ?? downloadURL ?? installURL.absoluteString,
            supportURL: supportURL,
            license: license,
            sourceURL: sourceURL,
            antifeatures: antifeatures,
            matches: matches,
            excludeMatches: excludeMatches,
            includes: includes,
            excludes: excludes,
            runAt: runAt,
            injectInto: injectInto,
            grants: grants,
            requires: requires,
            sumiCompat: sumiCompat,
            connects: connects,
            noframes: noframes,
            unwrap: unwrap,
            topLevelAwait: topLevelAwait,
            weight: weight,
            resources: resources,
            localizedNames: localizedNames,
            localizedDescriptions: localizedDescriptions,
            fileType: fileType,
            metablock: metablock,
            code: code,
            rawMetadata: rawMetadata
        )
    }
}
