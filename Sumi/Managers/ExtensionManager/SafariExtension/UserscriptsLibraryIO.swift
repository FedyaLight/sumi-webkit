import Foundation

struct UserscriptsLibraryLocation {
    let scriptsURL: URL
    let stateRootURL: URL

    var requiredResourcesRootURL: URL {
        stateRootURL.appendingPathComponent("require", isDirectory: true)
    }

    var manifestURL: URL {
        stateRootURL.appendingPathComponent("manifest.json", isDirectory: false)
    }
}

/// Owns filesystem access, path confinement, and durable manifest encoding.
struct UserscriptsLibraryRepository {
    private let fileManager: FileManager
    private let metadata: UserscriptsMetadataPolicy

    init(
        fileManager: FileManager = .default,
        metadata: UserscriptsMetadataPolicy = UserscriptsMetadataPolicy()
    ) {
        self.fileManager = fileManager
        self.metadata = metadata
    }

    func prepare(_ location: UserscriptsLibraryLocation) throws {
        try fileManager.createDirectory(
            at: location.stateRootURL,
            withIntermediateDirectories: true
        )
        try withSecurityScope(for: location.scriptsURL) {
            try fileManager.createDirectory(
                at: location.scriptsURL,
                withIntermediateDirectories: true
            )
        }
        try fileManager.createDirectory(
            at: location.requiredResourcesRootURL,
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: location.manifestURL.path) == false {
            try writeManifest(
                UserscriptsLibraryManifest(),
                at: location.stateRootURL
            )
        }
    }

    func files(in scriptsURL: URL) throws -> [UserscriptLibraryFile] {
        try withSecurityScope(for: scriptsURL) {
            let keys: Set<URLResourceKey> = [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .contentModificationDateKey,
            ]
            return try fileManager.contentsOfDirectory(
                at: scriptsURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ).compactMap { url in
                do {
                    let filename = url.lastPathComponent
                    guard metadata.isAllowedFilename(filename) else { return nil }
                    let values = try url.resourceValues(forKeys: keys)
                    let content = try String(
                        contentsOf: url,
                        encoding: .utf8
                    )
                    guard values.isRegularFile == true,
                          values.isSymbolicLink != true,
                          let parsed = metadata.parse(content: content),
                          let type = metadata.fileType(filename)
                    else { return nil }
                    return UserscriptLibraryFile(
                        url: url,
                        filename: filename,
                        type: type,
                        content: content,
                        code: parsed.code,
                        metablock: parsed.metablock,
                        metadata: parsed.metadata,
                        modifiedAt: values.contentModificationDate ?? .distantPast
                    )
                } catch {
                    return nil
                }
            }.sorted {
                $0.filename.localizedCaseInsensitiveCompare($1.filename)
                    == .orderedAscending
            }
        }
    }

    func manifest(at stateRootURL: URL) -> UserscriptsLibraryManifest {
        let manifestURL = stateRootURL.appendingPathComponent(
            "manifest.json",
            isDirectory: false
        )
        let decoded: UserscriptsLibraryManifest
        do {
            decoded = try JSONDecoder().decode(
                UserscriptsLibraryManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            return UserscriptsLibraryManifest()
        }
        var manifest = decoded
        for (key, value) in UserscriptsLibraryManifest.defaultSettings
            where manifest.settings[key] == nil {
            manifest.settings[key] = value
        }
        return manifest
    }

    func writeManifest(
        _ manifest: UserscriptsLibraryManifest,
        at stateRootURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: stateRootURL.appendingPathComponent(
                "manifest.json",
                isDirectory: false
            ),
            options: [.atomic]
        )
    }

    func scriptURL(
        named filename: String,
        in scriptsURL: URL,
        mustExist: Bool
    ) throws -> URL {
        guard metadata.isAllowedFilename(filename),
              URL(fileURLWithPath: filename).lastPathComponent == filename else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let scriptsRoot = scriptsURL.standardizedFileURL
        let resolvedRoot = scriptsRoot.resolvingSymlinksInPath()
        let candidate = scriptsRoot
            .appendingPathComponent(filename)
            .standardizedFileURL
        guard candidate.deletingLastPathComponent() == scriptsRoot else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        if mustExist {
            let resolved = candidate.resolvingSymlinksInPath()
            guard resolved.deletingLastPathComponent() == resolvedRoot,
                  fileManager.fileExists(atPath: resolved.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
        }
        return candidate
    }

    func writeScript(
        _ content: String,
        to destination: URL,
        replacing oldFilename: String?,
        in scriptsURL: URL
    ) throws {
        try withSecurityScope(for: scriptsURL) {
            try Data(content.utf8).write(to: destination, options: [.atomic])
            guard let oldFilename,
                  oldFilename.caseInsensitiveCompare(destination.lastPathComponent)
                    != .orderedSame else { return }
            do {
                let oldURL = try scriptURL(
                    named: oldFilename,
                    in: scriptsURL,
                    mustExist: true
                )
                try fileManager.trashItem(at: oldURL, resultingItemURL: nil)
            } catch {
                // A newly-created editor item has no old file.
            }
        }
    }

    func replaceScript(
        _ content: String,
        at url: URL,
        scriptsURL: URL
    ) throws {
        try withSecurityScope(for: scriptsURL) {
            try Data(content.utf8).write(to: url, options: [.atomic])
        }
    }

    func trashScript(named filename: String, in scriptsURL: URL) throws {
        let url = try scriptURL(named: filename, in: scriptsURL, mustExist: false)
        try withSecurityScope(for: scriptsURL) {
            guard fileManager.fileExists(atPath: url.path) else { return }
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        }
    }

    func requiredResourceURL(
        named resourceName: String,
        for filename: String,
        stateRootURL: URL
    ) -> URL {
        stateRootURL
            .appendingPathComponent("require", isDirectory: true)
            .appendingPathComponent(
                metadata.sanitizeFilename(filename),
                isDirectory: true
            )
            .appendingPathComponent(resourceName, isDirectory: false)
    }

    func ensureDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }

    func stringIfPresent(at url: URL) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func children(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]? = nil
    ) -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
    }

    func removeIfPresent(_ url: URL) {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            return
        }
    }

    private func withSecurityScope<T>(
        for url: URL,
        _ body: () throws -> T
    ) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}

/// Owns HTTP validation, payload limits, and cancellation semantics.
actor UserscriptsRemoteContentLoader {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func string(from url: URL) async throws -> String {
        let data = try await data(from: url)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return string
    }

    func stringIfAvailable(from url: URL) async -> String? {
        do {
            return try await string(from: url)
        } catch {
            return nil
        }
    }

    func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              data.count <= 16 * 1_024 * 1_024 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    func cancelAll() async {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                tasks.forEach { $0.cancel() }
                continuation.resume()
            }
        }
    }
}
