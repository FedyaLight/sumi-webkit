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
    var detectedExtensionID: String?
    var generatedOrTestExtensionID: String?
    var nativeFixtureRootState:
        ChromeMV3PasswordManagerRealPackageNativeHostFixtureRootState
    var fixtureManifestPathCandidates: [String]
    var fixtureExecutablePathCandidates: [String]
    var nativeHostBlockerState:
        ChromeMV3PasswordManagerRealPackageNativeHostReadinessState?
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
    private static let explicitFixtureRootBase =
        "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/native-host-fixtures"

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
                trustedFixtureHostRootPath:
                    "\(explicitFixtureRootBase)/bitwarden",
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
                trustedFixtureHostRootPath:
                    "\(explicitFixtureRootBase)/proton",
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
                trustedFixtureHostRootPath:
                    "\(explicitFixtureRootBase)/1password",
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
            detectedExtensionID: nil,
            generatedOrTestExtensionID: target.expectedExtensionID,
            nativeFixtureRootState:
                target.trustedFixtureHostRootPath == nil
                    ? .notConfigured : .missingFixtureRoot,
            fixtureManifestPathCandidates: [],
            fixtureExecutablePathCandidates: [],
            nativeHostBlockerState: nil,
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

enum ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case mainWorker
    case importScriptsDependency
    case dynamicImportCandidate
    case moduleDependencyCandidate
    case unknownComputedDependency

    static func < (
        lhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind,
        rhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerRealPackageDynamicImportShape:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case stringLiteralLocal
    case templateLiteralStatic
    case templateLiteralDynamic
    case identifier
    case memberExpression
    case callExpression
    case conditionalExpression
    case concatenation
    case unknownComputed
    case remoteOrUnsafe

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageDynamicImportShape,
        rhs: ChromeMV3PasswordManagerRealPackageDynamicImportShape
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerRealPackageAsyncAPI:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case asyncFunction
    case eventSource = "EventSource"
    case fetch
    case promiseThen = "Promise.then"
    case queueMicrotask
    case setInterval
    case setTimeout
    case webSocket = "WebSocket"

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageAsyncAPI,
        rhs: ChromeMV3PasswordManagerRealPackageAsyncAPI
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation:
    Codable,
    Equatable,
    Sendable
{
    var sourceKind:
        ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind
    var sourcePath: String
    var line: Int
    var snippet: String
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerDynamicImportInventory:
    Codable,
    Equatable,
    Sendable
{
    var sourceKind:
        ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind
    var sourcePath: String
    var line: Int
    var rawCallPreview: String
    var specifierPreview: String
    var shape: ChromeMV3PasswordManagerRealPackageDynamicImportShape
    var hasOptionsArgument: Bool
    var dependencyCandidatePath: String?
    var generatedRootContained: Bool?
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerImportScriptsInventory:
    Codable,
    Equatable,
    Sendable
{
    var sourceKind:
        ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind
    var sourcePath: String
    var line: Int
    var rawCallPreview: String
    var specifierPreview: String
    var shape: ChromeMV3PasswordManagerRealPackageDynamicImportShape
    var dependencyCandidatePath: String?
    var generatedRootContained: Bool?
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerModuleImportDeclaration:
    Codable,
    Equatable,
    Sendable
{
    var sourcePath: String
    var line: Int
    var rawDeclarationPreview: String
    var specifier: String
    var dependencyCandidatePath: String?
    var generatedRootContained: Bool?
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyCandidate:
    Codable,
    Equatable,
    Sendable
{
    var sourceKind:
        ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind
    var requestedSpecifier: String
    var parentSourcePath: String
    var resolvedCandidatePath: String?
    var generatedRootContained: Bool?
    var scanned: Bool
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerModuleWorkerInventory:
    Codable,
    Equatable,
    Sendable
{
    var declaredAsModuleWorker: Bool
    var staticImportDeclarations:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerModuleImportDeclaration]
    var exportUsageLocations:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation]
    var dynamicImportUsage:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerDynamicImportInventory]
    var topLevelAwaitDetected: Bool
    var topLevelAwaitLocations:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation]
    var dependencyCandidatePaths:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyCandidate]
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPITotal:
    Codable,
    Equatable,
    Sendable
{
    var api: ChromeMV3PasswordManagerRealPackageAsyncAPI
    var count: Int
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIOccurrence:
    Codable,
    Equatable,
    Sendable
{
    var api: ChromeMV3PasswordManagerRealPackageAsyncAPI
    var sourceKind:
        ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind
    var sourcePath: String
    var line: Int
    var snippet: String
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIInventory:
    Codable,
    Equatable,
    Sendable
{
    var totals:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPITotal]
    var occurrences:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIOccurrence]
    var diagnostics: [String]

    func count(
        _ api: ChromeMV3PasswordManagerRealPackageAsyncAPI
    ) -> Int {
        totals.first { $0.api == api }?.count ?? 0
    }
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerFetchClassification:
    Codable,
    Equatable,
    Sendable
{
    var sourceKind:
        ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind
    var sourcePath: String
    var line: Int
    var rawCallPreview: String
    var requestPreview: String
    var resolvedURL: String?
    var requestKind: ChromeMV3ServiceWorkerJSFetchRequestKind
    var networkAccessRequired: Bool
    var extensionLocalResource: Bool
    var executionAllowed: Bool
    var blocker: String
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerListenerRegistration:
    Codable,
    Equatable,
    Sendable
{
    var sourceKind:
        ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind
    var sourcePath: String
    var line: Int
    var eventTarget: String
    var snippet: String
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerListenerRegistrationMap:
    Codable,
    Equatable,
    Sendable
{
    var registrations:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerListenerRegistration]
    var mainWorkerCount: Int
    var importScriptsDependencyCount: Int
    var dynamicImportCandidateCount: Int
    var moduleDependencyCandidateCount: Int
    var unknownComputedDependencyReferenceCount: Int
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory:
    Codable,
    Equatable,
    Sendable
{
    var serviceWorkerPath: String?
    var serviceWorkerType: String
    var packageRootPath: String?
    var generatedBundleRootPath: String?
    var scannedSourceFileCount: Int
    var dynamicImportExpressions:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerDynamicImportInventory]
    var importScriptsCalls:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerImportScriptsInventory]
    var moduleWorkerInventory:
        ChromeMV3PasswordManagerRealPackageServiceWorkerModuleWorkerInventory
    var asyncAPIInventory:
        ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIInventory
    var fetchClassifications:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerFetchClassification]
    var listenerRegistrationMap:
        ChromeMV3PasswordManagerRealPackageServiceWorkerListenerRegistrationMap
    var browserPlatformDeviceToStringDetected: Bool
    var chromeUserAgentBrowserFamilyCheckDetected: Bool
    var nextRecommendedImplementationPath: String
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

enum ChromeMV3PasswordManagerRealPackageE2ERoute:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case popupRuntimeGetURL
    case popupStorageLocalSet
    case popupStorageLocalGet
    case popupRuntimeSendMessage
    case popupRuntimeConnect
    case popupTabsQuery
    case popupTabsSendMessage
    case popupTabsConnect
    case contentScriptRuntimeSendMessage
    case contentScriptRuntimeConnect

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageE2ERoute,
        rhs: ChromeMV3PasswordManagerRealPackageE2ERoute
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerRealPackageNoReceiverClassification:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case expectedNoListener
    case missingPopupListener
    case missingContentScriptEndpoint
    case serviceWorkerListenerMissing
    case routeUnsupported
    case permissionBlocked
    case endpointStale
    case listenerThrew
    case actualUnsupportedAPI

    static func < (
        lhs:
            ChromeMV3PasswordManagerRealPackageNoReceiverClassification,
        rhs:
            ChromeMV3PasswordManagerRealPackageNoReceiverClassification
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PasswordManagerRealPackageE2ERouteResult:
    Codable,
    Equatable,
    Sendable
{
    var route: ChromeMV3PasswordManagerRealPackageE2ERoute
    var sourceSurface: String
    var targetSurface: String
    var status: ChromeMV3PasswordManagerCompatibilityStatus
    var noReceiverClassification:
        ChromeMV3PasswordManagerRealPackageNoReceiverClassification?
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var serviceWorkerWakeAttempted: Bool
    var nativeHostLaunchAttempted: Bool
    var payloadSummary: String
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackageE2EEndpointRegistryState:
    Codable,
    Equatable,
    Sendable
{
    var endpointCount: Int
    var activeEndpointCount: Int
    var messageListenerEndpointCount: Int
    var connectListenerEndpointCount: Int
    var portCount: Int
    var activePortCount: Int
    var endpointIDs: [String]
    var portIDs: [String]
    var tabsWithEndpoints: [Int]
    var senderMetadataRedacted: Bool
    var staleEndpointDetected: Bool
    var diagnostics: [String]

    static func make(
        summary: ChromeMV3ContentScriptEndpointRegistrySummary,
        senderMetadataRedacted: Bool
    ) -> ChromeMV3PasswordManagerRealPackageE2EEndpointRegistryState {
        ChromeMV3PasswordManagerRealPackageE2EEndpointRegistryState(
            endpointCount: summary.endpointCount,
            activeEndpointCount: summary.activeEndpointCount,
            messageListenerEndpointCount:
                summary.messageListenerEndpointCount,
            connectListenerEndpointCount:
                summary.connectListenerEndpointCount,
            portCount: summary.portCount,
            activePortCount: summary.activePortCount,
            endpointIDs: summary.endpointIDs,
            portIDs: summary.portIDs,
            tabsWithEndpoints: summary.tabsWithEndpoints,
            senderMetadataRedacted: senderMetadataRedacted,
            staleEndpointDetected:
                summary.lifecycleStates.contains(.navigationInvalidated),
            diagnostics: summary.diagnostics
        )
    }

    static let empty =
        ChromeMV3PasswordManagerRealPackageE2EEndpointRegistryState(
            endpointCount: 0,
            activeEndpointCount: 0,
            messageListenerEndpointCount: 0,
            connectListenerEndpointCount: 0,
            portCount: 0,
            activePortCount: 0,
            endpointIDs: [],
            portIDs: [],
            tabsWithEndpoints: [],
            senderMetadataRedacted: true,
            staleEndpointDetected: false,
            diagnostics: [
                "No content-script endpoint registry activity was attempted.",
            ]
        )
}

struct ChromeMV3PasswordManagerRealPackageE2ESyntheticLoginSurface:
    Codable,
    Equatable,
    Sendable
{
    var url: String
    var origin: String?
    var hostPermissionState: String
    var activeTabState: String
    var declaredContentScriptCount: Int
    var matchedContentScriptCount: Int
    var attachedContentScriptCount: Int
    var cssAttachmentStatus: ChromeMV3PasswordManagerCompatibilityStatus
    var jsEndpointStatus: ChromeMV3PasswordManagerCompatibilityStatus
    var endpointID: String?
    var senderURLRedacted: Bool
    var senderOriginRedacted: Bool
    var diagnostics: [String]

    static func notAttempted(url: String) -> Self {
        ChromeMV3PasswordManagerRealPackageE2ESyntheticLoginSurface(
            url: url,
            origin: ChromeMV3RuntimeMessagingURL.origin(from: url),
            hostPermissionState: "notAttempted",
            activeTabState: "notAttempted",
            declaredContentScriptCount: 0,
            matchedContentScriptCount: 0,
            attachedContentScriptCount: 0,
            cssAttachmentStatus: .notRequired,
            jsEndpointStatus: .notRequired,
            endpointID: nil,
            senderURLRedacted: true,
            senderOriginRedacted: true,
            diagnostics: [
                "Synthetic login page attachment was not attempted.",
            ]
        )
    }
}

struct ChromeMV3PasswordManagerRealPackageE2ESmoke:
    Codable,
    Equatable,
    Sendable
{
    var attempted: Bool
    var status: ChromeMV3PasswordManagerCompatibilityStatus
    var targetID: String
    var packageIntakeResult: ChromeMV3PasswordManagerCompatibilityStatus
    var generatedBundleResult: ChromeMV3PasswordManagerCompatibilityStatus
    var extensionEnabled: Bool
    var popupOptionsAvailability: ChromeMV3PasswordManagerCompatibilityStatus
    var popupDocumentLoadStatus: ChromeMV3PasswordManagerCompatibilityStatus
    var serviceWorkerStartupResult: ChromeMV3PasswordManagerCompatibilityStatus
    var serviceWorkerListenerCaptureStatus: String
    var contentScriptAttachResult: ChromeMV3PasswordManagerCompatibilityStatus
    var syntheticLoginSurface:
        ChromeMV3PasswordManagerRealPackageE2ESyntheticLoginSurface
    var endpointRegistryState:
        ChromeMV3PasswordManagerRealPackageE2EEndpointRegistryState
    var messageRoutesTested:
        [ChromeMV3PasswordManagerRealPackageE2ERouteResult]
    var unsupportedAPIsEncountered: [String]
    var noListenerNoReceiverResults:
        [ChromeMV3PasswordManagerRealPackageE2ERouteResult]
    var nextBlockerClassification:
        ChromeMV3PasswordManagerRealPackageNoReceiverClassification?
    var nextBlocker: String
    var serviceWorkerWakeAttempted: Bool
    var nativeHostLaunchAttempted: Bool
    var noCredentialsOrNetwork: Bool
    var diagnostics: [String]

    static func notRequired(
        targetID: String,
        packageIntakeResult: ChromeMV3PasswordManagerCompatibilityStatus,
        generatedBundleResult: ChromeMV3PasswordManagerCompatibilityStatus,
        extensionEnabled: Bool,
        unsupportedAPIs: [String],
        diagnostics: [String]
    ) -> ChromeMV3PasswordManagerRealPackageE2ESmoke {
        let loginURL = ChromeMV3PasswordManagerRealPackageTrialRunner
            .bitwardenE2ESyntheticLoginURL
        return ChromeMV3PasswordManagerRealPackageE2ESmoke(
            attempted: false,
            status: .notRequired,
            targetID: targetID,
            packageIntakeResult: packageIntakeResult,
            generatedBundleResult: generatedBundleResult,
            extensionEnabled: extensionEnabled,
            popupOptionsAvailability: .notRequired,
            popupDocumentLoadStatus: .notRequired,
            serviceWorkerStartupResult: .notRequired,
            serviceWorkerListenerCaptureStatus: "notRequired",
            contentScriptAttachResult: .notRequired,
            syntheticLoginSurface: .notAttempted(url: loginURL),
            endpointRegistryState: .empty,
            messageRoutesTested: [],
            unsupportedAPIsEncountered:
                uniqueSortedRealPackages(unsupportedAPIs),
            noListenerNoReceiverResults: [],
            nextBlockerClassification: nil,
            nextBlocker: "Not a Bitwarden target.",
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false,
            noCredentialsOrNetwork: true,
            diagnostics: uniqueSortedRealPackages(diagnostics)
        )
    }

    static func blocked(
        targetID: String,
        packageIntakeResult: ChromeMV3PasswordManagerCompatibilityStatus,
        generatedBundleResult: ChromeMV3PasswordManagerCompatibilityStatus,
        extensionEnabled: Bool,
        popupOptionsAvailability: ChromeMV3PasswordManagerCompatibilityStatus,
        popupDocumentLoadStatus: ChromeMV3PasswordManagerCompatibilityStatus,
        serviceWorkerStartupResult: ChromeMV3PasswordManagerCompatibilityStatus,
        serviceWorkerListenerCaptureStatus: String,
        contentScriptAttachResult: ChromeMV3PasswordManagerCompatibilityStatus,
        unsupportedAPIs: [String],
        blockerClassification:
            ChromeMV3PasswordManagerRealPackageNoReceiverClassification?,
        blocker: String,
        diagnostics: [String]
    ) -> ChromeMV3PasswordManagerRealPackageE2ESmoke {
        let loginURL = ChromeMV3PasswordManagerRealPackageTrialRunner
            .bitwardenE2ESyntheticLoginURL
        return ChromeMV3PasswordManagerRealPackageE2ESmoke(
            attempted: false,
            status: .blocked,
            targetID: targetID,
            packageIntakeResult: packageIntakeResult,
            generatedBundleResult: generatedBundleResult,
            extensionEnabled: extensionEnabled,
            popupOptionsAvailability: popupOptionsAvailability,
            popupDocumentLoadStatus: popupDocumentLoadStatus,
            serviceWorkerStartupResult: serviceWorkerStartupResult,
            serviceWorkerListenerCaptureStatus:
                serviceWorkerListenerCaptureStatus,
            contentScriptAttachResult: contentScriptAttachResult,
            syntheticLoginSurface: .notAttempted(url: loginURL),
            endpointRegistryState: .empty,
            messageRoutesTested: [],
            unsupportedAPIsEncountered:
                uniqueSortedRealPackages(unsupportedAPIs),
            noListenerNoReceiverResults: [],
            nextBlockerClassification: blockerClassification,
            nextBlocker: blocker,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false,
            noCredentialsOrNetwork: true,
            diagnostics: uniqueSortedRealPackages(diagnostics)
        )
    }
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

struct ChromeMV3PasswordManagerRealPackageServiceWorkerEventStatus:
    Codable,
    Equatable,
    Sendable
{
    var source: ChromeMV3ServiceWorkerEventSource
    var targetListener: ChromeMV3ServiceWorkerSyntheticListenerEvent
    var status: ChromeMV3PasswordManagerCompatibilityStatus
    var routingResultKind: ChromeMV3ServiceWorkerEventRoutingResultKind?
    var listenerDetected: Bool
    var listenerDetectionPattern: String?
    var payloadSummary: String
    var diagnostics: [String]
}

enum ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blockedDefault
    case explicitTestTrial
    case managerDiagnosticAction

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource,
        rhs: ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var allowsScopedExecution: Bool {
        switch self {
        case .blockedDefault:
            return false
        case .explicitTestTrial, .managerDiagnosticAction:
            return true
        }
    }
}

enum ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blockedDefault
    case closedAfterTrial
    case openScopedTrial

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateState,
        rhs: ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateRecord:
    Codable,
    Equatable,
    Sendable
{
    var targetID: String
    var extensionID: String
    var profileID: String
    var localPackageRoot: String?
    var generatedBundleID: String?
    var state:
        ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateState
    var source:
        ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource
    var reason: String
    var blockers: [String]
}

enum ChromeMV3PasswordManagerRealPackageServiceWorkerCaptureDeltaStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case executionBlocked
    case executionCaptured
    case executionFailed
    case noListener
    case staticOnly
    case unknown

    static func < (
        lhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerCaptureDeltaStatus,
        rhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerCaptureDeltaStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerCaptureDelta:
    Codable,
    Equatable,
    Sendable
{
    var status:
        ChromeMV3PasswordManagerRealPackageServiceWorkerCaptureDeltaStatus
    var staticListenerFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    var executionCapturedListenerFamilies:
        [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    var missingListenerFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    var extraCapturedListenerFamilies:
        [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    var unsupportedListenerForms: [String]
    var failedExecutionReason: String?
    var diagnostics: [String]
}

enum ChromeMV3PasswordManagerRealPackageNextBlockerClassification:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case moduleWorkerUnsupported
    case dynamicImportNamespaceUnsupported
    case dynamicImportComputedUnsupported
    case dynamicImportRewriteSucceededButListenerMissing
    case importScriptsDependencyMissing
    case networkFetchUnsupported
    case unsupportedChromeAPI
    case webCryptoUnsupported
    case workerWindowDOMUnsupported
    case promiseCompletionUnsupported = "PromiseCompletionUnsupported"
    case dispatchDelivered
    case dispatchEnvelopeMismatch
    case unsupportedEventFamily
    case noMatchingListener
    case listenerInvocationFailed
    case portShapeUnsupported
    case asyncCompletionUnsupported
    case listenerThrew
    case noResponse
    case blockedByGate
    case unknownDispatchFailure
    case listenerCaptureSucceeded
    case otherPreciseBlocker

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageNextBlockerClassification,
        rhs: ChromeMV3PasswordManagerRealPackageNextBlockerClassification
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerRealPackageDeviceFailureClassification:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notObserved
    case resolvedWorkerNavigatorBrowserFamilySignal
    case workerNavigatorBrowserFamilySignalRequired
    case realAccountStateRequired
    case deviceIdentityRequired
    case vaultStateRequired
    case nativeMessagingRequired
    case networkAuthRequired
    case unknown

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageDeviceFailureClassification,
        rhs: ChromeMV3PasswordManagerRealPackageDeviceFailureClassification
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerPortSmoke:
    Codable,
    Equatable,
    Sendable
{
    var attempted: Bool
    var connectResult: ChromeMV3ServiceWorkerJSDispatchRecord?
    var portMessageDelivered: Bool
    var portDisconnected: Bool
    var keepaliveReleased: Bool
    var diagnostics: [String]

    static let notAttempted =
        ChromeMV3PasswordManagerRealPackageServiceWorkerPortSmoke(
            attempted: false,
            connectResult: nil,
            portMessageDelivered: false,
            portDisconnected: false,
            keepaliveReleased: false,
            diagnostics: [
                "runtime.onConnect smoke was not attempted because no executed listener registration was available.",
            ]
        )
}

struct ChromeMV3PasswordManagerRealPackageServiceWorkerEventReadiness:
    Codable,
    Equatable,
    Sendable
{
    var declared: Bool
    var declarationReadiness: ChromeMV3ServiceWorkerDeclarationReadiness?
    var trialGateRecords:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateRecord]
    var jsExecutionPolicy: ChromeMV3ServiceWorkerJSExecutionPolicy
    var resourceLoadResult: ChromeMV3ServiceWorkerJSResourceLoadRecord?
    var dependencyInventory:
        ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory
    var executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    var actualListenerRegistrationCaptureStatus: String
    var capturedListenerFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    var missingListenerFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    var importScriptsResolvedCount: Int
    var importedScriptPaths: [String]
    var importScriptsBlockers: [ChromeMV3ServiceWorkerJSImportScriptsBlocker]
    var dynamicImportBlockers: [ChromeMV3ServiceWorkerJSDynamicImportBlocker]
    var staticVsExecutionDelta:
        ChromeMV3PasswordManagerRealPackageServiceWorkerCaptureDelta
    var actualDispatchResults: [ChromeMV3ServiceWorkerJSDispatchRecord]
    var importScriptsResult: String
    var computedImportScriptsResult: String
    var dynamicImportRewriteResult: String
    var cryptoCapabilityResult: String
    var cryptoOperationSummary: [String]
    var cryptoSubtleSupportedAlgorithms: [String]
    var cryptoSubtleBlockedAlgorithms: [String]
    var i18nCapabilityResult: String
    var i18nOperationSummary: [String]
    var alarmPolicyResult: String
    var alarmRecords: [ChromeMV3ServiceWorkerJSAlarmRecord]
    var alarmOperationSummary: [String]
    var alarmDispatchResult: String
    var workerNavigatorUserAgentResult: String
    var deviceFailureClassification:
        ChromeMV3PasswordManagerRealPackageDeviceFailureClassification
    var deviceFailureDetail: String
    var precedingChromeAPICalls: [String]
    var storageOperationSummary: [String]
    var runtimeSendMessagePolicyResult: String
    var runtimeSendMessageSummary: [String]
    var runtimeLastErrorObjectShapeResult: String
    var runtimeLastErrorCallbackLifecycleResult: String
    var workerGlobalEventTargetResult: String
    var workerGlobalEventSummary: [String]
    var fetchClassificationResult: String
    var fetchClassificationSummary: [String]
    var generatedBundleFetchResourceSummary: [String]
    var webAssemblyCapabilityResult: String
    var workerWindowFailureClassification: String
    var timerShimResult: String
    var moduleWorkerReadinessResult: String
    var dispatchSmokeResult: String
    var runtimePortSmoke:
        ChromeMV3PasswordManagerRealPackageServiceWorkerPortSmoke
    var nativeMessagingIntegrationSmoke: String
    var idleTeardownResult: String
    var hardTimeoutTeardownResult: String
    var gateClosedAfterTrial: Bool
    var popupOptionsRuntimeMessage: ChromeMV3PasswordManagerCompatibilityStatus
    var popupOptionsRuntimeConnect: ChromeMV3PasswordManagerCompatibilityStatus
    var contentScriptRuntimeMessage: ChromeMV3PasswordManagerCompatibilityStatus
    var contentScriptRuntimeConnect: ChromeMV3PasswordManagerCompatibilityStatus
    var storageChanged: ChromeMV3PasswordManagerCompatibilityStatus
    var permissionsAdded: ChromeMV3PasswordManagerCompatibilityStatus
    var permissionsRemoved: ChromeMV3PasswordManagerCompatibilityStatus
    var nativeMessagingConnect: ChromeMV3PasswordManagerCompatibilityStatus
    var nativeMessagingMessage: ChromeMV3PasswordManagerCompatibilityStatus
    var eventStatuses:
        [ChromeMV3PasswordManagerRealPackageServiceWorkerEventStatus]
    var blockers: [String]
    var nextBlockerClassification:
        ChromeMV3PasswordManagerRealPackageNextBlockerClassification
    var nextBlockerDetail: String
    var nextRecommendedFix: String
    var diagnostics: [String]
}

enum ChromeMV3PasswordManagerRealPackageNativeHostRequirementDetectionConfidence:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notRequired
    case manifestPermission
    case observedRuntimeCall
    case configuredTarget
    case fixtureMetadata
    case hostNameNotObservable

    static func < (
        lhs:
            ChromeMV3PasswordManagerRealPackageNativeHostRequirementDetectionConfidence,
        rhs:
            ChromeMV3PasswordManagerRealPackageNativeHostRequirementDetectionConfidence
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerRealPackageNativeHostFixtureRootState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notRequired
    case notConfigured
    case missingFixtureRoot
    case invalidFixtureRoot
    case configured

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageNativeHostFixtureRootState,
        rhs: ChromeMV3PasswordManagerRealPackageNativeHostFixtureRootState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerRealPackageNativeHostManifestState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notRequired
    case hostNameNotObservable
    case missing
    case valid
    case invalidHostName
    case invalidManifest
    case unsupported

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageNativeHostManifestState,
        rhs: ChromeMV3PasswordManagerRealPackageNativeHostManifestState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerRealPackageAllowedOriginsState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notRequired
    case notEvaluated
    case compatible
    case mismatch
    case invalidManifest

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageAllowedOriginsState,
        rhs: ChromeMV3PasswordManagerRealPackageAllowedOriginsState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerRealPackageNativeHostReadinessState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notRequired
    case hostRequiredButNotConfigured
    case hostNameNotObservable
    case hostManifestConfiguredButInvalid
    case allowedOriginsMismatch
    case permissionMissing
    case userApprovalMissing
    case userDenied
    case userRevoked
    case approvedTrustedFixtureHostWorks
    case fixtureExchangeFailed
    case realVendorHostDiscoveryBlocked
    case realVendorHostLaunchBlockedUnlessFixtureConfigured

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageNativeHostReadinessState,
        rhs: ChromeMV3PasswordManagerRealPackageNativeHostReadinessState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PasswordManagerRealPackageNativeHostExchangeState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notRequired
    case notAttempted
    case sendNativeMessageSucceeded
    case connectNativeSucceeded
    case succeeded
    case failed

    static func < (
        lhs: ChromeMV3PasswordManagerRealPackageNativeHostExchangeState,
        rhs: ChromeMV3PasswordManagerRealPackageNativeHostExchangeState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PasswordManagerRealPackageNativeFixtureExchangeResult:
    Codable,
    Equatable,
    Sendable
{
    var attempted: Bool
    var state:
        ChromeMV3PasswordManagerRealPackageNativeHostExchangeState
    var sendNativeMessageSucceeded: Bool
    var connectNativeSucceeded: Bool
    var postMessageSucceeded: Bool
    var disconnectSucceeded: Bool
    var fixtureProcessLaunchAttempted: Bool
    var productProcessLaunchAttempted: Bool
    var sendNativeMessageLastError: String?
    var connectNativeLastError: String?
    var diagnostics: [String]

    static func notAttempted(
        state:
            ChromeMV3PasswordManagerRealPackageNativeHostExchangeState =
                .notAttempted,
        diagnostics: [String]
    ) -> ChromeMV3PasswordManagerRealPackageNativeFixtureExchangeResult {
        ChromeMV3PasswordManagerRealPackageNativeFixtureExchangeResult(
            attempted: false,
            state: state,
            sendNativeMessageSucceeded: false,
            connectNativeSucceeded: false,
            postMessageSucceeded: false,
            disconnectSucceeded: false,
            fixtureProcessLaunchAttempted: false,
            productProcessLaunchAttempted: false,
            sendNativeMessageLastError: nil,
            connectNativeLastError: nil,
            diagnostics: uniqueSortedRealPackages(diagnostics)
        )
    }
}

struct ChromeMV3PasswordManagerRealPackageNativeHostReadiness:
    Codable,
    Equatable,
    Sendable
{
    var fixturePackID: String?
    var fixturePackGeneratedState:
        ChromeMV3NativeMessagingFixturePackGeneratedState
    var fixturePackValidatedState:
        ChromeMV3NativeMessagingFixturePackValidatedState
    var hostNameSource: String
    var hostName: String?
    var required: Bool
    var optional: Bool
    var detectionSources: [String]
    var detectionConfidence:
        ChromeMV3PasswordManagerRealPackageNativeHostRequirementDetectionConfidence
    var nativeMessagingPermissionDeclared: Bool
    var nativeMessagingPermissionState:
        ChromeMV3NativeMessagingPermissionState
    var fixtureRootPath: String?
    var fixtureRootState:
        ChromeMV3PasswordManagerRealPackageNativeHostFixtureRootState
    var fixtureManifestPathCandidates: [String]
    var fixtureExecutablePathCandidates: [String]
    var lookupStatus: ChromeMV3NativeHostLookupStatus?
    var manifestState:
        ChromeMV3PasswordManagerRealPackageNativeHostManifestState
    var manifestValidation:
        ChromeMV3NativeHostManifestValidationSummary?
    var manifestPath: String?
    var executablePath: String?
    var resolvedExecutablePath: String?
    var executableInsideFixtureRoot: Bool
    var executableIsExecutable: Bool
    var allowedOrigins: [String]
    var expectedAllowedOrigin: String?
    var allowedOriginsSource: String
    var explicitTestAliasUsed: Bool
    var allowedOriginsState:
        ChromeMV3PasswordManagerRealPackageAllowedOriginsState
    var trustedHostApprovalState: ChromeMV3NativeTrustedHostTrustState
    var trustedHostApprovedForDeveloperPreview: Bool
    var sendNativeMessageReadiness: String
    var connectNativeReadiness: String
    var exchangeResult:
        ChromeMV3PasswordManagerRealPackageNativeFixtureExchangeResult
    var blockerState:
        ChromeMV3PasswordManagerRealPackageNativeHostReadinessState
    var remediation: String
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerRealPackageNativeMessagingSmoke:
    Codable,
    Equatable,
    Sendable
{
    var fixturePack: ChromeMV3NativeMessagingFixturePack?
    var required: Bool
    var optional: Bool
    var detectedExtensionID: String?
    var generatedOrTestExtensionID: String
    var expectedAllowedOrigin: String
    var explicitTestAliasUsed: Bool
    var nativeMessagingPermissionDeclared: Bool
    var nativeMessagingPermissionState:
        ChromeMV3NativeMessagingPermissionState
    var requirementDetectionConfidence:
        ChromeMV3PasswordManagerRealPackageNativeHostRequirementDetectionConfidence
    var hostNames: [String]
    var hostNamesNotObservable: Bool
    var trustedFixtureHostRootPath: String?
    var fixtureRootState:
        ChromeMV3PasswordManagerRealPackageNativeHostFixtureRootState
    var fixtureManifestPathCandidates: [String]
    var fixtureExecutablePathCandidates: [String]
    var hostReadiness:
        [ChromeMV3PasswordManagerRealPackageNativeHostReadiness]
    var noTrustedHostConfigured: Bool
    var arbitraryHostDiscoveryBlocked: Bool
    var realVendorHostLaunchBlocked: Bool
    var fixtureExchangeAttempted: Bool
    var fixtureExchangeSucceeded: Bool
    var sendNativeMessageReadiness: String
    var connectNativeReadiness: String
    var exactBlocker:
        ChromeMV3PasswordManagerRealPackageNativeHostReadinessState?
    var remediation: String?
    var previousTrialDelta: String
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
    var serviceWorkerEventReadiness:
        ChromeMV3PasswordManagerRealPackageServiceWorkerEventReadiness
    var dnrWebRequest: ChromeMV3PasswordManagerCompatibilityStatus
    var sidePanelOffscreenIdentity:
        ChromeMV3PasswordManagerCompatibilityStatus
    var manifestRequirements:
        ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction
    var popupOptionsSmoke:
        ChromeMV3PasswordManagerRealPackagePopupOptionsSmoke
    var contentScriptSmoke:
        ChromeMV3PasswordManagerRealPackageContentScriptSmoke
    var bitwardenE2ESmoke:
        ChromeMV3PasswordManagerRealPackageE2ESmoke
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
    static let schemaVersion = 10
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
    static let bitwardenE2ESyntheticLoginURL =
        "https://sumi.local.test/login"

    static func run(
        rootURL: URL,
        targets:
            [ChromeMV3PasswordManagerRealPackageTargetDefinition] =
                ChromeMV3PasswordManagerRealPackageTargetCatalog
                .explicitLocalTargets(),
        profileID: String = "password-manager-real-package-profile",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        serviceWorkerTrialGateSource:
            ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource =
                .blockedDefault,
        trustedHostApprovalRecords:
            [ChromeMV3NativeTrustedHostApprovalRecord] = [],
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

            let targetProfileID =
                "\(profileID)-\(target.targetClass.fixtureFallbackKind.pathComponent)"
            let trial = runPackage(
                selected: selected,
                profileID: targetProfileID,
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
                fixtureRow: fixtureRow,
                profileID: targetProfileID,
                moduleState: moduleState,
                serviceWorkerTrialGateSource: serviceWorkerTrialGateSource,
                trustedHostApprovalRecords: trustedHostApprovalRecords,
                fileManager: fileManager
            )
            configuration.nativeHostNames =
                uniqueSortedRealPackages(
                    configuration.nativeHostNames
                        + row.nativeMessagingSmoke.hostNames
                )
            configuration.detectedExtensionID =
                row.nativeMessagingSmoke.detectedExtensionID
            configuration.generatedOrTestExtensionID =
                row.nativeMessagingSmoke.generatedOrTestExtensionID
            configuration.nativeFixtureRootState =
                row.nativeMessagingSmoke.fixtureRootState
            configuration.fixtureManifestPathCandidates =
                row.nativeMessagingSmoke.fixtureManifestPathCandidates
            configuration.fixtureExecutablePathCandidates =
                row.nativeMessagingSmoke.fixtureExecutablePathCandidates
            configuration.nativeHostBlockerState =
                row.nativeMessagingSmoke.exactBlocker
            configurations.append(configuration)
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
                        "Stable password-manager runtime remains unavailable.",
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
        fixtureRow: ChromeMV3PasswordManagerCompatibilityMatrixRow?,
        profileID: String,
        moduleState: ChromeMV3ProfileHostModuleState,
        serviceWorkerTrialGateSource:
            ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource,
        trustedHostApprovalRecords:
            [ChromeMV3NativeTrustedHostApprovalRecord],
        fileManager: FileManager
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
            configuration: configuration,
            selected: selected,
            trial: trial,
            extraction: extraction,
            nativeRequired: nativeRequired,
            nativeOptional: nativeOptional,
            profileID: profileID,
            trustedHostApprovalRecords: trustedHostApprovalRecords,
            fileManager: fileManager
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
        let serviceWorkerReadiness = serviceWorkerEventReadiness(
            manifest: manifest,
            lifecycleResult: trial.lifecycleResult,
            extraction: extraction,
            selected: selected,
            target: target,
            moduleState: moduleState,
            trialGateSource: serviceWorkerTrialGateSource,
            trustedNativeFixturePolicyAllowed:
                nativeSmoke.fixtureExchangeSucceeded
        )
        let bitwardenE2ESmoke = bitwardenE2ESmoke(
            target: target,
            selected: selected,
            trial: trial,
            manifest: manifest,
            extraction: extraction,
            resourceScan: resourceScan,
            popupSmoke: popupSmoke,
            contentSmoke: contentSmoke,
            serviceWorkerReadiness: serviceWorkerReadiness,
            lifecycleSucceeded: lifecycleSucceeded,
            generatedAvailable: generatedAvailable,
            hasPopupOptions: hasPopupOptions,
            moduleState: moduleState,
            serviceWorkerTrialGateSource: serviceWorkerTrialGateSource,
            profileID: profileID
        )
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
                (requiresMainWorld ? ["MAIN-world content scripts require a constrained bridge design."] : [])
                    + (requiresMultiFrame ? ["Multi-frame/about:blank/origin-fallback content scripts require safe WebKit frame targeting."] : [])
                    + serviceWorkerReadiness.blockers
            )
        let packageBlockers =
            uniqueSortedRealPackages(
                (lifecycleSucceeded ? [] : trial.diagnostics)
                    + packageBlockers(for: configuration)
            )
        let nativeBlockers =
            uniqueSortedRealPackages(
                nativeSmoke.hostReadiness.map {
                    "\($0.hostName ?? "native host"): \($0.blockerState.rawValue) - \($0.remediation)"
                }
                    + nativeSmoke.diagnostics.filter {
                        $0.contains("blocked")
                            || $0.contains("No trusted")
                            || $0.contains("missing")
                    }
            )
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
                    "Local experimental diagnostics only; stable Bitwarden/1Password/Proton Pass support remains blocked.",
                    "Stable runtime is not globally loadable or exposed.",
                ]
                    + (extraction.declaresDNR ? ["Stable DNR content-rule enforcement is not enabled."] : [])
                    + (extraction.declaresWebRequest ? ["Stable webRequest runtime/enforcement is not enabled."] : [])
                    + (extraction.declaresSidePanel ? ["Stable sidePanel runtime is not enabled."] : [])
                    + (extraction.declaresOffscreen ? ["Stable offscreen runtime is not enabled."] : [])
                    + (extraction.declaresIdentity ? ["Stable identity/OAuth runtime is not enabled."] : [])
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
            css: requiresCSS ? .partial : .notRequired,
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
                serviceWorkerReadiness.declared
                    ? (
                        serviceWorkerReadiness.declarationReadiness?
                        .eventRoutingAvailable == true ? .partial : .blocked
                    )
                    : .notRequired,
            serviceWorkerEventReadiness: serviceWorkerReadiness,
            dnrWebRequest: dnrWebRequestStatus,
            sidePanelOffscreenIdentity: identityStatus,
            manifestRequirements: extraction,
            popupOptionsSmoke: popupSmoke,
            contentScriptSmoke: contentSmoke,
            bitwardenE2ESmoke: bitwardenE2ESmoke,
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
                "Local experimental/default-off diagnostic only; not Chrome parity and not stable Bitwarden/1Password/Proton Pass support."
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
                        ? "Popup/options pages were preflighted for local experimental/default-off bridge coverage; real vendor page execution was not required for this report."
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
        let activeGeneratedRoot =
            lifecycleResult?.generatedVersion?.generatedBundleRootPath
                ?? lifecycleResult?.record?.generatedBundleVersions.first {
                    $0.id == lifecycleResult?.record?.activeGeneratedVersionID
                }?.generatedBundleRootPath
                ?? packageRoot
        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL:
                URL(fileURLWithPath: activeGeneratedRoot, isDirectory: true),
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
                        "Generated bundle root was used for content-script JS/CSS resource validation.",
                        "No real page credentials or profile data were used.",
                    ]
                )
        )
    }

    private static func bitwardenE2ESmoke(
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        selected: SelectedPackage,
        trial: PackageTrialResult,
        manifest: ChromeMV3Manifest?,
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction,
        resourceScan: ChromeMV3PasswordManagerRealPackageResourceScan,
        popupSmoke: ChromeMV3PasswordManagerRealPackagePopupOptionsSmoke,
        contentSmoke: ChromeMV3PasswordManagerRealPackageContentScriptSmoke,
        serviceWorkerReadiness:
            ChromeMV3PasswordManagerRealPackageServiceWorkerEventReadiness,
        lifecycleSucceeded: Bool,
        generatedAvailable: Bool,
        hasPopupOptions: Bool,
        moduleState: ChromeMV3ProfileHostModuleState,
        serviceWorkerTrialGateSource:
            ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource,
        profileID fallbackProfileID: String
    ) -> ChromeMV3PasswordManagerRealPackageE2ESmoke {
        let packageIntakeResult:
            ChromeMV3PasswordManagerCompatibilityStatus =
                selected.source == .fixtureFallback
                    ? .fixtureOnly : (lifecycleSucceeded ? .pass : .blocked)
        let generatedBundleResult:
            ChromeMV3PasswordManagerCompatibilityStatus =
                generatedAvailable ? .pass : .blocked
        let extensionEnabled =
            trial.lifecycleResult?.record?.runtimeState.internalRuntimeEnabled
                ?? false
        let unsupportedAPIs = bitwardenE2EUnsupportedAPIs(
            popupSmoke: popupSmoke,
            resourceScan: resourceScan
        )
        let popupAvailability: ChromeMV3PasswordManagerCompatibilityStatus =
            hasPopupOptions ? .partial : .notRequired
        let generatedRootPath = activeGeneratedRootPath(
            selected: selected,
            trial: trial
        )
        let popupDocumentLoadStatus =
            bitwardenE2EPopupDocumentStatus(
                extraction: extraction,
                generatedRootPath: generatedRootPath
            )
        let serviceWorkerStartupResult =
            bitwardenE2EServiceWorkerStartupResult(
                readiness: serviceWorkerReadiness,
                gateSource: serviceWorkerTrialGateSource
            )

        guard target.targetClass == .bitwarden else {
            return .notRequired(
                targetID: target.targetID,
                packageIntakeResult: packageIntakeResult,
                generatedBundleResult: generatedBundleResult,
                extensionEnabled: extensionEnabled,
                unsupportedAPIs: unsupportedAPIs,
                diagnostics: [
                    "Bitwarden E2E smoke is scoped to the Bitwarden target only.",
                ]
            )
        }
        guard moduleState == .enabled else {
            return .blocked(
                targetID: target.targetID,
                packageIntakeResult: packageIntakeResult,
                generatedBundleResult: generatedBundleResult,
                extensionEnabled: extensionEnabled,
                popupOptionsAvailability: popupAvailability,
                popupDocumentLoadStatus: popupDocumentLoadStatus,
                serviceWorkerStartupResult: serviceWorkerStartupResult,
                serviceWorkerListenerCaptureStatus:
                    serviceWorkerReadiness
                    .actualListenerRegistrationCaptureStatus,
                contentScriptAttachResult: .blocked,
                unsupportedAPIs: unsupportedAPIs,
                blockerClassification: .routeUnsupported,
                blocker:
                    "Chrome MV3 module is disabled; Bitwarden E2E smoke did not attach content scripts, create popup/options bridge calls, or wake the service-worker fixture.",
                diagnostics: [
                    "Disabled module state blocks all local experimental Bitwarden E2E runtime work.",
                ]
            )
        }
        guard serviceWorkerTrialGateSource.allowsScopedExecution else {
            return .blocked(
                targetID: target.targetID,
                packageIntakeResult: packageIntakeResult,
                generatedBundleResult: generatedBundleResult,
                extensionEnabled: extensionEnabled,
                popupOptionsAvailability: popupAvailability,
                popupDocumentLoadStatus: popupDocumentLoadStatus,
                serviceWorkerStartupResult: serviceWorkerStartupResult,
                serviceWorkerListenerCaptureStatus:
                    serviceWorkerReadiness
                    .actualListenerRegistrationCaptureStatus,
                contentScriptAttachResult: .blocked,
                unsupportedAPIs: unsupportedAPIs,
                blockerClassification: .routeUnsupported,
                blocker:
                    "Default local experimental gate is closed; Bitwarden E2E smoke recorded package/popup/static readiness without routing real-surface messages.",
                diagnostics: [
                    "Default-off gate blocks service-worker, popup/options, and content-script route execution.",
                    "No permanent background page or wall-clock wake was created.",
                ]
            )
        }
        guard lifecycleSucceeded, generatedAvailable, let manifest,
              let generatedRootPath
        else {
            return .blocked(
                targetID: target.targetID,
                packageIntakeResult: packageIntakeResult,
                generatedBundleResult: generatedBundleResult,
                extensionEnabled: extensionEnabled,
                popupOptionsAvailability: popupAvailability,
                popupDocumentLoadStatus: popupDocumentLoadStatus,
                serviceWorkerStartupResult: serviceWorkerStartupResult,
                serviceWorkerListenerCaptureStatus:
                    serviceWorkerReadiness
                    .actualListenerRegistrationCaptureStatus,
                contentScriptAttachResult: .blocked,
                unsupportedAPIs: unsupportedAPIs,
                blockerClassification: .routeUnsupported,
                blocker:
                    "Package intake or generated bundle is unavailable for the local Bitwarden E2E smoke.",
                diagnostics:
                    trial.diagnostics
                        + ["Bitwarden E2E smoke requires accepted local package intake and an active generated bundle."]
            )
        }

        let extensionID = trial.lifecycleResult?.record?.extensionID
            ?? "bitwarden-e2e-extension"
        let profileID = trial.lifecycleResult?.record?.profileID
            ?? fallbackProfileID
        let loginURL = bitwardenE2ESyntheticLoginURL
        let documentID = "bitwarden-e2e-login-main-frame"
        let tabID = 1
        let frameID = 0
        let permissionBroker = ChromeMV3PermissionBroker(
            state: ChromeMV3PermissionBrokerState(
                extensionID: extensionID,
                profileID: profileID,
                requiredPermissions: manifest.permissions,
                optionalPermissions: manifest.optionalPermissions,
                hostPermissions: manifest.hostPermissions,
                optionalHostPermissions: manifest.optionalHostPermissions,
                diagnostics: [
                    "Bitwarden E2E smoke uses declared host permissions and activeTab state only; no silent optional grants are inserted.",
                ]
            )
        )
        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL:
                URL(fileURLWithPath: generatedRootPath, isDirectory: true),
            extensionID: extensionID,
            profileID: profileID
        )
        let preflight = ChromeMV3NormalTabContentScriptPreflightEvaluator
            .evaluate(
                input: ChromeMV3NormalTabContentScriptPreflightInput(
                    moduleEnabled: true,
                    extensionEnabled: extensionEnabled,
                    productRuntimePreflightAllowsNormalTabAttachment: true,
                    contentScriptGate:
                        ChromeMV3ContentScriptProductGateRecord
                        .developerPreviewAllowed(),
                    attachmentPlan: plan,
                    permissionBroker: permissionBroker,
                    tabID: tabID,
                    frameID: frameID,
                    documentID: documentID,
                    navigationSequence: 1,
                    urlString: loginURL,
                    tabSurface: .normalTab,
                    generatedBundleActive: true,
                    webKitUserContentControllerAvailable: true,
                    teardownPending: false
                )
            )
        let listenerProbe = bitwardenE2EContentScriptListenerProbe(
            matchedScripts: preflight.matchedScripts
        )
        let endpointRegistry = ChromeMV3ContentScriptEndpointRegistry()
        let endpoint = endpointRegistry.registerEndpoint(
            preflight: preflight,
            messageListenerRegistered:
                listenerProbe.messageListenerRegistered,
            connectListenerRegistered:
                listenerProbe.connectListenerRegistered
        )
        let contentAttachResult:
            ChromeMV3PasswordManagerCompatibilityStatus =
                preflight.canAttachDeclaredContentScriptsNow
                    ? .partial : .blocked
        let loginSurface =
            ChromeMV3PasswordManagerRealPackageE2ESyntheticLoginSurface(
                url: loginURL,
                origin: ChromeMV3RuntimeMessagingURL.origin(from: loginURL),
                hostPermissionState:
                    preflight.hostAccessDecision.status.rawValue,
                activeTabState:
                    preflight.hostAccessDecision.allowedByActiveTab
                        ? "activeTabGrant" : "notRequiredOrNotGranted",
                declaredContentScriptCount: plan.declaredScripts.count,
                matchedContentScriptCount: preflight.matchedScripts.count,
                attachedContentScriptCount:
                    preflight.canAttachDeclaredContentScriptsNow
                        ? preflight.matchedScripts.count : 0,
                cssAttachmentStatus:
                    preflight.matchedScripts.contains {
                        $0.validatedCSSFilePaths.isEmpty == false
                    } ? .partial : .notRequired,
                jsEndpointStatus:
                    endpoint == nil ? .blocked : .partial,
                endpointID: endpoint?.endpointID,
                senderURLRedacted:
                    endpoint?.senderMetadata.urlRedacted ?? true,
                senderOriginRedacted:
                    endpoint?.senderMetadata.originRedacted ?? true,
                diagnostics:
                    uniqueSortedRealPackages(
                        preflight.diagnostics
                            + listenerProbe.diagnostics
                            + [
                                "Synthetic login page is local-only diagnostic input; no page credentials were created or submitted.",
                            ]
                    )
            )
        let sharedLifecycleRegistry =
            ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
        let sharedSession = sharedLifecycleRegistry.session(
            profileID: profileID,
            extensionID: extensionID,
            lifecycleSessionID: "bitwarden-e2e-smoke",
            moduleState: moduleState,
            explicitInternalLifecycleAllowed: true,
            nativePortKeepaliveAvailableInFixture: false
        )
        registerBitwardenE2EServiceWorkerListeners(
            readiness: serviceWorkerReadiness,
            sharedSession: sharedSession
        )
        let popupHandler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                bitwardenE2EPopupConfiguration(
                    extensionID: extensionID,
                    profileID: profileID,
                    manifest: manifest,
                    moduleState: moduleState
                ),
            contentScriptEndpointRegistry: endpointRegistry,
            sharedLifecycleSession: sharedSession
        )
        let contentBridge = ChromeMV3ContentScriptBridgeHost(
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            frameID: frameID,
            documentID: documentID,
            urlString: loginURL,
            permissionBroker: permissionBroker,
            endpointRegistry: endpointRegistry,
            sharedLifecycleSession: sharedSession
        )

        var routes: [ChromeMV3PasswordManagerRealPackageE2ERouteResult] = []
        routes.append(
            bitwardenE2ERouteResult(
                route: .popupRuntimeGetURL,
                sourceSurface: "actionPopup",
                targetSurface: "extensionResource",
                response:
                    popupHandler.handle(
                        bitwardenE2EBridgeRequest(
                            route: .popupRuntimeGetURL,
                            namespace: "runtime",
                            methodName: "getURL",
                            arguments: [.string("popup/index.html")]
                        )
                    ),
                endpointRegistered: endpoint != nil,
                endpointMessageListenerRegistered:
                    listenerProbe.messageListenerRegistered,
                endpointConnectListenerRegistered:
                    listenerProbe.connectListenerRegistered,
                serviceWorkerCapturedFamilies:
                    serviceWorkerReadiness.capturedListenerFamilies,
                payloadSummary: "popup runtime.getURL popup/index.html"
            )
        )
        routes.append(
            bitwardenE2ERouteResult(
                route: .popupStorageLocalSet,
                sourceSurface: "actionPopup",
                targetSurface: "storage.local",
                response:
                    popupHandler.handle(
                        bitwardenE2EBridgeRequest(
                            route: .popupStorageLocalSet,
                            namespace: "storage",
                            methodName: "local.set",
                            arguments: [
                                .object([
                                    "sumiBitwardenE2ESmoke":
                                        .string("local-only"),
                                ]),
                            ]
                        )
                    ),
                endpointRegistered: endpoint != nil,
                endpointMessageListenerRegistered:
                    listenerProbe.messageListenerRegistered,
                endpointConnectListenerRegistered:
                    listenerProbe.connectListenerRegistered,
                serviceWorkerCapturedFamilies:
                    serviceWorkerReadiness.capturedListenerFamilies,
                payloadSummary: "popup storage.local.set deterministic key"
            )
        )
        routes.append(
            bitwardenE2ERouteResult(
                route: .popupStorageLocalGet,
                sourceSurface: "actionPopup",
                targetSurface: "storage.local",
                response:
                    popupHandler.handle(
                        bitwardenE2EBridgeRequest(
                            route: .popupStorageLocalGet,
                            namespace: "storage",
                            methodName: "local.get",
                            arguments: [
                                .array([.string("sumiBitwardenE2ESmoke")]),
                            ]
                        )
                    ),
                endpointRegistered: endpoint != nil,
                endpointMessageListenerRegistered:
                    listenerProbe.messageListenerRegistered,
                endpointConnectListenerRegistered:
                    listenerProbe.connectListenerRegistered,
                serviceWorkerCapturedFamilies:
                    serviceWorkerReadiness.capturedListenerFamilies,
                payloadSummary: "popup storage.local.get deterministic key"
            )
        )
        routes.append(
            bitwardenE2ERouteResult(
                route: .popupRuntimeSendMessage,
                sourceSurface: "actionPopup",
                targetSurface: "serviceWorker",
                response:
                    popupHandler.handle(
                        bitwardenE2EBridgeRequest(
                            route: .popupRuntimeSendMessage,
                            namespace: "runtime",
                            methodName: "sendMessage",
                            arguments: [bitwardenE2EMessagePayload()]
                        )
                    ),
                endpointRegistered: endpoint != nil,
                endpointMessageListenerRegistered:
                    listenerProbe.messageListenerRegistered,
                endpointConnectListenerRegistered:
                    listenerProbe.connectListenerRegistered,
                serviceWorkerCapturedFamilies:
                    serviceWorkerReadiness.capturedListenerFamilies,
                payloadSummary: "popup runtime.sendMessage service-worker route"
            )
        )
        routes.append(
            bitwardenE2ERouteResult(
                route: .popupRuntimeConnect,
                sourceSurface: "actionPopup",
                targetSurface: "serviceWorker",
                response:
                    popupHandler.handle(
                        bitwardenE2EBridgeRequest(
                            route: .popupRuntimeConnect,
                            namespace: "runtime",
                            methodName: "connect",
                            arguments: [
                                .object([
                                    "name": .string("sumi-bitwarden-e2e"),
                                ]),
                            ]
                        )
                    ),
                endpointRegistered: endpoint != nil,
                endpointMessageListenerRegistered:
                    listenerProbe.messageListenerRegistered,
                endpointConnectListenerRegistered:
                    listenerProbe.connectListenerRegistered,
                serviceWorkerCapturedFamilies:
                    serviceWorkerReadiness.capturedListenerFamilies,
                payloadSummary: "popup runtime.connect service-worker route"
            )
        )
        routes.append(
            bitwardenE2ERouteResult(
                route: .popupTabsQuery,
                sourceSurface: "actionPopup",
                targetSurface: "tabs",
                response:
                    popupHandler.handle(
                        bitwardenE2EBridgeRequest(
                            route: .popupTabsQuery,
                            namespace: "tabs",
                            methodName: "query",
                            arguments: [
                                .object([
                                    "active": .bool(true),
                                    "currentWindow": .bool(true),
                                ]),
                            ]
                        )
                    ),
                endpointRegistered: endpoint != nil,
                endpointMessageListenerRegistered:
                    listenerProbe.messageListenerRegistered,
                endpointConnectListenerRegistered:
                    listenerProbe.connectListenerRegistered,
                serviceWorkerCapturedFamilies:
                    serviceWorkerReadiness.capturedListenerFamilies,
                payloadSummary: "popup tabs.query active currentWindow"
            )
        )
        routes.append(
            bitwardenE2ERouteResult(
                route: .popupTabsSendMessage,
                sourceSurface: "actionPopup",
                targetSurface: "contentScriptEndpoint",
                response:
                    popupHandler.handle(
                        bitwardenE2EBridgeRequest(
                            route: .popupTabsSendMessage,
                            namespace: "tabs",
                            methodName: "sendMessage",
                            arguments: [
                                .number(Double(tabID)),
                                bitwardenE2EMessagePayload(),
                                .object([
                                    "frameId": .number(Double(frameID)),
                                    "documentId": .string(documentID),
                                ]),
                            ]
                        )
                    ),
                endpointRegistered: endpoint != nil,
                endpointMessageListenerRegistered:
                    listenerProbe.messageListenerRegistered,
                endpointConnectListenerRegistered:
                    listenerProbe.connectListenerRegistered,
                serviceWorkerCapturedFamilies:
                    serviceWorkerReadiness.capturedListenerFamilies,
                payloadSummary: "popup tabs.sendMessage content-script route"
            )
        )
        routes.append(
            bitwardenE2ERouteResult(
                route: .popupTabsConnect,
                sourceSurface: "actionPopup",
                targetSurface: "contentScriptEndpoint",
                response:
                    popupHandler.handle(
                        bitwardenE2EBridgeRequest(
                            route: .popupTabsConnect,
                            namespace: "tabs",
                            methodName: "connect",
                            arguments: [
                                .number(Double(tabID)),
                                .object([
                                    "frameId": .number(Double(frameID)),
                                    "documentId": .string(documentID),
                                    "name": .string("sumi-bitwarden-e2e"),
                                ]),
                            ]
                        )
                    ),
                endpointRegistered: endpoint != nil,
                endpointMessageListenerRegistered:
                    listenerProbe.messageListenerRegistered,
                endpointConnectListenerRegistered:
                    listenerProbe.connectListenerRegistered,
                serviceWorkerCapturedFamilies:
                    serviceWorkerReadiness.capturedListenerFamilies,
                payloadSummary: "popup tabs.connect content-script route"
            )
        )
        routes.append(
            bitwardenE2EContentScriptRouteResult(
                route: .contentScriptRuntimeSendMessage,
                response:
                    contentBridge.handle([
                        "namespace": "runtime",
                        "methodName": "sendMessage",
                        "bridgeCallID":
                            "bitwarden-e2e-contentScriptRuntimeSendMessage",
                        "arguments": [
                            [
                                "kind": "sumiBitwardenE2ESmoke",
                                "value": "deterministic",
                            ],
                        ],
                    ]),
                serviceWorkerCapturedFamilies:
                    serviceWorkerReadiness.capturedListenerFamilies,
                payloadSummary:
                    "content-script runtime.sendMessage service-worker route"
            )
        )
        routes.append(
            bitwardenE2EContentScriptRouteResult(
                route: .contentScriptRuntimeConnect,
                response:
                    contentBridge.handle([
                        "namespace": "runtime",
                        "methodName": "connect",
                        "bridgeCallID":
                            "bitwarden-e2e-contentScriptRuntimeConnect",
                        "arguments": [
                            [
                                "name": "sumi-bitwarden-e2e",
                            ],
                        ],
                    ]),
                serviceWorkerCapturedFamilies:
                    serviceWorkerReadiness.capturedListenerFamilies,
                payloadSummary:
                    "content-script runtime.connect service-worker route"
            )
        )

        let endpointState =
            ChromeMV3PasswordManagerRealPackageE2EEndpointRegistryState.make(
                summary: endpointRegistry.summary,
                senderMetadataRedacted:
                    endpoint?.senderMetadata.urlRedacted ?? true
            )
        popupHandler.tearDown()
        sharedSession?.triggerIdleRelease(reason: "bitwardenE2ESmokeComplete")
        sharedLifecycleRegistry.reset()

        let noReceiverResults = routes.filter {
            $0.noReceiverClassification != nil
        }
        let nextBlocker = bitwardenE2ENextBlocker(routes: routes)
        return ChromeMV3PasswordManagerRealPackageE2ESmoke(
            attempted: true,
            status: routes.contains { $0.status == .partial }
                ? .partial : .blocked,
            targetID: target.targetID,
            packageIntakeResult: packageIntakeResult,
            generatedBundleResult: generatedBundleResult,
            extensionEnabled: extensionEnabled,
            popupOptionsAvailability: popupAvailability,
            popupDocumentLoadStatus: popupDocumentLoadStatus,
            serviceWorkerStartupResult: serviceWorkerStartupResult,
            serviceWorkerListenerCaptureStatus:
                serviceWorkerReadiness.actualListenerRegistrationCaptureStatus,
            contentScriptAttachResult: contentAttachResult,
            syntheticLoginSurface: loginSurface,
            endpointRegistryState: endpointState,
            messageRoutesTested: routes,
            unsupportedAPIsEncountered: unsupportedAPIs,
            noListenerNoReceiverResults: noReceiverResults,
            nextBlockerClassification: nextBlocker.classification,
            nextBlocker: nextBlocker.detail,
            serviceWorkerWakeAttempted:
                routes.contains { $0.serviceWorkerWakeAttempted },
            nativeHostLaunchAttempted:
                routes.contains { $0.nativeHostLaunchAttempted },
            noCredentialsOrNetwork: true,
            diagnostics:
                uniqueSortedRealPackages(
                    contentSmoke.diagnostics
                        + preflight.diagnostics
                        + listenerProbe.diagnostics
                        + [
                            "Bitwarden E2E smoke used only \(selected.resourceScanRootPath ?? selected.packageURL?.path ?? "unknown local package root").",
                            "Action popup/options, service-worker shared lifecycle, and manifest content-script endpoint routes were exercised through existing Sumi developer-preview surfaces.",
                            "No public support flag, Web Store install, remote CRX, account, vault, credential, vendor native-host, arbitrary tab scan, or network-auth call was used.",
                        ]
                )
        )
    }

    private struct BitwardenE2EContentScriptListenerProbe {
        var messageListenerRegistered: Bool
        var connectListenerRegistered: Bool
        var diagnostics: [String]
    }

    private static func activeGeneratedRootPath(
        selected: SelectedPackage,
        trial: PackageTrialResult
    ) -> String? {
        trial.lifecycleResult?.generatedVersion?.generatedBundleRootPath
            ?? trial.lifecycleResult?.record?.generatedBundleVersions.first {
                $0.id == trial.lifecycleResult?.record?.activeGeneratedVersionID
            }?.generatedBundleRootPath
            ?? selected.resourceScanRootPath
            ?? trial.lifecycleResult?.record?.originalBundleRootPath
    }

    private static func bitwardenE2EPopupDocumentStatus(
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction,
        generatedRootPath: String?
    ) -> ChromeMV3PasswordManagerCompatibilityStatus {
        let path =
            extraction.actionDefaultPopup
                ?? extraction.optionsUIPage
                ?? extraction.optionsPage
        guard let path else { return .notRequired }
        guard let generatedRootPath else { return .blocked }
        let url = URL(fileURLWithPath: generatedRootPath, isDirectory: true)
            .appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path)
            ? .pass : .blocked
    }

    private static func bitwardenE2EServiceWorkerStartupResult(
        readiness:
            ChromeMV3PasswordManagerRealPackageServiceWorkerEventReadiness,
        gateSource:
            ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource
    ) -> ChromeMV3PasswordManagerCompatibilityStatus {
        guard readiness.declared else { return .notRequired }
        guard gateSource.allowsScopedExecution else { return .blocked }
        if readiness.executionStartResult?.status == .running
            || readiness.capturedListenerFamilies.isEmpty == false
        {
            return .partial
        }
        return .blocked
    }

    private static func bitwardenE2EUnsupportedAPIs(
        popupSmoke: ChromeMV3PasswordManagerRealPackagePopupOptionsSmoke,
        resourceScan: ChromeMV3PasswordManagerRealPackageResourceScan
    ) -> [String] {
        uniqueSortedRealPackages(
            popupSmoke.blockedAPIs.map {
                "\($0.namespace).\($0.methodName)"
            }
                + resourceScan.detectedChromeAPIs.filter {
                    ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                        .allowedMethods.contains($0) == false
                }
        )
    }

    private static func bitwardenE2EContentScriptListenerProbe(
        matchedScripts: [ChromeMV3DeclaredContentScriptAttachmentRecord]
    ) -> BitwardenE2EContentScriptListenerProbe {
        var message = false
        var connect = false
        var scanned: [String] = []
        var diagnostics: [String] = []
        for script in matchedScripts {
            let root = URL(
                fileURLWithPath: script.generatedBundleRootPath,
                isDirectory: true
            )
            for path in script.validatedJSFilePaths.sorted() {
                let url = root.appendingPathComponent(path)
                guard let source = try? String(contentsOf: url, encoding: .utf8)
                else {
                    diagnostics.append(
                        "Could not read matched content-script JS \(path) for listener probe."
                    )
                    continue
                }
                scanned.append(path)
                if source.contains("runtime.onMessage.addListener")
                    || source.contains("browser.runtime.onMessage.addListener")
                    || source.contains("chrome.runtime.onMessage.addListener")
                {
                    message = true
                }
                if source.contains("runtime.onConnect.addListener")
                    || source.contains("browser.runtime.onConnect.addListener")
                    || source.contains("chrome.runtime.onConnect.addListener")
                {
                    connect = true
                }
            }
        }
        diagnostics.append(
            "Content-script listener probe scanned \(scanned.count) matched JS file(s): \(scanned.prefix(4).joined(separator: ", "))."
        )
        diagnostics.append(
            "Content-script listener probe result: onMessage=\(message), onConnect=\(connect)."
        )
        return BitwardenE2EContentScriptListenerProbe(
            messageListenerRegistered: message,
            connectListenerRegistered: connect,
            diagnostics: uniqueSortedRealPackages(diagnostics)
        )
    }

    private static func registerBitwardenE2EServiceWorkerListeners(
        readiness:
            ChromeMV3PasswordManagerRealPackageServiceWorkerEventReadiness,
        sharedSession: ChromeMV3ServiceWorkerSharedLifecycleSession?
    ) {
        guard let sharedSession else { return }
        if readiness.capturedListenerFamilies.contains(.runtimeOnMessage) {
            sharedSession.registerListener(
                event: .runtimeOnMessage,
                listenerID: "bitwarden-e2e-runtime-on-message",
                outcome:
                    .modelDispatched(
                        .object([
                            "ok": .bool(true),
                            "target": .string("serviceWorker"),
                            "surface": .string("runtime.onMessage"),
                        ]),
                        diagnostics: [
                            "Bitwarden E2E smoke mirrored the captured service-worker runtime.onMessage listener into the shared lifecycle fixture.",
                        ]
                    )
            )
        }
        if readiness.capturedListenerFamilies.contains(.runtimeOnConnect) {
            sharedSession.registerListener(
                event: .runtimeOnConnect,
                listenerID: "bitwarden-e2e-runtime-on-connect",
                outcome:
                    .modelDispatched(
                        .object([
                            "ok": .bool(true),
                            "target": .string("serviceWorker"),
                            "surface": .string("runtime.onConnect"),
                        ]),
                        diagnostics: [
                            "Bitwarden E2E smoke mirrored the captured service-worker runtime.onConnect listener into the shared lifecycle fixture.",
                        ]
                    )
            )
        }
    }

    private static func bitwardenE2EPopupConfiguration(
        extensionID: String,
        profileID: String,
        manifest: ChromeMV3Manifest,
        moduleState: ChromeMV3ProfileHostModuleState
    ) -> ChromeMV3PopupOptionsJSBridgeConfiguration {
        ChromeMV3PopupOptionsJSBridgeConfiguration(
            extensionID: extensionID,
            profileID: profileID,
            surfaceID: "\(profileID):\(extensionID):bitwarden-e2e-popup",
            surface: .actionPopup,
            extensionBaseURLString: "chrome-extension://\(extensionID)/",
            permissionStateRootPath: nil,
            moduleState: moduleState,
            bridgeAvailable: moduleState == .enabled,
            popupOptionsJSBridgeAvailableInDeveloperPreview:
                moduleState == .enabled,
            popupOptionsJSBridgeAvailableInPublicProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            runtimeLoadable: false,
            manifestPermissions: manifest.permissions,
            manifestOptionalPermissions: manifest.optionalPermissions,
            manifestHostPermissions: manifest.hostPermissions,
            manifestOptionalHostPermissions: manifest.optionalHostPermissions,
            activeTabGrants: [],
            allowlist: .defaultPolicy,
            diagnostics: [
                "Bitwarden E2E popup/options bridge is local experimental and extension-owned only.",
                "Normal-tab runtime bridge, product content-script attachment, and public runtimeLoadable stay false.",
            ]
        )
    }

    private static func bitwardenE2EMessagePayload() -> ChromeMV3StorageValue {
        .object([
            "kind": .string("sumiBitwardenE2ESmoke"),
            "value": .string("deterministic"),
        ])
    }

    private static func bitwardenE2EBridgeRequest(
        route: ChromeMV3PasswordManagerRealPackageE2ERoute,
        namespace: String,
        methodName: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: "bitwarden-e2e-\(route.rawValue)",
            namespace: namespace,
            methodName: methodName,
            invocationMode: .promise,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: [
                "Bitwarden E2E route request generated by local compatibility smoke.",
            ]
        )
    }

    private static func bitwardenE2ERouteResult(
        route: ChromeMV3PasswordManagerRealPackageE2ERoute,
        sourceSurface: String,
        targetSurface: String,
        response: ChromeMV3PopupOptionsJSBridgeHostResponse,
        endpointRegistered: Bool,
        endpointMessageListenerRegistered: Bool,
        endpointConnectListenerRegistered: Bool,
        serviceWorkerCapturedFamilies:
            [ChromeMV3ServiceWorkerSyntheticListenerEvent],
        payloadSummary: String
    ) -> ChromeMV3PasswordManagerRealPackageE2ERouteResult {
        let classification =
            bitwardenE2ENoReceiverClassification(
                route: route,
                succeeded: response.succeeded,
                lastErrorCode: response.lastErrorCode,
                lastErrorMessage: response.lastErrorMessage,
                endpointRegistered: endpointRegistered,
                endpointMessageListenerRegistered:
                    endpointMessageListenerRegistered,
                endpointConnectListenerRegistered:
                    endpointConnectListenerRegistered,
                serviceWorkerCapturedFamilies: serviceWorkerCapturedFamilies,
                blockedDiagnostic: response.blockedAPIDiagnostic
            )
        return ChromeMV3PasswordManagerRealPackageE2ERouteResult(
            route: route,
            sourceSurface: sourceSurface,
            targetSurface: targetSurface,
            status: response.succeeded ? .partial : .blocked,
            noReceiverClassification: classification,
            lastErrorCode: response.lastErrorCode,
            lastErrorMessage: response.lastErrorMessage,
            serviceWorkerWakeAttempted: response.serviceWorkerWakeAttempted,
            nativeHostLaunchAttempted: response.nativeHostLaunchAttempted,
            payloadSummary: payloadSummary,
            diagnostics:
                uniqueSortedRealPackages(
                    response.diagnostics
                        + [
                            "Bitwarden E2E popup/options route \(route.rawValue) finished with succeeded=\(response.succeeded).",
                        ]
                )
        )
    }

    private static func bitwardenE2EContentScriptRouteResult(
        route: ChromeMV3PasswordManagerRealPackageE2ERoute,
        response: ChromeMV3ContentScriptBridgeResponse,
        serviceWorkerCapturedFamilies:
            [ChromeMV3ServiceWorkerSyntheticListenerEvent],
        payloadSummary: String
    ) -> ChromeMV3PasswordManagerRealPackageE2ERouteResult {
        let classification =
            bitwardenE2ENoReceiverClassification(
                route: route,
                succeeded: response.succeeded,
                lastErrorCode: response.lastErrorCode,
                lastErrorMessage: response.lastErrorMessage,
                endpointRegistered: true,
                endpointMessageListenerRegistered: true,
                endpointConnectListenerRegistered: true,
                serviceWorkerCapturedFamilies: serviceWorkerCapturedFamilies,
                blockedDiagnostic: nil
            )
        return ChromeMV3PasswordManagerRealPackageE2ERouteResult(
            route: route,
            sourceSurface: "contentScriptEndpoint",
            targetSurface: "serviceWorker",
            status: response.succeeded ? .partial : .blocked,
            noReceiverClassification: classification,
            lastErrorCode: response.lastErrorCode,
            lastErrorMessage: response.lastErrorMessage,
            serviceWorkerWakeAttempted: response.serviceWorkerWakeAttempted,
            nativeHostLaunchAttempted: response.nativeHostLaunchAttempted,
            payloadSummary: payloadSummary,
            diagnostics:
                uniqueSortedRealPackages(
                    response.diagnostics
                        + [
                            "Bitwarden E2E content-script route \(route.rawValue) finished with succeeded=\(response.succeeded).",
                        ]
                )
        )
    }

    private static func bitwardenE2ENoReceiverClassification(
        route: ChromeMV3PasswordManagerRealPackageE2ERoute,
        succeeded: Bool,
        lastErrorCode: String?,
        lastErrorMessage: String?,
        endpointRegistered: Bool,
        endpointMessageListenerRegistered: Bool,
        endpointConnectListenerRegistered: Bool,
        serviceWorkerCapturedFamilies:
            [ChromeMV3ServiceWorkerSyntheticListenerEvent],
        blockedDiagnostic: ChromeMV3PopupOptionsBlockedAPIDiagnostic?
    ) -> ChromeMV3PasswordManagerRealPackageNoReceiverClassification? {
        guard succeeded == false else { return nil }
        if blockedDiagnostic != nil
            || lastErrorCode == ChromeMV3JSBridgeErrorCode.unsupportedAPI.rawValue
        {
            return .actualUnsupportedAPI
        }
        if lastErrorCode == ChromeMV3JSBridgeErrorCode.permissionDenied.rawValue
            || lastErrorCode == ChromeMV3RuntimeLastErrorCase.permissionDenied.rawValue
            || lastErrorCode == ChromeMV3RuntimeLastErrorCase.hostPermissionMissing.rawValue
            || lastErrorCode == ChromeMV3RuntimeLastErrorCase.activeTabMissing.rawValue
        {
            return .permissionBlocked
        }
        if lastErrorCode == ChromeMV3RuntimeLastErrorCase.noReceivingEnd.rawValue
            || lastErrorMessage?.contains("Receiving end does not exist") == true
        {
            switch route {
            case .popupTabsSendMessage:
                if endpointRegistered == false {
                    return .missingContentScriptEndpoint
                }
                return endpointMessageListenerRegistered
                    ? .endpointStale
                    : .expectedNoListener
            case .popupTabsConnect:
                if endpointRegistered == false {
                    return .missingContentScriptEndpoint
                }
                return endpointConnectListenerRegistered
                    ? .endpointStale
                    : .expectedNoListener
            case .popupRuntimeSendMessage,
                 .contentScriptRuntimeSendMessage:
                return serviceWorkerCapturedFamilies.contains(.runtimeOnMessage)
                    ? .missingPopupListener
                    : .serviceWorkerListenerMissing
            case .popupRuntimeConnect,
                 .contentScriptRuntimeConnect:
                return serviceWorkerCapturedFamilies.contains(.runtimeOnConnect)
                    ? .missingPopupListener
                    : .serviceWorkerListenerMissing
            default:
                return .expectedNoListener
            }
        }
        if lastErrorMessage?.localizedCaseInsensitiveContains("throw") == true
            || lastErrorMessage?.localizedCaseInsensitiveContains("error") == true
        {
            return .listenerThrew
        }
        return .routeUnsupported
    }

    private static func bitwardenE2ENextBlocker(
        routes: [ChromeMV3PasswordManagerRealPackageE2ERouteResult]
    ) -> (
        classification:
            ChromeMV3PasswordManagerRealPackageNoReceiverClassification?,
        detail: String
    ) {
        if let unexpected = routes.first(where: {
            $0.status == .blocked
                && $0.noReceiverClassification != .expectedNoListener
        }) {
            return (
                unexpected.noReceiverClassification ?? .routeUnsupported,
                "\(unexpected.route.rawValue) blocked: \(unexpected.lastErrorMessage ?? "no lastError")."
            )
        }
        if let expected = routes.first(where: {
            $0.noReceiverClassification == .expectedNoListener
        }) {
            return (
                .expectedNoListener,
                "\(expected.route.rawValue) reported noReceiver because the matched Bitwarden endpoint/listener set does not include that listener in the static content-script surface; this is expected listener taxonomy, not unsupported API."
            )
        }
        return (
            nil,
            "No next Bitwarden E2E blocker observed in deterministic popup/options, service-worker, and content-script route smoke."
        )
    }

    private static func serviceWorkerEventReadiness(
        manifest: ChromeMV3Manifest?,
        lifecycleResult: ChromeMV3LifecycleOperationResult?,
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction,
        selected: SelectedPackage,
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        moduleState: ChromeMV3ProfileHostModuleState,
        trialGateSource:
            ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource,
        trustedNativeFixturePolicyAllowed: Bool
    ) -> ChromeMV3PasswordManagerRealPackageServiceWorkerEventReadiness {
        let declared = extraction.backgroundServiceWorker != nil
        let extensionID = lifecycleResult?.record?.extensionID
            ?? "password-manager-real-package-extension"
        let profileID = lifecycleResult?.record?.profileID
            ?? "password-manager-real-package-profile"
        let activeGeneratedVersion =
            lifecycleResult?.generatedVersion
                ?? lifecycleResult?.record?.generatedBundleVersions.first {
                    $0.id == lifecycleResult?.record?.activeGeneratedVersionID
                }
        let generatedRootPath =
            activeGeneratedVersion?.generatedBundleRootPath
                ?? selected.resourceScanRootPath
                ?? lifecycleResult?.record?.originalBundleRootPath
        let generatedRecord = activeGeneratedVersion?.generatedBundleRecord
        let dependencyInventory =
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventoryScanner
            .scan(
                manifest: manifest,
                packageRootPath:
                    selected.resourceScanRootPath
                        ?? lifecycleResult?.record?.originalBundleRootPath
                        ?? generatedRootPath,
                generatedBundleRecord: generatedRecord
            )
        let extensionEnabled =
            lifecycleResult?.record?.runtimeState.internalRuntimeEnabled ?? true
        let readiness = manifest.map {
            ChromeMV3ServiceWorkerDeclarationReadinessEvaluator.evaluate(
                manifest: $0,
                generatedBundleRootURL: generatedRootPath.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                },
                extensionID: extensionID,
                profileID: profileID,
                moduleState: moduleState,
                extensionEnabled: extensionEnabled,
                localExperimentalGateAllowed: false
            )
        }
        let closedPolicy = ChromeMV3ServiceWorkerJSExecutionPolicy.evaluate(
            moduleState: moduleState,
            extensionEnabled: extensionEnabled,
            localExperimentalGateAllowed: false,
            generatedBundleRecordAvailable: generatedRecord != nil
        )
        let staticFamilies = readiness?.listenerCoverage
            .filter(\.listenerDetected)
            .map(\.event)
            .uniqueSortedRealPackageValues() ?? []
        var gateRecords = [
            serviceWorkerTrialGateRecord(
                target: target,
                extensionID: extensionID,
                profileID: profileID,
                selected: selected,
                generatedRecord: generatedRecord,
                state: .blockedDefault,
                source: .blockedDefault,
                reason:
                    "Service-worker execution is default-off outside an explicit scoped local trial.",
                blockers: closedPolicy.blockers.map(\.rawValue)
            ),
        ]
        var policy = closedPolicy
        var resourceLoadResult: ChromeMV3ServiceWorkerJSResourceLoadRecord?
        var executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
        var capturedRegistrations:
            [ChromeMV3ServiceWorkerJSCapturedListenerRegistration] = []
        var capturedFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent] = []
        var dispatchResults: [ChromeMV3ServiceWorkerJSDispatchRecord] = []
        var runtimePortSmoke =
            ChromeMV3PasswordManagerRealPackageServiceWorkerPortSmoke
            .notAttempted
        var nativeMessagingIntegrationSmoke =
            "trustedNativeFixtureMissingOrBlocked: no native messaging service-worker event was dispatched."
        var timerShimResult =
            "notAttempted: scoped service-worker execution gate stayed closed."
        var idleTeardownResult =
            "notAttempted: scoped service-worker execution gate stayed closed."
        var hardTimeoutTeardownResult =
            "notAttempted: scoped service-worker execution gate stayed closed."
        var gateClosedAfterTrial = true

        if declared, let manifest,
           moduleState == .enabled,
           trialGateSource.allowsScopedExecution
        {
            gateRecords.append(
                serviceWorkerTrialGateRecord(
                    target: target,
                    extensionID: extensionID,
                    profileID: profileID,
                    selected: selected,
                    generatedRecord: generatedRecord,
                    state: .openScopedTrial,
                    source: trialGateSource,
                    reason:
                        "Explicit scoped local real-package service-worker execution trial opened.",
                    blockers: []
                )
            )
            let request = ChromeMV3ServiceWorkerJSExecutionRequest(
                manifest: manifest,
                generatedBundleRecord: generatedRecord,
                extensionID: extensionID,
                profileID: profileID,
                moduleState: moduleState,
                extensionEnabled: extensionEnabled,
                localExperimentalGateAllowed: true,
                dynamicImportRewriteExperimentAllowed: true
            )
            let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
                request: request
            )
            policy = harness.policy
            let started = harness.start()
            if started.status == .running {
                let drain = harness.drainQueuedTimeouts()
                timerShimResult = serviceWorkerTimerShimResult(
                    policy: harness.policy,
                    snapshot: harness.snapshot,
                    drain: drain
                )
            } else {
                timerShimResult = serviceWorkerTimerShimResult(
                    policy: harness.policy,
                    snapshot: harness.snapshot,
                    drain: nil
                )
            }
            executionStartResult = started
            resourceLoadResult = harness.snapshot.resourceLoad
            capturedRegistrations = harness.snapshot.capturedListeners
            capturedFamilies = capturedRegistrations
                .map(\.event)
                .uniqueSortedRealPackageValues()

            let dispatchAvailable =
                started.status == .running
                    || harness.canDispatchCapturedListeners
            if dispatchAvailable {
                dispatchResults.append(
                    contentsOf: dispatchSafeServiceWorkerSmoke(
                        harness: harness,
                        trustedNativeFixturePolicyAllowed:
                            trustedNativeFixturePolicyAllowed,
                        nativeMessagingIntegrationSmoke:
                            &nativeMessagingIntegrationSmoke,
                        runtimePortSmoke: &runtimePortSmoke
                    )
                )
            }
            if started.status == .running {
                _ = harness.triggerIdleRelease()
                idleTeardownResult =
                    harness.snapshot.startRecord.status == .stoppedAfterIdle
                        ? "verified: explicit idle release tore down the isolated JavaScriptCore worker surface."
                        : "failed: explicit idle release did not report stoppedAfterIdle."
                hardTimeoutTeardownResult =
                    verifyServiceWorkerHardTimeout(request: request)
            } else {
                _ = harness.triggerIdleRelease()
                idleTeardownResult =
                    dispatchAvailable
                    ? "verified: captured-listener diagnostic dispatch surface was explicitly released after the scoped trial."
                    : "notRequired: execution did not reach a running worker; scoped harness teardown still completed."
                hardTimeoutTeardownResult =
                    "notRequired: execution did not reach a running worker."
            }
            gateRecords.append(
                serviceWorkerTrialGateRecord(
                    target: target,
                    extensionID: extensionID,
                    profileID: profileID,
                    selected: selected,
                    generatedRecord: generatedRecord,
                    state: .closedAfterTrial,
                    source: trialGateSource,
                    reason:
                        "Scoped local real-package service-worker execution trial closed after deterministic teardown.",
                    blockers: []
                )
            )
            gateClosedAfterTrial = true
        }

        let delta = serviceWorkerCaptureDelta(
            declared: declared,
            trialGateSource: trialGateSource,
            staticFamilies: staticFamilies,
            capturedFamilies: capturedFamilies,
            capturedRegistrations: capturedRegistrations,
            snapshotUnsupportedCalls:
                resourceLoadResult == nil
                    ? [] : executionStartResult?.blockedUnsupportedCalls ?? [],
            startResult: executionStartResult,
            resourceLoadResult: resourceLoadResult
        )
        let statuses = serviceWorkerEventStatuses(
            declared: declared,
            readiness: readiness,
            capturedFamilies: capturedFamilies,
            actualDispatchResults: dispatchResults,
            executionCaptureAttempted:
                trialGateSource.allowsScopedExecution
        )
        let importScriptsResult = serviceWorkerImportScriptsResult(
            resourceLoadResult: resourceLoadResult
        )
        let computedImportScriptsResult =
            serviceWorkerComputedImportScriptsResult(
                dependencyInventory: dependencyInventory,
                resourceLoadResult: resourceLoadResult
            )
        let dynamicImportRewriteResult = serviceWorkerDynamicImportRewriteResult(
            policy: policy,
            resourceLoadResult: resourceLoadResult
        )
        let cryptoCapabilityResult = serviceWorkerCryptoCapabilityResult(
            policy: policy,
            executionStartResult: executionStartResult
        )
        let cryptoOperationSummary = serviceWorkerCryptoOperationSummary(
            executionStartResult: executionStartResult
        )
        let i18nCapabilityResult = serviceWorkerI18nCapabilityResult(
            policy: policy,
            executionStartResult: executionStartResult
        )
        let i18nOperationSummary = serviceWorkerI18nOperationSummary(
            executionStartResult: executionStartResult
        )
        let alarmPolicyResult = serviceWorkerAlarmPolicyResult(policy: policy)
        let alarmRecords = executionStartResult?.alarmRecords ?? []
        let alarmOperationSummary = serviceWorkerAlarmOperationSummary(
            executionStartResult: executionStartResult
        )
        let alarmDispatchResult = serviceWorkerAlarmDispatchResult(
            alarmRecords: alarmRecords,
            dispatchResults: dispatchResults
        )
        let workerNavigatorUserAgentResult =
            serviceWorkerWorkerNavigatorUserAgentResult(policy: policy)
        let deviceFailure = serviceWorkerDeviceFailureClassification(
            policy: policy,
            dependencyInventory: dependencyInventory,
            executionStartResult: executionStartResult
        )
        let precedingChromeAPICalls =
            executionStartResult?.precedingChromeAPICalls ?? []
        let storageOperationSummary = serviceWorkerStorageOperationSummary(
            executionStartResult: executionStartResult
        )
        let runtimeSendMessagePolicyResult =
            serviceWorkerRuntimeSendMessagePolicyResult(policy: policy)
        let runtimeSendMessageSummary =
            serviceWorkerRuntimeSendMessageSummary(
                executionStartResult: executionStartResult
            )
        let runtimeLastErrorObjectShapeResult =
            serviceWorkerRuntimeLastErrorObjectShapeResult(
                policy: policy
            )
        let runtimeLastErrorCallbackLifecycleResult =
            serviceWorkerRuntimeLastErrorCallbackLifecycleResult(
                policy: policy
            )
        let workerGlobalEventTargetResult =
            serviceWorkerWorkerGlobalEventTargetResult(
                policy: policy,
                executionStartResult: executionStartResult
            )
        let workerGlobalEventSummary = serviceWorkerWorkerGlobalEventSummary(
            executionStartResult: executionStartResult
        )
        let fetchClassificationResult =
            serviceWorkerFetchClassificationResult(
                policy: policy,
                dependencyInventory: dependencyInventory,
                executionStartResult: executionStartResult
            )
        let fetchClassificationSummary =
            serviceWorkerFetchClassificationSummary(
                dependencyInventory: dependencyInventory,
                executionStartResult: executionStartResult
            )
        let generatedBundleFetchResourceSummary =
            serviceWorkerGeneratedBundleFetchResourceSummary(
                generatedRecord: generatedRecord
            )
        let webAssemblyCapabilityResult =
            serviceWorkerWebAssemblyCapabilityResult(
                executionStartResult: executionStartResult
            )
        let workerWindowFailureClassification =
            serviceWorkerWorkerWindowFailureClassification(
                executionStartResult: executionStartResult
            )
        let moduleWorkerReadinessResult =
            serviceWorkerModuleWorkerReadinessResult(
                policy: policy,
                dependencyInventory: dependencyInventory
            )
        let dispatchSmokeResult = serviceWorkerDispatchSmokeResult(
            capturedFamilies: capturedFamilies,
            dispatchResults: dispatchResults,
            runtimePortSmoke: runtimePortSmoke
        )
        let nextBlocker = serviceWorkerNextBlockerClassification(
            declared: declared,
            delta: delta,
            dependencyInventory: dependencyInventory,
            resourceLoadResult: resourceLoadResult,
            executionStartResult: executionStartResult,
            capturedFamilies: capturedFamilies,
            dispatchResults: dispatchResults,
            runtimePortSmoke: runtimePortSmoke
        )
        let blockers: [String]
        if declared == false {
            blockers = []
        } else if let readiness {
            blockers = uniqueSortedRealPackages(
                readiness.blockers.map { "serviceWorker.\($0.rawValue)" }
                    + (resourceLoadResult?.blockers.map {
                        "serviceWorker.resource.\($0.rawValue)"
                    } ?? [])
                    + (resourceLoadResult?.importScriptsBlockers.map {
                        "serviceWorker.importScripts.\($0.rawValue)"
                    } ?? [])
                    + (resourceLoadResult?.dynamicImportBlockers.map {
                        "serviceWorker.dynamicImport.\($0.rawValue)"
                    } ?? [])
                    + (executionStartResult?.blockers.map {
                        "serviceWorker.execution.\($0.rawValue)"
                    } ?? [])
                    + statuses.compactMap { status in
                        status.status == .deferred
                            ? "serviceWorker.\(status.source.rawValue):noListener"
                            : nil
                    }
            )
        } else {
            blockers = [
                "serviceWorker.manifestUnavailable",
            ]
        }
        return ChromeMV3PasswordManagerRealPackageServiceWorkerEventReadiness(
            declared: declared,
            declarationReadiness: readiness,
            trialGateRecords: gateRecords,
            jsExecutionPolicy: policy,
            resourceLoadResult: resourceLoadResult,
            dependencyInventory: dependencyInventory,
            executionStartResult: executionStartResult,
            actualListenerRegistrationCaptureStatus:
                serviceWorkerListenerCaptureStatus(
                    trialGateSource: trialGateSource,
                    startResult: executionStartResult,
                    capturedFamilies: capturedFamilies
                ),
            capturedListenerFamilies: capturedFamilies,
            missingListenerFamilies: delta.missingListenerFamilies,
            importScriptsResolvedCount:
                resourceLoadResult?.importScriptsResolvedCount ?? 0,
            importedScriptPaths:
                resourceLoadResult?.importedScripts
                    .compactMap(\.resolvedRelativePath)
                    .sorted() ?? [],
            importScriptsBlockers:
                resourceLoadResult?.importScriptsBlockers ?? [],
            dynamicImportBlockers:
                resourceLoadResult?.dynamicImportBlockers ?? [],
            staticVsExecutionDelta: delta,
            actualDispatchResults: dispatchResults,
            importScriptsResult: importScriptsResult,
            computedImportScriptsResult: computedImportScriptsResult,
            dynamicImportRewriteResult: dynamicImportRewriteResult,
            cryptoCapabilityResult: cryptoCapabilityResult,
            cryptoOperationSummary: cryptoOperationSummary,
            cryptoSubtleSupportedAlgorithms:
                policy.subtleCryptoSupportedAlgorithms,
            cryptoSubtleBlockedAlgorithms:
                policy.subtleCryptoBlockedAlgorithms,
            i18nCapabilityResult: i18nCapabilityResult,
            i18nOperationSummary: i18nOperationSummary,
            alarmPolicyResult: alarmPolicyResult,
            alarmRecords: alarmRecords,
            alarmOperationSummary: alarmOperationSummary,
            alarmDispatchResult: alarmDispatchResult,
            workerNavigatorUserAgentResult: workerNavigatorUserAgentResult,
            deviceFailureClassification: deviceFailure.classification,
            deviceFailureDetail: deviceFailure.detail,
            precedingChromeAPICalls: precedingChromeAPICalls,
            storageOperationSummary: storageOperationSummary,
            runtimeSendMessagePolicyResult: runtimeSendMessagePolicyResult,
            runtimeSendMessageSummary: runtimeSendMessageSummary,
            runtimeLastErrorObjectShapeResult:
                runtimeLastErrorObjectShapeResult,
            runtimeLastErrorCallbackLifecycleResult:
                runtimeLastErrorCallbackLifecycleResult,
            workerGlobalEventTargetResult: workerGlobalEventTargetResult,
            workerGlobalEventSummary: workerGlobalEventSummary,
            fetchClassificationResult: fetchClassificationResult,
            fetchClassificationSummary: fetchClassificationSummary,
            generatedBundleFetchResourceSummary:
                generatedBundleFetchResourceSummary,
            webAssemblyCapabilityResult: webAssemblyCapabilityResult,
            workerWindowFailureClassification:
                workerWindowFailureClassification,
            timerShimResult: timerShimResult,
            moduleWorkerReadinessResult: moduleWorkerReadinessResult,
            dispatchSmokeResult: dispatchSmokeResult,
            runtimePortSmoke: runtimePortSmoke,
            nativeMessagingIntegrationSmoke: nativeMessagingIntegrationSmoke,
            idleTeardownResult: idleTeardownResult,
            hardTimeoutTeardownResult: hardTimeoutTeardownResult,
            gateClosedAfterTrial: gateClosedAfterTrial,
            popupOptionsRuntimeMessage:
                serviceWorkerStatus(
                    .popupOptionsRuntimeMessage,
                    from: statuses
                ),
            popupOptionsRuntimeConnect:
                serviceWorkerStatus(
                    .popupOptionsRuntimeConnect,
                    from: statuses
                ),
            contentScriptRuntimeMessage:
                serviceWorkerStatus(
                    .contentScriptRuntimeMessage,
                    from: statuses
                ),
            contentScriptRuntimeConnect:
                serviceWorkerStatus(
                    .contentScriptRuntimeConnect,
                    from: statuses
                ),
            storageChanged: serviceWorkerStatus(.storageChanged, from: statuses),
            permissionsAdded:
                serviceWorkerStatus(.permissionsAdded, from: statuses),
            permissionsRemoved:
                serviceWorkerStatus(.permissionsRemoved, from: statuses),
            nativeMessagingConnect:
                serviceWorkerStatus(.nativeMessagingConnect, from: statuses),
            nativeMessagingMessage:
                serviceWorkerStatus(.nativeMessagingMessage, from: statuses),
            eventStatuses: statuses,
            blockers: blockers,
            nextBlockerClassification: nextBlocker.classification,
            nextBlockerDetail: nextBlocker.detail,
            nextRecommendedFix:
                serviceWorkerNextRecommendedFix(
                    declared: declared,
                    delta: delta,
                    resourceLoadResult: resourceLoadResult,
                    dependencyInventory: dependencyInventory,
                    executionStartResult: executionStartResult
                ),
            diagnostics:
                uniqueSortedRealPackages(
                    (readiness?.diagnostics ?? [])
                        + dependencyInventory.diagnostics
                        + [
                            declared
                                ? "Real-package service-worker readiness was evaluated with stable runtimeLoadable still false."
                                : "No background.service_worker declaration requires routing.",
                            trialGateSource.allowsScopedExecution
                                ? "Actual JavaScript listener registration capture was attempted only inside an explicit scoped local trial."
                                : "Actual JavaScript listener registration capture was not attempted while the local experimental gate stayed closed.",
                            "No permanent background page, timer, repeated scheduling loop, arbitrary normal-tab wake, real credential bridge, or vendor native-host launch was enabled.",
                        ]
                )
        )
    }

    private static func serviceWorkerEventStatuses(
        declared: Bool,
        readiness: ChromeMV3ServiceWorkerDeclarationReadiness?,
        capturedFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent],
        actualDispatchResults: [ChromeMV3ServiceWorkerJSDispatchRecord],
        executionCaptureAttempted: Bool
    ) -> [ChromeMV3PasswordManagerRealPackageServiceWorkerEventStatus] {
        serviceWorkerReportSources.map { source in
            let coverage = readiness?.coverage(for: source.listenerEvent)
            let executedListenerDetected =
                capturedFamilies.contains(source.listenerEvent)
            let listenerDetected =
                executionCaptureAttempted
                    ? executedListenerDetected
                    : coverage?.listenerDetected == true
            let actual = actualDispatchResults.first {
                $0.source == source
            }
            let routingKind: ChromeMV3ServiceWorkerEventRoutingResultKind?
            let status: ChromeMV3PasswordManagerCompatibilityStatus
            if declared == false {
                routingKind = nil
                status = .notRequired
            } else if let actual {
                routingKind = actual.lifecycleRoutingRecord?.resultKind
                    ?? serviceWorkerRoutingKind(for: actual.resultKind)
                status =
                    actual.resultKind == .delivered ? .partial : .blocked
            } else if readiness == nil {
                routingKind = .failed
                status = .blocked
            } else if executionCaptureAttempted {
                routingKind = listenerDetected ? nil : noListenerKind(source)
                status = listenerDetected ? .partial : .deferred
            } else if readiness?.eventRoutingAvailable == true {
                routingKind = listenerDetected ? .delivered : noListenerKind(source)
                status = listenerDetected ? .partial : .deferred
            } else {
                routingKind = .blockedByGate
                status = .blocked
            }
            return ChromeMV3PasswordManagerRealPackageServiceWorkerEventStatus(
                source: source,
                targetListener: source.listenerEvent,
                status: status,
                routingResultKind: routingKind,
                listenerDetected: listenerDetected,
                listenerDetectionPattern:
                    executedListenerDetected
                        ? "executed JavaScriptCore registration capture"
                        : coverage?.detectionPattern,
                payloadSummary:
                    "diagnostic:\(source.rawValue)->\(source.listenerEvent.rawValue)",
                diagnostics:
                    uniqueSortedRealPackages(
                        (coverage?.diagnostics ?? [])
                            + [
                                declared
                                    ? "Event source is represented in the real-package readiness report."
                                    : "Event source is not required because no service worker is declared.",
                                actual == nil
                                    ? "No event was dispatched for this source during compatibility report generation."
                                    : "A safe synthetic event was dispatched through the executed listener capture.",
                            ]
                    )
            )
        }
    }

    private static func serviceWorkerTrialGateRecord(
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        extensionID: String,
        profileID: String,
        selected: SelectedPackage,
        generatedRecord: ChromeMV3GeneratedBundleRecord?,
        state:
            ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateState,
        source:
            ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource,
        reason: String,
        blockers: [String]
    ) -> ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateRecord {
        ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateRecord(
            targetID: target.targetID,
            extensionID: extensionID,
            profileID: profileID,
            localPackageRoot:
                selected.resourceScanRootPath
                    ?? selected.packageURL?.standardizedFileURL.path
                    ?? target.explicitAllowedLocalRoot,
            generatedBundleID: generatedRecord?.id,
            state: state,
            source: source,
            reason: reason,
            blockers: blockers.sorted()
        )
    }

    private static func serviceWorkerCaptureDelta(
        declared: Bool,
        trialGateSource:
            ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource,
        staticFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent],
        capturedFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent],
        capturedRegistrations:
            [ChromeMV3ServiceWorkerJSCapturedListenerRegistration],
        snapshotUnsupportedCalls: [String],
        startResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?,
        resourceLoadResult: ChromeMV3ServiceWorkerJSResourceLoadRecord?
    ) -> ChromeMV3PasswordManagerRealPackageServiceWorkerCaptureDelta {
        let attempted = trialGateSource.allowsScopedExecution
        let missing =
            attempted
                ? Array(Set(staticFamilies).subtracting(capturedFamilies))
                    .sorted()
                : []
        let extra =
            attempted
                ? Array(Set(capturedFamilies).subtracting(staticFamilies))
                    .sorted()
                : []
        let unsupportedForms =
            uniqueSortedRealPackages(
                snapshotUnsupportedCalls
                    + capturedRegistrations.compactMap {
                        $0.asyncFunctionDetected
                            ? "\($0.event.rawValue):asyncFunctionPromiseCompletionDeferred"
                            : nil
                    }
                    + (resourceLoadResult?.blockers.compactMap {
                        switch $0 {
                        case .dynamicImportExecutionSurfaceUnsupported,
                             .dynamicImportGeneratedRootContainmentUnproven,
                             .dynamicImportLowerLevelAPINotAvailable,
                             .dynamicImportModuleNamespaceUnsupported,
                             .dynamicImportNoLoader,
                             .dynamicImportParseUnsupported,
                             .dynamicImportPromiseDrainUnavailable,
                             .dynamicImportResolverHookUnavailable,
                             .dynamicImportUnsupported,
                             .staticModuleImportUnsupported:
                            return $0.rawValue
                        default:
                            return nil
                        }
                    } ?? [])
                    + (resourceLoadResult?.importScriptsBlockers.map {
                        "importScripts.\($0.rawValue)"
                    } ?? [])
                    + (resourceLoadResult?.dynamicImportBlockers.map {
                        "dynamicImport.\($0.rawValue)"
                    } ?? [])
            )
        let status:
            ChromeMV3PasswordManagerRealPackageServiceWorkerCaptureDeltaStatus
        if declared == false {
            status = .noListener
        } else if attempted == false {
            status = staticFamilies.isEmpty ? .noListener : .staticOnly
        } else if startResult?.status == .running {
            status = capturedFamilies.isEmpty ? .noListener : .executionCaptured
        } else if startResult?.status == .failed {
            status = .executionFailed
        } else if startResult?.status == .blocked {
            status = .executionBlocked
        } else {
            status = .unknown
        }
        return ChromeMV3PasswordManagerRealPackageServiceWorkerCaptureDelta(
            status: status,
            staticListenerFamilies: staticFamilies,
            executionCapturedListenerFamilies: capturedFamilies,
            missingListenerFamilies: missing,
            extraCapturedListenerFamilies: extra,
            unsupportedListenerForms: unsupportedForms,
            failedExecutionReason: startResult?.lastErrorMessage,
            diagnostics:
                uniqueSortedRealPackages([
                    attempted
                        ? "Static token detection was compared with executed JavaScriptCore listener registration capture."
                        : "Static token detection is recorded without executing the worker because the scoped trial gate stayed closed.",
                    "Missing listeners are static detections not observed during execution; extra listeners are execution captures missed by direct-token detection.",
                ])
        )
    }

    private static func serviceWorkerListenerCaptureStatus(
        trialGateSource:
            ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource,
        startResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?,
        capturedFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    ) -> String {
        guard trialGateSource.allowsScopedExecution else {
            return "notAttempted: real-package compatibility reporting kept the local experimental service-worker JavaScript gate closed."
        }
        switch startResult?.status {
        case .running:
            return capturedFamilies.isEmpty
                ? "executed:noListener registrations captured."
                : "executed:captured \(capturedFamilies.count) listener families."
        case .failed:
            return "executionFailed: \(startResult?.lastErrorMessage ?? "unknown JavaScriptCore evaluation failure")"
        case .blocked:
            return "executionBlocked: \(startResult?.lastErrorMessage ?? "resource or policy blocker")"
        case .none:
            return "executionBlocked: no execution start record was created."
        default:
            return "executionBlocked: worker did not remain running."
        }
    }

    private static func dispatchSafeServiceWorkerSmoke(
        harness: ChromeMV3ServiceWorkerJSExecutionHarness,
        trustedNativeFixturePolicyAllowed: Bool,
        nativeMessagingIntegrationSmoke: inout String,
        runtimePortSmoke:
            inout ChromeMV3PasswordManagerRealPackageServiceWorkerPortSmoke
    ) -> [ChromeMV3ServiceWorkerJSDispatchRecord] {
        var results: [ChromeMV3ServiceWorkerJSDispatchRecord] = []
        func dispatchIfCaptured(
            _ source: ChromeMV3ServiceWorkerEventSource,
            arguments: [ChromeMV3StorageValue],
            payloadSummary: String,
            sender: ChromeMV3ServiceWorkerEventSenderMetadata = .none
        ) {
            guard harness.capturedListener(for: source.listenerEvent) else {
                return
            }
            results.append(
                harness.dispatch(
                    source: source,
                    arguments: arguments,
                    sender: sender,
                    payloadSummary: payloadSummary
                )
            )
        }

        let message = ChromeMV3StorageValue.object([
            "kind": .string("sumiLocalExperimentalServiceWorkerTrial"),
            "value": .string("deterministic"),
        ])
        dispatchIfCaptured(
            .popupOptionsRuntimeMessage,
            arguments: [message],
            payloadSummary: "popup/options deterministic runtime.onMessage smoke"
        )
        dispatchIfCaptured(
            .contentScriptRuntimeMessage,
            arguments: [message],
            payloadSummary: "content-script deterministic runtime.onMessage smoke",
            sender: ChromeMV3ServiceWorkerEventSenderMetadata(
                tabID: 1,
                frameID: 0,
                documentID: "sumi-local-experimental-document",
                sourceURL: nil,
                urlRedacted: true,
                redactionState: "synthetic content-script sender URL redacted"
            )
        )

        if harness.capturedListener(for: .runtimeOnConnect) {
            let connected = harness.connectRuntime(
                name: "sumi-local-experimental-port"
            )
            results.append(connected)
            var messageDelivered = false
            var disconnected = false
            if let portID = connected.portID {
                messageDelivered =
                    harness.deliverPortMessage(
                        portID: portID,
                        message: message
                    ) != nil
                disconnected = harness.disconnectPort(portID: portID)
            }
            let released =
                harness.snapshot.lifecycleSnapshot?
                .activeKeepaliveRecords.isEmpty ?? true
            runtimePortSmoke =
                ChromeMV3PasswordManagerRealPackageServiceWorkerPortSmoke(
                    attempted: true,
                    connectResult: connected,
                    portMessageDelivered: messageDelivered,
                    portDisconnected: disconnected,
                    keepaliveReleased: released,
                    diagnostics: [
                        "A deterministic runtime Port was opened only when an executed runtime.onConnect listener was captured.",
                        "The runtime Port was disconnected explicitly and its lifecycle keepalive was checked.",
                    ]
                )
        }

        dispatchIfCaptured(
            .storageChanged,
            arguments: [
                .object([
                    "sumiTrialKey": .object([
                        "newValue": .string("local-experimental"),
                    ]),
                ]),
                .string("local"),
            ],
            payloadSummary: "deterministic storage.onChanged smoke"
        )
        let permissionPayload = ChromeMV3StorageValue.object([
            "permissions": .array([.string("storage")]),
            "origins": .array([]),
        ])
        dispatchIfCaptured(
            .permissionsAdded,
            arguments: [permissionPayload],
            payloadSummary: "deterministic permissions.onAdded smoke"
        )
        dispatchIfCaptured(
            .permissionsRemoved,
            arguments: [permissionPayload],
            payloadSummary: "deterministic permissions.onRemoved smoke"
        )
        if harness.capturedListener(for: .alarmsOnAlarm) {
            results.append(harness.triggerAlarm())
        }
        dispatchIfCaptured(
            .contextMenuClicked,
            arguments: [
                .object(["menuItemId": .string("sumi-local-trial")]),
                .object(["id": .number(1)]),
            ],
            payloadSummary: "deterministic contextMenus.onClicked smoke"
        )
        dispatchIfCaptured(
            .webNavigationSyntheticEvent,
            arguments: [
                .object([
                    "tabId": .number(1),
                    "frameId": .number(0),
                    "url": .string("https://example.com/local-trial"),
                ]),
            ],
            payloadSummary: "deterministic webNavigation.onCommitted smoke"
        )

        if trustedNativeFixturePolicyAllowed {
            let opened = harness.openTrustedNativeFixturePort(
                name: "com.sumi.local_experimental_fixture",
                trustedFixturePolicyAllowed: true
            )
            results.append(opened)
            if let portID = opened.portID {
                results.append(
                    harness.deliverTrustedNativeFixturePortMessage(
                        portID: portID,
                        message: message
                    )
                )
                _ = harness.disconnectPort(portID: portID)
            }
            nativeMessagingIntegrationSmoke =
                "trustedFixtureDispatched: synthetic native Port connect/message lifecycle was modeled without vendor-host discovery or launch."
        }
        return results
    }

    private static func verifyServiceWorkerHardTimeout(
        request: ChromeMV3ServiceWorkerJSExecutionRequest
    ) -> String {
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: request
        )
        guard harness.start().status == .running else {
            _ = harness.triggerIdleRelease()
            return "failed: hard-timeout verification could not start a second isolated worker instance."
        }
        if harness.capturedListener(for: .runtimeOnConnect) {
            _ = harness.connectRuntime(name: "sumi-local-hard-timeout-port")
        }
        _ = harness.triggerHardTimeout()
        let snapshot = harness.snapshot
        return snapshot.startRecord.status == .stoppedAfterHardTimeout
            && snapshot.ports.allSatisfy { $0.connected == false }
            ? "verified: explicit hard-timeout teardown released the isolated worker surface and disconnected ports."
            : "failed: explicit hard-timeout teardown did not release all isolated worker state."
    }

    private static func serviceWorkerRoutingKind(
        for kind: ChromeMV3ServiceWorkerJSDispatchResultKind
    ) -> ChromeMV3ServiceWorkerEventRoutingResultKind {
        switch kind {
        case .blockedByGate:
            return .blockedByGate
        case .blockedByPermission:
            return .blockedByPermission
        case .delivered:
            return .delivered
        case .listenerError:
            return .listenerError
        case .noListener:
            return .noListener
        case .noReceiver:
            return .noReceiver
        case .promiseRejected:
            return .promiseRejected
        case .sendResponseTimeoutDiagnostic:
            return .sendResponseTimeoutDiagnostic
        case .unsupportedListenerMode:
            return .unsupportedListenerMode
        }
    }

    private static func serviceWorkerImportScriptsResult(
        resourceLoadResult: ChromeMV3ServiceWorkerJSResourceLoadRecord?
    ) -> String {
        guard let resourceLoadResult else {
            return "notAttempted: service-worker resource loading was not reached."
        }
        if resourceLoadResult.importScriptsDetected == false {
            return "notRequired: no importScripts call was detected."
        }
        if let blocker = resourceLoadResult.importScriptsBlockers.first {
            return "blocked: \(blocker.rawValue)."
        }
        if resourceLoadResult.importScriptsResolvedCount > 0 {
            let paths = resourceLoadResult.importedScripts
                .compactMap(\.resolvedRelativePath)
                .sorted()
            return "resolved: \(resourceLoadResult.importScriptsResolvedCount) generated-bundle import(s)"
                + (paths.isEmpty ? "." : " - \(paths.prefix(3).joined(separator: ", ")).")
        }
        return "detected: importScripts was present but no generated-bundle dependency was resolved."
    }

    private static func serviceWorkerComputedImportScriptsResult(
        dependencyInventory:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory,
        resourceLoadResult: ChromeMV3ServiceWorkerJSResourceLoadRecord?
    ) -> String {
        let computed = dependencyInventory.importScriptsCalls.filter {
            $0.shape != .stringLiteralLocal
                && $0.shape != .templateLiteralStatic
        }
        guard computed.isEmpty == false else {
            return "notRequired: no computed importScripts dependency expression was inventoried."
        }
        let bounded = computed.filter {
            $0.dependencyCandidatePath != nil
        }.count
        if let resourceLoadResult,
           resourceLoadResult.importScriptsResolvedCount > 0,
           resourceLoadResult.importScriptsBlockers.isEmpty
        {
            let paths = resourceLoadResult.importedScripts
                .compactMap(\.resolvedRelativePath)
                .sorted()
            return "resolved: bounded computed importScripts resolved \(resourceLoadResult.importScriptsResolvedCount) generated-bundle import(s); bounded inventory candidates \(bounded)/\(computed.count)"
                + (paths.isEmpty ? "." : " - \(paths.prefix(3).joined(separator: ", ")).")
        }
        if let blocker = resourceLoadResult?.importScriptsBlockers.first(
            where: {
                $0 == .computedImportScriptsCandidateSetUnbounded
                    || $0 == .computedImportScriptsConstantMapCandidateUnsafe
                    || $0 == .computedImportScriptsRuntimeVariableRejected
            }
        ) {
            return "blocked: \(blocker.rawValue); bounded inventory candidates \(bounded)/\(computed.count)."
        }
        if bounded < computed.count {
            return "guarded: bounded inventory candidates \(bounded)/\(computed.count); runtime-variable or otherwise unbounded importScripts paths remain rejected unless the runtime call matches a statically authorized generated-root-contained candidate set."
        }
        return "inventoried: bounded computed candidates \(bounded)/\(computed.count); runtime authorization remains generated-root-contained."
    }

    private static func serviceWorkerTimerShimResult(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy,
        snapshot: ChromeMV3ServiceWorkerJSExecutionSnapshot,
        drain: ChromeMV3ServiceWorkerJSTimerDrainRecord?
    ) -> String {
        guard policy.timersAvailableInLocalExperimentalGate else {
            return "blockedByPolicy: deterministic timer shim requires the explicit local experimental gate."
        }
        guard let drain else {
            return "available: manual timer queue installed; worker did not reach an explicit timeout drain."
        }
        let activeIntervals = snapshot.timers.filter {
            $0.kind == .interval && $0.active
        }.count
        return "drained: \(drain.callbackCount) timeout callback(s), \(drain.callbackErrors.count) callback error(s), \(drain.pendingTimeoutCount) queued timeout(s), \(activeIntervals) manual interval(s); wallClockTimersAllowed=false."
    }

    private static func serviceWorkerModuleWorkerReadinessResult(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy,
        dependencyInventory:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory
    ) -> String {
        guard dependencyInventory.moduleWorkerInventory.declaredAsModuleWorker
        else {
            return "notRequired: background.type is classic."
        }
        let inventory = dependencyInventory.moduleWorkerInventory
        let blockers = policy.moduleWorkerReadinessProbe.blockers
            .map(\.rawValue)
            .joined(separator: ", ")
        return "blocked: staticImports=\(inventory.staticImportDeclarations.count), exports=\(inventory.exportUsageLocations.count), topLevelAwait=\(inventory.topLevelAwaitDetected), dynamicImports=\(inventory.dynamicImportUsage.count); public JavaScriptCore module loader unavailable; blockers=\(blockers)."
    }

    private static func serviceWorkerDynamicImportRewriteResult(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy,
        resourceLoadResult: ChromeMV3ServiceWorkerJSResourceLoadRecord?
    ) -> String {
        guard let resourceLoadResult else {
            return "notAttempted: service-worker resource loading was not reached."
        }
        if resourceLoadResult.dynamicImportDetected == false {
            return "notRequired: no dynamic import expression was detected."
        }
        if policy
            .dynamicImportRewriteExperimentAvailableInLocalExperimentalGate
            == false
        {
            return "blockedByPolicy: dynamic-import rewrite experiment was unavailable."
        }
        if resourceLoadResult.dynamicImportRewriteExperimentApplied {
            return "applied: evaluated \(resourceLoadResult.dynamicImportRewriteEvaluationCount) generated-bundle dynamic import(s)."
        }
        if let blocker = resourceLoadResult.dynamicImportBlockers.first {
            return "blocked: \(blocker.rawValue)."
        }
        let eligibleCount =
            resourceLoadResult.dynamicImportRecords.filter(\.rewriteEligible)
            .count
        return "notApplied: \(eligibleCount) rewrite-eligible import(s), no dependency evaluation needed."
    }

    private static func serviceWorkerCryptoCapabilityResult(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy,
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> String {
        guard policy.webCryptoAvailableInLocalExperimentalGate else {
            return "blockedByPolicy: WebCrypto requires the explicit local experimental MV3 gate."
        }
        let operations = executionStartResult?.cryptoOperationRecords ?? []
        let blocked = operations.filter { $0.status == "blocked" }
        let fulfilled = operations.filter { $0.status == "fulfilled" }
        return "available: crypto.getRandomValues=\(policy.cryptoGetRandomValuesAvailable), crypto.randomUUID=\(policy.cryptoRandomUUIDAvailable), subtleMethods=\(policy.subtleCryptoSupportedMethods.joined(separator: ",")), default=\(policy.webCryptoAvailableByDefault), fulfilled=\(fulfilled.count), blocked=\(blocked.count)."
    }

    private static func serviceWorkerCryptoOperationSummary(
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> [String] {
        (executionStartResult?.cryptoOperationRecords ?? []).map { record in
            [
                record.operation,
                record.algorithm ?? "none",
                record.status,
                record.blocker ?? "none",
            ].joined(separator: ":")
        }
        .sorted()
    }

    private static func serviceWorkerI18nCapabilityResult(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy,
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> String {
        guard policy.i18nGetUILanguageAvailableInLocalExperimentalGate else {
            return "blockedByPolicy: chrome.i18n.getUILanguage requires the explicit local experimental MV3 gate."
        }
        let operations = executionStartResult?.i18nOperationRecords ?? []
        let fulfilled = operations.filter { $0.status == "fulfilled" }.count
        let blocked = operations.filter { $0.status == "blocked" }.count
        let requestedMessages =
            uniqueSortedRealPackages(operations.compactMap(\.messageName))
                .joined(separator: ",")
        return "available: getUILanguage=true, getMessage=\(policy.i18nGetMessageAvailableInLocalExperimentalGate), defaultUILanguage=\(policy.i18nGetUILanguageAvailableByDefault), defaultGetMessage=\(policy.i18nGetMessageAvailableByDefault), generatedBundleLocalesOnly=\(policy.i18nGeneratedBundleLocalesOnly), networkLocales=\(policy.i18nNetworkLocalesAllowed), filesystemLocaleFallback=\(policy.i18nFilesystemLocaleFallbackAllowed), uiLanguage=\(policy.i18nSelectedUILanguage), localeSource=\(policy.i18nLocaleSource), selectedLocale=\(policy.i18nSelectedLocale), fallbackLocale=\(policy.i18nFallbackLocale ?? "none"), defaultLocale=\(policy.i18nDefaultLocale ?? "none"), availableLocales=\(policy.i18nAvailableLocales.joined(separator: ",")), missingCatalogs=\(policy.i18nMissingCatalogLocales.joined(separator: ",")), invalidCatalogs=\(policy.i18nInvalidCatalogPaths.joined(separator: ",")), malformedMessages=\(policy.i18nMalformedMessages.joined(separator: ",")), requestedMessages=\(requestedMessages), fulfilled=\(fulfilled), blocked=\(blocked), unsupported=\(policy.i18nUnsupportedAPIs.joined(separator: ","))."
    }

    private static func serviceWorkerI18nOperationSummary(
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> [String] {
        (executionStartResult?.i18nOperationRecords ?? []).map { record in
            [
                record.operation,
                record.status,
                record.messageName ?? "none",
                record.value ?? "none",
                record.source ?? "none",
                record.blocker ?? "none",
            ].joined(separator: ":")
        }
        .sorted()
    }

    private static func serviceWorkerAlarmPolicyResult(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy
    ) -> String {
        guard policy.alarmsAvailableInLocalExperimentalGate else {
            return "blockedByPolicy: chrome.alarms requires the explicit local experimental MV3 gate."
        }
        return "available: localExperimental=true, default=\(policy.alarmsAvailableByDefault), wallClockScheduling=\(policy.wallClockAlarmSchedulingAllowed), polling=\(policy.pollingAllowed), backgroundWake=\(policy.backgroundWakeAllowed), explicitTriggerOnly=\(policy.explicitAlarmTriggerOnly)."
    }

    private static func serviceWorkerAlarmOperationSummary(
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> [String] {
        (executionStartResult?.alarmOperationRecords ?? []).map { record in
            [
                record.methodName,
                record.succeeded ? "succeeded" : "blocked",
                record.alarmName ?? "none",
                record.lastErrorMessage ?? "none",
            ].joined(separator: ":")
        }
        .sorted()
    }

    private static func serviceWorkerAlarmDispatchResult(
        alarmRecords: [ChromeMV3ServiceWorkerJSAlarmRecord],
        dispatchResults: [ChromeMV3ServiceWorkerJSDispatchRecord]
    ) -> String {
        guard let result = dispatchResults.first(where: {
            $0.source == .alarmTriggered
        }) else {
            return "notAttempted: no captured alarms.onAlarm listener was dispatched."
        }
        let alarmName =
            alarmRecords.sorted {
                if $0.createdSequence != $1.createdSequence {
                    return $0.createdSequence < $1.createdSequence
                }
                return $0.name < $1.name
            }.first?.name ?? "sumi-local-trial"
        return "attempted: result=\(result.resultKind.rawValue), alarm=\(alarmName), event=\(result.event.rawValue)."
    }

    private static func serviceWorkerWorkerNavigatorUserAgentResult(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy
    ) -> String {
        guard
            policy.workerNavigatorUserAgentAvailableInLocalExperimentalGate
        else {
            return "blockedByPolicy: WorkerNavigator.userAgent requires the explicit local experimental MV3 gate."
        }
        return "available: deterministic harness-only Chrome/0 compatibility-family marker, default=\(policy.workerNavigatorUserAgentAvailableByDefault); this is not a product browser user agent or account/vault/session/device identity."
    }

    private static func serviceWorkerDeviceFailureClassification(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy,
        dependencyInventory:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory,
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> (
        classification:
            ChromeMV3PasswordManagerRealPackageDeviceFailureClassification,
        detail: String
    ) {
        if let receiver =
            executionStartResult?.exceptionDetails?.nullishReceiverDetails,
           receiver.receiverPath == "this.device"
        {
            if dependencyInventory.chromeUserAgentBrowserFamilyCheckDetected,
               policy.workerNavigatorChromeCompatibilityTokenAvailable == false
            {
                return (
                    .workerNavigatorBrowserFamilySignalRequired,
                    "this.device was \(receiver.receiverValue.rawValue) before \(receiver.accessedProperty ?? "property") access. Static local source inventory found a Chrome-family navigator.userAgent check; no fake device, account, vault, session, storage, runtime Port, or network-auth state was inserted."
                )
            }
            return (
                .unknown,
                "this.device was \(receiver.receiverValue.rawValue) before \(receiver.accessedProperty ?? "property") access. JavaScriptCore did not expose the concrete this receiver object, and storage/runtime Port/account/vault/device/network provenance remains unknown."
            )
        }
        if dependencyInventory.browserPlatformDeviceToStringDetected,
           dependencyInventory.chromeUserAgentBrowserFamilyCheckDetected,
           policy.workerNavigatorChromeCompatibilityTokenAvailable
        {
            return (
                .resolvedWorkerNavigatorBrowserFamilySignal,
                "Local source inventory contains this.device.toString and a Chrome-family navigator.userAgent check. The deterministic harness-only Chrome/0 WorkerNavigator marker let evaluation advance without inserting fake device identity, account, vault, session, storage, runtime Port, or network-auth state."
            )
        }
        return (
            .notObserved,
            "No Bitwarden-style this.device nullish receiver failure was observed or inferred from local source inventory."
        )
    }

    private static func serviceWorkerStorageOperationSummary(
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> [String] {
        (executionStartResult?.storageOperationRecords ?? []).map { record in
            [
                record.area,
                record.operation,
                record.keySelectorKind,
                "keys=\(record.keyCount)",
                "fingerprints=\(record.keyFingerprints.joined(separator: ","))",
                "callback=\(record.callbackProvided)",
                "promise=\(record.promiseReturned)",
                "valuesRecorded=\(record.valuesRecorded)",
            ].joined(separator: ":")
        }
    }

    private static func serviceWorkerRuntimeSendMessagePolicyResult(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy
    ) -> String {
        let blockers = policy.runtimeSendMessageBlockers.isEmpty
            ? "none"
            : policy.runtimeSendMessageBlockers.joined(separator: ",")
        return [
            "localExperimental=\(policy.runtimeSendMessageAvailableInLocalExperimentalGate)",
            "default=\(policy.runtimeSendMessageAvailableByDefault)",
            "sameExtensionOnly=\(policy.runtimeSendMessageSameExtensionOnly)",
            "crossExtension=\(policy.crossExtensionMessagingAllowed)",
            "hiddenPage=\(policy.hiddenPageCreationAllowed)",
            "arbitraryWake=\(policy.arbitraryWorkerWakeAllowed)",
            "blockers=\(blockers)",
        ].joined(separator: ":")
    }

    private static func serviceWorkerRuntimeSendMessageSummary(
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> [String] {
        let records = executionStartResult?.runtimeSendMessageRecords ?? []
        guard records.isEmpty == false else {
            return [
                "notObserved: no chrome.runtime.sendMessage call reached the executed service-worker harness.",
            ]
        }
        return records.map { record in
            [
                "seq=\(record.sequence)",
                "overload=\(record.overload)",
                "shape=\(record.messageShape)",
                "result=\(record.resultKind)",
                "responseShape=\(record.responseShape ?? "none")",
                "listeners=\(record.routedListenerCount)",
                "callback=\(record.callbackProvided)",
                "promise=\(record.promiseReturned)",
                "crossExtension=\(record.crossExtension)",
                "recursionBlocked=\(record.recursionBlocked)",
                "lastError=\(record.lastErrorMessage ?? "none")",
            ].joined(separator: ":")
        }
    }

    private static func serviceWorkerRuntimeLastErrorObjectShapeResult(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy
    ) -> String {
        guard
            policy.runtimeLastErrorAvailableInLocalExperimentalGate
        else {
            return "blockedByPolicy: chrome.runtime.lastError requires the explicit local experimental MV3 gate."
        }
        return "available: chrome.runtime.lastError is object-or-undefined, active message is a primitive string, String/template/concatenation coercion is ordinary string coercion, default=\(policy.runtimeLastErrorAvailableByDefault)."
    }

    private static func serviceWorkerRuntimeLastErrorCallbackLifecycleResult(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy
    ) -> String {
        guard policy.runtimeLastErrorCallbackScoped else {
            return "blockedByPolicy: callback-scoped chrome.runtime.lastError lifecycle is unavailable."
        }
        return "available: set before failing callback invocation, visible during callback execution, cleared in finally after callback return; Promise-returning APIs reject without setting runtime.lastError."
    }

    private static func serviceWorkerWorkerGlobalEventTargetResult(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy,
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> String {
        guard
            policy.workerGlobalEventTargetAvailableInLocalExperimentalGate
        else {
            return "blockedByPolicy: worker-global EventTarget requires the explicit local experimental MV3 gate."
        }
        let records = executionStartResult?.workerGlobalEventRecords ?? []
        let additions = records.filter {
            $0.operation == .addEventListener
        }.count
        let removals = records.filter {
            $0.operation == .removeEventListener
        }.count
        let dispatches = records.filter {
            $0.operation == .dispatchEvent
        }.count
        let blocked = records.filter(\.blocked).count
        return "available: addEventListener/removeEventListener/dispatchEvent=true, default=\(policy.workerGlobalEventTargetAvailableByDefault), supportedTypes=\(policy.workerGlobalEventTargetSupportedTypes.joined(separator: ",")), windowDocumentExposed=\(policy.workerGlobalWindowDocumentExposed), add=\(additions), remove=\(removals), dispatch=\(dispatches), blocked=\(blocked)."
    }

    private static func serviceWorkerWorkerGlobalEventSummary(
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> [String] {
        (executionStartResult?.workerGlobalEventRecords ?? []).map { record in
            [
                record.operation.rawValue,
                record.eventType,
                "listeners=\(record.listenerCount)",
                "dispatchListeners=\(record.dispatchListenerCount)",
                "defaultPrevented=\(record.defaultPrevented)",
                "blocked=\(record.blocked)",
            ].joined(separator: ":")
        }
        .sorted()
    }

    private static func serviceWorkerFetchClassificationResult(
        policy: ChromeMV3ServiceWorkerJSExecutionPolicy,
        dependencyInventory:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory,
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> String {
        guard policy.fetchClassificationAvailableInLocalExperimentalGate else {
            return "blockedByPolicy: fetch classification requires the explicit local experimental MV3 gate."
        }
        let runtime = executionStartResult?.fetchClassificationRecords ?? []
        let staticRecords = dependencyInventory.fetchClassifications
        let remote = runtime.filter(\.networkAccessRequired).count
            + staticRecords.filter(\.networkAccessRequired).count
        let local = runtime.filter(\.extensionLocalResource).count
            + staticRecords.filter(\.extensionLocalResource).count
        let fulfilled = runtime.filter(\.executionAllowed).count
        let unknown =
            runtime.filter {
                $0.requestKind == .unknownInput
                    || $0.requestKind == .unsupportedRequestShape
                    || $0.requestKind == .unsupportedScheme
            }.count
            + staticRecords.filter {
                $0.requestKind == .unknownInput
                    || $0.requestKind == .unsupportedRequestShape
                    || $0.requestKind == .unsupportedScheme
            }.count
        return "localExperimentalGeneratedBundleFetch: runtime=\(runtime.count), static=\(staticRecords.count), fulfilled=\(fulfilled), remote=\(remote), extensionLocal=\(local), unknown=\(unknown), available=\(policy.fetchAvailableInLocalExperimentalGate), default=\(policy.fetchAvailableByDefault), networkExecution=\(policy.fetchNetworkExecutionAllowed), extensionLocalExecution=\(policy.fetchExtensionLocalExecutionAllowed), generatedBundleOnly=\(policy.generatedBundleOnly), credentials=\(policy.credentialsAllowed), cache=\(policy.cacheAllowed)."
    }

    private static func serviceWorkerFetchClassificationSummary(
        dependencyInventory:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory,
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> [String] {
        let runtime =
            (executionStartResult?.fetchClassificationRecords ?? []).map {
                record in
                var components = [
                    "runtime",
                    record.sourcePath ?? "unknown",
                    "\(record.line ?? 0)",
                    record.requestKind.rawValue,
                    record.blocker,
                    "allowed=\(record.executionAllowed)",
                ]
                if let fetchedResourcePath = record.fetchedResourcePath {
                    components.append("path=\(fetchedResourcePath)")
                }
                if let status = record.status {
                    components.append("status=\(status)")
                }
                return components.joined(separator: ":")
            }
        let staticRecords = dependencyInventory.fetchClassifications.map {
            record in
            [
                "static",
                record.sourcePath,
                "\(record.line)",
                record.requestKind.rawValue,
                record.blocker,
                "allowed=\(record.executionAllowed)",
            ].joined(separator: ":")
        }
        return uniqueSortedRealPackages(runtime + staticRecords)
    }

    private static func serviceWorkerGeneratedBundleFetchResourceSummary(
        generatedRecord: ChromeMV3GeneratedBundleRecord?
    ) -> [String] {
        let records =
            generatedRecord?.serviceWorkerFetchResourceRecords ?? []
        guard records.isEmpty == false else {
            return [
                "notObserved: no statically discoverable service-worker fetch resources were recorded in the generated bundle.",
            ]
        }
        return uniqueSortedRealPackages(records.map { record in
            [
                record.sourceScriptPath,
                record.requestedPath,
                record.resolvedResourcePath ?? "unresolved",
                record.status.rawValue,
                record.blocker,
            ].joined(separator: ":")
        })
    }

    private static func serviceWorkerWebAssemblyCapabilityResult(
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> String {
        guard let capability = executionStartResult?.webAssemblyCapability else {
            return "notObserved: service-worker execution did not report WebAssembly capability."
        }
        return "webAssembly: global=\(capability.globalPresent), instantiate=\(capability.instantiatePresent), instantiateStreaming=\(capability.instantiateStreamingPresent), compile=\(capability.compilePresent)."
    }

    private static func serviceWorkerWorkerWindowFailureClassification(
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> String {
        guard
            let exception = executionStartResult?.exceptionDetails
        else {
            return "notObserved: no unguarded worker window access failure was observed."
        }
        if exception.message.contains("addEventListener is not a function") {
            return "workerGlobalEventTargetMissing: vendor code advanced past WorkerGlobalScope/self detection and now requires addEventListener on the worker global; DOM Window and document remain intentionally absent."
        }
        guard
            exception.classification == .missingWebAPI,
            exception.inferredMissingGlobal == "window"
        else {
            return "notObserved: no unguarded worker window access failure was observed."
        }
        let sourcePreview =
            exception.diagnostics.first {
                $0.contains("Exception source line preview:")
            } ?? ""
        if sourcePreview.contains("WorkerGlobalScope") {
            return "workerGlobalAliasFallback: vendor code fell back from WorkerGlobalScope/self detection to window; the harness keeps WorkerGlobalScope narrow and does not expose DOM Window or document."
        }
        return "domWindowDependency: vendor code required window inside a service worker; DOM Window and document remain intentionally absent."
    }

    private static func serviceWorkerWorkerWindowFailureObserved(
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> Bool {
        guard let exception = executionStartResult?.exceptionDetails else {
            return false
        }
        if exception.classification == .missingWebAPI,
           exception.inferredMissingGlobal == "window"
        {
            return true
        }
        return exception.message.contains("addEventListener is not a function")
    }

    private static func serviceWorkerDispatchSmokeResult(
        capturedFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent],
        dispatchResults: [ChromeMV3ServiceWorkerJSDispatchRecord],
        runtimePortSmoke:
            ChromeMV3PasswordManagerRealPackageServiceWorkerPortSmoke
    ) -> String {
        guard dispatchResults.isEmpty == false else {
            return capturedFamilies.isEmpty
                ? "notAttempted: no executed listener capture was available."
                : "notDelivered: captured listeners existed but no synthetic dispatch result was recorded."
        }
        let delivered = dispatchResults.filter {
            $0.resultKind == .delivered
        }.count
        var summary = "attempted: \(dispatchResults.count) synthetic dispatch(es), \(delivered) delivered."
        if runtimePortSmoke.attempted {
            summary += runtimePortSmoke.portMessageDelivered
                && runtimePortSmoke.portDisconnected
                && runtimePortSmoke.keepaliveReleased
                ? " Runtime Port smoke passed."
                : " Runtime Port smoke did not fully pass."
        }
        let gaps = dispatchResults
            .filter { $0.resultKind != .delivered }
            .map { result -> String in
                let classification: String
                switch result.resultKind {
                case .unsupportedListenerMode:
                    classification = "asyncCompletionUnsupported"
                case .sendResponseTimeoutDiagnostic:
                    classification = "sendResponseWaitUnsupported"
                case .listenerError:
                    classification = "listenerError"
                case .promiseRejected:
                    classification = "promiseRejected"
                case .noListener:
                    classification = "noListener"
                case .noReceiver:
                    classification = "noReceiver"
                case .blockedByGate:
                    classification = "blockedByGate"
                case .blockedByPermission:
                    classification = "blockedByPermission"
                case .delivered:
                    classification = "delivered"
                }
                return "\(result.source.rawValue)=\(classification)"
            }
        if gaps.isEmpty == false {
            summary += " Gaps: \(uniqueSortedRealPackages(gaps).joined(separator: ", "))."
        }
        return summary
    }

    private static func serviceWorkerNextBlockerClassification(
        declared: Bool,
        delta:
            ChromeMV3PasswordManagerRealPackageServiceWorkerCaptureDelta,
        dependencyInventory:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory,
        resourceLoadResult: ChromeMV3ServiceWorkerJSResourceLoadRecord?,
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?,
        capturedFamilies: [ChromeMV3ServiceWorkerSyntheticListenerEvent],
        dispatchResults: [ChromeMV3ServiceWorkerJSDispatchRecord],
        runtimePortSmoke:
            ChromeMV3PasswordManagerRealPackageServiceWorkerPortSmoke
    ) -> (
        classification:
            ChromeMV3PasswordManagerRealPackageNextBlockerClassification,
        detail: String
    ) {
        guard declared else {
            return (
                .otherPreciseBlocker,
                "No background.service_worker was declared."
            )
        }
        if let exception = executionStartResult?.exceptionDetails,
           exception.inferredMissingProperty == "crypto.subtle"
                || exception.message.localizedCaseInsensitiveContains(
                    "SubtleCrypto"
                )
                || exception.message.localizedCaseInsensitiveContains(
                    "Subtle crypto"
                )
        {
            return (
                .webCryptoUnsupported,
                "Execution requires WebCrypto/SubtleCrypto beyond the currently enabled local experimental slice: \(exception.message)"
            )
        }
        if serviceWorkerWorkerWindowFailureObserved(
            executionStartResult: executionStartResult
        ) {
            return (
                .workerWindowDOMUnsupported,
                serviceWorkerWorkerWindowFailureClassification(
                    executionStartResult: executionStartResult
                )
            )
        }
        if let fetchRecord =
            executionStartResult?.fetchClassificationRecords.first(where: {
                $0.executionAllowed == false
            })
        {
            let classification:
                ChromeMV3PasswordManagerRealPackageNextBlockerClassification =
                    fetchRecord.networkAccessRequired
                    ? .networkFetchUnsupported
                    : .otherPreciseBlocker
            let resourceScope =
                fetchRecord.networkAccessRequired
                ? "network"
                : "extension-local generated-bundle"
            return (
                classification,
                "Execution reached \(resourceScope) fetch classified as \(fetchRecord.requestKind.rawValue) at \(fetchRecord.sourcePath ?? "unknown"):\(fetchRecord.line ?? 0); networkRequired=\(fetchRecord.networkAccessRequired), extensionLocal=\(fetchRecord.extensionLocalResource), executionAllowed=\(fetchRecord.executionAllowed), blocker=\(fetchRecord.blocker)."
            )
        }
        if let fetchCall =
            executionStartResult?.blockedUnsupportedCalls.first(where: {
                $0.hasPrefix("globalThis.fetch")
            })
        {
            return (
                .networkFetchUnsupported,
                "Execution reached \(fetchCall); fetch remains classified but disabled."
            )
        }
        if dependencyInventory.serviceWorkerType == "module" {
            return (
                .moduleWorkerUnsupported,
                "Manifest declares a module service worker and module worker execution remains intentionally unsupported."
            )
        }
        if resourceLoadResult?.blockers.contains(.moduleWorkerUnsupported)
            == true
        {
            return (
                .moduleWorkerUnsupported,
                "Manifest declares a module service worker and module worker execution remains intentionally unsupported."
            )
        }
        if resourceLoadResult?.dynamicImportBlockers.contains(
            .dynamicImportArgumentNonString
        ) == true {
            return (
                .dynamicImportComputedUnsupported,
                "Dynamic import uses a non-string-literal/computed specifier, so the safe rewrite prototype cannot run."
            )
        }
        let dynamicNamespaceBlockers:
            Set<ChromeMV3ServiceWorkerJSDynamicImportBlocker> = [
                .dynamicImportModuleNamespaceUnsupported,
                .importedModuleSyntaxUnsupported,
            ]
        if let dynamicBlockers = resourceLoadResult?.dynamicImportBlockers,
           dynamicBlockers.contains(where: dynamicNamespaceBlockers.contains)
        {
            return (
                .dynamicImportNamespaceUnsupported,
                "Dynamic import dependency syntax or module namespace behavior requires module/export support that is still blocked."
            )
        }
        if resourceLoadResult?.dynamicImportBlockers.contains(
            .dynamicImportPromiseDrainUnavailable
        ) == true {
            return (
                .promiseCompletionUnsupported,
                "Dynamic import Promise completion cannot be drained deterministically on the public JavaScriptCore surface."
            )
        }
        let importDependencyBlockers:
            Set<ChromeMV3ServiceWorkerJSImportScriptsBlocker> = [
                .generatedBundleRecordMissing,
                .generatedBundleRootMissing,
                .importedScriptMissing,
                .importedScriptNotCopiedFromGeneratedBundleRecord,
            ]
        if let importBlockers = resourceLoadResult?.importScriptsBlockers,
           importBlockers.contains(where: importDependencyBlockers.contains)
        {
            return (
                .importScriptsDependencyMissing,
                "importScripts dependency resolution failed before all generated-bundle-contained imports could execute."
            )
        }
        if resourceLoadResult?.dynamicImportRewriteExperimentApplied == true,
           delta.staticListenerFamilies.isEmpty == false,
           capturedFamilies.isEmpty
        {
            return (
                .dynamicImportRewriteSucceededButListenerMissing,
                "Dynamic-import rewrite evaluated, but static listener families were still not captured during execution."
            )
        }
        if let unsupportedCall =
            executionStartResult?.blockedUnsupportedCalls.first,
            unsupportedCall.hasPrefix("chrome.")
                || unsupportedCall.hasPrefix("browser.")
        {
            return (
                .unsupportedChromeAPI,
                "Execution reached unsupported extension API call \(unsupportedCall)."
            )
        }
        if let cryptoBlocker =
            executionStartResult?.cryptoOperationRecords.first(where: {
                $0.status == "blocked"
            })
        {
            let algorithm = cryptoBlocker.algorithm.map {
                " algorithm \($0)"
            } ?? ""
            return (
                .webCryptoUnsupported,
                "Execution reached unsupported WebCrypto operation \(cryptoBlocker.operation)\(algorithm): \(cryptoBlocker.blocker ?? "blocked")."
            )
        }
        if capturedFamilies.isEmpty == false {
            if let dispatchBlocker = serviceWorkerDispatchBlocker(
                dispatchResults: dispatchResults,
                runtimePortSmoke: runtimePortSmoke
            ) {
                return dispatchBlocker
            }
            return (
                .dispatchDelivered,
                "Captured listener families dispatched successfully where a safe synthetic smoke exists: \(capturedFamilies.map(\.rawValue).joined(separator: ", "))."
            )
        }
        if let message = executionStartResult?.lastErrorMessage,
           message.isEmpty == false
        {
            return (.otherPreciseBlocker, message)
        }
        if let blocker = resourceLoadResult?.blockers.first {
            return (
                .otherPreciseBlocker,
                "Resource blocker: \(blocker.rawValue)."
            )
        }
        return (
            .otherPreciseBlocker,
            "No listener was captured and no more precise blocker was available."
        )
    }

    private static func serviceWorkerDispatchBlocker(
        dispatchResults: [ChromeMV3ServiceWorkerJSDispatchRecord],
        runtimePortSmoke:
            ChromeMV3PasswordManagerRealPackageServiceWorkerPortSmoke
    ) -> (
        classification:
            ChromeMV3PasswordManagerRealPackageNextBlockerClassification,
        detail: String
    )? {
        guard dispatchResults.isEmpty == false else {
            return (
                .unknownDispatchFailure,
                "Listener capture succeeded, but no safe synthetic dispatch result was recorded."
            )
        }
        if runtimePortSmoke.attempted,
           runtimePortSmoke.portMessageDelivered == false
                || runtimePortSmoke.portDisconnected == false
                || runtimePortSmoke.keepaliveReleased == false
        {
            return (
                .portShapeUnsupported,
                "runtime.onConnect delivered a Port, but the Port smoke did not fully pass: messageDelivered=\(runtimePortSmoke.portMessageDelivered), disconnected=\(runtimePortSmoke.portDisconnected), keepaliveReleased=\(runtimePortSmoke.keepaliveReleased)."
            )
        }
        guard let failed = dispatchResults.first(where: {
            $0.resultKind != .delivered
        }) else { return nil }
        let detail = [
            "Dispatch source \(failed.source.rawValue) for \(failed.event.rawValue) failed with \(failed.resultKind.rawValue).",
            failed.lastErrorMessage,
            failed.diagnostics.first,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        switch failed.resultKind {
        case .blockedByGate:
            return (.blockedByGate, detail)
        case .blockedByPermission:
            return (.unsupportedEventFamily, detail)
        case .listenerError:
            return (.listenerThrew, detail)
        case .noListener, .noReceiver:
            return (.noMatchingListener, detail)
        case .promiseRejected:
            return (.listenerInvocationFailed, detail)
        case .sendResponseTimeoutDiagnostic:
            return (.noResponse, detail)
        case .unsupportedListenerMode:
            return (.asyncCompletionUnsupported, detail)
        case .delivered:
            return nil
        }
    }

    private static func serviceWorkerNextRecommendedFix(
        declared: Bool,
        delta:
            ChromeMV3PasswordManagerRealPackageServiceWorkerCaptureDelta,
        resourceLoadResult: ChromeMV3ServiceWorkerJSResourceLoadRecord?,
        dependencyInventory:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory,
        executionStartResult: ChromeMV3ServiceWorkerJSExecutionStartRecord?
    ) -> String {
        guard declared else {
            return "No background.service_worker was declared."
        }
        if executionStartResult?.cryptoOperationRecords.contains(where: {
            $0.status == "blocked"
        }) == true {
            return "Implement only the next audited WebCrypto method or algorithm behind the local experimental MV3 gate; keep unsupported key, signing, derivation, encryption, and wrapping calls rejected precisely."
        }
        if let exception = executionStartResult?.exceptionDetails,
           exception.inferredMissingProperty == "crypto.subtle"
                || exception.message.localizedCaseInsensitiveContains(
                    "SubtleCrypto"
                )
                || exception.message.localizedCaseInsensitiveContains(
                    "Subtle crypto"
                )
        {
            return "Expose only the safely implemented WebCrypto/SubtleCrypto surface needed for the next local experimental service-worker trial; keep stable runtime default-off."
        }
        if serviceWorkerWorkerWindowFailureObserved(
            executionStartResult: executionStartResult
        ) {
            return "Classify the worker window/global dependency narrowly and prefer WorkerGlobalScope-compatible shims only; do not expose DOM Window or document."
        }
        if let fetchRecord =
            executionStartResult?.fetchClassificationRecords.first(where: {
                $0.executionAllowed == false
            })
        {
            if fetchRecord.networkAccessRequired {
                return "Keep remote fetch blocked; only consider network access as a separate audited service-worker slice with explicit credentials and cache policy."
            }
            return "Treat the blocked extension-local fetch as a generated-bundle resource issue: add the copied resource if appropriate, keep traversal/symlink/file/data/blob guards, and keep stable runtime default-off."
        }
        if executionStartResult?.blockedUnsupportedCalls.contains(
                where: { $0.hasPrefix("globalThis.fetch") }
            ) == true
        {
            return "Inspect the blocked fetch call and preserve the generated-bundle-only/no-network fetch policy before adding another harness slice."
        }
        if dependencyInventory.serviceWorkerType == "module" {
            return dependencyInventory.nextRecommendedImplementationPath
        }
        if let unsupportedCall =
            executionStartResult?.blockedUnsupportedCalls.first,
           unsupportedCall.hasPrefix("chrome.")
                || unsupportedCall.hasPrefix("browser.")
        {
            return "Inspect \(unsupportedCall) as the next bounded local-experimental Chrome API shape; add only general deterministic semantics if independently justified, and keep stable runtime default-off."
        }
        if dependencyInventory.dynamicImportExpressions.contains(where: {
            [.identifier, .memberExpression, .callExpression,
             .conditionalExpression, .concatenation, .unknownComputed]
                .contains($0.shape)
        }) {
            return dependencyInventory.nextRecommendedImplementationPath
        }
        if dependencyInventory.asyncAPIInventory.count(.setTimeout) > 0
            || dependencyInventory.asyncAPIInventory.count(.setInterval) > 0
        {
            return dependencyInventory.nextRecommendedImplementationPath
        }
        if let blocker = resourceLoadResult?.blockers.first {
            return "Resolve scoped service-worker resource blocker \(blocker.rawValue) without enabling stable runtime load."
        }
        if let blocker = resourceLoadResult?.dynamicImportBlockers.first {
            return "Resolve scoped dynamic import blocker \(blocker.rawValue) while keeping imports generated-bundle-contained and default-off."
        }
        if let blocker = resourceLoadResult?.importScriptsBlockers.first {
            return "Resolve scoped importScripts blocker \(blocker.rawValue) while keeping imports generated-bundle-contained."
        }
        switch delta.status {
        case .executionFailed:
            return "Add the smallest conservative shim diagnostic needed to explain the isolated JavaScriptCore evaluation failure; keep the stable runtime default-off."
        case .executionCaptured:
            return "Use the captured listener and dispatch deltas to prioritize the next bounded fixture-only shim gap; keep the stable runtime default-off."
        case .executionBlocked, .staticOnly, .noListener, .unknown:
            return "Keep service-worker routing behind the local experimental/default-off gate and reduce the next precise blocker without enabling stable runtime load."
        }
    }

    private static let serviceWorkerReportSources:
        [ChromeMV3ServiceWorkerEventSource] = [
            .popupOptionsRuntimeMessage,
            .popupOptionsRuntimeConnect,
            .contentScriptRuntimeMessage,
            .contentScriptRuntimeConnect,
            .storageChanged,
            .permissionsAdded,
            .permissionsRemoved,
            .nativeMessagingConnect,
            .nativeMessagingMessage,
            .contextMenuClicked,
            .alarmTriggered,
            .webNavigationSyntheticEvent,
        ]

    private static func serviceWorkerStatus(
        _ source: ChromeMV3ServiceWorkerEventSource,
        from statuses:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerEventStatus]
    ) -> ChromeMV3PasswordManagerCompatibilityStatus {
        statuses.first { $0.source == source }?.status ?? .notRequired
    }

    private static func noListenerKind(
        _ source: ChromeMV3ServiceWorkerEventSource
    ) -> ChromeMV3ServiceWorkerEventRoutingResultKind {
        switch source.listenerEvent {
        case .runtimeOnMessage, .runtimeOnConnect:
            return .noReceiver
        default:
            return .noListener
        }
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
        configuration:
            ChromeMV3PasswordManagerRealPackageTargetConfiguration,
        selected: SelectedPackage,
        trial: PackageTrialResult,
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction,
        nativeRequired: Bool,
        nativeOptional: Bool,
        profileID: String,
        trustedHostApprovalRecords:
            [ChromeMV3NativeTrustedHostApprovalRecord],
        fileManager: FileManager
    ) -> ChromeMV3PasswordManagerRealPackageNativeMessagingSmoke {
        let requiresNative = nativeRequired || nativeOptional
        let rootState = nativeFixtureRootState(
            rootPath: target.trustedFixtureHostRootPath,
            requiresNative: requiresNative,
            fileManager: fileManager
        )
        let fixtureCandidates = nativeFixtureManifestCandidates(
            rootPath: target.trustedFixtureHostRootPath,
            rootState: rootState,
            fileManager: fileManager
        )
        let candidateHostNames = fixtureCandidates.compactMap(\.hostName)
        let configuredAndObservedHostNames =
            uniqueSortedRealPackages(
                target.configuredNativeHostNames
                    + configuration.nativeHostNames
                    + selected.configuredNativeHostNames
                    + extraction.detectedNativeHostNames
            )
        let hostNames =
            configuredAndObservedHostNames.isEmpty && rootState == .configured
                ? uniqueSortedRealPackages(candidateHostNames)
                : configuredAndObservedHostNames
        let detectedExtensionID = trial.lifecycleResult?.record?.extensionID
        let extensionID =
            target.expectedExtensionID
                ?? detectedExtensionID
                ?? "password-manager-real-package-extension"
        let expectedAllowedOrigin =
            ChromeMV3NativeMessagingAllowedOrigin.originString(
                extensionID: extensionID
            )
        let permissionDeclared =
            extraction.permissions.contains("nativeMessaging")
                || extraction.optionalPermissions.contains("nativeMessaging")
        let permissionState = nativeMessagingPermissionState(
            extraction: extraction
        )
        let confidence = nativeRequirementConfidence(
            requiresNative: requiresNative,
            observedHostNames: extraction.detectedNativeHostNames,
            configuredHostNames:
                target.configuredNativeHostNames
                    + selected.configuredNativeHostNames,
            fixtureHostNames: candidateHostNames,
            permissionDeclared: permissionDeclared
        )
        let trustedRoot = target.trustedFixtureHostRootPath
        let noTrusted = requiresNative && trustedRoot == nil
        let fixturePack =
            requiresNative
                ? ChromeMV3NativeMessagingFixturePackBuilder
                    .describeExistingPack(
                        targetID: target.targetID,
                        fixtureRootPath: trustedRoot,
                        hostNames: hostNames,
                        extensionID: extensionID,
                        fileManager: fileManager
                    )
                : nil
        let readiness: [ChromeMV3PasswordManagerRealPackageNativeHostReadiness]
        if requiresNative == false {
            readiness = []
        } else if hostNames.isEmpty {
            readiness = [
                hostNameNotObservableReadiness(
                    target: target,
                    extensionID: extensionID,
                    expectedAllowedOrigin: expectedAllowedOrigin,
                    permissionDeclared: permissionDeclared,
                    permissionState: permissionState,
                    confidence: confidence,
                    rootState: rootState,
                    fixtureCandidates: fixtureCandidates,
                    fixturePack: fixturePack
                ),
            ]
        } else {
            readiness = hostNames.map { hostName in
                nativeHostReadiness(
                    hostName: hostName,
                    target: target,
                    extensionID: extensionID,
                    profileID: profileID,
                    expectedAllowedOrigin: expectedAllowedOrigin,
                    explicitTestAliasUsed: target.expectedExtensionID != nil,
                    nativeRequired: nativeRequired,
                    nativeOptional: nativeOptional,
                    detectionSources:
                        nativeHostDetectionSources(
                            hostName: hostName,
                            target: target,
                            selected: selected,
                            extraction: extraction,
                            fixtureCandidates: fixtureCandidates
                        ),
                    confidence: confidence,
                    permissionDeclared: permissionDeclared,
                    permissionState: permissionState,
                    rootState: rootState,
                    fixtureCandidates: fixtureCandidates,
                    fixturePackRecord:
                        fixturePack?.record(hostName: hostName),
                    trustedHostApprovalRecords:
                        trustedHostApprovalRecords,
                    fileManager: fileManager
                )
            }
        }
        let exchangeAttempted = readiness.contains {
            $0.exchangeResult.attempted
        }
        let exchangeSucceeded = readiness.contains {
            $0.exchangeResult.state == .succeeded
        }
        let exactBlocker =
            readiness.first {
                $0.blockerState != .approvedTrustedFixtureHostWorks
                    && $0.blockerState != .notRequired
            }?.blockerState
                ?? (requiresNative ? nil : .notRequired)
        let remediation =
            readiness.first {
                $0.blockerState != .approvedTrustedFixtureHostWorks
                    && $0.blockerState != .notRequired
            }?.remediation
        let fixtureManifestPaths =
            uniqueSortedRealPackages(fixtureCandidates.map(\.manifestPath))
        let fixtureExecutablePaths =
            uniqueSortedRealPackages(
                fixtureCandidates.compactMap(\.executablePath)
            )
        let sendReadiness =
            aggregateReadiness(
                readiness.map(\.sendNativeMessageReadiness),
                requiresNative: requiresNative
            )
        let connectReadiness =
            aggregateReadiness(
                readiness.map(\.connectNativeReadiness),
                requiresNative: requiresNative
            )

        return ChromeMV3PasswordManagerRealPackageNativeMessagingSmoke(
            fixturePack: fixturePack,
            required: nativeRequired,
            optional: nativeOptional,
            detectedExtensionID: detectedExtensionID,
            generatedOrTestExtensionID: extensionID,
            expectedAllowedOrigin: expectedAllowedOrigin,
            explicitTestAliasUsed: target.expectedExtensionID != nil,
            nativeMessagingPermissionDeclared: permissionDeclared,
            nativeMessagingPermissionState: permissionState,
            requirementDetectionConfidence: confidence,
            hostNames: hostNames,
            hostNamesNotObservable: requiresNative && hostNames.isEmpty,
            trustedFixtureHostRootPath: trustedRoot,
            fixtureRootState: rootState,
            fixtureManifestPathCandidates: fixtureManifestPaths,
            fixtureExecutablePathCandidates: fixtureExecutablePaths,
            hostReadiness: readiness.sorted {
                ($0.hostName ?? "") < ($1.hostName ?? "")
            },
            noTrustedHostConfigured: noTrusted,
            arbitraryHostDiscoveryBlocked: true,
            realVendorHostLaunchBlocked: true,
            fixtureExchangeAttempted: exchangeAttempted,
            fixtureExchangeSucceeded: exchangeSucceeded,
            sendNativeMessageReadiness: sendReadiness,
            connectNativeReadiness: connectReadiness,
            exactBlocker: exactBlocker,
            remediation: remediation,
            previousTrialDelta:
                requiresNative
                    ? "Previous real-package trial reported noTrustedHostConfigured; current blocker is \(exactBlocker?.rawValue ?? "none")."
                    : "Previous real-package trial did not require native messaging for this target.",
            diagnostics:
                uniqueSortedRealPackages(
                    readiness.flatMap(\.diagnostics)
                        + [
                            requiresNative
                                ? "Native messaging readiness was evaluated against explicit fixture roots only."
                                : "nativeMessaging is not required by this manifest/resource scan.",
                            noTrusted
                                ? "No trusted fixture native-host root is configured for this real package target."
                                : "Trusted fixture native-host root state is \(rootState.rawValue).",
                            "Arbitrary native host discovery is blocked.",
                            "Real vendor native host discovery is blocked.",
                            "Real vendor native host launch is blocked unless the executable is deliberately copied into an explicit reviewed fixture root.",
                            "No real credentials, accounts, vaults, tokens, or remote native hosts were used.",
                        ]
                )
        )
    }

    private static func nativeFixtureRootState(
        rootPath: String?,
        requiresNative: Bool,
        fileManager: FileManager
    ) -> ChromeMV3PasswordManagerRealPackageNativeHostFixtureRootState {
        guard requiresNative else { return .notRequired }
        guard let rootPath else { return .notConfigured }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: rootPath,
            isDirectory: &isDirectory
        ) else { return .missingFixtureRoot }
        return isDirectory.boolValue ? .configured : .invalidFixtureRoot
    }

    private static func nativeFixtureManifestCandidates(
        rootPath: String?,
        rootState:
            ChromeMV3PasswordManagerRealPackageNativeHostFixtureRootState,
        fileManager: FileManager
    ) -> [NativeFixtureManifestCandidate] {
        guard rootState == .configured, let rootPath else { return [] }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
        let children =
            (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ],
                options: [.skipsPackageDescendants]
            )) ?? []
        return children.compactMap { url in
            guard url.pathExtension.lowercased() == "json",
                  isRegularFile(url),
                  isSymlink(url) == false,
                  safeURLInsideRoot(url.resolvingSymlinksInPath(), root: root)
            else { return nil }
            let basename = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url) else {
                return NativeFixtureManifestCandidate(
                    hostName: basename,
                    manifestPath: url.path,
                    executablePath: nil,
                    manifest: nil,
                    diagnostics: [
                        "Fixture host manifest \(url.path) could not be read.",
                    ]
                )
            }
            let source = ChromeMV3NativeHostManifestSourceLocation
                .explicitTestRoot(rootPath: root.path, hostName: basename)
            let manifest = ChromeMV3NativeHostManifestDecoder.decode(
                data: data,
                sourceLocation: source,
                requestedHostName: basename
            )
            return NativeFixtureManifestCandidate(
                hostName:
                    (manifest.name?.isEmpty == false)
                        ? manifest.name : basename,
                manifestPath: url.path,
                executablePath: manifest.path,
                manifest: manifest,
                diagnostics: manifest.diagnostics.map(\.message)
            )
        }.sorted { $0.manifestPath < $1.manifestPath }
    }

    private static func nativeMessagingPermissionState(
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction
    ) -> ChromeMV3NativeMessagingPermissionState {
        if extraction.permissions.contains("nativeMessaging") {
            return .grantedByManifest
        }
        if extraction.optionalPermissions.contains("nativeMessaging") {
            return .missing
        }
        return .missing
    }

    private static func nativeRequirementConfidence(
        requiresNative: Bool,
        observedHostNames: [String],
        configuredHostNames: [String],
        fixtureHostNames: [String],
        permissionDeclared: Bool
    ) -> ChromeMV3PasswordManagerRealPackageNativeHostRequirementDetectionConfidence {
        guard requiresNative else { return .notRequired }
        if observedHostNames.isEmpty == false { return .observedRuntimeCall }
        if configuredHostNames.isEmpty == false { return .configuredTarget }
        if fixtureHostNames.isEmpty == false { return .fixtureMetadata }
        if permissionDeclared { return .manifestPermission }
        return .hostNameNotObservable
    }

    private static func nativeHostDetectionSources(
        hostName: String,
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        selected: SelectedPackage,
        extraction:
            ChromeMV3PasswordManagerRealPackageManifestRequirementExtraction,
        fixtureCandidates: [NativeFixtureManifestCandidate]
    ) -> [String] {
        uniqueSortedRealPackages(
            [
                target.configuredNativeHostNames.contains(hostName)
                    ? "configuredTarget" : nil,
                selected.configuredNativeHostNames.contains(hostName)
                    ? "selectedFixtureMetadata" : nil,
                extraction.detectedNativeHostNames.contains(hostName)
                    ? "observedRuntimeCall" : nil,
                fixtureCandidates.contains { $0.hostName == hostName }
                    ? "fixtureMetadata" : nil,
            ].compactMap { $0 }
        )
    }

    private static func hostNameNotObservableReadiness(
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        extensionID: String,
        expectedAllowedOrigin: String,
        permissionDeclared: Bool,
        permissionState: ChromeMV3NativeMessagingPermissionState,
        confidence:
            ChromeMV3PasswordManagerRealPackageNativeHostRequirementDetectionConfidence,
        rootState:
            ChromeMV3PasswordManagerRealPackageNativeHostFixtureRootState,
        fixtureCandidates: [NativeFixtureManifestCandidate],
        fixturePack: ChromeMV3NativeMessagingFixturePack?
    ) -> ChromeMV3PasswordManagerRealPackageNativeHostReadiness {
        let blocker:
            ChromeMV3PasswordManagerRealPackageNativeHostReadinessState =
                rootState == .notConfigured || rootState == .missingFixtureRoot
                    ? .hostRequiredButNotConfigured
                    : .hostNameNotObservable
        let remediation =
            rootState == .notConfigured
                ? "Configure an explicit reviewed fixture root for \(target.displayName) and provide a host manifest whose name is observable from package calls or fixture metadata."
                : "Record the native host name from reviewed local package diagnostics or place a matching manifest in the explicit fixture root."
        return ChromeMV3PasswordManagerRealPackageNativeHostReadiness(
            fixturePackID: fixturePack?.packID,
            fixturePackGeneratedState:
                fixturePack?.generatedState ?? .notConfigured,
            fixturePackValidatedState:
                fixturePack?.validatedState ?? .notEvaluated,
            hostNameSource: "notObservable",
            hostName: nil,
            required: true,
            optional: false,
            detectionSources: [],
            detectionConfidence: confidence,
            nativeMessagingPermissionDeclared: permissionDeclared,
            nativeMessagingPermissionState: permissionState,
            fixtureRootPath: target.trustedFixtureHostRootPath,
            fixtureRootState: rootState,
            fixtureManifestPathCandidates:
                uniqueSortedRealPackages(fixtureCandidates.map(\.manifestPath)),
            fixtureExecutablePathCandidates:
                uniqueSortedRealPackages(
                    fixtureCandidates.compactMap(\.executablePath)
                ),
            lookupStatus: nil,
            manifestState: .hostNameNotObservable,
            manifestValidation: nil,
            manifestPath: nil,
            executablePath: nil,
            resolvedExecutablePath: nil,
            executableInsideFixtureRoot: false,
            executableIsExecutable: false,
            allowedOrigins: [],
            expectedAllowedOrigin: expectedAllowedOrigin,
            allowedOriginsSource: "notEvaluated",
            explicitTestAliasUsed: false,
            allowedOriginsState: .notEvaluated,
            trustedHostApprovalState: .unknown,
            trustedHostApprovedForDeveloperPreview: false,
            sendNativeMessageReadiness: "blocked:\(blocker.rawValue)",
            connectNativeReadiness: "blocked:\(blocker.rawValue)",
            exchangeResult: .notAttempted(diagnostics: [
                "Fixture exchange was not attempted because no native host name was observable.",
            ]),
            blockerState: blocker,
            remediation: remediation,
            diagnostics: [
                "nativeMessaging was detected, but no concrete native host name was found in package calls or fixture metadata.",
                "Real vendor host discovery remains blocked.",
            ]
        )
    }

    private static func nativeHostReadiness(
        hostName: String,
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        extensionID: String,
        profileID: String,
        expectedAllowedOrigin: String,
        explicitTestAliasUsed: Bool,
        nativeRequired: Bool,
        nativeOptional: Bool,
        detectionSources: [String],
        confidence:
            ChromeMV3PasswordManagerRealPackageNativeHostRequirementDetectionConfidence,
        permissionDeclared: Bool,
        permissionState: ChromeMV3NativeMessagingPermissionState,
        rootState:
            ChromeMV3PasswordManagerRealPackageNativeHostFixtureRootState,
        fixtureCandidates: [NativeFixtureManifestCandidate],
        fixturePackRecord: ChromeMV3NativeMessagingFixturePackRecord?,
        trustedHostApprovalRecords:
            [ChromeMV3NativeTrustedHostApprovalRecord],
        fileManager: FileManager
    ) -> ChromeMV3PasswordManagerRealPackageNativeHostReadiness {
        let fixtureManifestPaths =
            uniqueSortedRealPackages(fixtureCandidates.map(\.manifestPath))
        let fixtureExecutablePaths =
            uniqueSortedRealPackages(
                fixtureCandidates.compactMap(\.executablePath)
            )
        let lookupPolicy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: target.trustedFixtureHostRootPath,
            extensionModuleEnabled: true
        )
        let lookup = lookupPolicy.lookupHost(
            named: hostName,
            fileManager: fileManager
        )
        let manifest = lookup.manifest
        let expectedOriginID =
            ChromeMV3NativeMessagingAllowedOrigin
            .nativeMessagingOriginExtensionID(for: extensionID)
        let allowedOriginIDs =
            manifest?.allowedOrigins.compactMap(\.extensionID) ?? []
        let allowedOriginsState:
            ChromeMV3PasswordManagerRealPackageAllowedOriginsState
        if manifest == nil {
            allowedOriginsState = .notEvaluated
        } else if manifest?.isValid != true {
            allowedOriginsState = .invalidManifest
        } else if allowedOriginIDs.contains(expectedOriginID) {
            allowedOriginsState = .compatible
        } else {
            allowedOriginsState = .mismatch
        }
        let resolvedExecutable =
            manifest?.path.map {
                URL(fileURLWithPath: $0)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
            }
        let resolvedRoot =
            target.trustedFixtureHostRootPath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
            }
        let executableInsideRoot: Bool
        if let resolvedExecutable, let resolvedRoot {
            executableInsideRoot =
                resolvedExecutable.path == resolvedRoot.path
                    || resolvedExecutable.path
                    .hasPrefix(resolvedRoot.path + "/")
        } else {
            executableInsideRoot = false
        }
        let executableIsExecutable =
            resolvedExecutable.map {
                fileManager.isExecutableFile(atPath: $0.path)
            } ?? false
        let trustedRecord = matchingTrustedHostRecord(
            records: trustedHostApprovalRecords,
            hostName: hostName,
            extensionID: extensionID,
            profileID: profileID,
            manifestSHA256: manifest?.canonicalJSONSHA256
        )
        let productPolicy = ChromeMV3NativeMessagingProductPolicy
            .blockedRuntimeDefault
        let oneShot = ChromeMV3NativeMessagingPreflightEvaluator.evaluate(
            input: ChromeMV3NativeMessagingPreflightInput(
                extensionID: extensionID,
                profileID: profileID,
                hostName: hostName,
                operationKind: .oneShotNativeMessage,
                sourceContext: .extensionPage,
                permissionState: permissionState,
                productPolicy: productPolicy,
                trustedHostPolicyRecord: trustedRecord
            ),
            lookupPolicy: lookupPolicy,
            lookupResult: lookup,
            fileManager: fileManager
        )
        let long = ChromeMV3NativeMessagingPreflightEvaluator.evaluate(
            input: ChromeMV3NativeMessagingPreflightInput(
                extensionID: extensionID,
                profileID: profileID,
                hostName: hostName,
                operationKind: .longLivedNativePort,
                sourceContext: .extensionPage,
                permissionState: permissionState,
                productPolicy: productPolicy,
                trustedHostPolicyRecord: trustedRecord
            ),
            lookupPolicy: lookupPolicy,
            lookupResult: lookup,
            fileManager: fileManager
        )
        let manifestState = nativeManifestState(
            lookup: lookup,
            requestedHostName: hostName
        )
        let preExchangeBlocker = nativeBlockerState(
            rootState: rootState,
            lookup: lookup,
            manifestState: manifestState,
            requestedHostName: hostName,
            permissionState: permissionState,
            allowedOriginsState: allowedOriginsState,
            trustedRecord: trustedRecord,
            oneShot: oneShot,
            long: long
        )
        let exchange =
            preExchangeBlocker == .approvedTrustedFixtureHostWorks
                ? runNativeFixtureExchange(
                    hostName: hostName,
                    targetID: target.targetID,
                    extensionID: extensionID,
                    profileID: profileID,
                    fixtureRootPath: target.trustedFixtureHostRootPath,
                    permissionState: permissionState,
                    trustedHostApprovalRecords: trustedHostApprovalRecords
                )
                : .notAttempted(diagnostics: [
                    "Fixture exchange was not attempted because \(preExchangeBlocker.rawValue) blocked launch.",
                ])
        let blocker =
            exchange.attempted && exchange.state != .succeeded
                ? .fixtureExchangeFailed
                : preExchangeBlocker
        return ChromeMV3PasswordManagerRealPackageNativeHostReadiness(
            fixturePackID: fixturePackRecord?.packID,
            fixturePackGeneratedState:
                fixturePackRecord?.generatedState ?? .notGenerated,
            fixturePackValidatedState:
                fixturePackRecord?.validatedState ?? .notEvaluated,
            hostNameSource:
                detectionSources.isEmpty
                    ? "explicitFixtureMetadata"
                    : detectionSources.joined(separator: "+"),
            hostName: hostName,
            required: nativeRequired,
            optional: nativeOptional,
            detectionSources: detectionSources,
            detectionConfidence: confidence,
            nativeMessagingPermissionDeclared: permissionDeclared,
            nativeMessagingPermissionState: permissionState,
            fixtureRootPath: target.trustedFixtureHostRootPath,
            fixtureRootState: rootState,
            fixtureManifestPathCandidates: fixtureManifestPaths,
            fixtureExecutablePathCandidates: fixtureExecutablePaths,
            lookupStatus: lookup.status,
            manifestState: manifestState,
            manifestValidation: manifest?.validationSummary,
            manifestPath: manifest?.sourceLocation.manifestPath,
            executablePath: manifest?.path,
            resolvedExecutablePath: resolvedExecutable?.path,
            executableInsideFixtureRoot: executableInsideRoot,
            executableIsExecutable: executableIsExecutable,
            allowedOrigins:
                manifest?.allowedOrigins.map(\.rawValue).sorted() ?? [],
            expectedAllowedOrigin: expectedAllowedOrigin,
            allowedOriginsSource:
                manifest == nil
                    ? "notEvaluated"
                    : "fixtureManifest.allowed_origins",
            explicitTestAliasUsed: explicitTestAliasUsed,
            allowedOriginsState: allowedOriginsState,
            trustedHostApprovalState:
                trustedRecord?.trustState ?? .unknown,
            trustedHostApprovedForDeveloperPreview:
                trustedRecord?.trustedForDeveloperPreview ?? false,
            sendNativeMessageReadiness:
                oneShot.canSendNativeMessageNow
                    ? "ready" : "blocked:\(blocker.rawValue)",
            connectNativeReadiness:
                long.canConnectNativeNow
                    ? "ready" : "blocked:\(blocker.rawValue)",
            exchangeResult: exchange,
            blockerState: blocker,
            remediation:
                nativeRemediation(
                    blocker: blocker,
                    target: target,
                    hostName: hostName,
                    expectedAllowedOrigin: expectedAllowedOrigin
                ),
            diagnostics:
                uniqueSortedRealPackages(
                    lookup.diagnostics
                        + oneShot.diagnostics
                        + long.diagnostics
                        + exchange.diagnostics
                        + (trustedRecord?.diagnostics ?? [
                            "No trusted fixture host approval record was supplied for this target/profile/host.",
                        ])
                        + [
                            "Host readiness was evaluated for \(hostName) inside explicit fixture roots only.",
                            "Allowed origins expected \(expectedAllowedOrigin); state \(allowedOriginsState.rawValue).",
                            "Real vendor host discovery remains blocked.",
                            "Real vendor host launch remains blocked unless the executable is fixture-configured and approved.",
                        ]
                )
        )
    }

    private static func nativeManifestState(
        lookup: ChromeMV3NativeHostLookupResult,
        requestedHostName: String
    ) -> ChromeMV3PasswordManagerRealPackageNativeHostManifestState {
        switch lookup.status {
        case .found:
            guard lookup.manifest?.name == requestedHostName else {
                return .invalidManifest
            }
            return .valid
        case .invalidHostName:
            return .invalidHostName
        case .malformedManifest:
            return .invalidManifest
        case .missing:
            return .missing
        case .disabledModule, .unsupported:
            return .unsupported
        }
    }

    private static func nativeBlockerState(
        rootState:
            ChromeMV3PasswordManagerRealPackageNativeHostFixtureRootState,
        lookup: ChromeMV3NativeHostLookupResult,
        manifestState:
            ChromeMV3PasswordManagerRealPackageNativeHostManifestState,
        requestedHostName: String,
        permissionState: ChromeMV3NativeMessagingPermissionState,
        allowedOriginsState:
            ChromeMV3PasswordManagerRealPackageAllowedOriginsState,
        trustedRecord: ChromeMV3NativeTrustedHostApprovalRecord?,
        oneShot: ChromeMV3NativeMessagingOperationPreflight,
        long: ChromeMV3NativeMessagingOperationPreflight
    ) -> ChromeMV3PasswordManagerRealPackageNativeHostReadinessState {
        if rootState == .notConfigured || rootState == .missingFixtureRoot
            || rootState == .invalidFixtureRoot
        {
            return .hostRequiredButNotConfigured
        }
        if lookup.status == .missing {
            return .hostRequiredButNotConfigured
        }
        if manifestState != .valid || lookup.manifest?.name != requestedHostName {
            return .hostManifestConfiguredButInvalid
        }
        if permissionState.hasPermission == false {
            return .permissionMissing
        }
        if allowedOriginsState != .compatible {
            return .allowedOriginsMismatch
        }
        if trustedRecord?.trustState == .userDenied {
            return .userDenied
        }
        if trustedRecord?.trustState == .revoked {
            return .userRevoked
        }
        if oneShot.canSendNativeMessageNow && long.canConnectNativeNow {
            return .approvedTrustedFixtureHostWorks
        }
        return .userApprovalMissing
    }

    private static func matchingTrustedHostRecord(
        records: [ChromeMV3NativeTrustedHostApprovalRecord],
        hostName: String,
        extensionID: String,
        profileID: String,
        manifestSHA256: String?
    ) -> ChromeMV3NativeTrustedHostApprovalRecord? {
        records.last {
            $0.hostName == hostName
                && $0.extensionID == extensionID
                && $0.profileID == profileID
                && ($0.manifestSHA256 == manifestSHA256
                    || $0.trustState == .userDenied
                    || $0.trustState == .revoked)
        }
    }

    private static func runNativeFixtureExchange(
        hostName: String,
        targetID: String,
        extensionID: String,
        profileID: String,
        fixtureRootPath: String?,
        permissionState: ChromeMV3NativeMessagingPermissionState,
        trustedHostApprovalRecords:
            [ChromeMV3NativeTrustedHostApprovalRecord]
    ) -> ChromeMV3PasswordManagerRealPackageNativeFixtureExchangeResult {
        guard let fixtureRootPath else {
            return .notAttempted(diagnostics: [
                "Fixture exchange was not attempted because no fixture root path was configured.",
            ])
        }
        let owner = ChromeMV3NativeMessagingRuntimeOwner(
            configuration: .internalFixture(
                extensionID: extensionID,
                profileID: profileID,
                fixtureHostRootPaths: [fixtureRootPath],
                permissionState: permissionState,
                trustedHostApprovalRecords: trustedHostApprovalRecords
            )
        )
        let payload = ChromeMV3StorageValue.object([
            "fixtureOnly": .bool(true),
            "noRealData": .bool(true),
            "targetID": .string(targetID),
        ])
        let send = owner.sendNativeMessage(
            hostName: hostName,
            message: payload
        )
        let connect = owner.connectNative(hostName: hostName)
        var postSucceeded = false
        var disconnectSucceeded = false
        var postDiagnostics: [String] = []
        var disconnectDiagnostics: [String] = []
        if let portID = connect.portID {
            let post = owner.postMessage(portID: portID, message: payload)
            postSucceeded = post.succeeded
            postDiagnostics = post.diagnostics
            let disconnect = owner.disconnect(
                portID: portID,
                reason: .extensionDisabled
            )
            disconnectSucceeded = disconnect.disconnected
            disconnectDiagnostics = disconnect.diagnostics
        }
        let succeeded =
            send.succeeded
                && connect.succeeded
                && postSucceeded
                && disconnectSucceeded
        let state:
            ChromeMV3PasswordManagerRealPackageNativeHostExchangeState
        if succeeded {
            state = .succeeded
        } else if send.succeeded && connect.succeeded {
            state = .connectNativeSucceeded
        } else if send.succeeded {
            state = .sendNativeMessageSucceeded
        } else {
            state = .failed
        }
        return ChromeMV3PasswordManagerRealPackageNativeFixtureExchangeResult(
            attempted: true,
            state: state,
            sendNativeMessageSucceeded: send.succeeded,
            connectNativeSucceeded: connect.succeeded,
            postMessageSucceeded: postSucceeded,
            disconnectSucceeded: disconnectSucceeded,
            fixtureProcessLaunchAttempted:
                send.lifecycle.processLaunchAttempted
                    || connect.lifecycle.processLaunchAttempted,
            productProcessLaunchAttempted:
                send.lifecycle.processLaunchAllowedInProduct
                    || connect.lifecycle.processLaunchAllowedInProduct,
            sendNativeMessageLastError: send.lastErrorMessage,
            connectNativeLastError: connect.lastErrorMessage,
            diagnostics:
                uniqueSortedRealPackages(
                    send.diagnostics
                        + connect.diagnostics
                        + postDiagnostics
                        + disconnectDiagnostics
                        + [
                            "Fixture exchange used an explicit reviewed fixture root only.",
                            "No product native messaging process launch was allowed.",
                        ]
                )
        )
    }

    private static func nativeRemediation(
        blocker:
            ChromeMV3PasswordManagerRealPackageNativeHostReadinessState,
        target: ChromeMV3PasswordManagerRealPackageTargetDefinition,
        hostName: String,
        expectedAllowedOrigin: String
    ) -> String {
        switch blocker {
        case .notRequired:
            return "No native host fixture is needed for this target."
        case .hostRequiredButNotConfigured:
            return "Create \(target.trustedFixtureHostRootPath ?? "an explicit fixture root")/\(hostName).json with an executable copied into that reviewed fixture root."
        case .hostNameNotObservable:
            return "Record the requested host name from package diagnostics or reviewed fixture metadata."
        case .hostManifestConfiguredButInvalid:
            return "Fix the fixture host manifest name, type, allowed_origins, absolute path, JSON syntax, and executable containment."
        case .allowedOriginsMismatch:
            return "Add \(expectedAllowedOrigin) to allowed_origins in the fixture manifest or configure an explicit test alias."
        case .permissionMissing:
            return "Grant nativeMessaging through the manifest or an explicit optional-permission approval before fixture launch."
        case .userApprovalMissing:
            return "Approve the reviewed fixture host through developer-preview trusted-host policy."
        case .userDenied:
            return "Reset or approve the denied trusted-host record before launch."
        case .userRevoked:
            return "Approve the fixture host again after revocation."
        case .approvedTrustedFixtureHostWorks:
            return "No remediation needed for this fixture host; stable password-manager support remains unavailable."
        case .fixtureExchangeFailed:
            return "Inspect fixture host stdio framing, executable permissions, and teardown diagnostics."
        case .realVendorHostDiscoveryBlocked:
            return "Real vendor host discovery is intentionally blocked; copy a reviewed fixture into the explicit fixture root instead."
        case .realVendorHostLaunchBlockedUnlessFixtureConfigured:
            return "Real vendor host launch remains blocked unless the executable is deliberately fixture-configured and approved."
        }
    }

    private static func aggregateReadiness(
        _ values: [String],
        requiresNative: Bool
    ) -> String {
        guard requiresNative else { return "notRequired" }
        if values.contains("ready") { return "ready" }
        return values.first ?? "blocked:hostNameNotObservable"
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))
            .flatMap(\.isRegularFile) == true
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))
            .flatMap(\.isSymbolicLink) == true
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
                "Checked static content scripts, CSS ordering, MAIN/ISOLATED worlds, all_frames, match_about_blank, and match_origin_as_fallback."
            ),
            source(
                "Chrome scripting API",
                "https://developer.chrome.com/docs/extensions/reference/api/scripting",
                "Checked that scripting.insertCSS is a distinct runtime API and remains blocked outside manifest-declared CSS planning."
            ),
            source(
                "Apple WebKit user content headers",
                "xcode://MacOSX.sdk/System/Library/Frameworks/WebKit.framework/Headers/",
                "Checked WKUserScript, WKContentWorld, WKUserContentController, and the local _WKUserStyleSheet bridge used for scoped stylesheet attachment/removal."
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
                "Checked storage.local and storage.session callback/Promise behavior, missing-key empty objects, defaults-object reads, mutation APIs, and storage.onChanged. The harness keeps values scoped in-memory and reports only redacted key fingerprints."
            ),
            source(
                "Chrome native messaging",
                "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                "Checked nativeMessaging permission, host manifest format, host names, allowed_origins, stdio framing, message size limits, host lifecycle, and process boundary."
            ),
            source(
                "Chrome runtime API",
                "https://developer.chrome.com/docs/extensions/reference/api/runtime",
                "Checked runtime.connectNative, runtime.sendNativeMessage, Port lifecycle, and callback-scoped lastError object behavior; lastError.message is an optional string and Promise APIs do not set lastError."
            ),
            source(
                "MDN Symbol.toPrimitive",
                "https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Symbol/toPrimitive",
                "Checked ordinary object-to-primitive lookup semantics; runtime.lastError.message remains a primitive string rather than a custom coercion object."
            ),
            source(
                "Chrome service-worker lifecycle",
                "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                "Checked MV3 event-driven service-worker lifecycle constraints."
            ),
            source(
                "Chrome service-worker basics",
                "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/basics",
                "Checked background.service_worker, classic versus module workers, importScripts, static module imports, and unsupported dynamic imports. Chrome extension-worker docs do not prescribe a WorkerNavigator.userAgent browser-family token contract, so the harness reports its deterministic Chrome/0 compatibility-family marker explicitly."
            ),
            source(
                "WHATWG WorkerGlobalScope importScripts",
                "https://html.spec.whatwg.org/multipage/workers.html#importing-scripts-and-libraries",
                "Checked synchronous classic-worker importScripts processing; filesystem/generated-bundle containment remains a Sumi diagnostic policy."
            ),
            source(
                "MDN dynamic import",
                "https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/import",
                "Checked import() expression semantics and expression-based specifiers; the trial runner reports computed specifiers as outside the safe rewrite prototype."
            ),
            source(
                "TC39 dynamic import proposal",
                "https://tc39.es/proposal-dynamic-import/",
                "Checked Promise resolution to module namespace semantics; dependency namespace/export behavior remains intentionally unsupported."
            ),
            source(
                "Chrome events in service workers",
                "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/events",
                "Checked synchronous top-level extension event listener registration requirements."
            ),
            source(
                "Chrome alarms API",
                "https://developer.chrome.com/docs/extensions/reference/api/alarms",
                "Checked alarms.onAlarm event routing expectations."
            ),
            source(
                "Chrome contextMenus API",
                "https://developer.chrome.com/docs/extensions/reference/api/contextMenus",
                "Checked contextMenus.onClicked event routing expectations."
            ),
            source(
                "Chrome webNavigation API",
                "https://developer.chrome.com/docs/extensions/reference/api/webNavigation",
                "Checked selected webNavigation event routing expectations."
            ),
            source(
                "Chrome permissions API",
                "https://developer.chrome.com/docs/extensions/reference/api/permissions",
                "Checked permissions.onAdded and permissions.onRemoved event behavior."
            ),
            source(
                "Apple Foundation Process and FileManager",
                "https://developer.apple.com/documentation/foundation",
                "Checked Foundation Process/FileManager API surface relevant to explicit fixture process launch, executable checks, and symlink-resolved containment."
            ),
            source(
                "Apple JSContext SDK header",
                "xcode://MacOSX.sdk/System/Library/Frameworks/JavaScriptCore.framework/Headers/JSContext.h",
                "Checked evaluateScript:withSourceURL:, exception handling, JSVirtualMachine association, and inspectable default-off behavior. The header does not document a Promise job-drain contract, so deferred Promise completion stays diagnostic-only."
            ),
            source(
                "Apple JavaScriptCore C API SDK headers",
                "xcode://MacOSX.sdk/System/Library/Frameworks/JavaScriptCore.framework/Headers/JSBase.h",
                "Checked JSBase, JSObjectRef, JSValue, and JSVirtualMachine headers. They expose script evaluation, syntax checks, source URL metadata, Promise construction helpers, and VM lifecycle, but no public module loader, resolver hook, dynamic import callback, module namespace accessor, or deterministic job-drain API."
            ),
            source(
                "Apple JavaScriptCore binary symbol table",
                "xcode://MacOSX.sdk/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore.tbd",
                "The local SDK binary exports unheadered JSScript and C++ module/import symbols. They are not declared in public SDK headers or Swift overlay and are not used by this trial runner."
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

private struct NativeFixtureManifestCandidate {
    var hostName: String?
    var manifestPath: String
    var executablePath: String?
    var manifest: ChromeMV3NativeHostManifest?
    var diagnostics: [String]
}

enum ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventoryScanner {
    static func scan(
        manifest: ChromeMV3Manifest?,
        packageRootPath: String?,
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord?,
        fileManager: FileManager = .default
    ) -> ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory {
        let serviceWorkerPath = manifest?.background?.serviceWorker
        let serviceWorkerType = manifest?.background?.type ?? "classic"
        let generatedRootPath = generatedBundleRecord?.generatedBundleRootPath
        guard manifest != nil,
              let serviceWorkerPath,
              let packageRootPath
        else {
            return emptyInventory(
                serviceWorkerPath: serviceWorkerPath,
                serviceWorkerType: serviceWorkerType,
                packageRootPath: packageRootPath,
                generatedBundleRootPath: generatedRootPath,
                diagnostics: [
                    "Service-worker dependency inventory was skipped because the manifest, package root, or background.service_worker was unavailable.",
                ]
            )
        }
        let root = URL(fileURLWithPath: packageRootPath, isDirectory: true)
            .standardizedFileURL
        guard fileManager.fileExists(atPath: root.path),
              isSafeRelativeInventoryPath(serviceWorkerPath)
        else {
            return emptyInventory(
                serviceWorkerPath: serviceWorkerPath,
                serviceWorkerType: serviceWorkerType,
                packageRootPath: packageRootPath,
                generatedBundleRootPath: generatedRootPath,
                diagnostics: [
                    "Service-worker dependency inventory could not read a safe package-root-contained worker path.",
                ]
            )
        }
        let workerURL = root.appendingPathComponent(serviceWorkerPath)
            .standardizedFileURL
        guard safeURLInsideRoot(workerURL.resolvingSymlinksInPath(), root: root),
              fileManager.fileExists(atPath: workerURL.path),
              let workerSource = try? String(
                contentsOf: workerURL,
                encoding: .utf8
              )
        else {
            return emptyInventory(
                serviceWorkerPath: serviceWorkerPath,
                serviceWorkerType: serviceWorkerType,
                packageRootPath: packageRootPath,
                generatedBundleRootPath: generatedRootPath,
                diagnostics: [
                    "Service-worker dependency inventory could not load the local worker source as UTF-8.",
                ]
            )
        }

        let generatedRoot = generatedBundleRecord.map {
            URL(fileURLWithPath: $0.generatedBundleRootPath, isDirectory: true)
                .standardizedFileURL
        }
        var scannedSources = [
            InventorySource(
                kind: .mainWorker,
                relativePath: serviceWorkerPath,
                url: workerURL,
                source: workerSource
            ),
        ]
        var candidates:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyCandidate] = []
        var scannedKeys = Set(["mainWorker:\(serviceWorkerPath)"])

        let mainDynamicImports = dynamicImportInventory(
            source: scannedSources[0],
            root: root,
            generatedBundleRecord: generatedBundleRecord,
            generatedRoot: generatedRoot
        )
        let mainImportScripts = importScriptsInventory(
            source: scannedSources[0],
            root: root,
            generatedBundleRecord: generatedBundleRecord,
            generatedRoot: generatedRoot
        )
        let mainStaticImports = staticImportDeclarations(
            source: scannedSources[0],
            root: root,
            generatedBundleRecord: generatedBundleRecord,
            generatedRoot: generatedRoot
        )

        for item in mainImportScripts {
            candidates.append(
                dependencyCandidate(
                    sourceKind: .importScriptsDependency,
                    requestedSpecifier: item.specifierPreview,
                    parentSourcePath: item.sourcePath,
                    resolvedCandidatePath: item.dependencyCandidatePath,
                    generatedRootContained: item.generatedRootContained,
                    scanned: false,
                    diagnostics: item.diagnostics
                )
            )
            addScannedDependency(
                kind: .importScriptsDependency,
                relativePath: item.dependencyCandidatePath,
                root: root,
                scannedSources: &scannedSources,
                scannedKeys: &scannedKeys,
                fileManager: fileManager
            )
        }
        for item in mainDynamicImports {
            candidates.append(
                dependencyCandidate(
                    sourceKind: .dynamicImportCandidate,
                    requestedSpecifier: item.specifierPreview,
                    parentSourcePath: item.sourcePath,
                    resolvedCandidatePath: item.dependencyCandidatePath,
                    generatedRootContained: item.generatedRootContained,
                    scanned: false,
                    diagnostics: item.diagnostics
                )
            )
            addScannedDependency(
                kind: .dynamicImportCandidate,
                relativePath: item.dependencyCandidatePath,
                root: root,
                scannedSources: &scannedSources,
                scannedKeys: &scannedKeys,
                fileManager: fileManager
            )
        }
        for item in mainStaticImports {
            candidates.append(
                dependencyCandidate(
                    sourceKind: .moduleDependencyCandidate,
                    requestedSpecifier: item.specifier,
                    parentSourcePath: item.sourcePath,
                    resolvedCandidatePath: item.dependencyCandidatePath,
                    generatedRootContained: item.generatedRootContained,
                    scanned: false,
                    diagnostics: [
                        "Static module import candidate was discovered by diagnostics-only inventory.",
                    ]
                )
            )
            addScannedDependency(
                kind: .moduleDependencyCandidate,
                relativePath: item.dependencyCandidatePath,
                root: root,
                scannedSources: &scannedSources,
                scannedKeys: &scannedKeys,
                fileManager: fileManager
            )
        }

        var dynamicImports: [ChromeMV3PasswordManagerRealPackageServiceWorkerDynamicImportInventory] = []
        var importScriptsCalls: [ChromeMV3PasswordManagerRealPackageServiceWorkerImportScriptsInventory] = []
        var staticImports: [ChromeMV3PasswordManagerRealPackageServiceWorkerModuleImportDeclaration] = []
        var exportLocations:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation] = []
        var topLevelAwaitLocations:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation] = []
        var asyncOccurrences:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIOccurrence] = []
        var asyncTotalsByAPI:
            [ChromeMV3PasswordManagerRealPackageAsyncAPI: Int] = [:]
        var fetchClassifications:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerFetchClassification] = []
        var listenerRegistrationRecords:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerListenerRegistration] = []

        for scannedSource in scannedSources {
            dynamicImports.append(
                contentsOf: dynamicImportInventory(
                    source: scannedSource,
                    root: root,
                    generatedBundleRecord: generatedBundleRecord,
                    generatedRoot: generatedRoot
                )
            )
            importScriptsCalls.append(
                contentsOf: importScriptsInventory(
                    source: scannedSource,
                    root: root,
                    generatedBundleRecord: generatedBundleRecord,
                    generatedRoot: generatedRoot
                )
            )
            staticImports.append(
                contentsOf: staticImportDeclarations(
                    source: scannedSource,
                    root: root,
                    generatedBundleRecord: generatedBundleRecord,
                    generatedRoot: generatedRoot
                )
            )
            exportLocations.append(contentsOf: exportUsageLocations(scannedSource))
            topLevelAwaitLocations.append(
                contentsOf: topLevelAwaitUsageLocations(scannedSource)
            )
            let asyncScan = asyncAPIScan(scannedSource)
            asyncOccurrences.append(contentsOf: asyncScan.occurrences)
            for total in asyncScan.totals {
                asyncTotalsByAPI[total.api, default: 0] += total.count
            }
            fetchClassifications.append(
                contentsOf: fetchClassificationInventory(
                    source: scannedSource,
                    root: root,
                    generatedBundleRecord: generatedBundleRecord,
                    generatedRoot: generatedRoot
                )
            )
            listenerRegistrationRecords.append(
                contentsOf: listenerRegistrations(in: scannedSource)
            )
        }

        candidates = candidates.map { candidate in
            var updated = candidate
            updated.scanned =
                candidate.resolvedCandidatePath.map { relativePath in
                    scannedSources.contains {
                        $0.relativePath == relativePath
                            && $0.kind == candidate.sourceKind
                    }
                } ?? false
            return updated
        }

        let unknownComputedReferences =
            dynamicImports.filter { $0.dependencyCandidatePath == nil }.count
                + importScriptsCalls.filter { $0.dependencyCandidatePath == nil }
                .count
        let listenerMap = listenerRegistrationMap(
            registrations: listenerRegistrationRecords,
            unknownComputedReferences: unknownComputedReferences
        )
        let asyncInventory = asyncAPIInventory(
            asyncOccurrences,
            totalsByAPI: asyncTotalsByAPI
        )
        let browserPlatformDeviceToStringDetected = scannedSources.contains {
            $0.source.contains("this.device.toString")
        }
        let chromeUserAgentBrowserFamilyCheckDetected = scannedSources.contains {
            $0.source.contains(#"navigator.userAgent.indexOf(" Chrome/")"#)
                || $0.source.contains(
                    #"navigator.userAgent.indexOf(' Chrome/')"#
                )
        }
        let moduleInventory =
            ChromeMV3PasswordManagerRealPackageServiceWorkerModuleWorkerInventory(
                declaredAsModuleWorker: serviceWorkerType == "module",
                staticImportDeclarations:
                    staticImports.sorted(by: moduleImportSort),
                exportUsageLocations:
                    exportLocations.sorted(by: sourceLocationSort),
                dynamicImportUsage:
                    dynamicImports.sorted(by: dynamicImportSort),
                topLevelAwaitDetected: topLevelAwaitLocations.isEmpty == false,
                topLevelAwaitLocations:
                    topLevelAwaitLocations.sorted(by: sourceLocationSort),
                dependencyCandidatePaths:
                    candidates.filter {
                        $0.sourceKind == .moduleDependencyCandidate
                    }.sorted(by: dependencyCandidateSort),
                diagnostics:
                    uniqueSortedRealPackages([
                        serviceWorkerType == "module"
                            ? "Manifest declares background.type=module; this inventory is static-only and does not enable module worker execution."
                            : "Manifest does not declare a module service worker.",
                        staticImports.isEmpty
                            ? "No static module import declarations were detected in scanned service-worker sources."
                            : "Static module import declarations were inventoried without evaluating module code.",
                        exportLocations.isEmpty
                            ? "No export usage was detected in scanned service-worker sources."
                            : "Export usage was detected and remains diagnostics-only.",
                        topLevelAwaitLocations.isEmpty
                            ? "No top-level await was detected by conservative lexical scan."
                            : "Top-level await was detected by conservative lexical scan.",
                    ])
            )
        let nextPath = nextImplementationPath(
            serviceWorkerType: serviceWorkerType,
            dynamicImports: dynamicImports,
            moduleInventory: moduleInventory,
            asyncInventory: asyncInventory,
            importScriptsCalls: importScriptsCalls
        )
        return ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory(
            serviceWorkerPath: serviceWorkerPath,
            serviceWorkerType: serviceWorkerType,
            packageRootPath: root.path,
            generatedBundleRootPath: generatedRootPath,
            scannedSourceFileCount: scannedSources.count,
            dynamicImportExpressions:
                dynamicImports.sorted(by: dynamicImportSort),
            importScriptsCalls:
                importScriptsCalls.sorted(by: importScriptsSort),
            moduleWorkerInventory: moduleInventory,
            asyncAPIInventory: asyncInventory,
            fetchClassifications:
                fetchClassifications.sorted(by: fetchClassificationSort),
            listenerRegistrationMap: listenerMap,
            browserPlatformDeviceToStringDetected:
                browserPlatformDeviceToStringDetected,
            chromeUserAgentBrowserFamilyCheckDetected:
                chromeUserAgentBrowserFamilyCheckDetected,
            nextRecommendedImplementationPath: nextPath,
            diagnostics:
                uniqueSortedRealPackages([
                    "Service-worker dependency inventory scanned only package-root-contained local text resources.",
                    "Dynamic import, importScripts, module import/export, async API, and listener registration findings are diagnostics-only.",
                    "No service-worker runtime behavior, timer, module loader, dynamic import resolver, or generated-bundle mutation was enabled.",
                ])
        )
    }

    private static func emptyInventory(
        serviceWorkerPath: String?,
        serviceWorkerType: String,
        packageRootPath: String?,
        generatedBundleRootPath: String?,
        diagnostics: [String]
    ) -> ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory {
        ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyInventory(
            serviceWorkerPath: serviceWorkerPath,
            serviceWorkerType: serviceWorkerType,
            packageRootPath: packageRootPath,
            generatedBundleRootPath: generatedBundleRootPath,
            scannedSourceFileCount: 0,
            dynamicImportExpressions: [],
            importScriptsCalls: [],
            moduleWorkerInventory:
                ChromeMV3PasswordManagerRealPackageServiceWorkerModuleWorkerInventory(
                    declaredAsModuleWorker: serviceWorkerType == "module",
                    staticImportDeclarations: [],
                    exportUsageLocations: [],
                    dynamicImportUsage: [],
                    topLevelAwaitDetected: false,
                    topLevelAwaitLocations: [],
                    dependencyCandidatePaths: [],
                    diagnostics: diagnostics
                ),
            asyncAPIInventory:
                ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIInventory(
                    totals: [],
                    occurrences: [],
                    diagnostics: diagnostics
                ),
            fetchClassifications: [],
            listenerRegistrationMap:
                ChromeMV3PasswordManagerRealPackageServiceWorkerListenerRegistrationMap(
                    registrations: [],
                    mainWorkerCount: 0,
                    importScriptsDependencyCount: 0,
                    dynamicImportCandidateCount: 0,
                    moduleDependencyCandidateCount: 0,
                    unknownComputedDependencyReferenceCount: 0,
                    diagnostics: diagnostics
                ),
            browserPlatformDeviceToStringDetected: false,
            chromeUserAgentBrowserFamilyCheckDetected: false,
            nextRecommendedImplementationPath:
                "No service-worker source was available for dependency inventory.",
            diagnostics: uniqueSortedRealPackages(diagnostics)
        )
    }

    private struct InventorySource {
        var kind:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind
        var relativePath: String
        var url: URL
        var source: String
    }

    private struct InventoryCall {
        var line: Int
        var rawCallPreview: String
        var argumentSource: String
    }

    private struct CandidateResolution {
        var requestedSpecifier: String
        var resolvedCandidatePath: String?
        var generatedRootContained: Bool?
        var diagnostics: [String]
    }

    private static func addScannedDependency(
        kind:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind,
        relativePath: String?,
        root: URL,
        scannedSources: inout [InventorySource],
        scannedKeys: inout Set<String>,
        fileManager: FileManager
    ) {
        guard let relativePath,
              isSafeRelativeInventoryPath(relativePath)
        else { return }
        let key = "\(kind.rawValue):\(relativePath)"
        guard scannedKeys.contains(key) == false else { return }
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard safeURLInsideRoot(url.resolvingSymlinksInPath(), root: root),
              fileManager.fileExists(atPath: url.path),
              isScannableServiceWorkerInventoryResource(url),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        scannedKeys.insert(key)
        scannedSources.append(
            InventorySource(
                kind: kind,
                relativePath: relativePath,
                url: url,
                source: source
            )
        )
    }

    private static func dynamicImportInventory(
        source: InventorySource,
        root: URL,
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord?,
        generatedRoot: URL?
    ) -> [ChromeMV3PasswordManagerRealPackageServiceWorkerDynamicImportInventory] {
        javascriptCalls(
            named: "import",
            in: source.source,
            rejectMemberAccess: true
        ).map { call in
            let split = firstTopLevelArgument(call.argumentSource)
            let shape = importShape(split.first)
            let resolution = resolveCandidate(
                specifier: split.first,
                shape: shape,
                parentSource: source,
                root: root,
                generatedBundleRecord: generatedBundleRecord,
                generatedRoot: generatedRoot
            )
            return ChromeMV3PasswordManagerRealPackageServiceWorkerDynamicImportInventory(
                sourceKind: source.kind,
                sourcePath: source.relativePath,
                line: call.line,
                rawCallPreview: call.rawCallPreview,
                specifierPreview: previewInventory(split.first),
                shape: shape,
                hasOptionsArgument: split.hasAdditionalArguments,
                dependencyCandidatePath: resolution.resolvedCandidatePath,
                generatedRootContained: resolution.generatedRootContained,
                diagnostics:
                    uniqueSortedRealPackages(
                        [
                            "Dynamic import expression was classified without execution.",
                            split.hasAdditionalArguments
                                ? "Dynamic import uses an options argument; only the first specifier argument determines dependency shape."
                                : "Dynamic import has a single specifier argument.",
                        ] + resolution.diagnostics
                    )
            )
        }
    }

    private static func importScriptsInventory(
        source: InventorySource,
        root: URL,
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord?,
        generatedRoot: URL?
    ) -> [ChromeMV3PasswordManagerRealPackageServiceWorkerImportScriptsInventory] {
        javascriptCalls(
            named: "importScripts",
            in: source.source,
            rejectMemberAccess: false
        ).map { call in
            let split = firstTopLevelArgument(call.argumentSource)
            let shape = importShape(split.first)
            let resolution = resolveCandidate(
                specifier: split.first,
                shape: shape,
                parentSource: source,
                root: root,
                generatedBundleRecord: generatedBundleRecord,
                generatedRoot: generatedRoot
            )
            return ChromeMV3PasswordManagerRealPackageServiceWorkerImportScriptsInventory(
                sourceKind: source.kind,
                sourcePath: source.relativePath,
                line: call.line,
                rawCallPreview: call.rawCallPreview,
                specifierPreview: previewInventory(split.first),
                shape: shape,
                dependencyCandidatePath: resolution.resolvedCandidatePath,
                generatedRootContained: resolution.generatedRootContained,
                diagnostics:
                    uniqueSortedRealPackages(
                        [
                            "importScripts call was inventoried without executing the worker.",
                            split.hasAdditionalArguments
                                ? "Only the first importScripts argument is used for dependency-source mapping; all arguments remain diagnostics."
                                : "Single importScripts argument was inventoried.",
                        ] + resolution.diagnostics
                    )
            )
        }
    }

    private static func fetchClassificationInventory(
        source: InventorySource,
        root: URL,
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord?,
        generatedRoot: URL?
    ) -> [ChromeMV3PasswordManagerRealPackageServiceWorkerFetchClassification] {
        javascriptCalls(
            named: "fetch",
            in: source.source,
            rejectMemberAccess: true
        ).map { call in
            let split = firstTopLevelArgument(call.argumentSource)
            let argument = split.first
            let shape = importShape(argument)
            let literal = staticInventorySpecifierValue(argument)
            let requestKind: ChromeMV3ServiceWorkerJSFetchRequestKind
            let resolvedURL: String?
            let networkAccessRequired: Bool
            let extensionLocalResource: Bool
            let blocker: String
            var diagnostics = [
                "fetch call was classified statically without executing network or extension resource loading.",
            ]

            if let literal,
               literal.lowercased().hasPrefix("http://")
                    || literal.lowercased().hasPrefix("https://")
            {
                requestKind = .remoteNetworkBlocked
                resolvedURL = literal
                networkAccessRequired = true
                extensionLocalResource = false
                blocker = "networkFetchDisabled"
                diagnostics.append("Remote http(s) fetch requires network access and remains disabled.")
            } else if let literal,
                      literal.lowercased().hasPrefix("chrome-extension://")
            {
                requestKind = .extensionLocalGeneratedResource
                resolvedURL = literal
                networkAccessRequired = false
                extensionLocalResource = true
                blocker = "staticInventoryOnly"
                diagnostics.append("Extension-local chrome-extension fetch is eligible only for runtime generated-bundle containment checks.")
            } else if let literal,
                      literal.hasPrefix("/"),
                      literal.hasPrefix("//") == false
            {
                let normalized = normalizeInventoryImportPath(
                    String(literal.drop(while: { $0 == "/" }))
                )
                resolvedURL = normalized.path
                networkAccessRequired = false
                extensionLocalResource = true
                let generatedContained = normalized.path.flatMap {
                    path -> Bool? in
                    guard let generatedRoot else { return nil }
                    let candidate = generatedRoot
                        .appendingPathComponent(path)
                        .standardizedFileURL
                    return safeURLInsideRoot(
                        candidate.resolvingSymlinksInPath(),
                        root: generatedRoot
                    )
                        && generatedBundleRecord?.copiedResourcePaths
                            .contains(path) == true
                        && FileManager.default.fileExists(atPath: candidate.path)
                }
                requestKind =
                    generatedContained == false
                        ? .missingResource
                        : .relativeGeneratedResource
                blocker =
                    generatedContained == false
                        ? "missingResource"
                        : "staticInventoryOnly"
                diagnostics.append(
                    generatedContained == false
                        ? "Root-relative fetch does not resolve to a copied generated-bundle resource."
                        : "Root-relative fetch is eligible only for runtime generated-bundle containment checks."
                )
                diagnostics.append(normalized.message)
            } else if [.stringLiteralLocal, .templateLiteralStatic, .concatenation]
                .contains(shape)
            {
                let resolution = resolveCandidate(
                    specifier: argument,
                    shape: shape,
                    parentSource: source,
                    root: root,
                    generatedBundleRecord: generatedBundleRecord,
                    generatedRoot: generatedRoot
                )
                requestKind =
                    resolution.generatedRootContained == false
                        ? .missingResource
                        : .relativeGeneratedResource
                resolvedURL = resolution.resolvedCandidatePath
                networkAccessRequired = false
                extensionLocalResource = true
                blocker =
                    resolution.generatedRootContained == false
                        ? "missingResource"
                        : "staticInventoryOnly"
                diagnostics.append(
                    contentsOf:
                        resolution.diagnostics + [
                            resolution.generatedRootContained == false
                                ? "Relative fetch does not resolve to a copied generated-bundle resource."
                                : "Relative fetch is eligible only for runtime generated-bundle containment checks.",
                        ]
                )
            } else {
                requestKind = .unknownInput
                resolvedURL = nil
                networkAccessRequired = false
                extensionLocalResource = false
                blocker = "fetchInputUnsupported"
                diagnostics.append(
                    "Computed or request-object fetch input could not be safely resolved by static inventory."
                )
            }

            return ChromeMV3PasswordManagerRealPackageServiceWorkerFetchClassification(
                sourceKind: source.kind,
                sourcePath: source.relativePath,
                line: call.line,
                rawCallPreview: call.rawCallPreview,
                requestPreview: previewInventory(argument),
                resolvedURL: resolvedURL,
                requestKind: requestKind,
                networkAccessRequired: networkAccessRequired,
                extensionLocalResource: extensionLocalResource,
                executionAllowed: false,
                blocker: blocker,
                diagnostics: uniqueSortedRealPackages(diagnostics)
            )
        }
    }

    private static func staticImportDeclarations(
        source: InventorySource,
        root: URL,
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord?,
        generatedRoot: URL?
    ) -> [ChromeMV3PasswordManagerRealPackageServiceWorkerModuleImportDeclaration] {
        regexMatches(
            pattern:
                #"(?m)(^|;)\s*import\s+(?!\()(?:(?:[^;"']+?\s+from\s*)?["']([^"']+)["']|["']([^"']+)["'])"#,
            in: source.source
        ).compactMap { match in
            let specifier = match.capture(2) ?? match.capture(3)
            guard let specifier else { return nil }
            let quotedSpecifier = "'\(specifier)'"
            let resolution = resolveCandidate(
                specifier: quotedSpecifier,
                shape: importShape(quotedSpecifier),
                parentSource: source,
                root: root,
                generatedBundleRecord: generatedBundleRecord,
                generatedRoot: generatedRoot
            )
            return ChromeMV3PasswordManagerRealPackageServiceWorkerModuleImportDeclaration(
                sourcePath: source.relativePath,
                line: lineNumber(in: source.source, utf16Offset: match.range.location),
                rawDeclarationPreview: previewInventory(match.text),
                specifier: specifier,
                dependencyCandidatePath: resolution.resolvedCandidatePath,
                generatedRootContained: resolution.generatedRootContained
            )
        }
    }

    private static func exportUsageLocations(
        _ source: InventorySource
    ) -> [ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation] {
        regexMatches(
            pattern: #"(?m)(^|;)\s*export\s+"#,
            in: source.source
        ).prefix(20).map { match in
            sourceLocation(
                source: source,
                line: lineNumber(in: source.source, utf16Offset: match.range.location),
                snippet: match.text
            )
        }
    }

    private static func topLevelAwaitUsageLocations(
        _ source: InventorySource
    ) -> [ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation] {
        topLevelTokenLocations(token: "await", in: source)
    }

    private static func asyncAPIScan(
        _ source: InventorySource
    ) -> (
        occurrences:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIOccurrence],
        totals:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPITotal]
    ) {
        let patterns:
            [(ChromeMV3PasswordManagerRealPackageAsyncAPI, String)] = [
            (.setTimeout, #"\bsetTimeout\s*\("#),
            (.setInterval, #"\bsetInterval\s*\("#),
            (.queueMicrotask, #"\bqueueMicrotask\s*\("#),
            (.promiseThen, #"\.then\s*\("#),
            (.asyncFunction, #"\basync\s+function\b|\basync\s*(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>"#),
            (.fetch, #"\bfetch\s*\("#),
            (.webSocket, #"\bWebSocket\b"#),
            (.eventSource, #"\bEventSource\b"#),
        ]
        var occurrences:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIOccurrence] = []
        var totals:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPITotal] = []
        for (api, pattern) in patterns {
            let matches = regexMatches(pattern: pattern, in: source.source)
            if matches.isEmpty == false {
                totals.append(
                    ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPITotal(
                        api: api,
                        count: matches.count
                    )
                )
            }
            occurrences.append(
                contentsOf:
                    matches.prefix(20).map { match in
                    ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIOccurrence(
                        api: api,
                        sourceKind: source.kind,
                        sourcePath: source.relativePath,
                        line: lineNumber(
                            in: source.source,
                            utf16Offset: match.range.location
                        ),
                        snippet: previewInventory(match.text)
                    )
                }
            )
        }
        return (occurrences, totals)
    }

    private static func listenerRegistrations(
        in source: InventorySource
    ) -> [ChromeMV3PasswordManagerRealPackageServiceWorkerListenerRegistration] {
        regexMatches(
            pattern:
                #"([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)+)\.addListener\s*\("#,
            in: source.source
        ).prefix(200).compactMap { match in
            guard let target = match.capture(1) else { return nil }
            return ChromeMV3PasswordManagerRealPackageServiceWorkerListenerRegistration(
                sourceKind: source.kind,
                sourcePath: source.relativePath,
                line: lineNumber(in: source.source, utf16Offset: match.range.location),
                eventTarget: target,
                snippet: previewInventory(match.text)
            )
        }
    }

    private static func asyncAPIInventory(
        _ occurrences:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIOccurrence],
        totalsByAPI:
            [ChromeMV3PasswordManagerRealPackageAsyncAPI: Int]
    ) -> ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIInventory {
        let totals = ChromeMV3PasswordManagerRealPackageAsyncAPI.allCases
            .map { api in
                ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPITotal(
                    api: api,
                    count: totalsByAPI[api] ?? 0
                )
            }
            .filter { $0.count > 0 }
            .sorted { $0.api < $1.api }
        return ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIInventory(
            totals: totals,
            occurrences:
                occurrences.sorted {
                    if $0.sourcePath != $1.sourcePath {
                        return $0.sourcePath < $1.sourcePath
                    }
                    if $0.line != $1.line { return $0.line < $1.line }
                    return $0.api < $1.api
                },
            diagnostics:
                uniqueSortedRealPackages([
                    totals.isEmpty
                        ? "No requested timer/async API tokens were detected."
                        : "Timer, microtask, Promise, async function, fetch, WebSocket, and EventSource tokens were counted statically.",
                    "Counts are diagnostic tokens and do not imply execution or API enablement.",
                ])
        )
    }

    private static func listenerRegistrationMap(
        registrations:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerListenerRegistration],
        unknownComputedReferences: Int
    ) -> ChromeMV3PasswordManagerRealPackageServiceWorkerListenerRegistrationMap {
        func count(
            _ kind:
                ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind
        ) -> Int {
            registrations.filter { $0.sourceKind == kind }.count
        }
        return ChromeMV3PasswordManagerRealPackageServiceWorkerListenerRegistrationMap(
            registrations:
                registrations.sorted {
                    if $0.sourceKind != $1.sourceKind {
                        return $0.sourceKind < $1.sourceKind
                    }
                    if $0.sourcePath != $1.sourcePath {
                        return $0.sourcePath < $1.sourcePath
                    }
                    if $0.line != $1.line { return $0.line < $1.line }
                    return $0.eventTarget < $1.eventTarget
                },
            mainWorkerCount: count(.mainWorker),
            importScriptsDependencyCount: count(.importScriptsDependency),
            dynamicImportCandidateCount: count(.dynamicImportCandidate),
            moduleDependencyCandidateCount: count(.moduleDependencyCandidate),
            unknownComputedDependencyReferenceCount: unknownComputedReferences,
            diagnostics:
                uniqueSortedRealPackages([
                    "Listener registration locations were mapped by static addListener token scan.",
                    unknownComputedReferences == 0
                        ? "No unknown/computed dependency reference required a listener-location caveat."
                        : "Computed dependency references may contain additional listeners that this diagnostics-only scan did not execute or resolve.",
                ])
        )
    }

    private static func nextImplementationPath(
        serviceWorkerType: String,
        dynamicImports:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerDynamicImportInventory],
        moduleInventory:
            ChromeMV3PasswordManagerRealPackageServiceWorkerModuleWorkerInventory,
        asyncInventory:
            ChromeMV3PasswordManagerRealPackageServiceWorkerAsyncAPIInventory,
        importScriptsCalls:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerImportScriptsInventory]
    ) -> String {
        if serviceWorkerType == "module" {
            let staticCount =
                moduleInventory.staticImportDeclarations.count
            return "Classify and design a default-off module-worker loader boundary first; this worker declares type=module with \(staticCount) static module import candidate(s)."
        }
        if dynamicImports.contains(where: {
            [.identifier, .memberExpression, .callExpression,
             .conditionalExpression, .concatenation, .unknownComputed]
                .contains($0.shape)
        }) {
            let shapes = uniqueSortedRealPackages(
                dynamicImports.map(\.shape.rawValue)
            ).joined(separator: ", ")
            return "Inventory the computed dynamic-import and chunk-loader contract next; detected shape(s): \(shapes). Do not enable computed import execution yet."
        }
        if importScriptsCalls.contains(where: { $0.dependencyCandidatePath == nil }) {
            return "Resolve computed importScripts dependency mapping as diagnostics before adding any runtime import behavior."
        }
        if asyncInventory.count(.setTimeout) > 0
            || asyncInventory.count(.setInterval) > 0
        {
            return "Design timer lifecycle semantics and cancellation diagnostics before enabling any setTimeout or setInterval behavior."
        }
        return "Use listener registration and dependency inventory to choose the next smallest diagnostics-only compatibility probe."
    }

    private static func resolveCandidate(
        specifier: String,
        shape: ChromeMV3PasswordManagerRealPackageDynamicImportShape,
        parentSource: InventorySource,
        root: URL,
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord?,
        generatedRoot: URL?
    ) -> CandidateResolution {
        guard
            [.stringLiteralLocal, .templateLiteralStatic, .concatenation]
                .contains(shape),
            let literal = staticInventorySpecifierValue(specifier)
        else {
            return CandidateResolution(
                requestedSpecifier: specifier,
                resolvedCandidatePath: nil,
                generatedRootContained: nil,
                diagnostics: [
                    "No dependency candidate path was resolved because the specifier is not a static local literal.",
                ]
            )
        }
        let normalized = normalizeInventoryImportPath(literal)
        guard normalized.path != nil else {
            return CandidateResolution(
                requestedSpecifier: specifier,
                resolvedCandidatePath: nil,
                generatedRootContained: false,
                diagnostics: [normalized.message]
            )
        }
        guard let normalizedPath = normalized.path else {
            return CandidateResolution(
                requestedSpecifier: specifier,
                resolvedCandidatePath: nil,
                generatedRootContained: false,
                diagnostics: [normalized.message]
            )
        }
        let parentDirectory = parentSource.url.deletingLastPathComponent()
        let candidate = parentDirectory.appendingPathComponent(normalizedPath)
            .standardizedFileURL
        let resolvedRelative = relativeInventoryPath(candidate, root: root)
        guard let resolvedRelative else {
            return CandidateResolution(
                requestedSpecifier: specifier,
                resolvedCandidatePath: nil,
                generatedRootContained: false,
                diagnostics: [
                    "Dependency candidate resolves outside the package root.",
                ]
            )
        }
        let generatedContained: Bool? = generatedRoot.map { generatedRoot in
            let generatedCandidate = generatedRoot
                .appendingPathComponent(resolvedRelative)
                .standardizedFileURL
            return safeURLInsideRoot(
                generatedCandidate.resolvingSymlinksInPath(),
                root: generatedRoot
            )
                && generatedBundleRecord?.copiedResourcePaths
                    .contains(resolvedRelative) == true
                && FileManager.default.fileExists(atPath: generatedCandidate.path)
        }
        return CandidateResolution(
            requestedSpecifier: specifier,
            resolvedCandidatePath: resolvedRelative,
            generatedRootContained: generatedContained,
            diagnostics: [
                generatedContained == true
                    ? "Dependency candidate is generated-root-contained and recorded as a copied generated-bundle resource."
                    : "Dependency candidate is not proven generated-root-contained.",
            ]
        )
    }

    private static func dependencyCandidate(
        sourceKind:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencySourceKind,
        requestedSpecifier: String,
        parentSourcePath: String,
        resolvedCandidatePath: String?,
        generatedRootContained: Bool?,
        scanned: Bool,
        diagnostics: [String]
    ) -> ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyCandidate {
        ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyCandidate(
            sourceKind: sourceKind,
            requestedSpecifier: previewInventory(requestedSpecifier),
            parentSourcePath: parentSourcePath,
            resolvedCandidatePath: resolvedCandidatePath,
            generatedRootContained: generatedRootContained,
            scanned: scanned,
            diagnostics: uniqueSortedRealPackages(diagnostics)
        )
    }

    private struct RegexMatch {
        var text: String
        var range: NSRange
        var captures: [String?]

        func capture(_ index: Int) -> String? {
            guard index > 0, index <= captures.count else { return nil }
            return captures[index - 1]
        }
    }

    private static func regexMatches(
        pattern: String,
        in source: String
    ) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern)
        else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let fullRange = Range(match.range, in: source)
            else { return nil }
            let captures = (1..<match.numberOfRanges).map { index -> String? in
                guard let range = Range(match.range(at: index), in: source)
                else { return nil }
                return String(source[range])
            }
            return RegexMatch(
                text: String(source[fullRange]),
                range: match.range,
                captures: captures
            )
        }
    }

    private static func javascriptCalls(
        named name: String,
        in source: String,
        rejectMemberAccess: Bool
    ) -> [InventoryCall] {
        let bytes = Array(source.utf8)
        let newlines = bytes.enumerated().compactMap {
            $0.element == 10 ? $0.offset : nil
        }
        var calls: [InventoryCall] = []
        var index = 0
        var quote: UInt8?
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if byte == 92 {
                    escaped = true
                } else if byte == activeQuote {
                    quote = nil
                }
                index += 1
                continue
            }
            if byte == 34 || byte == 39 || byte == 96 {
                quote = byte
                index += 1
                continue
            }
            if byte == 47, index + 1 < bytes.count, bytes[index + 1] == 47 {
                index += 2
                while index < bytes.count, bytes[index] != 10 {
                    index += 1
                }
                continue
            }
            if byte == 47, index + 1 < bytes.count, bytes[index + 1] == 42 {
                index += 2
                while index + 1 < bytes.count,
                      !(bytes[index] == 42 && bytes[index + 1] == 47)
                {
                    index += 1
                }
                index += 2
                continue
            }
            guard isIdentifierStart(byte) else {
                index += 1
                continue
            }
            let start = index
            index += 1
            while index < bytes.count, isIdentifierPart(bytes[index]) {
                index += 1
            }
            guard String(decoding: bytes[start..<index], as: UTF8.self) == name
            else { continue }
            if rejectMemberAccess,
               previousSignificantByte(bytes, before: start) == 46
            {
                continue
            }
            var open = index
            while open < bytes.count, isASCIIWhitespace(bytes[open]) {
                open += 1
            }
            guard open < bytes.count, bytes[open] == 40 else { continue }
            guard let close = matchingParenClose(bytes, open: open) else {
                continue
            }
            if rejectMemberAccess,
               followingSignificantByte(bytes, after: close) == 123
            {
                index = close + 1
                continue
            }
            let argument = String(
                decoding: bytes[(open + 1)..<close],
                as: UTF8.self
            )
            let raw = String(decoding: bytes[start...(close)], as: UTF8.self)
            calls.append(
                InventoryCall(
                    line: lineNumber(newlines: newlines, offset: start),
                    rawCallPreview: previewInventory(raw),
                    argumentSource: argument
                )
            )
            index = close + 1
        }
        for fallback in fallbackJavascriptCalls(
            named: name,
            in: source,
            rejectMemberAccess: rejectMemberAccess
        ) {
            guard calls.contains(where: {
                $0.line == fallback.line
                    && $0.rawCallPreview == fallback.rawCallPreview
            }) == false else { continue }
            calls.append(fallback)
        }
        return calls
    }

    private static func fallbackJavascriptCalls(
        named name: String,
        in source: String,
        rejectMemberAccess: Bool
    ) -> [InventoryCall] {
        let bytes = Array(source.utf8)
        let newlines = bytes.enumerated().compactMap {
            $0.element == 10 ? $0.offset : nil
        }
        var calls: [InventoryCall] = []
        var index = 0
        while index < bytes.count {
            guard isIdentifierStart(bytes[index]) else {
                index += 1
                continue
            }
            let start = index
            index += 1
            while index < bytes.count, isIdentifierPart(bytes[index]) {
                index += 1
            }
            guard String(decoding: bytes[start..<index], as: UTF8.self) == name
            else { continue }
            if rejectMemberAccess,
               previousSignificantByte(bytes, before: start) == 46
            {
                continue
            }
            var open = index
            while open < bytes.count, isASCIIWhitespace(bytes[open]) {
                open += 1
            }
            guard open < bytes.count, bytes[open] == 40,
                  let close = matchingParenClose(bytes, open: open)
            else { continue }
            if rejectMemberAccess,
               followingSignificantByte(bytes, after: close) == 123
            {
                index = close + 1
                continue
            }
            let argument = String(
                decoding: bytes[(open + 1)..<close],
                as: UTF8.self
            )
            let raw = String(decoding: bytes[start...close], as: UTF8.self)
            calls.append(
                InventoryCall(
                    line: lineNumber(newlines: newlines, offset: start),
                    rawCallPreview: previewInventory(raw),
                    argumentSource: argument
                )
            )
            index = close + 1
        }
        return calls
    }

    private static func matchingParenClose(
        _ bytes: [UInt8],
        open: Int
    ) -> Int? {
        var depth = 1
        var index = open + 1
        var quote: UInt8?
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if byte == 92 {
                    escaped = true
                } else if byte == activeQuote {
                    quote = nil
                }
                index += 1
                continue
            }
            if byte == 34 || byte == 39 || byte == 96 {
                quote = byte
            } else if byte == 47, index + 1 < bytes.count,
                      bytes[index + 1] == 47
            {
                index += 2
                while index < bytes.count, bytes[index] != 10 {
                    index += 1
                }
                continue
            } else if byte == 47, index + 1 < bytes.count,
                      bytes[index + 1] == 42
            {
                index += 2
                while index + 1 < bytes.count,
                      !(bytes[index] == 42 && bytes[index + 1] == 47)
                {
                    index += 1
                }
                index += 2
                continue
            } else if byte == 40 {
                depth += 1
            } else if byte == 41 {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    private static func firstTopLevelArgument(
        _ arguments: String
    ) -> (first: String, hasAdditionalArguments: Bool) {
        let bytes = Array(arguments.utf8)
        var quote: UInt8?
        var escaped = false
        var parenDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
        for index in bytes.indices {
            let byte = bytes[index]
            if let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if byte == 92 {
                    escaped = true
                } else if byte == activeQuote {
                    quote = nil
                }
                continue
            }
            if byte == 34 || byte == 39 || byte == 96 {
                quote = byte
            } else if byte == 40 {
                parenDepth += 1
            } else if byte == 41 {
                parenDepth = max(0, parenDepth - 1)
            } else if byte == 123 {
                braceDepth += 1
            } else if byte == 125 {
                braceDepth = max(0, braceDepth - 1)
            } else if byte == 91 {
                bracketDepth += 1
            } else if byte == 93 {
                bracketDepth = max(0, bracketDepth - 1)
            } else if byte == 44,
                      parenDepth == 0,
                      braceDepth == 0,
                      bracketDepth == 0
            {
                let first = String(
                    decoding: bytes[..<index],
                    as: UTF8.self
                )
                return (
                    first.trimmingCharacters(in: .whitespacesAndNewlines),
                    true
                )
            }
        }
        return (
            arguments.trimmingCharacters(in: .whitespacesAndNewlines),
            false
        )
    }

    private static func importShape(
        _ argument: String
    ) -> ChromeMV3PasswordManagerRealPackageDynamicImportShape {
        let value = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return .unknownComputed }
        if let literal = literalSpecifierValue(value) {
            return isRemoteOrUnsafeInventoryImport(literal)
                ? .remoteOrUnsafe : .stringLiteralLocal
        }
        if value.hasPrefix("`"), value.hasSuffix("`") {
            let literal = String(value.dropFirst().dropLast())
            if literal.contains("${") { return .templateLiteralDynamic }
            return isRemoteOrUnsafeInventoryImport(literal)
                ? .remoteOrUnsafe : .templateLiteralStatic
        }
        if containsTopLevelToken("?", in: value)
            && containsTopLevelToken(":", in: value)
        {
            return .conditionalExpression
        }
        if containsTopLevelToken("+", in: value) {
            return .concatenation
        }
        if matchesInventoryRegex(#"^[A-Za-z_$][\w$]*$"#, value) {
            return .identifier
        }
        if matchesInventoryRegex(
            #"^[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*|\[[^\]]+\])+$"#,
            value
        ) {
            return .memberExpression
        }
        if matchesInventoryRegex(
            #"^[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?\s*\("#,
            value
        ) {
            return .callExpression
        }
        return .unknownComputed
    }

    private static func literalSpecifierValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(trimmed.utf8)
        guard let first = bytes.first,
              (first == 34 || first == 39),
              bytes.last == first,
              bytes.count >= 2
        else { return nil }
        var escaped = false
        for byte in bytes.dropFirst().dropLast() {
            if escaped {
                escaped = false
            } else if byte == 92 {
                escaped = true
            } else if byte == first {
                return nil
            }
        }
        return String(trimmed.dropFirst().dropLast())
    }

    private static func staticInventorySpecifierValue(
        _ value: String
    ) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let literal = literalSpecifierValue(trimmed) {
            return literal
        }
        if trimmed.first == "`", trimmed.last == "`" {
            let literal = String(trimmed.dropFirst().dropLast())
            return literal.contains("${") || literal.contains("\\")
                ? nil : literal
        }
        let parts = topLevelInventorySegments(trimmed, separator: 43)
        guard parts.count > 1 else { return nil }
        var result = ""
        for part in parts {
            guard let literal = staticInventorySpecifierValue(part)
            else { return nil }
            result += literal
        }
        return result
    }

    private static func topLevelInventorySegments(
        _ source: String,
        separator: UInt8
    ) -> [String] {
        let bytes = Array(source.utf8)
        var results: [String] = []
        var start = 0
        var quote: UInt8?
        var escaped = false
        var parenDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
        for index in bytes.indices {
            let byte = bytes[index]
            if let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if byte == 92 {
                    escaped = true
                } else if byte == activeQuote {
                    quote = nil
                }
                continue
            }
            if byte == 34 || byte == 39 || byte == 96 {
                quote = byte
            } else if byte == 40 {
                parenDepth += 1
            } else if byte == 41 {
                parenDepth = max(0, parenDepth - 1)
            } else if byte == 123 {
                braceDepth += 1
            } else if byte == 125 {
                braceDepth = max(0, braceDepth - 1)
            } else if byte == 91 {
                bracketDepth += 1
            } else if byte == 93 {
                bracketDepth = max(0, bracketDepth - 1)
            } else if byte == separator,
                      parenDepth == 0,
                      braceDepth == 0,
                      bracketDepth == 0
            {
                results.append(
                    String(decoding: bytes[start..<index], as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
                start = index + 1
            }
        }
        results.append(
            String(decoding: bytes[start...], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return results
    }

    private static func containsTopLevelToken(
        _ token: Character,
        in source: String
    ) -> Bool {
        let needle = String(token).utf8.first
        let bytes = Array(source.utf8)
        var quote: UInt8?
        var escaped = false
        var parenDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
        for byte in bytes {
            if let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if byte == 92 {
                    escaped = true
                } else if byte == activeQuote {
                    quote = nil
                }
                continue
            }
            if byte == 34 || byte == 39 || byte == 96 {
                quote = byte
            } else if byte == 40 {
                parenDepth += 1
            } else if byte == 41 {
                parenDepth = max(0, parenDepth - 1)
            } else if byte == 123 {
                braceDepth += 1
            } else if byte == 125 {
                braceDepth = max(0, braceDepth - 1)
            } else if byte == 91 {
                bracketDepth += 1
            } else if byte == 93 {
                bracketDepth = max(0, bracketDepth - 1)
            } else if byte == needle,
                      parenDepth == 0,
                      braceDepth == 0,
                      bracketDepth == 0
            {
                return true
            }
        }
        return false
    }

    private static func topLevelTokenLocations(
        token: String,
        in source: InventorySource
    ) -> [ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation] {
        let bytes = Array(source.source.utf8)
        let tokenBytes = Array(token.utf8)
        let newlines = bytes.enumerated().compactMap {
            $0.element == 10 ? $0.offset : nil
        }
        var locations:
            [ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation] = []
        var index = 0
        var quote: UInt8?
        var escaped = false
        var parenDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
        while index < bytes.count {
            let byte = bytes[index]
            if let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if byte == 92 {
                    escaped = true
                } else if byte == activeQuote {
                    quote = nil
                }
                index += 1
                continue
            }
            if byte == 34 || byte == 39 || byte == 96 {
                quote = byte
                index += 1
                continue
            }
            if byte == 47, index + 1 < bytes.count, bytes[index + 1] == 47 {
                index += 2
                while index < bytes.count, bytes[index] != 10 {
                    index += 1
                }
                continue
            }
            if byte == 47, index + 1 < bytes.count, bytes[index + 1] == 42 {
                index += 2
                while index + 1 < bytes.count,
                      !(bytes[index] == 42 && bytes[index + 1] == 47)
                {
                    index += 1
                }
                index += 2
                continue
            }
            if byte == 123 {
                braceDepth += 1
            } else if byte == 125 {
                braceDepth = max(0, braceDepth - 1)
            } else if byte == 40 {
                parenDepth += 1
            } else if byte == 41 {
                parenDepth = max(0, parenDepth - 1)
            } else if byte == 91 {
                bracketDepth += 1
            } else if byte == 93 {
                bracketDepth = max(0, bracketDepth - 1)
            }
            if braceDepth == 0,
               parenDepth == 0,
               bracketDepth == 0,
               index + tokenBytes.count <= bytes.count,
               Array(bytes[index..<(index + tokenBytes.count)]) == tokenBytes,
               (index == 0 || isIdentifierPart(bytes[index - 1]) == false),
               index + tokenBytes.count == bytes.count
                    || isIdentifierPart(bytes[index + tokenBytes.count])
                    == false
            {
                locations.append(
                    sourceLocation(
                        source: source,
                        line: lineNumber(newlines: newlines, offset: index),
                        snippet: token
                    )
                )
                if locations.count >= 20 { break }
            }
            index += 1
        }
        return locations
    }

    private static func sourceLocation(
        source: InventorySource,
        line: Int,
        snippet: String
    ) -> ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation {
        ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation(
            sourceKind: source.kind,
            sourcePath: source.relativePath,
            line: line,
            snippet: previewInventory(snippet)
        )
    }

    private static func normalizeInventoryImportPath(
        _ path: String
    ) -> (path: String?, message: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.contains("\0") == false,
              trimmed.contains("\\") == false,
              trimmed.contains("?") == false,
              trimmed.contains("#") == false
        else {
            return (
                nil,
                "Import path is empty or contains unsupported characters."
            )
        }
        guard isRemoteOrUnsafeInventoryImport(trimmed) == false else {
            return (
                nil,
                "Import path is remote, absolute, or otherwise unsafe."
            )
        }
        var components: [String] = []
        for component in trimmed.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init) {
            if component == "." { continue }
            guard component != "..", component.isEmpty == false else {
                return (
                    nil,
                    "Import path traversal or empty segment was rejected."
                )
            }
            components.append(component)
        }
        return (
            components.isEmpty ? nil : components.joined(separator: "/"),
            "Import path normalized safely."
        )
    }

    private static func isRemoteOrUnsafeInventoryImport(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("http:")
            || lower.hasPrefix("https:")
            || lower.hasPrefix("data:")
            || lower.hasPrefix("blob:")
            || lower.hasPrefix("file:")
            || value.hasPrefix("/")
            || value.hasPrefix("~")
            || value.hasPrefix("../")
            || value.contains("\\")
    }

    private static func isSafeRelativeInventoryPath(_ path: String) -> Bool {
        normalizeInventoryImportPath(path).path != nil
    }

    private static func relativeInventoryPath(
        _ candidate: URL,
        root: URL
    ) -> String? {
        guard safeURLInsideRoot(candidate.resolvingSymlinksInPath(), root: root)
        else { return nil }
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidatePath.hasPrefix(prefix) else { return nil }
        let relative = String(candidatePath.dropFirst(prefix.count))
        return relative.isEmpty ? nil : relative
    }

    private static func isScannableServiceWorkerInventoryResource(
        _ url: URL
    ) -> Bool {
        ["js", "mjs"].contains(url.pathExtension.lowercased())
    }

    private static func previousSignificantByte(
        _ bytes: [UInt8],
        before index: Int
    ) -> UInt8? {
        guard index > 0 else { return nil }
        var cursor = index - 1
        while cursor >= 0 {
            if isASCIIWhitespace(bytes[cursor]) == false {
                return bytes[cursor]
            }
            if cursor == 0 { break }
            cursor -= 1
        }
        return nil
    }

    private static func followingSignificantByte(
        _ bytes: [UInt8],
        after index: Int
    ) -> UInt8? {
        var cursor = index + 1
        while cursor < bytes.count {
            if isASCIIWhitespace(bytes[cursor]) == false {
                return bytes[cursor]
            }
            cursor += 1
        }
        return nil
    }

    private static func matchesInventoryRegex(
        _ pattern: String,
        _ value: String
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern)
        else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    private static func lineNumber(
        in source: String,
        utf16Offset: Int
    ) -> Int {
        let utf16 = Array(source.utf16)
        guard utf16Offset > 0 else { return 1 }
        return utf16.prefix(min(utf16Offset, utf16.count))
            .filter { $0 == 10 }
            .count + 1
    }

    private static func lineNumber(newlines: [Int], offset: Int) -> Int {
        var low = 0
        var high = newlines.count
        while low < high {
            let mid = (low + high) / 2
            if newlines[mid] < offset {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low + 1
    }

    private static func previewInventory(_ value: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 160 else { return collapsed }
        return String(collapsed.prefix(157)) + "..."
    }

    private static func isIdentifierStart(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || byte == 95
            || byte == 36
    }

    private static func isIdentifierPart(_ byte: UInt8) -> Bool {
        isIdentifierStart(byte) || (byte >= 48 && byte <= 57)
    }

    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 9 || byte == 10 || byte == 11 || byte == 12 || byte == 13
            || byte == 32
    }

    private static func dynamicImportSort(
        _ lhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDynamicImportInventory,
        _ rhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDynamicImportInventory
    ) -> Bool {
        if lhs.sourcePath != rhs.sourcePath {
            return lhs.sourcePath < rhs.sourcePath
        }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.specifierPreview < rhs.specifierPreview
    }

    private static func importScriptsSort(
        _ lhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerImportScriptsInventory,
        _ rhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerImportScriptsInventory
    ) -> Bool {
        if lhs.sourcePath != rhs.sourcePath {
            return lhs.sourcePath < rhs.sourcePath
        }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.specifierPreview < rhs.specifierPreview
    }

    private static func fetchClassificationSort(
        _ lhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerFetchClassification,
        _ rhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerFetchClassification
    ) -> Bool {
        if lhs.sourcePath != rhs.sourcePath {
            return lhs.sourcePath < rhs.sourcePath
        }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.requestPreview < rhs.requestPreview
    }

    private static func moduleImportSort(
        _ lhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerModuleImportDeclaration,
        _ rhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerModuleImportDeclaration
    ) -> Bool {
        if lhs.sourcePath != rhs.sourcePath {
            return lhs.sourcePath < rhs.sourcePath
        }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.specifier < rhs.specifier
    }

    private static func sourceLocationSort(
        _ lhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation,
        _ rhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerSourceLocation
    ) -> Bool {
        if lhs.sourcePath != rhs.sourcePath {
            return lhs.sourcePath < rhs.sourcePath
        }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.snippet < rhs.snippet
    }

    private static func dependencyCandidateSort(
        _ lhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyCandidate,
        _ rhs:
            ChromeMV3PasswordManagerRealPackageServiceWorkerDependencyCandidate
    ) -> Bool {
        if lhs.parentSourcePath != rhs.parentSourcePath {
            return lhs.parentSourcePath < rhs.parentSourcePath
        }
        return (lhs.resolvedCandidatePath ?? lhs.requestedSpecifier)
            < (rhs.resolvedCandidatePath ?? rhs.requestedSpecifier)
    }
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
        let nativeConnectAPI = "chrome.runtime." + "connect" + "Native"
        let nativeSendAPI = "chrome.runtime." + "send" + "Native" + "Message"
        return [
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
            nativeConnectAPI,
            "chrome.runtime.getURL",
            "chrome.runtime.sendMessage",
            nativeSendAPI,
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
        let nativeConnectMethod = "connect" + "Native"
        let nativeSendMethod = "send" + "Native" + "Message"
        let pattern =
            "(?:\(nativeConnectMethod)|\(nativeSendMethod))"
            + #"\s*\(\s*["']([^"']+)["']"#
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

private extension Sequence where Element: Hashable & Comparable {
    func uniqueSortedRealPackageValues() -> [Element] {
        Array(Set(self)).sorted()
    }
}
