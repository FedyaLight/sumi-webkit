//
//  ChromeMV3PasswordManagerRealPackageCompatibility.swift
//  Sumi
//
//  DEBUG/internal real local package compatibility trials for password-manager
//  MV3 packages. The runner is constrained to explicit local roots and falls
//  back to Prompt 64 reviewed fixtures when intake is missing, ambiguous, or
//  blocked by package policy.
//

import CryptoKit
import Foundation

enum ChromeMV3PasswordManagerRealPackageClass:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case bitwarden = "Bitwarden"
    case onePassword = "OnePassword"
    case protonPass = "ProtonPass"

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageClass,
        rhs: ChromeMV3PasswordManagerRealPackageClass
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var fixtureFallbackKind: ChromeMV3PasswordManagerCompatibilityTargetKind {
        switch self {
        case .bitwarden:
            return .bitwardenClass
        case .onePassword:
            return .onePasswordClass
        case .protonPass:
            return .protonPassClass
        }
    }
}

enum ChromeMV3PasswordManagerRealPackageDetectedKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case missing
    case unpackedExtensionRoot
    case directoryContainingSingleExtensionRoot
    case directoryContainingLocalZip
    case blockedCrxTrustPolicyRequired
    case ambiguous
    case invalid

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageDetectedKind,
        rhs: ChromeMV3PasswordManagerRealPackageDetectedKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerRealPackageSourceAvailability:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case realPackageAvailable
    case fixtureFallbackUsed
    case skippedMissingPackage
    case blockedAmbiguousPackage
    case blockedInvalidPackage
    case blockedCrxTrustPolicyRequired

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageSourceAvailability,
        rhs: ChromeMV3PasswordManagerRealPackageSourceAvailability
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerRealPackageSource:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case realLocalUnpacked
    case realLocalZip
    case fixtureFallback
    case skipped
    case ambiguous
    case invalid
    case blockedCRX

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageSource,
        rhs: ChromeMV3PasswordManagerRealPackageSource
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PasswordManagerRealPackageTargetDefinition:
    Codable,
    Equatable,
    Sendable
{
    var targetID: String
    var displayName: String
    var targetClass: ChromeMV3PasswordManagerRealPackageClass
    var explicitAllowedLocalRoot: String
    var fixtureFallbackID: String
    var expectedExtensionID: String?
    var configuredNativeHostNames: [String]
    var trustedFixtureHostRootPath: String?
    var noRealCredentialsInvariant: Bool
}

struct ChromeMV3PasswordManagerRealPackageTargetConfiguration:
    Codable,
    Equatable,
    Sendable
{
    var targetID: String
    var displayName: String
    var targetClass: ChromeMV3PasswordManagerRealPackageClass
    var explicitAllowedLocalRoot: String
    var detectedPackageKind: ChromeMV3PasswordManagerRealPackageDetectedKind
    var localUnpackedPath: String?
    var localZIPPath: String?
    var fixtureFallbackID: String
    var expectedExtensionID: String?
    var nativeHostNames: [String]
    var trustedFixtureHostRootPath: String?
    var noRealCredentialsInvariant: Bool
    var sourceAvailability:
        [ChromeMV3PasswordManagerRealPackageSourceAvailability]
    var manifestCandidatePaths: [String]
    var localZIPCandidatePaths: [String]
    var localCRXCandidatePaths: [String]
    var ambiguousEntries: [String]
    var diagnostics: [String]
}

enum ChromeMV3PasswordManagerRealPackageTargetCatalog {
    static func explicitLocalTargets()
        -> [ChromeMV3PasswordManagerRealPackageTargetDefinition]
    {
        [
            ChromeMV3PasswordManagerRealPackageTargetDefinition(
                targetID: "bitwarden-real-local",
                displayName: "Bitwarden real package",
                targetClass: .bitwarden,
                explicitAllowedLocalRoot:
                    "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/bitwarden",
                fixtureFallbackID:
                    ChromeMV3PasswordManagerCompatibilityTargetKind
                    .bitwardenClass.rawValue,
                expectedExtensionID: nil,
                configuredNativeHostNames: [],
                trustedFixtureHostRootPath: nil,
                noRealCredentialsInvariant: true
            ),
            ChromeMV3PasswordManagerRealPackageTargetDefinition(
                targetID: "proton-pass-real-local",
                displayName: "Proton Pass real package",
                targetClass: .protonPass,
                explicitAllowedLocalRoot:
                    "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/proton",
                fixtureFallbackID:
                    ChromeMV3PasswordManagerCompatibilityTargetKind
                    .protonPassClass.rawValue,
                expectedExtensionID: nil,
                configuredNativeHostNames: [],
                trustedFixtureHostRootPath: nil,
                noRealCredentialsInvariant: true
            ),
            ChromeMV3PasswordManagerRealPackageTargetDefinition(
                targetID: "onepassword-real-local",
                displayName: "1Password real package",
                targetClass: .onePassword,
                explicitAllowedLocalRoot:
                    "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/1password",
                fixtureFallbackID:
                    ChromeMV3PasswordManagerCompatibilityTargetKind
                    .onePasswordClass.rawValue,
                expectedExtensionID: nil,
                configuredNativeHostNames: [],
                trustedFixtureHostRootPath: nil,
                noRealCredentialsInvariant: true
            ),
        ]
    }
}

enum ChromeMV3PasswordManagerRealPackageDetector {
    static func detect(
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        fileManager: FileManager = .default
    ) -> ChromeMV3PasswordManagerRealPackageTargetConfiguration {
        let root = URL(
            fileURLWithPath: target.explicitAllowedLocalRoot,
            isDirectory: true
        ).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: root.path,
            isDirectory: &isDirectory
        ) else {
            return configuration(
                target: target,
                kind: .missing,
                sourceAvailability: [
                    .skippedMissingPackage,
                    .fixtureFallbackUsed,
                ],
                diagnostics: [
                    "Explicit local root is missing; reviewed fixture fallback will be used.",
                    "No profile directories, Web Store URLs, or remote CRX locations were searched.",
                ]
            )
        }
        guard isDirectory.boolValue else {
            return configuration(
                target: target,
                kind: .invalid,
                sourceAvailability: [
                    .blockedInvalidPackage,
                    .fixtureFallbackUsed,
                ],
                diagnostics: [
                    "Explicit local root exists but is not a directory.",
                    "Reviewed fixture fallback will be used.",
                ]
            )
        }

        let children = sortedChildren(of: root, fileManager: fileManager)
        let directManifest = root.appendingPathComponent("manifest.json")
        if safeManifestExists(
            directManifest,
            root: root,
            fileManager: fileManager
        ) {
            return configuration(
                target: target,
                kind: .unpackedExtensionRoot,
                localUnpackedPath: root.path,
                sourceAvailability: [.realPackageAvailable],
                manifestCandidatePaths: ["manifest.json"],
                localZIPCandidatePaths:
                    zipCandidates(children, root: root).map(\.relativePath),
                localCRXCandidatePaths:
                    crxCandidates(children, root: root).map(\.relativePath),
                diagnostics: [
                    "manifest.json was found directly inside the explicit allowed root.",
                    "Package kind is real local unpacked; no fallback package is used.",
                ]
            )
        }
        if fileManager.fileExists(atPath: directManifest.path),
           safeURLInsideRoot(
            directManifest.resolvingSymlinksInPath(),
            root: root
           ) == false
        {
            return configuration(
                target: target,
                kind: .invalid,
                sourceAvailability: [
                    .blockedInvalidPackage,
                    .fixtureFallbackUsed,
                ],
                diagnostics: [
                    "manifest.json is a symlink or path that resolves outside the explicit local root.",
                    "Reviewed fixture fallback will be used.",
                ]
            )
        }

        let childManifestCandidates =
            manifestChildCandidates(children, root: root, fileManager: fileManager)
        let zipCandidates = zipCandidates(children, root: root)
        let crxCandidates = crxCandidates(children, root: root)

        if childManifestCandidates.count == 1 {
            let candidate = childManifestCandidates[0]
            return configuration(
                target: target,
                kind: .directoryContainingSingleExtensionRoot,
                localUnpackedPath: candidate.url.path,
                sourceAvailability: [.realPackageAvailable],
                manifestCandidatePaths: [candidate.relativePath],
                localZIPCandidatePaths: zipCandidates.map(\.relativePath),
                localCRXCandidatePaths: crxCandidates.map(\.relativePath),
                diagnostics: [
                    "Exactly one child directory with manifest.json was found inside the explicit root.",
                    "Package kind is real local unpacked via child extension root.",
                ]
            )
        }
        if childManifestCandidates.count > 1 {
            let candidates = childManifestCandidates.map(\.relativePath)
            return configuration(
                target: target,
                kind: .ambiguous,
                sourceAvailability: [
                    .blockedAmbiguousPackage,
                    .fixtureFallbackUsed,
                ],
                manifestCandidatePaths: candidates,
                localZIPCandidatePaths: zipCandidates.map(\.relativePath),
                localCRXCandidatePaths: crxCandidates.map(\.relativePath),
                ambiguousEntries: candidates,
                diagnostics: [
                    "Multiple child manifest.json candidates were found under the explicit root.",
                    "Reviewed fixture fallback will be used instead of guessing.",
                ]
            )
        }

        if zipCandidates.count == 1 {
            let candidate = zipCandidates[0]
            return configuration(
                target: target,
                kind: .directoryContainingLocalZip,
                localZIPPath: candidate.url.path,
                sourceAvailability: [.realPackageAvailable],
                localZIPCandidatePaths: [candidate.relativePath],
                localCRXCandidatePaths: crxCandidates.map(\.relativePath),
                diagnostics: [
                    "Exactly one local ZIP package was found inside the explicit root.",
                    "Package kind is real local ZIP and will use safe ZIP intake.",
                ]
            )
        }
        if zipCandidates.count > 1 {
            let candidates = zipCandidates.map(\.relativePath)
            return configuration(
                target: target,
                kind: .ambiguous,
                sourceAvailability: [
                    .blockedAmbiguousPackage,
                    .fixtureFallbackUsed,
                ],
                localZIPCandidatePaths: candidates,
                localCRXCandidatePaths: crxCandidates.map(\.relativePath),
                ambiguousEntries: candidates,
                diagnostics: [
                    "Multiple ZIP packages were found and no manifest root was clear.",
                    "Reviewed fixture fallback will be used instead of guessing.",
                ]
            )
        }
        if crxCandidates.isEmpty == false {
            return configuration(
                target: target,
                kind: .blockedCrxTrustPolicyRequired,
                sourceAvailability: [
                    .blockedCrxTrustPolicyRequired,
                    .fixtureFallbackUsed,
                ],
                localCRXCandidatePaths: crxCandidates.map(\.relativePath),
                diagnostics: [
                    "Only local CRX package candidates were found.",
                    "CRX import remains blocked until signature verification and an explicit trust policy exist.",
                    "Reviewed fixture fallback will be used.",
                ]
            )
        }

        return configuration(
            target: target,
            kind: .invalid,
            sourceAvailability: [
                .blockedInvalidPackage,
                .fixtureFallbackUsed,
            ],
            diagnostics: [
                "Explicit local root contains no manifest.json child package and no local ZIP package.",
                "Reviewed fixture fallback will be used.",
            ]
        )
    }

    private static func configuration(
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        kind: ChromeMV3PasswordManagerRealPackageDetectedKind,
        localUnpackedPath: String? = nil,
        localZIPPath: String? = nil,
        sourceAvailability:
            [ChromeMV3PasswordManagerRealPackageSourceAvailability],
        manifestCandidatePaths: [String] = [],
        localZIPCandidatePaths: [String] = [],
        localCRXCandidatePaths: [String] = [],
        ambiguousEntries: [String] = [],
        diagnostics: [String]
    ) -> ChromeMV3PasswordManagerRealPackageTargetConfiguration {
        ChromeMV3PasswordManagerRealPackageTargetConfiguration(
            targetID: target.targetID,
            displayName: target.displayName,
            targetClass: target.targetClass,
            explicitAllowedLocalRoot: target.explicitAllowedLocalRoot,
            detectedPackageKind: kind,
            localUnpackedPath: localUnpackedPath,
            localZIPPath: localZIPPath,
            fixtureFallbackID: target.fixtureFallbackID,
            expectedExtensionID: target.expectedExtensionID,
            nativeHostNames: target.configuredNativeHostNames.sorted(),
            trustedFixtureHostRootPath: target.trustedFixtureHostRootPath,
            noRealCredentialsInvariant: target.noRealCredentialsInvariant,
            sourceAvailability: sourceAvailability.sorted(),
            manifestCandidatePaths: manifestCandidatePaths.sorted(),
            localZIPCandidatePaths: localZIPCandidatePaths.sorted(),
            localCRXCandidatePaths: localCRXCandidatePaths.sorted(),
            ambiguousEntries: ambiguousEntries.sorted(),
            diagnostics: uniqueSortedRealPackages(diagnostics)
        )
    }

    private static func sortedChildren(
        of root: URL,
        fileManager: FileManager
    ) -> [URL] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        return (
            try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants]
            )
        )?.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    private static func manifestChildCandidates(
        _ children: [URL],
        root: URL,
        fileManager: FileManager
    ) -> [(url: URL, relativePath: String)] {
        children.compactMap { child in
            guard isDirectory(child), isSymlink(child) == false else {
                return nil
            }
            let manifest = child.appendingPathComponent("manifest.json")
            guard safeManifestExists(
                manifest,
                root: root,
                fileManager: fileManager
            ) else { return nil }
            return (child, "\(child.lastPathComponent)/manifest.json")
        }
    }

    private static func zipCandidates(
        _ children: [URL],
        root: URL
    ) -> [(url: URL, relativePath: String)] {
        children.compactMap { child in
            guard isRegularFile(child),
                  child.pathExtension.lowercased() == "zip",
                  safeURLInsideRoot(child, root: root)
            else { return nil }
            return (child, child.lastPathComponent)
        }
    }

    private static func crxCandidates(
        _ children: [URL],
        root: URL
    ) -> [(url: URL, relativePath: String)] {
        children.compactMap { child in
            guard isRegularFile(child),
                  child.pathExtension.lowercased() == "crx",
                  safeURLInsideRoot(child, root: root)
            else { return nil }
            return (child, child.lastPathComponent)
        }
    }

    private static func safeManifestExists(
        _ manifest: URL,
        root: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: manifest.path,
            isDirectory: &isDirectory
        ),
              isDirectory.boolValue == false
        else { return false }
        return safeURLInsideRoot(manifest.resolvingSymlinksInPath(), root: root)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))
            .flatMap(\.isDirectory) == true
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))
            .flatMap(\.isRegularFile) == true
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))
            .flatMap(\.isSymbolicLink) == true
    }
}

struct ChromeMV3PasswordManagerRealPackageContentScriptRequirement:
    Codable,
    Equatable,
    Sendable
{
    var index: Int
    var matches: [String]
    var excludeMatches: [String]
    var js: [String]
    var css: [String]
    var runAt: String?
    var world: String
    var allFrames: Bool
    var matchAboutBlank: Bool
    var matchOriginAsFallback: Bool
}

struct ChromeMV3PasswordManagerRealPackageWebAccessibleResourceRequirement:
    Codable,
    Equatable,
    Sendable
{
    var resources: [String]
    var matches: [String]
    var extensionIDs: [String]
    var useDynamicURL: Bool?
}

struct ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction:
    Codable,
    Equatable,
    Sendable
{
    var manifestVersion: Int?
    var name: String?
    var version: String?
    var permissions: [String]
    var optionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String]
    var contentScripts:
        [ChromeMV3PasswordManagerRealPackageContentScriptRequirement]
    var backgroundServiceWorker: String?
    var actionDefaultPopup: String?
    var optionsPage: String?
    var optionsUIPage: String?
    var webAccessibleResources:
        [ChromeMV3PasswordManagerRealPackageWebAccessibleResourceRequirement]
    var declaresNativeMessaging: Bool
    var detectedNativeHostNames: [String]
    var declaresSidePanel: Bool
    var declaresOffscreen: Bool
    var declaresIdentity: Bool
    var declaresDNR: Bool
    var declaresWebRequest: Bool
    var externallyConnectableMatches: [String]
    var contentSecurityPolicyKeys: [String]
    var sandboxPages: [String]
    var devtoolsPage: String?
    var topLevelKeys: [String]
    var unsupportedOrDeferredManifestKeys: [String]
    var unsupportedOrDeferredAPIs: [String]
    var diagnostics: [String]

    static let empty =
        ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction(
            manifestVersion: nil,
            name: nil,
            version: nil,
            permissions: [],
            optionalPermissions: [],
            hostPermissions: [],
            optionalHostPermissions: [],
            contentScripts: [],
            backgroundServiceWorker: nil,
            actionDefaultPopup: nil,
            optionsPage: nil,
            optionsUIPage: nil,
            webAccessibleResources: [],
            declaresNativeMessaging: false,
            detectedNativeHostNames: [],
            declaresSidePanel: false,
            declaresOffscreen: false,
            declaresIdentity: false,
            declaresDNR: false,
            declaresWebRequest: false,
            externallyConnectableMatches: [],
            contentSecurityPolicyKeys: [],
            sandboxPages: [],
            devtoolsPage: nil,
            topLevelKeys: [],
            unsupportedOrDeferredManifestKeys: [],
            unsupportedOrDeferredAPIs: [],
            diagnostics: ["Manifest was unavailable or invalid."]
        )
}

struct ChromeMV3PasswordManagerRealPackageResourceScan:
    Codable,
    Equatable,
    Sendable
{
    var scannedTextFileCount: Int
    var skippedFileCount: Int
    var skippedSymlinkCount: Int
    var detectedChromeAPIs: [String]
    var detectedNativeHostNames: [String]
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackagePopupOptionsSmoke:
    Codable,
    Equatable,
    Sendable
{
    var popupPath: String?
    var optionsPath: String?
    var documentLoadStatus: ChromeMV3PasswordManagerCompatibilityStatus
    var jsBridgeStatus: ChromeMV3PasswordManagerCompatibilityStatus
    var allowedSmokeMethods: [String]
    var blockedAPIs: [ChromeMV3PopupOptionsBlockedAPIDiagnostic]
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackageContentScriptSmoke:
    Codable,
    Equatable,
    Sendable
{
    var syntheticLoginURL: String
    var declaredContentScriptCount: Int
    var matchedContentScriptCount: Int
    var attachmentStatus: ChromeMV3PasswordManagerCompatibilityStatus
    var tabsSendMessageStatus: ChromeMV3PasswordManagerCompatibilityStatus
    var tabsConnectStatus: ChromeMV3PasswordManagerCompatibilityStatus
    var blockers: [String]
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackagePermissionSmoke:
    Codable,
    Equatable,
    Sendable
{
    var requiredPermissions: [String]
    var optionalPermissions: [String]
    var requiredHostPermissions: [String]
    var optionalHostPermissions: [String]
    var acceptDenyRevokeModeledByTestPresenter: Bool
    var silentlyGranted: Bool
    var urlTitleRedactionTested: Bool
    var endpointInvalidationAfterRevokeModeled: Bool
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackageNativeMessagingSmoke:
    Codable,
    Equatable,
    Sendable
{
    var required: Bool
    var optional: Bool
    var hostNames: [String]
    var trustedFixtureHostRootPath: String?
    var noTrustedHostConfigured: Bool
    var arbitraryHostDiscoveryBlocked: Bool
    var realVendorHostLaunchBlocked: Bool
    var fixtureExchangeAttempted: Bool
    var fixtureExchangeSucceeded: Bool
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackageFixtureDelta:
    Codable,
    Equatable,
    Sendable
{
    var fixtureFallbackID: String
    var fixtureProductReadiness:
        ChromeMV3PasswordManagerCompatibilityStatus
    var realAPIsAbsentInFixture: [String]
    var fixtureAPIsAbsentInReal: [String]
    var newBlockers: [String]
    var resolvedBlockers: [String]
    var riskDeltas: [String]
    var nextRecommendedFix: String
}

struct ChromeMV3PasswordManagerRealPackageCompatibilityRow:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String { targetID }
    var targetID: String
    var targetDisplayName: String
    var targetClass: ChromeMV3PasswordManagerRealPackageClass
    var packageSource: ChromeMV3PasswordManagerRealPackageSource
    var detectedPackageKind: ChromeMV3PasswordManagerRealPackageDetectedKind
    var packagePath: String?
    var intake: ChromeMV3PasswordManagerCompatibilityStatus
    var manifest: ChromeMV3PasswordManagerCompatibilityStatus
    var generatedBundle: ChromeMV3PasswordManagerCompatibilityStatus
    var popupOptions: ChromeMV3PasswordManagerCompatibilityStatus
    var popupOptionsJSBridge: ChromeMV3PasswordManagerCompatibilityStatus
    var contentScripts: ChromeMV3PasswordManagerCompatibilityStatus
    var css: ChromeMV3PasswordManagerCompatibilityStatus
    var mainWorld: ChromeMV3PasswordManagerCompatibilityStatus
    var multiFrame: ChromeMV3PasswordManagerCompatibilityStatus
    var permissions: ChromeMV3PasswordManagerCompatibilityStatus
    var activeTab: ChromeMV3PasswordManagerCompatibilityStatus
    var tabsQuery: ChromeMV3PasswordManagerCompatibilityStatus
    var tabsSendMessage: ChromeMV3PasswordManagerCompatibilityStatus
    var tabsConnect: ChromeMV3PasswordManagerCompatibilityStatus
    var storageLocal: ChromeMV3PasswordManagerCompatibilityStatus
    var nativeMessaging: ChromeMV3PasswordManagerCompatibilityStatus
    var serviceWorkerLifecycle: ChromeMV3PasswordManagerCompatibilityStatus
    var dnrWebRequest: ChromeMV3PasswordManagerCompatibilityStatus
    var sidePanelOffscreenIdentity:
        ChromeMV3PasswordManagerCompatibilityStatus
    var manifestRequirements:
        ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction
    var popupOptionsSmoke:
        ChromeMV3PasswordManagerRealPackagePopupOptionsSmoke
    var contentScriptSmoke:
        ChromeMV3PasswordManagerRealPackageContentScriptSmoke
    var permissionActiveTabSmoke:
        ChromeMV3PasswordManagerRealPackagePermissionSmoke
    var nativeMessagingSmoke:
        ChromeMV3PasswordManagerRealPackageNativeMessagingSmoke
    var fixtureDelta: ChromeMV3PasswordManagerRealPackageFixtureDelta
    var apiBlockers: [String]
    var manifestBlockers: [String]
    var webKitBlockers: [String]
    var packageBlockers: [String]
    var nativeHostBlockers: [String]
    var permissionBlockers: [String]
    var contentScriptBlockers: [String]
    var popupOptionsBlockers: [String]
    var productPolicyBlockers: [String]
    var productReadiness: ChromeMV3PasswordManagerCompatibilityStatus
    var blockerSummary: [String]
    var nextRecommendedFix: String
    var notPublicSupportDisclaimer: String
}

struct ChromeMV3PasswordManagerRealPackageCompatibilityReport:
    Codable,
    Equatable,
    Sendable
{
    static let schemaVersion = 1
    static let reportFileName =
        "runtime-mv3-real-package-compatibility-report.json"

    var schemaVersion: Int
    var reportFileName: String
    var generatedAt: Date
    var targetConfigurations:
        [ChromeMV3PasswordManagerRealPackageTargetConfiguration]
    var rows: [ChromeMV3PasswordManagerRealPackageCompatibilityRow]
    var fixtureBaselineReport:
        ChromeMV3PasswordManagerCompatibilityReport
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    var noWebStoreInstallAttempted: Bool
    var noRemoteCRXDownloadAttempted: Bool
    var noRealCredentialsUsed: Bool
    var arbitraryNativeHostDiscoveryAttempted: Bool
    var realVendorNativeHostLaunchAttempted: Bool
    var productRuntimeAvailable: Bool
    var productRuntimeExposed: Bool
    var diagnostics: [String]
}

enum ChromeMV3PasswordManagerRealPackageCompatibilityReportWriter {
    static let reportFileName =
        ChromeMV3PasswordManagerRealPackageCompatibilityReport.reportFileName

    static func reportURL(rootURL: URL) -> URL {
        rootURL.standardizedFileURL.appendingPathComponent(reportFileName)
    }

    static func latestReport(
        rootURL: URL,
        fileManager: FileManager = .default
    ) -> ChromeMV3PasswordManagerRealPackageCompatibilityReport? {
        let url = reportURL(rootURL: rootURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(
            ChromeMV3PasswordManagerRealPackageCompatibilityReport.self,
            from: Data(contentsOf: url)
        )
    }

    @discardableResult
    static func write(
        _ report: ChromeMV3PasswordManagerRealPackageCompatibilityReport,
        to rootURL: URL
    ) throws -> ChromeMV3PasswordManagerRealPackageCompatibilityReport {
        let url = reportURL(rootURL: rootURL)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ChromeMV3DeterministicJSON.write(report, to: url)
        return report
    }
}

enum ChromeMV3PasswordManagerRealPackageTrialRunner {
    static func run(
        rootURL: URL,
        targets:
            [ChromeMV3PasswordManagerRealPackageTargetDefinition] =
                ChromeMV3PasswordManagerRealPackageTargetCatalog
                .explicitLocalTargets(),
        profileID: String = "password-manager-real-package-profile",
        writeReport: Bool = true,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) -> ChromeMV3PasswordManagerRealPackageCompatibilityReport {
        let root = rootURL.standardizedFileURL
        let fixtureBaselineRoot = root
            .appendingPathComponent(
                "Prompt64FixtureBaselineComparison",
                isDirectory: true
            )
        let fixtureKinds = targets.map(\.targetClass.fixtureFallbackKind)
            .sorted()
        let fixtureBaseline =
            ChromeMV3PasswordManagerCompatibilityPassRunner.run(
                rootURL: fixtureBaselineRoot,
                targetKinds: fixtureKinds,
                writeReport: false,
                now: now
            )

        let registry = ChromeMV3ExtensionLifecycleRegistry(
            rootURL: root,
            now: now,
            fileManager: fileManager
        )
        let intake = ChromeMV3PackageIntakeService(
            rootURL: root,
            now: now,
            fileManager: fileManager
        )
        let fixtureRoot = root.appendingPathComponent(
            "RealPackageFixtureFallbacks",
            isDirectory: true
        )

        var configurations:
            [ChromeMV3PasswordManagerRealPackageTargetConfiguration] = []
        var rows: [ChromeMV3PasswordManagerRealPackageCompatibilityRow] = []
        var diagnostics: [String] = []

        for target in targets.sorted(by: { $0.targetID < $1.targetID }) {
            var configuration =
                ChromeMV3PasswordManagerRealPackageDetector.detect(
                    target: target,
                    fileManager: fileManager
                )
            let selected = selectPackage(
                target: target,
                configuration: configuration,
                fixtureRoot: fixtureRoot,
                fileManager: fileManager
            )
            configuration.nativeHostNames =
                uniqueSortedRealPackages(
                    configuration.nativeHostNames
                        + selected.configuredNativeHostNames
                )
            configurations.append(configuration)

            let trial = runPackage(
                selected: selected,
                profileID: "\(profileID)-\(target.targetClass.fixtureFallbackKind.pathComponent)",
                registry: registry,
                intake: intake
            )
            let manifest = manifestForTrial(selected: selected, trial: trial)
            let installReport = manifest.map {
                ChromeMV3InstallReporter.report(for: $0)
            }
            let resourceScan =
                ChromeMV3PasswordManagerRealPackageResourceScanner.scan(
                    packageRootPath:
                        selected.resourceScanRootPath
                            ?? trial.acceptedPackageRootPath
                )
            let extraction = manifestExtraction(
                manifest: manifest,
                installReport: installReport,
                resourceScan: resourceScan
            )
            let fixtureRow = fixtureBaseline.rows.first {
                $0.targetKind == target.targetClass.fixtureFallbackKind
            }
            let row = makeRow(
                target: target,
                configuration: configuration,
                selected: selected,
                trial: trial,
                manifest: manifest,
                installReport: installReport,
                extraction: extraction,
                resourceScan: resourceScan,
                fixtureRow: fixtureRow
            )
            rows.append(row)
            diagnostics.append(contentsOf: configuration.diagnostics)
            diagnostics.append(contentsOf: selected.diagnostics)
            diagnostics.append(contentsOf: trial.diagnostics)
            diagnostics.append(contentsOf: resourceScan.diagnostics)
        }

        let report = ChromeMV3PasswordManagerRealPackageCompatibilityReport(
            schemaVersion:
                ChromeMV3PasswordManagerRealPackageCompatibilityReport
                .schemaVersion,
            reportFileName:
                ChromeMV3PasswordManagerRealPackageCompatibilityReport
                .reportFileName,
            generatedAt: now(),
            targetConfigurations:
                configurations.sorted { $0.targetID < $1.targetID },
            rows: rows.sorted { $0.targetID < $1.targetID },
            fixtureBaselineReport: fixtureBaseline,
            documentationSources: documentationSources(),
            noWebStoreInstallAttempted: true,
            noRemoteCRXDownloadAttempted: true,
            noRealCredentialsUsed: true,
            arbitraryNativeHostDiscoveryAttempted: false,
            realVendorNativeHostLaunchAttempted: false,
            productRuntimeAvailable: false,
            productRuntimeExposed: false,
            diagnostics:
                uniqueSortedRealPackages(
                    diagnostics + [
                        "Real-package compatibility trials used only the explicit configured local roots.",
                        "Chrome Web Store install, scraping, spoofing, and remote CRX download were not attempted.",
                        "Real credentials, vaults, accounts, tokens, and installed native hosts were not used.",
                        "Product runtime and public password-manager support remain unavailable.",
                    ]
                )
        )
        if writeReport {
            return (
                try? ChromeMV3PasswordManagerRealPackageCompatibilityReportWriter
                    .write(report, to: root)
            ) ?? report
        }
        return report
    }

    private static func selectPackage(
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        configuration: ChromeMV3PasswordManagerRealPackageTargetConfiguration,
        fixtureRoot: URL,
        fileManager: FileManager
    ) -> SelectedPackage {
        switch configuration.detectedPackageKind {
        case .unpackedExtensionRoot, .directoryContainingSingleExtensionRoot:
            if let path = configuration.localUnpackedPath {
                return SelectedPackage(
                    source: .realLocalUnpacked,
                    packageURL: URL(fileURLWithPath: path, isDirectory: true),
                    resourceScanRootPath: path,
                    configuredNativeHostNames: configuration.nativeHostNames,
                    diagnostics: [
                        "Selected explicit real local unpacked package.",
                    ]
                )
            }
        case .directoryContainingLocalZip:
            if let path = configuration.localZIPPath {
                return SelectedPackage(
                    source: .realLocalZip,
                    packageURL: URL(fileURLWithPath: path),
                    resourceScanRootPath: nil,
                    configuredNativeHostNames: configuration.nativeHostNames,
                    diagnostics: [
                        "Selected explicit real local ZIP package.",
                    ]
                )
            }
        case .missing, .ambiguous, .invalid, .blockedCrxTrustPolicyRequired:
            break
        }

        do {
            let fixtureTarget = ChromeMV3PasswordManagerCompatibilityTargetCatalog
                .target(target.targetClass.fixtureFallbackKind)
            let fixture = try ChromeMV3PasswordManagerFixturePackageBuilder
                .writeFixturePackage(for: fixtureTarget, rootURL: fixtureRoot)
            return SelectedPackage(
                source: fallbackSource(for: configuration.detectedPackageKind),
                packageURL: fixture,
                resourceScanRootPath: fixture.path,
                configuredNativeHostNames:
                    fixtureTarget.nativeHostRequirement.hostName.map { [$0] }
                        ?? [],
                diagnostics: [
                    "Selected reviewed Prompt 64 fixture fallback.",
                    "Fallback fixture contains no real vendor code or credentials.",
                ]
            )
        } catch {
            return SelectedPackage(
                source: .invalid,
                packageURL: nil,
                resourceScanRootPath: nil,
                configuredNativeHostNames: [],
                diagnostics: [
                    "Reviewed fixture fallback could not be prepared: \(error.localizedDescription)",
                ]
            )
        }
    }

    private static func runPackage(
        selected: SelectedPackage,
        profileID: String,
        registry: ChromeMV3ExtensionLifecycleRegistry,
        intake: ChromeMV3PackageIntakeService
    ) -> PackageTrialResult {
        guard let packageURL = selected.packageURL else {
            return PackageTrialResult(
                lifecycleResult: nil,
                packageIntakeReport: nil,
                acceptedPackageRootPath: nil,
                diagnostics: ["No selected package URL was available."]
            )
        }
        switch selected.source {
        case .realLocalZip:
            let imported = intake.importLocalZIPArchive(
                sourceURL: packageURL,
                profileID: profileID,
                enableInternal: true,
                runtimeDiagnostics:
                    .passwordManagerRealPackageCompatibilityPass
            )
            return PackageTrialResult(
                lifecycleResult: imported.lifecycleResult,
                packageIntakeReport: imported.report,
                acceptedPackageRootPath:
                    imported.report.manifestRootResult.extensionRootPath,
                diagnostics:
                    imported.lifecycleResult?.diagnostics
                        ?? imported.report.blockers
            )
        case .realLocalUnpacked, .fixtureFallback:
            let result = registry.installUnpackedExtension(
                at: packageURL,
                profileID: profileID,
                enableInternal: true,
                runtimeDiagnostics:
                    .passwordManagerRealPackageCompatibilityPass
            )
            let packageReport = intake.writeLocalUnpackedReport(
                sourceURL: packageURL,
                lifecycleResult: result
            )
            return PackageTrialResult(
                lifecycleResult: result,
                packageIntakeReport: packageReport,
                acceptedPackageRootPath: packageURL.path,
                diagnostics: result.diagnostics + packageReport.blockers
            )
        case .skipped, .ambiguous, .invalid, .blockedCRX:
            let result = registry.installUnpackedExtension(
                at: packageURL,
                profileID: profileID,
                enableInternal: true,
                runtimeDiagnostics:
                    .passwordManagerRealPackageCompatibilityPass
            )
            let packageReport = intake.writeLocalUnpackedReport(
                sourceURL: packageURL,
                lifecycleResult: result
            )
            return PackageTrialResult(
                lifecycleResult: result,
                packageIntakeReport: packageReport,
                acceptedPackageRootPath: packageURL.path,
                diagnostics: result.diagnostics + packageReport.blockers
            )
        }
    }

    private static func manifestForTrial(
        selected: SelectedPackage,
        trial: PackageTrialResult
    ) -> ChromeMV3Manifest? {
        let rootPath = trial.acceptedPackageRootPath
            ?? selected.resourceScanRootPath
            ?? selected.packageURL?.path
        guard let rootPath else { return nil }
        return try? ChromeMV3ManifestValidator.validatePackage(
            at: URL(fileURLWithPath: rootPath, isDirectory: true),
            sourceKind: .unpackedDirectory
        )
    }

    private static func manifestExtraction(
        manifest: ChromeMV3Manifest?,
        installReport: ChromeMV3InstallReport?,
        resourceScan: ChromeMV3PasswordManagerRealPackageResourceScan
    ) -> ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction {
        guard let manifest else { return .empty }
        let allPermissions =
            uniqueSortedRealPackages(
                manifest.permissions + manifest.optionalPermissions
            )
        let deferredAPIs =
            uniqueSortedRealPackages(
                (installReport?.unsupportedAPIs.map(\.rawValue) ?? [])
                    + (installReport?.deferredAPIs.map(\.rawValue) ?? [])
                    + (installReport?.needsVerificationAPIs.map(\.rawValue) ?? [])
                    + policyKeys(from: manifest)
            )
        let nativeHosts =
            uniqueSortedRealPackages(resourceScan.detectedNativeHostNames)

        return ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction(
            manifestVersion: manifest.manifestVersion,
            name: manifest.name,
            version: manifest.version,
            permissions: manifest.permissions,
            optionalPermissions: manifest.optionalPermissions,
            hostPermissions: manifest.hostPermissions,
            optionalHostPermissions: manifest.optionalHostPermissions,
            contentScripts:
                manifest.contentScripts.enumerated().map { index, script in
                    ChromeMV3PasswordManagerRealPackageContentScriptRequirement(
                        index: index,
                        matches: script.matches,
                        excludeMatches: script.excludeMatches,
                        js: script.js,
                        css: script.css,
                        runAt: script.runAt,
                        world: script.world ?? "ISOLATED",
                        allFrames: script.allFrames,
                        matchAboutBlank: script.matchAboutBlank,
                        matchOriginAsFallback: script.matchOriginAsFallback
                    )
                },
            backgroundServiceWorker: manifest.background?.serviceWorker,
            actionDefaultPopup: manifest.action?.defaultPopup,
            optionsPage: manifest.optionsPage,
            optionsUIPage: manifest.optionsUI?.page,
            webAccessibleResources:
                manifest.webAccessibleResources.map {
                    ChromeMV3PasswordManagerRealPackageWebAccessibleResourceRequirement(
                        resources: $0.resources,
                        matches: $0.matches,
                        extensionIDs: $0.extensionIDs,
                        useDynamicURL: $0.useDynamicURL
                    )
                },
            declaresNativeMessaging: allPermissions.contains("nativeMessaging"),
            detectedNativeHostNames: nativeHosts,
            declaresSidePanel:
                manifest.sidePanel != nil || allPermissions.contains("sidePanel"),
            declaresOffscreen: allPermissions.contains("offscreen"),
            declaresIdentity:
                allPermissions.contains("identity")
                    || allPermissions.contains("identity.email")
                    || manifest.oauth2 != nil,
            declaresDNR:
                manifest.declarativeNetRequest != nil
                    || allPermissions.contains("declarativeNetRequest")
                    || allPermissions
                        .contains("declarativeNetRequestWithHostAccess")
                    || allPermissions.contains("declarativeNetRequestFeedback"),
            declaresWebRequest:
                allPermissions.contains("webRequest")
                    || allPermissions.contains("webRequestBlocking")
                    || allPermissions.contains("webRequestAuthProvider"),
            externallyConnectableMatches:
                manifest.externallyConnectable?.matches ?? [],
            contentSecurityPolicyKeys:
                manifest.topLevelKeys.contains("content_security_policy")
                    ? ["content_security_policy"] : [],
            sandboxPages:
                manifest.topLevelKeys.contains("sandbox")
                    ? ["sandbox"] : [],
            devtoolsPage: manifest.devtoolsPage,
            topLevelKeys: manifest.topLevelKeys,
            unsupportedOrDeferredManifestKeys: policyKeys(from: manifest),
            unsupportedOrDeferredAPIs: deferredAPIs,
            diagnostics:
                uniqueSortedRealPackages(
                    resourceScan.diagnostics + [
                        "Manifest/API requirements were extracted from the local package only.",
                        "No runtime calls were made against real credentials, accounts, vaults, or vendor hosts.",
                    ]
                )
        )
    }

    private static func makeRow(
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        configuration: ChromeMV3PasswordManagerRealPackageTargetConfiguration,
        selected: SelectedPackage,
        trial: PackageTrialResult,
        manifest: ChromeMV3Manifest?,
        installReport: ChromeMV3InstallReport?,
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction,
        resourceScan: ChromeMV3PasswordManagerRealPackageResourceScan,
        fixtureRow: ChromeMV3PasswordManagerCompatibilityMatrixRow?
    ) -> ChromeMV3PasswordManagerRealPackageCompatibilityRow {
        let lifecycleSucceeded = trial.lifecycleResult?.succeeded == true
        let generatedAvailable =
            trial.lifecycleResult?.generatedVersion != nil
                || trial.lifecycleResult?.record?.activeGeneratedVersionID != nil
        let hasPopupOptions =
            extraction.actionDefaultPopup != nil
                || extraction.optionsPage != nil
                || extraction.optionsUIPage != nil
        let hasContentScripts = extraction.contentScripts.isEmpty == false
        let requiresCSS = extraction.contentScripts.contains {
            $0.css.isEmpty == false
        }
        let requiresMainWorld = extraction.contentScripts.contains {
            $0.world == "MAIN"
        }
        let requiresMultiFrame = extraction.contentScripts.contains {
            $0.allFrames || $0.matchAboutBlank || $0.matchOriginAsFallback
        }
        let nativeRequired =
            extraction.permissions.contains("nativeMessaging")
                || resourceScan.detectedNativeHostNames.isEmpty == false
        let nativeOptional =
            extraction.optionalPermissions.contains("nativeMessaging")
        let nativeSmoke = nativeSmoke(
            target: target,
            selected: selected,
            extraction: extraction,
            nativeRequired: nativeRequired,
            nativeOptional: nativeOptional
        )
        let popupSmoke = popupSmoke(
            extraction: extraction,
            resourceScan: resourceScan,
            hasPopupOptions: hasPopupOptions
        )
        let contentSmoke = contentSmoke(
            manifest: manifest,
            lifecycleResult: trial.lifecycleResult,
            extraction: extraction,
            selected: selected
        )
        let permissionSmoke = permissionSmoke(extraction: extraction)
        let apiBlockers =
            uniqueSortedRealPackages(extraction.unsupportedOrDeferredAPIs)
        let manifestBlockers =
            uniqueSortedRealPackages(
                (installReport?.warnings.map {
                    "\($0.code): \($0.message)"
                } ?? [])
                    + (installReport?.fatalValidationErrors.map {
                        "\($0.code): \($0.message)"
                    } ?? [])
            )
        let webKitBlockers =
            uniqueSortedRealPackages(
                (requiresCSS ? ["CSS content-script injection requires scoped WebKit strategy and deterministic teardown."] : [])
                    + (requiresMainWorld ? ["MAIN-world content scripts require a constrained bridge design."] : [])
                    + (requiresMultiFrame ? ["Multi-frame/about:blank/origin-fallback content scripts require safe WebKit frame targeting."] : [])
                    + (extraction.backgroundServiceWorker != nil ? ["MV3 service-worker wake/keepalive behavior remains diagnostics-only."] : [])
            )
        let packageBlockers =
            uniqueSortedRealPackages(
                (lifecycleSucceeded ? [] : trial.diagnostics)
                    + packageBlockers(for: configuration)
            )
        let nativeBlockers =
            uniqueSortedRealPackages(nativeSmoke.diagnostics.filter {
                $0.contains("blocked") || $0.contains("No trusted")
            })
        let permissionBlockers =
            permissionSmoke.silentlyGranted
                ? ["Permission smoke silently granted a permission."]
                : ["Permission smoke records required/optional access without silent grants."]
        let contentBlockers = contentSmoke.blockers
        let popupBlockers =
            uniqueSortedRealPackages(popupSmoke.blockedAPIs.map {
                "\($0.namespace).\($0.methodName): \($0.reason)"
            })
        let productPolicyBlockers =
            uniqueSortedRealPackages(
                [
                    "Developer-preview diagnostic only; public password-manager support remains blocked.",
                    "Product runtime is not globally loadable or exposed.",
                ]
                    + (extraction.declaresDNR ? ["Product DNR/WKContentRuleList enforcement is not enabled."] : [])
                    + (extraction.declaresWebRequest ? ["Product webRequest runtime/enforcement is not enabled."] : [])
                    + (extraction.declaresSidePanel ? ["Product sidePanel runtime is not enabled."] : [])
                    + (extraction.declaresOffscreen ? ["Product offscreen runtime is not enabled."] : [])
                    + (extraction.declaresIdentity ? ["Product identity/OAuth runtime is not enabled."] : [])
            )
        let blockers =
            uniqueSortedRealPackages(
                packageBlockers
                    + manifestBlockers
                    + webKitBlockers
                    + nativeBlockers
                    + contentBlockers
                    + popupBlockers
                    + productPolicyBlockers
            )
        let fixtureDelta = fixtureDelta(
            target: target,
            extraction: extraction,
            realBlockers: blockers,
            fixtureRow: fixtureRow
        )
        let nativeStatus:
            ChromeMV3PasswordManagerCompatibilityStatus =
                nativeRequired || nativeOptional
                    ? (nativeSmoke.fixtureExchangeSucceeded ? .partial : .blocked)
                    : .notRequired
        let dnrWebRequestStatus:
            ChromeMV3PasswordManagerCompatibilityStatus =
                extraction.declaresDNR || extraction.declaresWebRequest
                    ? .deferred : .notRequired
        let identityStatus:
            ChromeMV3PasswordManagerCompatibilityStatus =
                extraction.declaresSidePanel
                    || extraction.declaresOffscreen
                    || extraction.declaresIdentity
                    ? .deferred : .notRequired

        return ChromeMV3PasswordManagerRealPackageCompatibilityRow(
            targetID: target.targetID,
            targetDisplayName: target.displayName,
            targetClass: target.targetClass,
            packageSource: selected.source,
            detectedPackageKind: configuration.detectedPackageKind,
            packagePath: selected.packageURL?.path,
            intake:
                selected.source == .fixtureFallback
                    ? .fixtureOnly : (lifecycleSucceeded ? .pass : .blocked),
            manifest:
                manifest != nil && lifecycleSucceeded ? .pass : .blocked,
            generatedBundle: generatedAvailable ? .pass : .blocked,
            popupOptions: hasPopupOptions ? .partial : .notRequired,
            popupOptionsJSBridge:
                hasPopupOptions ? popupSmoke.jsBridgeStatus : .notRequired,
            contentScripts: hasContentScripts ? .partial : .notRequired,
            css: requiresCSS ? .unsafeWithoutReview : .notRequired,
            mainWorld:
                requiresMainWorld ? .unsafeWithoutReview : .notRequired,
            multiFrame: requiresMultiFrame ? .deferred : .notRequired,
            permissions: .partial,
            activeTab:
                extraction.permissions.contains("activeTab")
                    || extraction.optionalPermissions.contains("activeTab")
                    ? .partial : .notRequired,
            tabsQuery:
                extraction.permissions.contains("tabs")
                    || extraction.optionalPermissions.contains("tabs")
                    || extraction.permissions.contains("activeTab")
                    ? .partial : .notRequired,
            tabsSendMessage: contentSmoke.tabsSendMessageStatus,
            tabsConnect: contentSmoke.tabsConnectStatus,
            storageLocal:
                extraction.permissions.contains("storage")
                    || extraction.optionalPermissions.contains("storage")
                    ? .partial : .notRequired,
            nativeMessaging: nativeStatus,
            serviceWorkerLifecycle:
                extraction.backgroundServiceWorker != nil ? .blocked : .notRequired,
            dnrWebRequest: dnrWebRequestStatus,
            sidePanelOffscreenIdentity: identityStatus,
            manifestRequirements: extraction,
            popupOptionsSmoke: popupSmoke,
            contentScriptSmoke: contentSmoke,
            permissionActiveTabSmoke: permissionSmoke,
            nativeMessagingSmoke: nativeSmoke,
            fixtureDelta: fixtureDelta,
            apiBlockers: apiBlockers,
            manifestBlockers: manifestBlockers,
            webKitBlockers: webKitBlockers,
            packageBlockers: packageBlockers,
            nativeHostBlockers: nativeBlockers,
            permissionBlockers: permissionBlockers,
            contentScriptBlockers: contentBlockers,
            popupOptionsBlockers: popupBlockers,
            productPolicyBlockers: productPolicyBlockers,
            productReadiness: .blocked,
            blockerSummary: blockers,
            nextRecommendedFix: fixtureDelta.nextRecommendedFix,
            notPublicSupportDisclaimer:
                "Developer-preview diagnostic only; not Chrome parity and not public Bitwarden/1Password/Proton Pass support."
        )
    }

    private static func popupSmoke(
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction,
        resourceScan: ChromeMV3PasswordManagerRealPackageResourceScan,
        hasPopupOptions: Bool
    ) -> ChromeMV3PasswordManagerRealPackagePopupOptionsSmoke {
        let policy = ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
        let detectedUnsupported = resourceScan.detectedChromeAPIs.filter {
            policy.allowedMethods.contains($0) == false
        }
        let blocked = uniqueSortedRealPackages(detectedUnsupported).map {
            let api = $0.hasPrefix("chrome.")
                ? String($0.dropFirst("chrome.".count))
                : $0
            let parts = api.split(separator: ".", maxSplits: 1)
            let namespace = parts.first.map(String.init) ?? "unsupported"
            let method = parts.count > 1 ? String(parts[1]) : "*"
            return policy.blockedDiagnostic(
                namespace: namespace,
                methodName: method
            )
        }
        return ChromeMV3PasswordManagerRealPackagePopupOptionsSmoke(
            popupPath: extraction.actionDefaultPopup,
            optionsPath: extraction.optionsUIPage ?? extraction.optionsPage,
            documentLoadStatus: hasPopupOptions ? .deferred : .notRequired,
            jsBridgeStatus: hasPopupOptions ? .partial : .notRequired,
            allowedSmokeMethods: [
                "permissions.getAll",
                "runtime.getURL",
                "runtime.sendMessage",
                "storage.local.get",
                "storage.local.set",
                "tabs.query",
            ],
            blockedAPIs: blocked.sorted {
                if $0.namespace != $1.namespace {
                    return $0.namespace < $1.namespace
                }
                return $0.methodName < $1.methodName
            },
            diagnostics:
                uniqueSortedRealPackages([
                    hasPopupOptions
                        ? "Popup/options pages were preflighted for developer-preview bridge coverage; real vendor page execution was not required for this report."
                        : "No popup/options page was declared.",
                    "No login, account, vault, token, or intentional network/auth call was performed.",
                    "Unsupported popup/options API calls are reported from manifest/resource analysis and bridge allowlist policy.",
                ])
        )
    }

    private static func contentSmoke(
        manifest: ChromeMV3Manifest?,
        lifecycleResult: ChromeMV3LifecycleOperationResult?,
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction,
        selected: SelectedPackage
    ) -> ChromeMV3PasswordManagerRealPackageContentScriptSmoke {
        let loginURL = "https://example.com/login"
        guard let manifest,
              let packageRoot = selected.resourceScanRootPath
                ?? lifecycleResult?.record?.originalBundleRootPath
        else {
            return ChromeMV3PasswordManagerRealPackageContentScriptSmoke(
                syntheticLoginURL: loginURL,
                declaredContentScriptCount: extraction.contentScripts.count,
                matchedContentScriptCount: 0,
                attachmentStatus: .blocked,
                tabsSendMessageStatus: .blocked,
                tabsConnectStatus: .blocked,
                blockers: ["Manifest or package root unavailable for content-script preflight."],
                diagnostics: ["Content-script preflight was skipped."]
            )
        }
        let extensionID = lifecycleResult?.record?.extensionID
            ?? "password-manager-real-package-extension"
        let profileID = lifecycleResult?.record?.profileID
            ?? "password-manager-real-package-profile"
        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL:
                URL(fileURLWithPath: packageRoot, isDirectory: true),
            extensionID: extensionID,
            profileID: profileID
        )
        let broker = ChromeMV3PermissionBroker(
            state: ChromeMV3PermissionBrokerState(
                extensionID: extensionID,
                profileID: profileID,
                requiredPermissions: manifest.permissions,
                optionalPermissions: manifest.optionalPermissions,
                hostPermissions: manifest.hostPermissions,
                optionalHostPermissions: manifest.optionalHostPermissions,
                diagnostics: [
                    "Real-package content-script preflight does not silently grant permissions.",
                ]
            )
        )
        let preflight = ChromeMV3NormalTabContentScriptPreflightEvaluator
            .evaluate(
                input: ChromeMV3NormalTabContentScriptPreflightInput(
                    moduleEnabled: true,
                    extensionEnabled: true,
                    productRuntimePreflightAllowsNormalTabAttachment: false,
                    contentScriptGate:
                        ChromeMV3ContentScriptProductGateRecord
                        .defaultBlocked(),
                    attachmentPlan: plan,
                    permissionBroker: broker,
                    tabID: 1,
                    frameID: 0,
                    documentID: "real-package-synthetic-login-main-frame",
                    navigationSequence: 1,
                    urlString: loginURL,
                    tabSurface: .normalTab,
                    generatedBundleActive:
                        lifecycleResult?.generatedVersion != nil,
                    webKitUserContentControllerAvailable: true,
                    teardownPending: false
                )
            )
        let blockers = uniqueSortedRealPackages(
            preflight.blockers.map(\.rawValue)
                + plan.declaredScripts.flatMap { script in
                    script.blockers.map(\.rawValue)
                }
        )
        let hasMessageListener = plan.declaredScripts.contains(where: { script in
            script.jsFiles.contains(where: { path in
                path.localizedCaseInsensitiveContains("message")
                    || path.localizedCaseInsensitiveContains("autofill")
            })
        })
        return ChromeMV3PasswordManagerRealPackageContentScriptSmoke(
            syntheticLoginURL: loginURL,
            declaredContentScriptCount: plan.declaredScripts.count,
            matchedContentScriptCount: preflight.matchedScripts.count,
            attachmentStatus:
                preflight.canAttachDeclaredContentScriptsNow
                    ? .partial : .blocked,
            tabsSendMessageStatus:
                hasMessageListener ? .partial : .blocked,
            tabsConnectStatus:
                preflight.canRegisterEndpointNow ? .partial : .blocked,
            blockers: blockers,
            diagnostics:
                uniqueSortedRealPackages(
                    preflight.diagnostics + [
                        "Synthetic login URL was used for match-pattern preflight.",
                        "No real page credentials or profile data were used.",
                    ]
                )
        )
    }

    private static func permissionSmoke(
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction
    ) -> ChromeMV3PasswordManagerRealPackagePermissionSmoke {
        ChromeMV3PasswordManagerRealPackagePermissionSmoke(
            requiredPermissions: extraction.permissions,
            optionalPermissions: extraction.optionalPermissions,
            requiredHostPermissions: extraction.hostPermissions,
            optionalHostPermissions: extraction.optionalHostPermissions,
            acceptDenyRevokeModeledByTestPresenter: true,
            silentlyGranted: false,
            urlTitleRedactionTested: true,
            endpointInvalidationAfterRevokeModeled: true,
            diagnostics: [
                "Required and optional permissions are summarized without granting anything silently.",
                "Accept/deny/revoke, URL/title redaction, and endpoint invalidation remain modeled through existing developer-preview test presenters.",
            ]
        )
    }

    private static func nativeSmoke(
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        selected: SelectedPackage,
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction,
        nativeRequired: Bool,
        nativeOptional: Bool
    ) -> ChromeMV3PasswordManagerRealPackageNativeMessagingSmoke {
        let hostNames =
            uniqueSortedRealPackages(
                target.configuredNativeHostNames
                    + selected.configuredNativeHostNames
                    + extraction.detectedNativeHostNames
            )
        let requiresNative = nativeRequired || nativeOptional
        let trustedRoot = target.trustedFixtureHostRootPath
        let noTrusted = requiresNative && trustedRoot == nil
        return ChromeMV3PasswordManagerRealPackageNativeMessagingSmoke(
            required: nativeRequired,
            optional: nativeOptional,
            hostNames: hostNames,
            trustedFixtureHostRootPath: trustedRoot,
            noTrustedHostConfigured: noTrusted,
            arbitraryHostDiscoveryBlocked: true,
            realVendorHostLaunchBlocked: true,
            fixtureExchangeAttempted: false,
            fixtureExchangeSucceeded: false,
            diagnostics:
                uniqueSortedRealPackages(
                    requiresNative
                        ? [
                            noTrusted
                                ? "No trusted fixture native-host root is configured for this real package target."
                                : "Trusted fixture native-host root is configured; exchange remains explicit test-only.",
                            "Arbitrary native host discovery is blocked.",
                            "Real vendor native host launch is blocked.",
                        ]
                        : [
                            "nativeMessaging is not required by this manifest/resource scan.",
                            "Arbitrary native host discovery remains blocked.",
                            "Real vendor native host launch remains blocked.",
                        ]
                )
        )
    }

    private static func fixtureDelta(
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction,
        realBlockers: [String],
        fixtureRow: ChromeMV3PasswordManagerCompatibilityMatrixRow?
    ) -> ChromeMV3PasswordManagerRealPackageFixtureDelta {
        let fixtureTarget = ChromeMV3PasswordManagerCompatibilityTargetCatalog
            .target(target.targetClass.fixtureFallbackKind)
        let fixtureAPIs =
            uniqueSortedRealPackages(
                fixtureTarget.requiredPermissions
                    + fixtureTarget.optionalPermissions
                    + fixtureTarget.knownBlockedDeferredAPIs
                    + fixtureTarget.runtimeTabsMessagingRequirements
            )
        let realAPIs =
            uniqueSortedRealPackages(
                extraction.permissions
                    + extraction.optionalPermissions
                    + extraction.unsupportedOrDeferredAPIs
            )
        let realOnly = Array(Set(realAPIs).subtracting(fixtureAPIs)).sorted()
        let fixtureOnly = Array(Set(fixtureAPIs).subtracting(realAPIs)).sorted()
        var riskDeltas = realOnly.map {
            "Real package declares or references \($0), which is absent from the Prompt 64 fixture baseline."
        }
        if extraction.contentScripts.count
            > fixtureTarget.contentScriptRequirement.matches.count
        {
            riskDeltas.append(
                "Real package has a broader/more numerous content-script surface than the class fixture."
            )
        }
        let nextFix = nextFix(
            extraction: extraction,
            realOnly: realOnly,
            realBlockers: realBlockers
        )
        return ChromeMV3PasswordManagerRealPackageFixtureDelta(
            fixtureFallbackID: target.fixtureFallbackID,
            fixtureProductReadiness:
                fixtureRow?.productReadiness ?? .blocked,
            realAPIsAbsentInFixture: realOnly,
            fixtureAPIsAbsentInReal: fixtureOnly,
            newBlockers: realBlockers,
            resolvedBlockers: [],
            riskDeltas: uniqueSortedRealPackages(riskDeltas),
            nextRecommendedFix: nextFix
        )
    }

    private static func nextFix(
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction,
        realOnly: [String],
        realBlockers: [String]
    ) -> String {
        if realBlockers.contains(where: { $0.contains("MAIN-world") }) {
            return "Design a constrained MAIN-world content-script bridge before accepting these real package scripts."
        }
        if realBlockers.contains(where: { $0.contains("CSS") }) {
            return "Review WebKit-safe CSS content-script scoping and teardown before enabling manifest CSS."
        }
        if realBlockers.contains(where: { $0.contains("Multi-frame") }) {
            return "Add safe frame-targeted attachment diagnostics before multi-frame real package support."
        }
        if extraction.declaresNativeMessaging {
            return "Configure only trusted fixture native-host roots and keep real vendor host launch blocked."
        }
        if extraction.declaresDNR || extraction.declaresWebRequest {
            return "Keep DNR/webRequest as diagnostics until a product network policy exists."
        }
        if realOnly.isEmpty == false {
            return "Triage real-package APIs absent from the Prompt 64 fixture baseline before broadening compatibility."
        }
        return "Continue real local package trials while keeping product support claims blocked."
    }

    private static func packageBlockers(
        for configuration:
            ChromeMV3PasswordManagerRealPackageTargetConfiguration
    ) -> [String] {
        switch configuration.detectedPackageKind {
        case .missing:
            return ["Real package root missing; fixture fallback used."]
        case .ambiguous:
            return ["Real package root ambiguous; fixture fallback used."]
        case .invalid:
            return ["Real package root invalid; fixture fallback used."]
        case .blockedCrxTrustPolicyRequired:
            return ["Local CRX package blocked by missing trust policy; fixture fallback used."]
        case .unpackedExtensionRoot, .directoryContainingSingleExtensionRoot,
             .directoryContainingLocalZip:
            return []
        }
    }

    private static func fallbackSource(
        for detectedKind: ChromeMV3PasswordManagerRealPackageDetectedKind
    ) -> ChromeMV3PasswordManagerRealPackageSource {
        switch detectedKind {
        case .missing:
            return .fixtureFallback
        case .ambiguous:
            return .fixtureFallback
        case .invalid:
            return .fixtureFallback
        case .blockedCrxTrustPolicyRequired:
            return .fixtureFallback
        case .unpackedExtensionRoot, .directoryContainingSingleExtensionRoot:
            return .realLocalUnpacked
        case .directoryContainingLocalZip:
            return .realLocalZip
        }
    }

    private static func policyKeys(from manifest: ChromeMV3Manifest) -> [String] {
        var keys: [String] = []
        let permissions =
            uniqueSortedRealPackages(
                manifest.permissions + manifest.optionalPermissions
            )
        if manifest.topLevelKeys.contains("content_security_policy") {
            keys.append("content_security_policy")
        }
        if manifest.topLevelKeys.contains("sandbox") {
            keys.append("sandbox")
        }
        if manifest.topLevelKeys.contains("externally_connectable") {
            keys.append("externally_connectable")
        }
        if manifest.topLevelKeys.contains("update_url") {
            keys.append("update_url")
        }
        if manifest.topLevelKeys.contains("storage") {
            keys.append("storage.managed_schema")
        }
        if manifest.devtoolsPage != nil {
            keys.append("devtools_page")
        }
        if manifest.declarativeNetRequest != nil
            || permissions.contains("declarativeNetRequest")
            || permissions.contains("declarativeNetRequestWithHostAccess")
            || permissions.contains("declarativeNetRequestFeedback")
        {
            keys.append("declarativeNetRequest")
        }
        if permissions.contains("webRequest")
            || permissions.contains("webRequestBlocking")
            || permissions.contains("webRequestAuthProvider")
        {
            keys.append("webRequest")
        }
        if manifest.sidePanel != nil || permissions.contains("sidePanel") {
            keys.append("sidePanel")
        }
        if permissions.contains("offscreen") {
            keys.append("offscreen")
        }
        if permissions.contains("identity")
            || permissions.contains("identity.email")
            || manifest.oauth2 != nil
        {
            keys.append("identity")
        }
        return uniqueSortedRealPackages(keys)
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                "Chrome manifest file format",
                "https://developer.chrome.com/docs/extensions/reference/manifest",
                "Checked MV3 manifest keys, host permissions, web accessible resources, action/options, CSP, sandbox, and devtools metadata."
            ),
            source(
                "Chrome action popup",
                "https://developer.chrome.com/docs/extensions/develop/ui/add-popup",
                "Checked action.default_popup and popup lifecycle expectations."
            ),
            source(
                "Chrome options pages",
                "https://developer.chrome.com/docs/extensions/develop/ui/options-page",
                "Checked options_page and options_ui.page behavior."
            ),
            source(
                "Chrome content scripts",
                "https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts",
                "Checked static content scripts, CSS, MAIN/ISOLATED worlds, all_frames, match_about_blank, and match_origin_as_fallback."
            ),
            source(
                "Chrome message passing",
                "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
                "Checked runtime.sendMessage/connect and tabs.sendMessage/connect expectations."
            ),
            source(
                "Chrome tabs API",
                "https://developer.chrome.com/docs/extensions/reference/api/tabs",
                "Checked tabs.query sensitive fields and tab messaging."
            ),
            source(
                "Chrome permissions and activeTab",
                "https://developer.chrome.com/docs/extensions/develop/concepts/declare-permissions",
                "Checked permission declarations, host permissions, optional permissions, and activeTab implications."
            ),
            source(
                "Chrome storage API",
                "https://developer.chrome.com/docs/extensions/reference/api/storage",
                "Checked storage.local behavior for extension pages and content scripts."
            ),
            source(
                "Chrome native messaging",
                "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                "Checked nativeMessaging permission, host manifests, allowed_origins, and process boundary."
            ),
            source(
                "Chrome service-worker lifecycle",
                "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                "Checked MV3 event-driven service-worker lifecycle constraints."
            ),
            source(
                "Chrome extension packaging",
                "https://developer.chrome.com/docs/extensions/how-to/distribute/package-host",
                "Checked local package/distribution constraints; this runner does not download or import remote CRX packages."
            ),
        ]
    }

    private static func source(
        _ title: String,
        _ url: String,
        _ note: String
    ) -> ChromeMV3WebKitObjectAcceptanceDocumentationSource {
        ChromeMV3WebKitObjectAcceptanceDocumentationSource(
            kind: "chromeDocumentation",
            title: title,
            url: url,
            note: note
        )
    }
}

private struct SelectedPackage {
    var source: ChromeMV3PasswordManagerRealPackageSource
    var packageURL: URL?
    var resourceScanRootPath: String?
    var configuredNativeHostNames: [String]
    var diagnostics: [String]
}

private struct PackageTrialResult {
    var lifecycleResult: ChromeMV3LifecycleOperationResult?
    var packageIntakeReport: ChromeMV3PackageIntakeReport?
    var acceptedPackageRootPath: String?
    var diagnostics: [String]
}

enum ChromeMV3PasswordManagerRealPackageResourceScanner {
    static func scan(
        packageRootPath: String?,
        fileManager: FileManager = .default
    ) -> ChromeMV3PasswordManagerRealPackageResourceScan {
        guard let packageRootPath else {
            return ChromeMV3PasswordManagerRealPackageResourceScan(
                scannedTextFileCount: 0,
                skippedFileCount: 0,
                skippedSymlinkCount: 0,
                detectedChromeAPIs: [],
                detectedNativeHostNames: [],
                diagnostics: ["No package root was available for resource scan."]
            )
        }
        let root = URL(fileURLWithPath: packageRootPath, isDirectory: true)
            .standardizedFileURL
        guard fileManager.fileExists(atPath: root.path) else {
            return ChromeMV3PasswordManagerRealPackageResourceScan(
                scannedTextFileCount: 0,
                skippedFileCount: 0,
                skippedSymlinkCount: 0,
                detectedChromeAPIs: [],
                detectedNativeHostNames: [],
                diagnostics: ["Package root does not exist for resource scan."]
            )
        }
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        )
        var scanned = 0
        var skipped = 0
        var skippedSymlink = 0
        var apis: [String] = []
        var hosts: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            if isSymlink(url) {
                skippedSymlink += 1
                enumerator?.skipDescendants()
                continue
            }
            guard isRegularFile(url),
                  safeURLInsideRoot(url.resolvingSymlinksInPath(), root: root),
                  isScannableTextResource(url)
            else {
                skipped += 1
                continue
            }
            guard scanned < 4_000 else {
                skipped += 1
                continue
            }
            guard let data = try? Data(contentsOf: url),
                  data.count <= 2_000_000,
                  let text = String(data: data, encoding: .utf8)
            else {
                skipped += 1
                continue
            }
            scanned += 1
            apis.append(contentsOf: detectedAPIs(in: text))
            hosts.append(contentsOf: nativeHostNames(in: text))
        }
        return ChromeMV3PasswordManagerRealPackageResourceScan(
            scannedTextFileCount: scanned,
            skippedFileCount: skipped,
            skippedSymlinkCount: skippedSymlink,
            detectedChromeAPIs: uniqueSortedRealPackages(apis),
            detectedNativeHostNames: uniqueSortedRealPackages(hosts),
            diagnostics: [
                "Resource scan stayed inside the selected explicit local package root.",
                "Text resource scan detected Chrome API tokens only; no credentials or secret values are serialized.",
            ]
        )
    }

    private static func detectedAPIs(in text: String) -> [String] {
        [
            "chrome.alarms",
            "chrome.contextMenus",
            "chrome.declarativeNetRequest",
            "chrome.downloads",
            "chrome.identity",
            "chrome.management",
            "chrome.notifications",
            "chrome.offscreen",
            "chrome.permissions.contains",
            "chrome.permissions.getAll",
            "chrome.permissions.remove",
            "chrome.permissions.request",
            "chrome.runtime.connect",
            "chrome.runtime.connectNative",
            "chrome.runtime.getURL",
            "chrome.runtime.sendMessage",
            "chrome.runtime.sendNativeMessage",
            "chrome.scripting.executeScript",
            "chrome.sidePanel",
            "chrome.storage.local",
            "chrome.tabs.connect",
            "chrome.tabs.query",
            "chrome.tabs.sendMessage",
            "chrome.webNavigation",
            "chrome.webRequest",
        ].filter { text.contains($0) }
    }

    private static func nativeHostNames(in text: String) -> [String] {
        let pattern =
            #"(?:connectNative|sendNativeMessage)\s*\(\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern)
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let hostRange = Range(match.range(at: 1), in: text)
            else { return nil }
            let host = String(text[hostRange])
            return host.isEmpty ? nil : host
        }
    }

    private static func isScannableTextResource(_ url: URL) -> Bool {
        [
            "css",
            "html",
            "js",
            "json",
            "mjs",
        ].contains(url.pathExtension.lowercased())
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))
            .flatMap(\.isRegularFile) == true
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))
            .flatMap(\.isSymbolicLink) == true
    }
}

extension ChromeMV3LifecycleRuntimeDiagnosticsSnapshot {
    static let passwordManagerRealPackageCompatibilityPass =
        ChromeMV3LifecycleRuntimeDiagnosticsSnapshot(
            WebKitObjectDiagnosticsAvailable: true,
            contextCreationGateDiagnosticsAvailable: true,
            controllerLoadGateDiagnosticsAvailable: true,
            runtimeBridgeReadinessDiagnosticsAvailable: true,
            runtimeJSMessagingDiagnosticsAvailable: true,
            tabsScriptingDiagnosticsAvailable: true,
            permissionsDiagnosticsAvailable: true,
            storageDiagnosticsAvailable: true,
            nativeMessagingDiagnosticsAvailable: true,
            serviceWorkerDiagnosticsAvailable: true,
            eventAPIDiagnosticsAvailable: true,
            networkDiagnosticsAvailable: true,
            sidePanelOffscreenIdentityDiagnosticsAvailable: true,
            passwordManagerDiagnosticsAvailable: true,
            diagnostics: [
                "Real-package compatibility pass links existing MV3 diagnostics without enabling product runtime.",
            ]
        )
}

private func safeURLInsideRoot(_ url: URL, root: URL) -> Bool {
    let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    return path == rootPath || path.hasPrefix(rootPath + "/")
}

private func uniqueSortedRealPackages(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}
