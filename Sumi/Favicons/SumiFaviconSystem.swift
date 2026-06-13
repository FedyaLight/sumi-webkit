import Darwin
import Foundation

enum SumiFaviconLookupKey {
    static func cacheKey(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }

        if let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty
        {
            return host.lowercased()
        }

        let absoluteString = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return absoluteString.isEmpty ? nil : absoluteString.lowercased()
    }

    static func documentURL(for key: String) -> URL? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let explicitURL = URL(string: trimmed),
           let scheme = explicitURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https"
        {
            return explicitURL
        }

        return URL(string: "https://\(trimmed)")
    }
}

@MainActor
private enum SumiFaviconPersistence {
    private static var didRegisterTestDirectoryCleanup = false

    static func rootDirectoryURL() -> URL {
        if RuntimeDiagnostics.isRunningTests {
            removeStaleTestDirectories()
            registerCurrentTestDirectoryCleanupIfNeeded()
            let testURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("SumiFavicons-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            try? FileManager.default.createDirectory(at: testURL, withIntermediateDirectories: true)
            return testURL
        }

        if let overridePath = ProcessInfo.processInfo.environment["SUMI_APP_SUPPORT_OVERRIDE"],
           !overridePath.isEmpty
        {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
            try? FileManager.default.createDirectory(at: overrideURL, withIntermediateDirectories: true)
            return overrideURL
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleDirectory = appSupport.appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        return bundleDirectory
    }

    static func directory(named component: String) -> URL {
        let directory = rootDirectoryURL().appendingPathComponent(component, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func removeStaleTestDirectories() {
        let fileManager = FileManager.default
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        for directory in contents {
            let prefix = "SumiFavicons-"
            let name = directory.lastPathComponent
            guard name.hasPrefix(prefix),
                  let pid = Int32(name.dropFirst(prefix.count)),
                  pid != currentPID,
                  !isProcessRunning(pid)
            else {
                continue
            }
            try? fileManager.removeItem(at: directory)
        }
    }

    private static func isProcessRunning(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func registerCurrentTestDirectoryCleanupIfNeeded() {
        guard !didRegisterTestDirectoryCleanup else { return }
        didRegisterTestDirectoryCleanup = true
        atexit {
            SumiFaviconPersistence.removeCurrentTestDirectory()
        }
    }

    private static func removeCurrentTestDirectory() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SumiFavicons-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
final class SumiFaviconSystem {
    static let shared = SumiFaviconSystem()

    let service: SumiFaviconService
    private var bookmarkHosts: Set<String> = []

    private init() {
        service = SumiFaviconService(
            rootDirectory: SumiFaviconPersistence.directory(named: "Favicons/v2")
        )
    }

    func syncShortcutPins(_ pins: [ShortcutPin]) {
        let hosts = Set(pins.compactMap { $0.launchURL.host?.lowercased() })
        bookmarkHosts.formUnion(hosts)
        for pin in pins {
            service.scheduleColdFetch(
                for: pin.launchURL,
                partition: .regular(pin.executionProfileId),
                priority: .pinnedLauncher
            )
        }
    }

    func syncBookmarks(
        _ bookmarks: [SumiBookmark],
        partition: SumiFaviconPartition = .regular(nil)
    ) {
        let hosts = Set(bookmarks.compactMap { $0.url.host?.lowercased() })
        bookmarkHosts.formUnion(hosts)
        for bookmark in bookmarks {
            service.scheduleColdFetch(
                for: bookmark.url,
                partition: partition,
                priority: .backgroundPrefetch
            )
        }
    }

    func invalidateSite(domain: String, profile: Profile?) {
        service.invalidateSite(
            domain: domain,
            partition: partition(profile: profile)
        )
    }

    func clearFaviconPartition(for profile: Profile) {
        service.clearPartition(partition(profile: profile))
    }

    func burnAfterHistoryClear(savedLogins: Set<String>) async {
        service.burnAfterHistoryClear(
            savedLogins: savedLogins,
            bookmarkHosts: bookmarkHosts
        )
    }

    func burnDomains(
        _ domains: Set<String>,
        remainingHistoryHosts: Set<String>,
        savedLogins: Set<String>
    ) async {
        service.burnDomains(
            domains,
            remainingHistoryHosts: remainingHistoryHosts,
            savedLogins: savedLogins,
            bookmarkHosts: bookmarkHosts
        )
    }

    func partition(profile: Profile?) -> SumiFaviconPartition {
        guard let profile else { return .regular(nil) }
        return profile.isEphemeral
            ? .privateEphemeral(profile.id)
            : .regular(profile.id)
    }

    func invalidateSite(domain: String, partition: SumiFaviconPartition) {
        service.invalidateSite(domain: domain, partition: partition)
    }
}
