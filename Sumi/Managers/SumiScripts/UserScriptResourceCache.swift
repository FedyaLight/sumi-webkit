import Foundation
import OSLog

struct UserScriptCachedResourceRecord {
    let scriptId: UUID
    let kind: String
    let name: String
    let sourceURL: URL
    let localFile: URL
    let mimeType: String?
    let data: Data
}

@MainActor
final class UserScriptResourceCache {
    struct Dependencies {
        let scriptsDirectory: @MainActor () -> URL
        let persistResource: @MainActor (UserScriptCachedResourceRecord) -> Void
    }

    private static let log = Logger.sumi(category: "SumiScripts")

    private let dependencies: Dependencies
    private let fileManager: FileManager
    private let session: URLSession

    init(
        dependencies: Dependencies,
        fileManager: FileManager = .default,
        session: URLSession = SumiNonPersistentURLSession.shared
    ) {
        self.dependencies = dependencies
        self.fileManager = fileManager
        self.session = session
    }

    func loadRequiredResources(for filename: String, requires: [String]) -> [String] {
        guard !requires.isEmpty else { return [] }

        let scriptRequireDir = cacheDirectory(for: filename, kind: "requires")
        ensureDirectoryExists(scriptRequireDir)

        var results: [String] = []

        for urlString in requires {
            if let bundled = UserScriptInternalRequireURL.content(from: urlString) {
                results.append(bundled)
                continue
            }
            let sanitizedName = UserScriptStore.sanitizeFilename(urlString)
            let localFile = scriptRequireDir.appendingPathComponent(sanitizedName)

            if fileManager.fileExists(atPath: localFile.path),
               let content = readCachedTextFile(localFile, description: "userscript @require cache") {
                results.append(content)
            }
        }

        return results
    }

    func loadResourceData(for filename: String, resources: [String: String]) -> [String: String] {
        guard !resources.isEmpty else { return [:] }

        let scriptResourceDir = cacheDirectory(for: filename, kind: "resources")
        ensureDirectoryExists(scriptResourceDir)

        var result: [String: String] = [:]

        for (name, _) in resources {
            let sanitizedName = UserScriptStore.sanitizeFilename(name)
            let localFile = scriptResourceDir.appendingPathComponent(sanitizedName)

            if fileManager.fileExists(atPath: localFile.path),
               let content = readCachedTextFile(localFile, description: "userscript @resource cache") {
                result[name] = content
            }
        }

        return result
    }

    func cacheRequiredResources(
        for filename: String,
        scriptId: UUID,
        requires: [String],
        installURL: URL
    ) async throws -> [String] {
        guard requires.isEmpty == false else { return [] }
        let scriptRequireDir = cacheDirectory(for: filename, kind: "requires")
        ensureDirectoryExists(scriptRequireDir)

        var result: [String] = []
        for urlString in requires {
            if let bundled = UserScriptInternalRequireURL.content(from: urlString) {
                let sanitizedName = UserScriptStore.sanitizeFilename(urlString)
                let localFile = scriptRequireDir.appendingPathComponent(sanitizedName)
                let data = Data(bundled.utf8)
                try data.write(to: localFile, options: .atomic)
                if let internalURL = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    dependencies.persistResource(
                        UserScriptCachedResourceRecord(
                            scriptId: scriptId,
                            kind: "require",
                            name: urlString,
                            sourceURL: internalURL,
                            localFile: localFile,
                            mimeType: "text/javascript",
                            data: data
                        )
                    )
                }
                result.append(bundled)
                continue
            }
            let url = try resolvedResourceURL(urlString, baseURL: installURL)
            let (data, response) = try await session.data(from: url)
            let content = String(data: data, encoding: .utf8) ?? ""
            let localFile = scriptRequireDir.appendingPathComponent(
                UserScriptStore.sanitizeFilename(url.absoluteString)
            )
            try data.write(to: localFile, options: .atomic)
            dependencies.persistResource(
                UserScriptCachedResourceRecord(
                    scriptId: scriptId,
                    kind: "require",
                    name: url.absoluteString,
                    sourceURL: url,
                    localFile: localFile,
                    mimeType: response.mimeType,
                    data: data
                )
            )
            result.append(content)
        }
        return result
    }

    func cacheResources(
        for filename: String,
        scriptId: UUID,
        resources: [String: String],
        installURL: URL
    ) async throws -> [String: String] {
        guard resources.isEmpty == false else { return [:] }
        let scriptResourceDir = cacheDirectory(for: filename, kind: "resources")
        ensureDirectoryExists(scriptResourceDir)

        var result: [String: String] = [:]
        for (name, urlString) in resources {
            let url = try resolvedResourceURL(urlString, baseURL: installURL)
            let (data, response) = try await session.data(from: url)
            let content = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
            let localFile = scriptResourceDir.appendingPathComponent(
                UserScriptStore.sanitizeFilename(name)
            )
            try data.write(to: localFile, options: .atomic)
            dependencies.persistResource(
                UserScriptCachedResourceRecord(
                    scriptId: scriptId,
                    kind: "resource",
                    name: name,
                    sourceURL: url,
                    localFile: localFile,
                    mimeType: response.mimeType,
                    data: data
                )
            )
            result[name] = content
        }
        return result
    }

    func clearCachedResources(for filename: String) {
        let directory = requireDirectory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            Self.log.error(
                "Failed to remove userscript resource cache at \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private var requireDirectory: URL {
        dependencies.scriptsDirectory().appendingPathComponent("require")
    }

    private func cacheDirectory(for filename: String, kind: String) -> URL {
        requireDirectory
            .appendingPathComponent(filename)
            .appendingPathComponent(kind)
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

    private func ensureDirectoryExists(_ url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                Self.log.error(
                    "Failed to create userscript resource cache directory at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func readCachedTextFile(_ url: URL, description: String) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            Self.log.error(
                "Failed to read \(description, privacy: .public) at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}

@MainActor
extension UserScriptResourceCache.Dependencies {
    static func live(store: UserScriptStore) -> Self {
        Self(
            scriptsDirectory: { [weak store] in
                store?.scriptsDirectory ?? UserScriptStore.defaultScriptsDirectory()
            },
            persistResource: { [weak store] record in
                store?.persistResource(
                    scriptId: record.scriptId,
                    kind: record.kind,
                    name: record.name,
                    sourceURL: record.sourceURL,
                    localFile: record.localFile,
                    mimeType: record.mimeType,
                    data: record.data
                )
            }
        )
    }
}
