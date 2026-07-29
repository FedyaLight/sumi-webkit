import AppKit
import Foundation

enum SumiBrowserFamily: String, Codable, Sendable {
    case arc
    case zen
    case chromium
    case firefox
    case safari
}

enum SumiImportSourceCapability: String, Codable, Hashable, Sendable {
    case structure
    case bookmarks
    case history
    case favicons
    case cookies
}

/// Why a detected browser cannot be imported right now. Each case names a
/// remedy the user can actually act on.
enum SumiBrowserAccessIssue: Equatable, Sendable {
    case fullDiskAccessRequired
    case sourceBrowserRunning(String)
    case noProfilesFound
    case unreadable(String)
}

struct SumiDetectedBrowserProfile: Identifiable, Equatable, Sendable {
    var id: String
    var displayName: String
    var directoryURL: URL
    /// Join key for bulk (history/cookies/favicon) extraction.
    var sourceDirectoryKey: String
}

struct SumiDetectedBrowser: Identifiable, Equatable, Sendable {
    var id: String
    var displayName: String
    var family: SumiBrowserFamily
    var sourceKind: SumiImportSourceKind
    var dataRoot: URL
    var bundleIdentifiers: [String]
    var capabilities: Set<SumiImportSourceCapability>
    var profiles: [SumiDetectedBrowserProfile]
    var accessIssue: SumiBrowserAccessIssue?

    var isImportable: Bool {
        switch accessIssue {
        case .none, .sourceBrowserRunning:
            return true
        case .fullDiskAccessRequired, .noProfilesFound, .unreadable:
            return false
        }
    }
}

/// Locates installed applications. Injected so detection is testable without
/// depending on what happens to be installed.
protocol SumiInstalledApplicationLocating: Sendable {
    func isInstalled(bundleIdentifier: String) -> Bool
    func isRunning(bundleIdentifier: String) -> Bool
}

struct SumiWorkspaceApplicationLocator: SumiInstalledApplicationLocating {
    func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    func isRunning(bundleIdentifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }
}

/// The single authority on which browsers Sumi can import from.
///
/// Detection deliberately does not rely on data files alone. Safari's data
/// lives behind Full Disk Access, so a pure `fileExists` check reports "Safari
/// is not installed" on every Mac that has not granted it — the user is told
/// the wrong thing and given nothing to fix. Presence is therefore established
/// from the installed application, and unreadable data becomes an access issue
/// carrying its remedy.
enum SumiBrowserSourceCatalog {
    struct Vendor {
        var id: String
        var displayName: String
        var family: SumiBrowserFamily
        var sourceKind: SumiImportSourceKind
        var bundleIdentifiers: [String]
        var relativeDataPath: String
        var capabilities: Set<SumiImportSourceCapability>
    }

    static let vendors: [Vendor] = [
        Vendor(
            id: "arc",
            displayName: "Arc",
            family: .arc,
            sourceKind: .arc,
            bundleIdentifiers: ["company.thebrowser.Browser"],
            relativeDataPath: "Library/Application Support/Arc",
            capabilities: [.structure, .bookmarks, .history, .favicons, .cookies]
        ),
        Vendor(
            id: "zen",
            displayName: "Zen",
            family: .zen,
            sourceKind: .zen,
            bundleIdentifiers: ["app.zen-browser.zen", "org.mozilla.zen"],
            relativeDataPath: "Library/Application Support/zen",
            capabilities: [.structure, .bookmarks, .history, .favicons, .cookies]
        ),
        chromium("chrome", "Google Chrome", ["com.google.Chrome"], "Google/Chrome"),
        chromium("chrome-beta", "Chrome Beta", ["com.google.Chrome.beta"], "Google/Chrome Beta"),
        chromium("chrome-canary", "Chrome Canary", ["com.google.Chrome.canary"], "Google/Chrome Canary"),
        chromium("chromium", "Chromium", ["org.chromium.Chromium"], "Chromium"),
        chromium("edge", "Microsoft Edge", ["com.microsoft.edgemac"], "Microsoft Edge"),
        chromium("brave", "Brave", ["com.brave.Browser"], "BraveSoftware/Brave-Browser"),
        chromium("vivaldi", "Vivaldi", ["com.vivaldi.Vivaldi"], "Vivaldi"),
        chromium("opera", "Opera", ["com.operasoftware.Opera"], "com.operasoftware.Opera"),
        chromium("opera-gx", "Opera GX", ["com.operasoftware.OperaGX"], "com.operasoftware.OperaGX"),
        chromium("yandex", "Yandex", ["ru.yandex.desktop.yandex-browser"], "Yandex/YandexBrowser"),
        Vendor(
            id: "firefox",
            displayName: "Firefox",
            family: .firefox,
            sourceKind: .firefox,
            bundleIdentifiers: ["org.mozilla.firefox"],
            relativeDataPath: "Library/Application Support/Firefox",
            capabilities: [.structure, .bookmarks, .history, .favicons, .cookies]
        ),
        Vendor(
            id: "safari",
            displayName: "Safari",
            family: .safari,
            sourceKind: .safari,
            bundleIdentifiers: ["com.apple.Safari"],
            relativeDataPath: "Library/Safari",
            capabilities: [.structure, .bookmarks, .history, .cookies]
        ),
    ]

    private static func chromium(
        _ id: String,
        _ displayName: String,
        _ bundleIdentifiers: [String],
        _ supportPath: String
    ) -> Vendor {
        Vendor(
            id: id,
            displayName: displayName,
            family: .chromium,
            sourceKind: .chromium,
            bundleIdentifiers: bundleIdentifiers,
            relativeDataPath: "Library/Application Support/\(supportPath)",
            capabilities: [.structure, .bookmarks, .history, .favicons, .cookies]
        )
    }

    static func detect(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applications: any SumiInstalledApplicationLocating = SumiWorkspaceApplicationLocator()
    ) -> [SumiDetectedBrowser] {
        vendors.compactMap { vendor in
            detect(vendor: vendor, homeDirectory: homeDirectory, applications: applications)
        }
    }

    static func detect(
        vendor: Vendor,
        homeDirectory: URL,
        applications: any SumiInstalledApplicationLocating
    ) -> SumiDetectedBrowser? {
        let dataRoot = homeDirectory.appendingPathComponent(vendor.relativeDataPath, isDirectory: true)
        let isInstalled = vendor.bundleIdentifiers.contains(where: applications.isInstalled)
        let hasData = FileManager.default.fileExists(atPath: dataRoot.path)
        guard isInstalled || hasData else { return nil }

        let running = vendor.bundleIdentifiers.first(where: applications.isRunning)
        let discovery = profiles(vendor: vendor, dataRoot: dataRoot)
        var issue = discovery.issue
        if issue == nil, discovery.profiles.isEmpty {
            // An uninstalled browser whose leftover support folder holds nothing
            // importable is not worth showing — listing it as broken invites the
            // user to fix something they do not have.
            guard isInstalled else { return nil }
            issue = .noProfilesFound
        }
        // A running browser is importable — its databases are snapshotted with
        // their write-ahead logs — but its newest state may not be on disk yet.
        if issue == nil, running != nil {
            issue = .sourceBrowserRunning(vendor.displayName)
        }

        return SumiDetectedBrowser(
            id: vendor.id,
            displayName: vendor.displayName,
            family: vendor.family,
            sourceKind: vendor.sourceKind,
            dataRoot: dataRoot,
            bundleIdentifiers: vendor.bundleIdentifiers,
            capabilities: vendor.capabilities,
            profiles: discovery.profiles,
            accessIssue: issue
        )
    }

    private static func profiles(
        vendor: Vendor,
        dataRoot: URL
    ) -> (profiles: [SumiDetectedBrowserProfile], issue: SumiBrowserAccessIssue?) {
        switch vendor.family {
        case .arc:
            let sidebar = dataRoot.appendingPathComponent("StorableSidebar.json")
            guard FileManager.default.fileExists(atPath: sidebar.path) else {
                return ([], .noProfilesFound)
            }
            // Arc's spaces span its Chromium profiles; the import is always
            // whole-sidebar, so it presents as a single selectable source.
            return ([
                SumiDetectedBrowserProfile(
                    id: "arc|default",
                    displayName: "All spaces",
                    directoryURL: dataRoot,
                    sourceDirectoryKey: "Default"
                ),
            ], nil)

        case .chromium:
            let found = SumiChromiumProfileCatalogReader.profiles(userDataURL: dataRoot)
            return (found.map { profile in
                SumiDetectedBrowserProfile(
                    id: "\(vendor.id)|\(profile.directoryName)",
                    displayName: profile.displayName,
                    directoryURL: profile.directoryURL,
                    sourceDirectoryKey: profile.directoryName
                )
            }, nil)

        case .firefox, .zen:
            // Both are Mozilla layouts: `profiles.ini` at the root, or failing
            // that a `Profiles/` directory of folders holding `places.sqlite`.
            return (SumiFirefoxImportParser.profiles(rootURL: dataRoot).map { profile in
                SumiDetectedBrowserProfile(
                    id: "\(vendor.id)|\(profile.directoryName)",
                    displayName: profile.displayName,
                    directoryURL: profile.directoryURL,
                    sourceDirectoryKey: profile.directoryName
                )
            }, nil)

        case .safari:
            // Reading, not `fileExists`, is what distinguishes "absent" from
            // "protected": under TCC the directory listing itself fails.
            do {
                _ = try FileManager.default.contentsOfDirectory(
                    at: dataRoot,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            } catch {
                if SumiSafariImportParser.isPermissionError(error) {
                    return ([], .fullDiskAccessRequired)
                }
                return ([], .unreadable(error.localizedDescription))
            }
            return ([
                SumiDetectedBrowserProfile(
                    id: "safari|default",
                    displayName: "Safari",
                    directoryURL: dataRoot,
                    sourceDirectoryKey: "default"
                ),
            ], nil)
        }
    }
}
