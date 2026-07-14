import CryptoKit
import Foundation

struct SumiSmokeStoreFixtureManifest: Decodable, Equatable {
    struct Provenance: Decodable, Equatable {
        let sourcePath: String
        let sourceFamily: String
        let sourceProvenance: String
        let copiedForUIOwnershipAt: String
    }

    struct FileEntry: Decodable, Equatable {
        let name: String
        let bytes: Int
        let sha256: String
    }

    let version: Int
    let family: String
    let provenance: Provenance
    let files: [FileEntry]
}

struct SumiSmokeStoreFixtureFamily {
    let resourceDirectoryURL: URL
    let manifestURL: URL
    let manifest: SumiSmokeStoreFixtureManifest

    var primaryStoreURL: URL {
        resourceDirectoryURL.appendingPathComponent("default.store", isDirectory: false)
    }

    var fileURLs: [URL] {
        manifest.files.map {
            resourceDirectoryURL.appendingPathComponent($0.name, isDirectory: false)
        }
    }

    func verifyIntegrity() throws {
        try verifyIntegrity(in: resourceDirectoryURL)
    }

    @discardableResult
    func copyVerifiedFamily(to directoryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let existingNames = try Set(
            fileManager.contentsOfDirectory(atPath: directoryURL.path)
                .filter { $0.hasPrefix("default.store") }
        )
        guard existingNames.isEmpty else {
            throw SumiSmokeStoreFixtureError.copyDestinationNotEmpty(directoryURL.path)
        }

        for entry in manifest.files {
            let sourceURL = resourceDirectoryURL.appendingPathComponent(entry.name)
            let targetURL = directoryURL.appendingPathComponent(entry.name)
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        }

        try verifyIntegrity(in: directoryURL)
        return directoryURL.appendingPathComponent("default.store", isDirectory: false)
    }

    func hashes(in directoryURL: URL? = nil) throws -> [String: String] {
        let directoryURL = directoryURL ?? resourceDirectoryURL
        return try Dictionary(uniqueKeysWithValues: manifest.files.map { entry in
            let url = directoryURL.appendingPathComponent(entry.name, isDirectory: false)
            return (entry.name, try Self.sha256(at: url))
        })
    }

    private func verifyIntegrity(in directoryURL: URL) throws {
        let fileManager = FileManager.default
        let actualNames = try Set(
            fileManager.contentsOfDirectory(atPath: directoryURL.path)
                .filter { $0.hasPrefix("default.store") }
        )
        let expectedNames = Set(manifest.files.map(\.name))
        guard actualNames == expectedNames else {
            throw SumiSmokeStoreFixtureError.familyMismatch(
                expected: expectedNames.sorted(),
                actual: actualNames.sorted(),
                directory: directoryURL.path
            )
        }

        for entry in manifest.files {
            let url = directoryURL.appendingPathComponent(entry.name, isDirectory: false)
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw SumiSmokeStoreFixtureError.invalidFile(entry.name, directoryURL.path)
            }
            guard values.fileSize == entry.bytes else {
                throw SumiSmokeStoreFixtureError.sizeMismatch(
                    file: entry.name,
                    expected: entry.bytes,
                    actual: values.fileSize,
                    directory: directoryURL.path
                )
            }

            let actualHash = try Self.sha256(at: url)
            guard actualHash == entry.sha256 else {
                throw SumiSmokeStoreFixtureError.hashMismatch(
                    file: entry.name,
                    expected: entry.sha256,
                    actual: actualHash,
                    directory: directoryURL.path
                )
            }
        }
    }

    private static func sha256(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum SumiSmokeStoreFixture {
    static let manifestFileName = "sumi-ui-smoke-store-manifest.json"
    static let expectedFamily = "sumi-ui-smoke-startup-swiftdata"
    static let expectedFileNames = [
        "default.store",
        "default.store-shm",
        "default.store-wal",
    ]

    static func resolveBundledFamily(
        bundle: Bundle = Bundle(for: SumiLaunchSmokeUITestCase.self)
    ) throws -> SumiSmokeStoreFixtureFamily {
        guard let resourceDirectoryURL = bundle.resourceURL else {
            throw SumiSmokeStoreFixtureError.missingBundleResources(bundle.bundlePath)
        }
        guard let manifestURL = bundle.url(
            forResource: "sumi-ui-smoke-store-manifest",
            withExtension: "json"
        ) else {
            throw SumiSmokeStoreFixtureError.missingManifest(
                resourceDirectoryURL.appendingPathComponent(manifestFileName).path
            )
        }
        return try resolveFamily(
            resourceDirectoryURL: resourceDirectoryURL,
            manifestURL: manifestURL
        )
    }

    static func resolveFamily(
        resourceDirectoryURL: URL
    ) throws -> SumiSmokeStoreFixtureFamily {
        try resolveFamily(
            resourceDirectoryURL: resourceDirectoryURL,
            manifestURL: resourceDirectoryURL.appendingPathComponent(manifestFileName)
        )
    }

    private static func resolveFamily(
        resourceDirectoryURL: URL,
        manifestURL: URL
    ) throws -> SumiSmokeStoreFixtureFamily {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw SumiSmokeStoreFixtureError.missingManifest(manifestURL.path)
        }

        let manifest: SumiSmokeStoreFixtureManifest
        do {
            manifest = try JSONDecoder().decode(
                SumiSmokeStoreFixtureManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw SumiSmokeStoreFixtureError.invalidManifest(manifestURL.path, error.localizedDescription)
        }

        guard manifest.version == 1,
              manifest.family == expectedFamily,
              manifest.files.map(\.name) == expectedFileNames,
              Set(manifest.files.map(\.name)).count == expectedFileNames.count
        else {
            throw SumiSmokeStoreFixtureError.invalidManifest(
                manifestURL.path,
                "expected version 1, family \(expectedFamily), and exact ordered files \(expectedFileNames)"
            )
        }

        let family = SumiSmokeStoreFixtureFamily(
            resourceDirectoryURL: resourceDirectoryURL,
            manifestURL: manifestURL,
            manifest: manifest
        )
        try family.verifyIntegrity()
        return family
    }
}

enum SumiSmokeStoreFixtureError: LocalizedError {
    case missingBundleResources(String)
    case missingManifest(String)
    case invalidManifest(String, String)
    case familyMismatch(expected: [String], actual: [String], directory: String)
    case invalidFile(String, String)
    case sizeMismatch(file: String, expected: Int, actual: Int?, directory: String)
    case hashMismatch(file: String, expected: String, actual: String, directory: String)
    case copyDestinationNotEmpty(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleResources(let bundlePath):
            "UI smoke fixture bundle has no resource directory: \(bundlePath)"
        case .missingManifest(let path):
            "UI smoke fixture manifest is missing at \(path); rebuild SumiUITests with its Fixtures resources"
        case .invalidManifest(let path, let reason):
            "UI smoke fixture manifest is invalid at \(path): \(reason)"
        case .familyMismatch(let expected, let actual, let directory):
            "UI smoke fixture family is partial or unexpected in \(directory); expected \(expected), found \(actual)"
        case .invalidFile(let file, let directory):
            "UI smoke fixture \(file) in \(directory) must be a regular, non-symlink file"
        case .sizeMismatch(let file, let expected, let actual, let directory):
            "UI smoke fixture \(file) in \(directory) has \(actual.map(String.init) ?? "unknown") bytes; expected \(expected)"
        case .hashMismatch(let file, let expected, let actual, let directory):
            "UI smoke fixture \(file) in \(directory) has SHA-256 \(actual); expected \(expected)"
        case .copyDestinationNotEmpty(let path):
            "UI smoke scratch destination already contains a default.store family: \(path)"
        }
    }
}
