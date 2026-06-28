//
//  SafariExtensionScanner.swift
//  Sumi
//
//  Discovers installed Safari Web Extensions packaged inside macOS .app bundles
//  without loading WKWebExtension runtime state.
//

import Foundation

/// Metadata for a Safari Web Extension discovered on disk. Not loaded into WebKit.
struct DiscoveredSafariExtensionCandidate: Identifiable, Equatable, Sendable {
    /// Stable identity for UI lists — the `.appex` bundle identifier.
    var id: String { extensionBundleIdentifier }

    let extensionBundleIdentifier: String
    let displayName: String
    let version: String?
    let extensionPointIdentifier: String
    let bundleKind: SafariExtensionBundleKind
    let runtimeStatus: SafariExtensionRuntimeStatus
    let containingAppName: String
    let containingAppBundleIdentifier: String?
    let containingAppURL: URL
    let appexURL: URL
    let manifestURL: URL?
    let isReadable: Bool

    init(
        extensionBundleIdentifier: String,
        displayName: String,
        version: String?,
        extensionPointIdentifier: String,
        bundleKind: SafariExtensionBundleKind = .webExtension,
        runtimeStatus: SafariExtensionRuntimeStatus = .webExtensionImportable,
        containingAppName: String,
        containingAppBundleIdentifier: String?,
        containingAppURL: URL,
        appexURL: URL,
        manifestURL: URL?,
        isReadable: Bool
    ) {
        self.extensionBundleIdentifier = extensionBundleIdentifier
        self.displayName = displayName
        self.version = version
        self.extensionPointIdentifier = extensionPointIdentifier
        self.bundleKind = bundleKind
        self.runtimeStatus = runtimeStatus
        self.containingAppName = containingAppName
        self.containingAppBundleIdentifier = containingAppBundleIdentifier
        self.containingAppURL = containingAppURL
        self.appexURL = appexURL
        self.manifestURL = manifestURL
        self.isReadable = isReadable
    }
}

enum SafariExtensionScannerIssue: Equatable, Sendable {
    case unreadableBundle(URL)
    case invalidExtensionPoint(URL, found: String?)
    case missingManifest(URL)
    case duplicateExtensionIdentifier(String)
}

/// Filesystem scanner for installed Safari Web Extensions.
struct SafariExtensionScanner {
    static let safariWebExtensionPointIdentifier = "com.apple.Safari.web-extension"
    static let safariContentBlockerExtensionPointIdentifier = "com.apple.Safari.content-blocker"
    static let legacySafariExtensionPointIdentifier = "com.apple.Safari.extension"

    private static let manifestRelativeCandidates = [
        "manifest.json",
        "Resources/manifest.json",
    ]

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Default install locations for user and system applications.
    static func defaultApplicationSearchRoots(
        fileManager: FileManager = .default
    ) -> [URL] {
        var roots: [URL] = []
        let domains: [FileManager.SearchPathDomainMask] = [
            .localDomainMask,
            .userDomainMask,
        ]
        for domain in domains {
            if let url = fileManager.urls(for: .applicationDirectory, in: domain).first {
                roots.append(url)
            }
        }
        var seen: Set<String> = []
        return roots.filter { seen.insert($0.path).inserted }
    }

    /// Scans application directories for Safari Web Extension `.appex` bundles.
    func scanInstalledExtensions(
        applicationSearchRoots: [URL]? = nil,
        includeUnsupported: Bool = false,
        issues: inout [SafariExtensionScannerIssue]
    ) -> [DiscoveredSafariExtensionCandidate] {
        let roots = applicationSearchRoots ?? Self.defaultApplicationSearchRoots(
            fileManager: fileManager
        )
        var candidates: [DiscoveredSafariExtensionCandidate] = []
        var seenExtensionIDs: [String: URL] = [:]

        for root in roots {
            guard let appURLs = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for appURL in appURLs where appURL.pathExtension == "app" {
                let discovered = inspectContainingAppBundle(
                    at: appURL,
                    includeUnsupported: includeUnsupported,
                    issues: &issues
                )
                for candidate in discovered {
                    if let previous = seenExtensionIDs[candidate.extensionBundleIdentifier],
                       previous != candidate.appexURL {
                        issues.append(
                            .duplicateExtensionIdentifier(
                                candidate.extensionBundleIdentifier
                            )
                        )
                    }
                    seenExtensionIDs[candidate.extensionBundleIdentifier] = candidate.appexURL
                    candidates.append(candidate)
                }
            }
        }

        return candidates.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func scanInstalledExtensions() -> [DiscoveredSafariExtensionCandidate] {
        var issues: [SafariExtensionScannerIssue] = []
        return scanInstalledExtensions(issues: &issues)
    }

    /// Inspects a containing `.app` bundle for Safari Web Extension plug-ins.
    func inspectContainingAppBundle(
        at appURL: URL,
        includeUnsupported: Bool = false,
        issues: inout [SafariExtensionScannerIssue]
    ) -> [DiscoveredSafariExtensionCandidate] {
        let pluginsURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("PlugIns", isDirectory: true)

        guard fileManager.fileExists(atPath: pluginsURL.path) else {
            return []
        }

        let containingAppName = bundleDisplayName(at: appURL) ?? appURL.deletingPathExtension().lastPathComponent
        let containingAppBundleID = bundleIdentifier(at: appURL)

        guard let pluginURLs = try? fileManager.contentsOfDirectory(
            at: pluginsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            issues.append(.unreadableBundle(pluginsURL))
            return []
        }

        return pluginURLs.compactMap { pluginURL in
            guard pluginURL.pathExtension == "appex" else { return nil }
            return inspectAppexBundle(
                at: pluginURL,
                containingAppURL: appURL,
                containingAppName: containingAppName,
                containingAppBundleIdentifier: containingAppBundleID,
                includeUnsupported: includeUnsupported,
                issues: &issues
            )
        }
    }

    /// Inspects a single `.appex` bundle. Returns nil for non-Safari extension points.
    func inspectAppexBundle(
        at appexURL: URL,
        containingAppURL: URL? = nil,
        containingAppName: String? = nil,
        containingAppBundleIdentifier: String? = nil,
        includeUnsupported: Bool = false,
        issues: inout [SafariExtensionScannerIssue]
    ) -> DiscoveredSafariExtensionCandidate? {
        guard fileManager.isReadableFile(atPath: appexURL.path) else {
            issues.append(.unreadableBundle(appexURL))
            return nil
        }

        guard let extensionPoint = extensionPointIdentifier(at: appexURL) else {
            issues.append(.invalidExtensionPoint(appexURL, found: nil))
            return nil
        }

        let bundleKind = Self.bundleKind(forExtensionPointIdentifier: extensionPoint)
        guard bundleKind != .unsupported || includeUnsupported else {
            issues.append(.invalidExtensionPoint(appexURL, found: extensionPoint))
            return nil
        }

        let manifestURL = locateManifest(in: appexURL)
        if bundleKind == .webExtension, manifestURL == nil {
            issues.append(.missingManifest(appexURL))
        }

        let resolvedContainingAppURL = containingAppURL ?? appexURL
        let resolvedContainingName = containingAppName
            ?? bundleDisplayName(at: resolvedContainingAppURL)
            ?? resolvedContainingAppURL.deletingPathExtension().lastPathComponent

        return DiscoveredSafariExtensionCandidate(
            extensionBundleIdentifier: bundleIdentifier(at: appexURL) ?? appexURL.lastPathComponent,
            displayName: bundleDisplayName(at: appexURL) ?? appexURL.deletingPathExtension().lastPathComponent,
            version: bundleShortVersion(at: appexURL),
            extensionPointIdentifier: extensionPoint,
            bundleKind: bundleKind,
            runtimeStatus: Self.runtimeStatus(
                for: bundleKind,
                isReadable: fileManager.isReadableFile(atPath: appexURL.path)
            ),
            containingAppName: resolvedContainingName,
            containingAppBundleIdentifier: containingAppBundleIdentifier
                ?? bundleIdentifier(at: resolvedContainingAppURL),
            containingAppURL: resolvedContainingAppURL,
            appexURL: appexURL,
            manifestURL: manifestURL,
            isReadable: fileManager.isReadableFile(atPath: appexURL.path)
        )
    }

    func inspectAppexBundle(at appexURL: URL) -> DiscoveredSafariExtensionCandidate? {
        var issues: [SafariExtensionScannerIssue] = []
        return inspectAppexBundle(at: appexURL, issues: &issues)
    }

    static func bundleKind(
        forExtensionPointIdentifier extensionPointIdentifier: String
    ) -> SafariExtensionBundleKind {
        switch extensionPointIdentifier {
        case safariWebExtensionPointIdentifier:
            return .webExtension
        case safariContentBlockerExtensionPointIdentifier:
            return .contentBlocker
        case legacySafariExtensionPointIdentifier:
            return .legacySafariAppExtension
        default:
            return .unsupported
        }
    }

    private static func runtimeStatus(
        for bundleKind: SafariExtensionBundleKind,
        isReadable: Bool
    ) -> SafariExtensionRuntimeStatus {
        guard isReadable else { return .unreadable }
        switch bundleKind {
        case .webExtension:
            return .webExtensionImportable
        case .contentBlocker:
            return .contentBlockerImportable
        case .legacySafariAppExtension:
            return .unsupportedLegacySafariAppExtension
        case .unsupported:
            return .unsupportedExtensionPoint
        }
    }

    // MARK: - Bundle helpers

    private func bundleIdentifier(at bundleURL: URL) -> String? {
        plistValue(at: bundleURL, keyPath: ["CFBundleIdentifier"]) as? String
    }

    private func bundleDisplayName(at bundleURL: URL) -> String? {
        if let displayName = plistValue(at: bundleURL, keyPath: ["CFBundleDisplayName"]) as? String,
           displayName.isEmpty == false {
            return displayName
        }
        if let name = plistValue(at: bundleURL, keyPath: ["CFBundleName"]) as? String,
           name.isEmpty == false {
            return name
        }
        return nil
    }

    private func bundleShortVersion(at bundleURL: URL) -> String? {
        plistValue(at: bundleURL, keyPath: ["CFBundleShortVersionString"]) as? String
    }

    private func extensionPointIdentifier(at appexURL: URL) -> String? {
        plistValue(
            at: appexURL,
            keyPath: ["NSExtension", "NSExtensionPointIdentifier"]
        ) as? String
    }

    private func plistValue(at bundleURL: URL, keyPath: [String]) -> Any? {
        let plistURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        guard fileManager.fileExists(atPath: plistURL.path),
              let data = fileManager.contents(atPath: plistURL.path),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any]
        else {
            return nil
        }

        var current: Any = plist
        for key in keyPath {
            guard let dictionary = current as? [String: Any], let next = dictionary[key] else {
                return nil
            }
            current = next
        }
        return current
    }

    private func locateManifest(in appexURL: URL) -> URL? {
        let contentsURL = appexURL.appendingPathComponent("Contents", isDirectory: true)
        for relative in Self.manifestRelativeCandidates {
            let candidate = contentsURL.appendingPathComponent(relative)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
