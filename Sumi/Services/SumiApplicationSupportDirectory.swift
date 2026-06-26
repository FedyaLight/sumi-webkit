import Foundation
import OSLog

enum SumiApplicationSupportDirectory {
    private static let log = Logger.sumi(category: "ApplicationSupportDirectory")
    private static let overrideEnvironmentKey = "SUMI_APP_SUPPORT_OVERRIDE"

    static func appRootURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment[overrideEnvironmentKey],
           !overridePath.isEmpty
        {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
            createDirectory(overrideURL, description: "overridden Application Support directory")
            return overrideURL
        }

        let fileManager = FileManager.default
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
        createDirectory(appURL, description: "Application Support directory")
        return appURL
    }

    private static func createDirectory(_ directory: URL, description: String) {
        do {
            try FileManager.default.createDirectory(
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
