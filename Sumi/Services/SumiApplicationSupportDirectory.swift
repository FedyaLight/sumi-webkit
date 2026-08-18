import Foundation
import OSLog

enum SumiApplicationSupportDirectory {
    private static let log = Logger.sumi(category: "ApplicationSupportDirectory")
    private static let overrideEnvironmentKey = "SUMI_APP_SUPPORT_OVERRIDE"

    static func appRootURL(fileManager: FileManager = .default) -> URL {
        if let overridePath = ProcessInfo.processInfo.environment[overrideEnvironmentKey],
           !overridePath.isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
            createDirectory(
                overrideURL,
                description: "overridden Application Support directory",
                fileManager: fileManager
            )
            return overrideURL
        }

        let baseURL: URL
        if let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            baseURL = applicationSupportURL
        } else {
            baseURL = fileManager.temporaryDirectory
            log.fault(
                "Application Support directory is unavailable. Falling back to temporary directory: \(baseURL.path, privacy: .public)"
            )
        }

        let appURL = baseURL.appendingPathComponent(
            SumiAppIdentity.runtimeBundleIdentifier,
            isDirectory: true
        )
        createDirectory(
            appURL,
            description: "Application Support directory",
            fileManager: fileManager
        )
        return appURL
    }

    static func cachesRootURL(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let appURL = baseURL.appendingPathComponent(
            SumiAppIdentity.runtimeBundleIdentifier,
            isDirectory: true
        )
        createDirectory(
            appURL,
            description: "Caches directory",
            fileManager: fileManager
        )
        return appURL
    }

    /// Moves one pre-canonical directory atomically when the destination is
    /// still absent. Test and Debug identities never touch production legacy data.
    static func migrateLegacyDirectoryIfNeeded(
        from legacyURL: URL,
        to canonicalURL: URL,
        fileManager: FileManager = .default,
        allowsMigration: Bool = SumiAppIdentity.runtimeBundleIdentifier
            == SumiAppIdentity.bundleIdentifier
    ) -> URL {
        guard allowsMigration,
            fileManager.fileExists(atPath: canonicalURL.path) == false,
            fileManager.fileExists(atPath: legacyURL.path)
        else {
            return canonicalURL
        }

        do {
            try fileManager.createDirectory(
                at: canonicalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: legacyURL, to: canonicalURL)
            return canonicalURL
        } catch {
            log.error(
                "Failed to migrate legacy storage directory from \(legacyURL.path, privacy: .public) to \(canonicalURL.path, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return legacyURL
        }
    }

    private static func createDirectory(
        _ directory: URL,
        description: String,
        fileManager: FileManager
    ) {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            log.error(
                "Failed to create \(description, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }
}
