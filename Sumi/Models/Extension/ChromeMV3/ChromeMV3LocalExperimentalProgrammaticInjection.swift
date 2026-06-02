//
//  ChromeMV3LocalExperimentalProgrammaticInjection.swift
//  Sumi
//
//  Narrow local-only modeled programmatic injection for reviewed diagnostic
//  generated resources. This does not expose arbitrary script execution.
//

import CryptoKit
import Foundation

enum ChromeMV3LocalExperimentalProgrammaticInjectionBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case arbitraryFunctionInjectionRequired
    case argumentsBlocked
    case extensionDisabled
    case fileSchemeScriptBlocked
    case generatedBundleRecordMissing
    case generatedBundleRootMissing
    case generatedResourceEscapedRoot
    case generatedResourceMissing
    case generatedResourceNotCopied
    case generatedResourceNotRegularFile
    case generatedResourceSymbolicLink
    case hostPermissionBlocked
    case injectImmediatelyRequired
    case localExperimentalGateClosed
    case mainWorldRequired
    case moduleDisabled
    case multiFrameRequired
    case profileScopedExtensionMissing
    case remoteScriptBlocked
    case reviewedGeneratedBundleFileRequired
    case targetOutsideSyntheticLogin
    case unsupportedTargetShape
    case unsupportedTargetURLScheme
    case unsafeScriptPath
    case webKitExecutionSurfaceUnavailable

    static func < (
        lhs: ChromeMV3LocalExperimentalProgrammaticInjectionBlocker,
        rhs: ChromeMV3LocalExperimentalProgrammaticInjectionBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3LocalExperimentalProgrammaticInjectionResourceStatus:
    String,
    Codable,
    Sendable
{
    case copiedGeneratedBundleFile
    case blocked
}

struct ChromeMV3LocalExperimentalProgrammaticInjectionPolicy:
    Codable,
    Equatable,
    Sendable
{
    var programmaticInjectionAvailableInLocalExperimentalGate: Bool
    var programmaticInjectionAvailableByDefault: Bool
    var webKitProgrammaticInjectionAvailableInLocalExperimentalGate: Bool
    var webKitProgrammaticInjectionAvailableByDefault: Bool
    var syntheticHarnessOnly: Bool
    var reviewedGeneratedBundleFileOnly: Bool
    var isolatedWorldOnly: Bool
    var topFrameOnly: Bool
    var generatedBundleFilesOnly: Bool
    var allowedGeneratedBundleFiles: [String]
    var arbitraryFunctionInjectionAllowed: Bool
    var argumentsAllowed: Bool
    var mainWorldAllowed: Bool
    var multiFrameAllowed: Bool
    var fileSchemeAllowed: Bool
    var remoteScriptAllowed: Bool
    var productNormalTabsAllowed: Bool
    var requiresHostPermissionOrActiveTab: Bool
    var teardownRequired: Bool
    var teardownPolicy: String

    static let bitwardenDetectFill = Self(
        programmaticInjectionAvailableInLocalExperimentalGate: true,
        programmaticInjectionAvailableByDefault: false,
        webKitProgrammaticInjectionAvailableInLocalExperimentalGate: true,
        webKitProgrammaticInjectionAvailableByDefault: false,
        syntheticHarnessOnly: true,
        reviewedGeneratedBundleFileOnly: true,
        isolatedWorldOnly: true,
        topFrameOnly: true,
        generatedBundleFilesOnly: true,
        allowedGeneratedBundleFiles:
            ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
            .reviewedGeneratedBundleResourceAllowlist,
        arbitraryFunctionInjectionAllowed: false,
        argumentsAllowed: false,
        mainWorldAllowed: false,
        multiFrameAllowed: false,
        fileSchemeAllowed: false,
        remoteScriptAllowed: false,
        productNormalTabsAllowed: false,
        requiresHostPermissionOrActiveTab: true,
        teardownRequired: true,
        teardownPolicy:
            "Remove the modeled attachment and any scoped synthetic WebKit adapter objects on navigation, extension disable, profile teardown, or smoke completion."
    )
}

struct ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle:
    Codable,
    Equatable,
    Sendable
{
    var recordAvailable: Bool
    var rootPath: String?
    var copiedResourcePaths: [String]

    static func make(_ record: ChromeMV3GeneratedBundleRecord?) -> Self {
        Self(
            recordAvailable: record != nil,
            rootPath: record?.generatedBundleRootPath,
            copiedResourcePaths: record?.copiedResourcePaths ?? []
        )
    }
}

struct ChromeMV3LocalExperimentalReviewedResourceRecord:
    Codable,
    Equatable,
    Sendable
{
    var resourcePath: String
    var reviewedSHA256: String
    var previousReviewedSHA256: String?
    var reviewReason: String
    var packageName: String
    var packageVersion: String
    var shapeSummary: [String]
}

enum ChromeMV3LocalExperimentalReviewedResourceRegistry {
    static let bitwardenBootstrapAutofill =
        ChromeMV3LocalExperimentalReviewedResourceRecord(
            resourcePath:
                ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
                .bitwardenDetectFillBootstrapFile,
            reviewedSHA256:
                "7d3a88b4b1b8ae882a20ba4decd2df6fc9859c72fe1e7d3a5a60eabb6e7d5d8e",
            previousReviewedSHA256:
                "89b0c2ce4d57431ddbfc8a28992ddf2cd36f2d2bbe64657c89bc164c76fe2b58",
            reviewReason: "reviewedLocalPackageHashUpdated",
            packageName: "Bitwarden",
            packageVersion: "2026.4.1",
            shapeSummary: [
                "resourcePath=content/bootstrap-autofill.js",
                "generated-bundle-contained",
                "package-owned",
                "no function injection",
                "no args",
                "isolated world",
                "top frame",
                "synthetic HTTPS only",
            ]
        )

    static let syntheticReviewedResourceMarker =
        ChromeMV3LocalExperimentalReviewedResourceRecord(
            resourcePath:
                ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
                .syntheticReviewedResourceMarkerFile,
            reviewedSHA256:
                "4e43384cab92e840effc30c2c5e128a1a8a48fb8587cf799349e8c35938f6b9e",
            previousReviewedSHA256: nil,
            reviewReason: "syntheticNonVendorReviewedResourceFixture",
            packageName: "Sumi Synthetic Reviewed Resource Fixture",
            packageVersion: "1.0.0",
            shapeSummary: [
                "resourcePath=content/sumi-reviewed-resource-marker.js",
                "generated-bundle-contained",
                "package-owned",
                "non-vendor synthetic fixture",
                "dummy DOM marker only",
                "no function injection",
                "no args",
                "isolated world",
                "top frame",
                "synthetic HTTPS only",
            ]
        )

    static let records = [
        bitwardenBootstrapAutofill,
        syntheticReviewedResourceMarker,
    ]

    static func record(
        forResourcePath path: String
    ) -> ChromeMV3LocalExperimentalReviewedResourceRecord? {
        records.first { $0.resourcePath == path }
    }
}

struct ChromeMV3LocalExperimentalProgrammaticInjectionResourceResolution:
    Codable,
    Equatable,
    Sendable
{
    var requestedPath: String
    var resolvedPath: String?
    var resolvedFileSystemPath: String?
    var status: ChromeMV3LocalExperimentalProgrammaticInjectionResourceStatus
    var blockers: [ChromeMV3LocalExperimentalProgrammaticInjectionBlocker]
    var diagnostics: [String]
}

struct ChromeMV3LocalExperimentalReviewedResourceAudit:
    Codable,
    Equatable,
    Sendable
{
    var resourcePath: String
    var sourcePackagePath: String?
    var generatedResourcePath: String?
    var sourcePackageSHA256: String?
    var generatedResourceSHA256: String?
    var expectedReviewedSHA256: String
    var previousReviewedSHA256: String?
    var manifestSHA256: String?
    var packageName: String?
    var packageVersion: String?
    var sourceAndGeneratedByteEqual: Bool
    var generatedBundleContained: Bool
    var reviewedResourcePathExact: Bool
    var packageOwned: Bool
    var noRemoteScript: Bool
    var noRuntimeGeneratedJS: Bool
    var noNetworkAuthNativeHostRequirement: Bool
    var compatibleWithIsolatedTopFrameSyntheticHTTPS: Bool
    var shapeEquivalentToReviewedRecord: Bool
    var reviewReason: String
    var shapeBlockers: [String]
    var diagnostics: [String]
}

struct ChromeMV3LocalExperimentalProgrammaticInjectionShapeAudit:
    Codable,
    Equatable,
    Sendable
{
    var apiUsed: String
    var sourceFile: String
    var sourceChunk: String
    var callLocation: String
    var legacyTabsInjectionPresent: Bool
    var internalInjectedScriptBridgePresent: Bool
    var contentScriptDOMInjectionPresent: Bool
    var otherInjectionPresent: Bool
    var packageOwnedFiles: Bool
    var packageOwnedFunction: Bool
    var packageShapeMatched: Bool
    var reviewedBootstrapSHA256: String?
    var reviewedResourceAudit:
        ChromeMV3LocalExperimentalReviewedResourceAudit?
    var tabID: Int
    var frameIDs: [Int]
    var allFrames: Bool
    var world: String
    var files: [String]
    var functionInjected: Bool
    var argumentCount: Int
    var injectImmediately: Bool
    var generatedBundleFilesOnly: Bool
    var syntheticLoginTarget: Bool
    var hostPermissionOrActiveTabAllowed: Bool
    var diagnostics: [String]

    static func notAttempted(reason: String) -> Self {
        Self(
            apiUsed: "notAttempted",
            sourceFile: "notAttempted",
            sourceChunk: "notAttempted",
            callLocation: "notAttempted",
            legacyTabsInjectionPresent: false,
            internalInjectedScriptBridgePresent: false,
            contentScriptDOMInjectionPresent: false,
            otherInjectionPresent: false,
            packageOwnedFiles: false,
            packageOwnedFunction: false,
            packageShapeMatched: false,
            reviewedBootstrapSHA256: nil,
            reviewedResourceAudit: nil,
            tabID: -1,
            frameIDs: [],
            allFrames: false,
            world: "notAttempted",
            files: [],
            functionInjected: false,
            argumentCount: 0,
            injectImmediately: false,
            generatedBundleFilesOnly: true,
            syntheticLoginTarget: false,
            hostPermissionOrActiveTabAllowed: false,
            diagnostics: [reason]
        )
    }
}

struct ChromeMV3LocalExperimentalProgrammaticInjectionRequest {
    var moduleState: ChromeMV3ProfileHostModuleState
    var localExperimentalGateAllowed: Bool
    var extensionEnabled: Bool
    var profileScopedExtensionLoaded: Bool
    var generatedBundle:
        ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle
    var packageRootPath: String?
    var targetURL: String
    var syntheticLoginURL: String
    var tabID: Int
    var frameIDs: [Int]
    var allFrames: Bool
    var world: String
    var files: [String]
    var functionSource: String?
    var arguments: [String]
    var injectImmediately: Bool
    var hostPermissionOrActiveTabAllowed: Bool
}

struct ChromeMV3LocalExperimentalProgrammaticInjectionAttempt:
    Codable,
    Equatable,
    Sendable
{
    var attempted: Bool
    var allowed: Bool
    var policy:
        ChromeMV3LocalExperimentalProgrammaticInjectionPolicy
    var shapeAudit:
        ChromeMV3LocalExperimentalProgrammaticInjectionShapeAudit
    var resourceResolutions:
        [ChromeMV3LocalExperimentalProgrammaticInjectionResourceResolution]
    var blockers: [ChromeMV3LocalExperimentalProgrammaticInjectionBlocker]
    var currentBlocker: String
    var activeInjectionCountAfterAttempt: Int
    var syntheticDOMModelAttachmentRecorded: Bool
    var diagnostics: [String]

    static func notAttempted(reason: String) -> Self {
        Self(
            attempted: false,
            allowed: false,
            policy: .bitwardenDetectFill,
            shapeAudit: .notAttempted(reason: reason),
            resourceResolutions: [],
            blockers: [],
            currentBlocker: "notAttempted",
            activeInjectionCountAfterAttempt: 0,
            syntheticDOMModelAttachmentRecorded: false,
            diagnostics: [reason]
        )
    }
}

enum ChromeMV3LocalExperimentalProgrammaticInjectionTeardownReason:
    String,
    Codable,
    Sendable
{
    case extensionDisable
    case navigation
    case profileTeardown
    case smokeComplete
}

final class ChromeMV3LocalExperimentalProgrammaticInjectionSession {
    private(set) var activeGeneratedBundleFiles: [String] = []
    private(set) var teardownDiagnostics: [String] = []

    var activeInjectionCount: Int {
        activeGeneratedBundleFiles.count
    }

    func attempt(
        _ request: ChromeMV3LocalExperimentalProgrammaticInjectionRequest
    ) -> ChromeMV3LocalExperimentalProgrammaticInjectionAttempt {
        let policy =
            ChromeMV3LocalExperimentalProgrammaticInjectionPolicy
            .bitwardenDetectFill
        let audit =
            ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
            .audit(request)
        var blockers:
            [ChromeMV3LocalExperimentalProgrammaticInjectionBlocker] = []
        if request.moduleState != .enabled {
            blockers.append(.moduleDisabled)
        }
        if request.localExperimentalGateAllowed == false {
            blockers.append(.localExperimentalGateClosed)
        }
        if request.extensionEnabled == false {
            blockers.append(.extensionDisabled)
        }
        if request.profileScopedExtensionLoaded == false {
            blockers.append(.profileScopedExtensionMissing)
        }
        if request.hostPermissionOrActiveTabAllowed == false {
            blockers.append(.hostPermissionBlocked)
        }
        if request.targetURL != request.syntheticLoginURL {
            blockers.append(.targetOutsideSyntheticLogin)
        }
        if URL(string: request.targetURL)?.scheme?.lowercased() != "https" {
            blockers.append(.unsupportedTargetURLScheme)
        }
        if request.frameIDs != [0] || request.allFrames {
            blockers.append(.multiFrameRequired)
        }
        if request.world != "ISOLATED" {
            blockers.append(.mainWorldRequired)
        }
        if request.functionSource?.isEmpty == false {
            blockers.append(.arbitraryFunctionInjectionRequired)
        }
        if request.arguments.isEmpty == false {
            blockers.append(.argumentsBlocked)
        }
        if request.injectImmediately == false {
            blockers.append(.injectImmediatelyRequired)
        }
        if request.files.count != 1
            || request.files.first.map({
                policy.allowedGeneratedBundleFiles.contains($0)
            }) != true
        {
            blockers.append(.unsupportedTargetShape)
        }
        if audit.packageShapeMatched == false {
            blockers.append(.unsupportedTargetShape)
        }
        if audit.reviewedResourceAudit?.shapeEquivalentToReviewedRecord
            == false
        {
            blockers.append(.unsupportedTargetShape)
        }

        let resolutions = request.files.map {
            Self.resolveGeneratedBundleFile(
                $0,
                generatedBundle: request.generatedBundle
            )
        }
        blockers.append(contentsOf: resolutions.flatMap(\.blockers))
        blockers = Array(Set(blockers)).sorted()
        let allowed = blockers.isEmpty
        if allowed {
            activeGeneratedBundleFiles = request.files
        }
        return ChromeMV3LocalExperimentalProgrammaticInjectionAttempt(
            attempted: true,
            allowed: allowed,
            policy: policy,
            shapeAudit: audit,
            resourceResolutions: resolutions,
            blockers: blockers,
            currentBlocker: blockers.first?.rawValue ?? "none",
            activeInjectionCountAfterAttempt: activeInjectionCount,
            syntheticDOMModelAttachmentRecorded: allowed,
            diagnostics: uniqueSortedLocalExperimentalInjection(
                audit.diagnostics
                    + resolutions.flatMap(\.diagnostics)
                    + [
                        allowed
                            ? "Recorded the reviewed generated-bundle bootstrap attachment in the synthetic login DOM model."
                            : "Programmatic injection remained blocked; no synthetic DOM model attachment was recorded.",
                        "No arbitrary JavaScript source, MAIN-world evaluation, multi-frame attachment, file URL, remote script, normal-tab product bridge, native host, auth flow, or network request was enabled.",
                    ]
            )
        )
    }

    func tearDown(
        reason: ChromeMV3LocalExperimentalProgrammaticInjectionTeardownReason
    ) {
        let removed = activeGeneratedBundleFiles.count
        activeGeneratedBundleFiles.removeAll()
        teardownDiagnostics = [
            "Removed \(removed) modeled local experimental programmatic injection attachment(s) for \(reason.rawValue).",
        ]
    }

    static func resolveGeneratedBundleFile(
        _ requestedPath: String,
        generatedBundle:
            ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle,
        fileManager: FileManager = .default
    ) -> ChromeMV3LocalExperimentalProgrammaticInjectionResourceResolution {
        var blockers:
            [ChromeMV3LocalExperimentalProgrammaticInjectionBlocker] = []
        let lowercased = requestedPath.lowercased()
        if ChromeMV3LocalExperimentalReviewedResourceRegistry
            .record(forResourcePath: requestedPath) == nil
        {
            blockers.append(.reviewedGeneratedBundleFileRequired)
        }
        if lowercased.hasPrefix("http://")
            || lowercased.hasPrefix("https://")
        {
            blockers.append(.remoteScriptBlocked)
        }
        if lowercased.hasPrefix("file:") {
            blockers.append(.fileSchemeScriptBlocked)
        }
        guard let normalized = normalizedRelativePath(requestedPath) else {
            blockers.append(.unsafeScriptPath)
            return blockedResolution(
                requestedPath: requestedPath,
                blockers: blockers,
                diagnostic: "Rejected an unsafe programmatic injection resource path."
            )
        }
        guard generatedBundle.recordAvailable else {
            blockers.append(.generatedBundleRecordMissing)
            return blockedResolution(
                requestedPath: requestedPath,
                resolvedPath: normalized,
                blockers: blockers,
                diagnostic: "Generated-bundle metadata record is required."
            )
        }
        guard let rootPath = generatedBundle.rootPath else {
            blockers.append(.generatedBundleRootMissing)
            return blockedResolution(
                requestedPath: requestedPath,
                resolvedPath: normalized,
                blockers: blockers,
                diagnostic: "Generated-bundle root is required."
            )
        }
        guard generatedBundle.copiedResourcePaths.contains(normalized) else {
            blockers.append(.generatedResourceNotCopied)
            return blockedResolution(
                requestedPath: requestedPath,
                resolvedPath: normalized,
                blockers: blockers,
                diagnostic:
                    "Programmatic injection file was not recorded as a copied generated-bundle resource."
            )
        }

        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let unresolvedCandidate = root.appendingPathComponent(normalized)
            .standardizedFileURL
        guard fileManager.fileExists(atPath: unresolvedCandidate.path) else {
            blockers.append(.generatedResourceMissing)
            return blockedResolution(
                requestedPath: requestedPath,
                resolvedPath: normalized,
                blockers: blockers,
                diagnostic: "Copied generated-bundle injection file is missing."
            )
        }
        guard
            let values = try? unresolvedCandidate.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
        else {
            blockers.append(.generatedResourceMissing)
            return blockedResolution(
                requestedPath: requestedPath,
                resolvedPath: normalized,
                blockers: blockers,
                diagnostic: "Copied generated-bundle injection file could not be inspected."
            )
        }
        if values.isSymbolicLink == true {
            blockers.append(.generatedResourceSymbolicLink)
        }
        if values.isRegularFile != true {
            blockers.append(.generatedResourceNotRegularFile)
        }
        let candidate = unresolvedCandidate.resolvingSymlinksInPath()
        if contains(root: root, candidate: candidate) == false {
            blockers.append(.generatedResourceEscapedRoot)
        }
        blockers = Array(Set(blockers)).sorted()
        guard blockers.isEmpty else {
            return blockedResolution(
                requestedPath: requestedPath,
                resolvedPath: normalized,
                blockers: blockers,
                diagnostic:
                    "Generated-bundle injection resource failed regular-file, symlink, or containment validation."
            )
        }
        return ChromeMV3LocalExperimentalProgrammaticInjectionResourceResolution(
            requestedPath: requestedPath,
            resolvedPath: normalized,
            resolvedFileSystemPath: candidate.path,
            status: .copiedGeneratedBundleFile,
            blockers: [],
            diagnostics: [
                "Resolved a package-owned copied generated-bundle file for the reviewed local experimental injection shape.",
            ]
        )
    }

    private static func blockedResolution(
        requestedPath: String,
        resolvedPath: String? = nil,
        blockers: [ChromeMV3LocalExperimentalProgrammaticInjectionBlocker],
        diagnostic: String
    ) -> ChromeMV3LocalExperimentalProgrammaticInjectionResourceResolution {
        ChromeMV3LocalExperimentalProgrammaticInjectionResourceResolution(
            requestedPath: requestedPath,
            resolvedPath: resolvedPath,
            resolvedFileSystemPath: nil,
            status: .blocked,
            blockers: Array(Set(blockers)).sorted(),
            diagnostics: [diagnostic]
        )
    }

    private static func normalizedRelativePath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        guard decoded.isEmpty == false,
              decoded.hasPrefix("/") == false,
              decoded.hasPrefix("~") == false,
              decoded.contains("\\") == false,
              decoded.contains("\0") == false,
              decoded.contains("?") == false,
              decoded.contains("#") == false,
              decoded.contains("*") == false,
              URLComponents(string: decoded)?.scheme == nil
        else { return nil }
        let components = decoded.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard components.isEmpty == false,
              components.allSatisfy({
                  $0.isEmpty == false && $0 != "." && $0 != ".."
              })
        else { return nil }
        return components.map(String.init).joined(separator: "/")
    }

    private static func contains(root: URL, candidate: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath
            || candidatePath.hasPrefix(rootPath + "/")
    }
}

enum ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog {
    static let bitwardenDetectFillBootstrapFile =
        "content/bootstrap-autofill.js"
    static let bitwardenTriggerFile =
        "content/trigger-autofill-script-injection.js"
    static let syntheticReviewedResourceMarkerFile =
        "content/sumi-reviewed-resource-marker.js"

    static var reviewedGeneratedBundleResourceAllowlist: [String] {
        ChromeMV3LocalExperimentalReviewedResourceRegistry.records
            .map(\.resourcePath)
            .sorted()
    }

    static func reviewedGeneratedBundleResourcePaths(
        manifest: [String: Any],
        originalRootURL: URL
    ) -> [String] {
        var paths: [String] = []
        if exactBitwardenDetectFillShapePresent(
            manifest: manifest,
            rootURL: originalRootURL
        ) {
            paths.append(bitwardenDetectFillBootstrapFile)
        }
        if exactSyntheticReviewedResourceMarkerShapePresent(
            manifest: manifest,
            rootURL: originalRootURL
        ) {
            paths.append(syntheticReviewedResourceMarkerFile)
        }
        return Array(Set(paths)).sorted()
    }

    static func audit(
        _ request: ChromeMV3LocalExperimentalProgrammaticInjectionRequest
    ) -> ChromeMV3LocalExperimentalProgrammaticInjectionShapeAudit {
        guard request.files == [bitwardenDetectFillBootstrapFile] else {
            if request.files == [syntheticReviewedResourceMarkerFile] {
                return syntheticReviewedResourceMarkerAudit(request)
            }
            return unsupportedReviewedResourceAudit(request)
        }
        let root = request.packageRootPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let reviewedRecord =
            ChromeMV3LocalExperimentalReviewedResourceRegistry
            .bitwardenBootstrapAutofill
        let background = root.flatMap {
            read($0.appendingPathComponent("background.js"))
        } ?? ""
        let contentMessageHandler = root.flatMap {
            read($0.appendingPathComponent("content/content-message-handler.js"))
        } ?? ""
        let sourceBootstrapURL = root?
            .appendingPathComponent(bitwardenDetectFillBootstrapFile)
            .standardizedFileURL
        let sourceBootstrapData = sourceBootstrapURL.flatMap { readData($0) }
        let bootstrap = sourceBootstrapData.flatMap {
            String(data: $0, encoding: .utf8)
        } ?? ""
        let generatedRootURL = request.generatedBundle.rootPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .standardizedFileURL
        }
        let generatedBootstrapURL = generatedRootURL?
            .appendingPathComponent(bitwardenDetectFillBootstrapFile)
            .standardizedFileURL
        let generatedBundleContained =
            request.generatedBundle.copiedResourcePaths.contains(
                bitwardenDetectFillBootstrapFile
            )
                && generatedRootURL.map { root in
                    generatedBootstrapURL.map {
                        contains(root: root, candidate: $0)
                    } ?? false
                } == true
        let generatedBootstrapData =
            generatedBundleContained
                ? generatedBootstrapURL.flatMap { readData($0) }
                : nil
        let sourceBootstrapSHA256 = sourceBootstrapData.map(sha256)
        let generatedBootstrapSHA256 = generatedBootstrapData.map(sha256)
        let sourceAndGeneratedByteEqual =
            sourceBootstrapData != nil
                && generatedBootstrapData != nil
                && sourceBootstrapData == generatedBootstrapData
        let manifestURL = root?.appendingPathComponent("manifest.json")
        let manifestData = manifestURL.flatMap { readData($0) }
        let manifestMetadata = metadata(fromManifestData: manifestData)
        let packageOwnedFiles =
            request.files == [bitwardenDetectFillBootstrapFile]
            && bootstrap.isEmpty == false
        let basePackageShapeMatched =
            background.contains("chrome.scripting.executeScript")
            && background.contains("triggerAutofillScriptInjection")
            && background.contains("bootstrap-autofill.js")
            && bootstrap.contains("collectPageDetailsImmediately")
            && bootstrap.contains("fillForm")
        let reviewedResourcePathExact =
            request.files == [bitwardenDetectFillBootstrapFile]
        let noRemoteScript =
            bootstrap.contains("document.createElement(\"script") == false
                && bootstrap.contains("document.createElement('script") == false
        let noRuntimeGeneratedJS =
            bootstrap.contains("eval(") == false
                && bootstrap.contains("new Function(") == false
                && bootstrap.contains("import(") == false
        let noNetworkAuthNativeHostRequirement =
            bootstrap.contains("fetch(") == false
                && bootstrap.contains("XMLHttpRequest") == false
                && bootstrap.contains("WebSocket") == false
                && bootstrap.contains("connect" + "Native") == false
                && bootstrap.contains("send" + "NativeMessage") == false
        let compatibleWithIsolatedTopFrameSyntheticHTTPS =
            request.world == "ISOLATED"
                && request.frameIDs == [0]
                && request.allFrames == false
                && (request.functionSource?.isEmpty ?? true)
                && request.arguments.isEmpty
                && URL(string: request.targetURL)?.scheme?.lowercased()
                    == "https"
                && request.targetURL == request.syntheticLoginURL
        var shapeBlockers: [String] = []
        if reviewedResourcePathExact == false {
            shapeBlockers.append("reviewedResourcePathChanged")
        }
        if generatedBundleContained == false {
            shapeBlockers.append("generatedBundleContainmentMissing")
        }
        if sourceAndGeneratedByteEqual == false {
            shapeBlockers.append("sourceGeneratedCopyMismatch")
        }
        if basePackageShapeMatched == false {
            shapeBlockers.append("reviewedShapeChanged")
        }
        if noRemoteScript == false {
            shapeBlockers.append("remoteScriptInjectionDetected")
        }
        if noRuntimeGeneratedJS == false {
            shapeBlockers.append("runtimeGeneratedJavaScriptDetected")
        }
        if noNetworkAuthNativeHostRequirement == false {
            shapeBlockers.append("networkAuthOrNativeHostRequirementDetected")
        }
        if compatibleWithIsolatedTopFrameSyntheticHTTPS == false {
            shapeBlockers.append("isolatedTopFrameSyntheticHTTPSShapeChanged")
        }
        let shapeEquivalentToReviewedRecord = shapeBlockers.isEmpty
        let reviewedResourceAudit =
            ChromeMV3LocalExperimentalReviewedResourceAudit(
                resourcePath: bitwardenDetectFillBootstrapFile,
                sourcePackagePath: sourceBootstrapURL?.path,
                generatedResourcePath: generatedBootstrapURL?.path,
                sourcePackageSHA256: sourceBootstrapSHA256,
                generatedResourceSHA256: generatedBootstrapSHA256,
                expectedReviewedSHA256: reviewedRecord.reviewedSHA256,
                previousReviewedSHA256:
                    reviewedRecord.previousReviewedSHA256,
                manifestSHA256: manifestData.map(sha256),
                packageName: manifestMetadata.name,
                packageVersion: manifestMetadata.version,
                sourceAndGeneratedByteEqual: sourceAndGeneratedByteEqual,
                generatedBundleContained: generatedBundleContained,
                reviewedResourcePathExact: reviewedResourcePathExact,
                packageOwned: packageOwnedFiles && generatedBundleContained,
                noRemoteScript: noRemoteScript,
                noRuntimeGeneratedJS: noRuntimeGeneratedJS,
                noNetworkAuthNativeHostRequirement:
                    noNetworkAuthNativeHostRequirement,
                compatibleWithIsolatedTopFrameSyntheticHTTPS:
                    compatibleWithIsolatedTopFrameSyntheticHTTPS,
                shapeEquivalentToReviewedRecord:
                    shapeEquivalentToReviewedRecord,
                reviewReason: reviewedRecord.reviewReason,
                shapeBlockers: shapeBlockers.sorted(),
                diagnostics: [
                    "Reviewed resource audit reason: \(reviewedRecord.reviewReason).",
                    "Reviewed resource expected SHA-256: \(reviewedRecord.reviewedSHA256).",
                    "Previous reviewed SHA-256: \(reviewedRecord.previousReviewedSHA256 ?? "none").",
                    "Source package SHA-256: \(sourceBootstrapSHA256 ?? "missing").",
                    "Generated resource SHA-256: \(generatedBootstrapSHA256 ?? "missing").",
                    "Source/generated byte-equal: \(sourceAndGeneratedByteEqual).",
                    "Package metadata: name=\(manifestMetadata.name ?? "unknown"), version=\(manifestMetadata.version ?? "unknown").",
                    shapeEquivalentToReviewedRecord
                        ? "Reviewed resource shape is equivalent to the local experimental reviewed record."
                        : "Reviewed resource shape is blocked pending review: \(shapeBlockers.sorted().joined(separator: ", ")).",
                ]
            )
        return ChromeMV3LocalExperimentalProgrammaticInjectionShapeAudit(
            apiUsed: "chrome.scripting.executeScript",
            sourceFile: "background.js",
            sourceChunk:
                "runtime.background triggerAutofillScriptInjection -> AutofillService.injectAutofillScripts -> BrowserApi.executeScriptInTab",
            callLocation:
                "service-worker-triggered package-owned file injection for content/bootstrap-autofill.js",
            legacyTabsInjectionPresent:
                background.contains("chrome.tabs.executeScript"),
            internalInjectedScriptBridgePresent:
                contentMessageHandler.contains("autofill-injected-script-port")
                    || bootstrap.contains("autofill-injected-script-port"),
            contentScriptDOMInjectionPresent:
                bootstrap.contains("collectPageDetailsImmediately")
                    && bootstrap.contains("fillForm"),
            otherInjectionPresent: false,
            packageOwnedFiles: packageOwnedFiles,
            packageOwnedFunction: false,
            packageShapeMatched: basePackageShapeMatched,
            reviewedBootstrapSHA256: generatedBootstrapSHA256,
            reviewedResourceAudit: reviewedResourceAudit,
            tabID: request.tabID,
            frameIDs: request.frameIDs,
            allFrames: request.allFrames,
            world: request.world,
            files: request.files,
            functionInjected: request.functionSource?.isEmpty == false,
            argumentCount: request.arguments.count,
            injectImmediately: request.injectImmediately,
            generatedBundleFilesOnly: true,
            syntheticLoginTarget:
                request.targetURL == request.syntheticLoginURL,
            hostPermissionOrActiveTabAllowed:
                request.hostPermissionOrActiveTabAllowed,
            diagnostics: [
                basePackageShapeMatched
                    ? "Matched the reviewed local Bitwarden worker-triggered bootstrap injection shape."
                    : "Did not match the reviewed local Bitwarden worker-triggered bootstrap injection shape.",
                "Reviewed resource source/generated equality recorded as \(sourceAndGeneratedByteEqual).",
                "Reviewed resource audit blockers: \(shapeBlockers.sorted().joined(separator: ", ")).",
            ]
        )
    }

    private static func syntheticReviewedResourceMarkerAudit(
        _ request: ChromeMV3LocalExperimentalProgrammaticInjectionRequest
    ) -> ChromeMV3LocalExperimentalProgrammaticInjectionShapeAudit {
        let root = request.packageRootPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let reviewedRecord =
            ChromeMV3LocalExperimentalReviewedResourceRegistry
            .syntheticReviewedResourceMarker
        let background = root.flatMap {
            read($0.appendingPathComponent("background.js"))
        } ?? ""
        let sourceURL = root?
            .appendingPathComponent(syntheticReviewedResourceMarkerFile)
            .standardizedFileURL
        let sourceData = sourceURL.flatMap { readData($0) }
        let source = sourceData.flatMap {
            String(data: $0, encoding: .utf8)
        } ?? ""
        let generatedRootURL = request.generatedBundle.rootPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .standardizedFileURL
        }
        let generatedURL = generatedRootURL?
            .appendingPathComponent(syntheticReviewedResourceMarkerFile)
            .standardizedFileURL
        let generatedBundleContained =
            request.generatedBundle.copiedResourcePaths.contains(
                syntheticReviewedResourceMarkerFile
            )
                && generatedRootURL.map { root in
                    generatedURL.map {
                        contains(root: root, candidate: $0)
                    } ?? false
                } == true
        let generatedData =
            generatedBundleContained
                ? generatedURL.flatMap { readData($0) }
                : nil
        let sourceSHA256 = sourceData.map(sha256)
        let generatedSHA256 = generatedData.map(sha256)
        let sourceAndGeneratedByteEqual =
            sourceData != nil
                && generatedData != nil
                && sourceData == generatedData
        let manifestURL = root?.appendingPathComponent("manifest.json")
        let manifestData = manifestURL.flatMap { readData($0) }
        let manifestMetadata = metadata(fromManifestData: manifestData)
        let reviewedResourcePathExact =
            request.files == [syntheticReviewedResourceMarkerFile]
        let packageOwnedFiles =
            reviewedResourcePathExact && source.isEmpty == false
        let basePackageShapeMatched =
            background.contains("chrome.scripting.executeScript")
                && background.contains(syntheticReviewedResourceMarkerFile)
                && source.contains("__sumiSyntheticReviewedResourceMarker")
                && source.contains("__sumiSyntheticReviewedResourceDiagnostic")
                && source.contains("sumi-login-email")
                && source.contains("sumi-login-password")
        let noRemoteScript =
            source.contains("document.createElement(\"script") == false
                && source.contains("document.createElement('script") == false
        let noRuntimeGeneratedJS =
            source.contains("eval(") == false
                && source.contains("new Function(") == false
                && source.contains("import(") == false
        let noNetworkAuthNativeHostRequirement =
            source.contains("fetch(") == false
                && source.contains("XMLHttpRequest") == false
                && source.contains("WebSocket") == false
                && source.contains("connect" + "Native") == false
                && source.contains("send" + "NativeMessage") == false
        let compatibleWithIsolatedTopFrameSyntheticHTTPS =
            request.world == "ISOLATED"
                && request.frameIDs == [0]
                && request.allFrames == false
                && (request.functionSource?.isEmpty ?? true)
                && request.arguments.isEmpty
                && URL(string: request.targetURL)?.scheme?.lowercased()
                    == "https"
                && request.targetURL == request.syntheticLoginURL
        var shapeBlockers: [String] = []
        if reviewedResourcePathExact == false {
            shapeBlockers.append("reviewedResourcePathChanged")
        }
        if generatedBundleContained == false {
            shapeBlockers.append("generatedBundleContainmentMissing")
        }
        if sourceAndGeneratedByteEqual == false {
            shapeBlockers.append("sourceGeneratedCopyMismatch")
        }
        if basePackageShapeMatched == false {
            shapeBlockers.append("reviewedShapeChanged")
        }
        if noRemoteScript == false {
            shapeBlockers.append("remoteScriptInjectionDetected")
        }
        if noRuntimeGeneratedJS == false {
            shapeBlockers.append("runtimeGeneratedJavaScriptDetected")
        }
        if noNetworkAuthNativeHostRequirement == false {
            shapeBlockers.append("networkAuthOrNativeHostRequirementDetected")
        }
        if compatibleWithIsolatedTopFrameSyntheticHTTPS == false {
            shapeBlockers.append("isolatedTopFrameSyntheticHTTPSShapeChanged")
        }
        let shapeEquivalentToReviewedRecord = shapeBlockers.isEmpty
        let reviewedResourceAudit =
            ChromeMV3LocalExperimentalReviewedResourceAudit(
                resourcePath: syntheticReviewedResourceMarkerFile,
                sourcePackagePath: sourceURL?.path,
                generatedResourcePath: generatedURL?.path,
                sourcePackageSHA256: sourceSHA256,
                generatedResourceSHA256: generatedSHA256,
                expectedReviewedSHA256: reviewedRecord.reviewedSHA256,
                previousReviewedSHA256:
                    reviewedRecord.previousReviewedSHA256,
                manifestSHA256: manifestData.map(sha256),
                packageName: manifestMetadata.name,
                packageVersion: manifestMetadata.version,
                sourceAndGeneratedByteEqual: sourceAndGeneratedByteEqual,
                generatedBundleContained: generatedBundleContained,
                reviewedResourcePathExact: reviewedResourcePathExact,
                packageOwned: packageOwnedFiles && generatedBundleContained,
                noRemoteScript: noRemoteScript,
                noRuntimeGeneratedJS: noRuntimeGeneratedJS,
                noNetworkAuthNativeHostRequirement:
                    noNetworkAuthNativeHostRequirement,
                compatibleWithIsolatedTopFrameSyntheticHTTPS:
                    compatibleWithIsolatedTopFrameSyntheticHTTPS,
                shapeEquivalentToReviewedRecord:
                    shapeEquivalentToReviewedRecord,
                reviewReason: reviewedRecord.reviewReason,
                shapeBlockers: shapeBlockers.sorted(),
                diagnostics: [
                    "Reviewed resource audit reason: \(reviewedRecord.reviewReason).",
                    "Reviewed resource expected SHA-256: \(reviewedRecord.reviewedSHA256).",
                    "Previous reviewed SHA-256: \(reviewedRecord.previousReviewedSHA256 ?? "none").",
                    "Source package SHA-256: \(sourceSHA256 ?? "missing").",
                    "Generated resource SHA-256: \(generatedSHA256 ?? "missing").",
                    "Source/generated byte-equal: \(sourceAndGeneratedByteEqual).",
                    "Package metadata: name=\(manifestMetadata.name ?? "unknown"), version=\(manifestMetadata.version ?? "unknown").",
                    shapeEquivalentToReviewedRecord
                        ? "Synthetic reviewed resource shape is equivalent to the local experimental reviewed record."
                        : "Synthetic reviewed resource shape is blocked pending review: \(shapeBlockers.sorted().joined(separator: ", ")).",
                ]
            )
        return ChromeMV3LocalExperimentalProgrammaticInjectionShapeAudit(
            apiUsed: "chrome.scripting.executeScript",
            sourceFile: "background.js",
            sourceChunk:
                "runtime.background synthetic reviewed-resource diagnostic marker file",
            callLocation:
                "service-worker-triggered package-owned file injection for \(syntheticReviewedResourceMarkerFile)",
            legacyTabsInjectionPresent:
                background.contains("chrome.tabs.executeScript"),
            internalInjectedScriptBridgePresent: false,
            contentScriptDOMInjectionPresent:
                source.contains("__sumiSyntheticReviewedResourceDiagnostic"),
            otherInjectionPresent: false,
            packageOwnedFiles: packageOwnedFiles,
            packageOwnedFunction: false,
            packageShapeMatched: basePackageShapeMatched,
            reviewedBootstrapSHA256: generatedSHA256,
            reviewedResourceAudit: reviewedResourceAudit,
            tabID: request.tabID,
            frameIDs: request.frameIDs,
            allFrames: request.allFrames,
            world: request.world,
            files: request.files,
            functionInjected: request.functionSource?.isEmpty == false,
            argumentCount: request.arguments.count,
            injectImmediately: request.injectImmediately,
            generatedBundleFilesOnly: true,
            syntheticLoginTarget:
                request.targetURL == request.syntheticLoginURL,
            hostPermissionOrActiveTabAllowed:
                request.hostPermissionOrActiveTabAllowed,
            diagnostics: [
                basePackageShapeMatched
                    ? "Matched the reviewed synthetic non-vendor marker resource shape."
                    : "Did not match the reviewed synthetic non-vendor marker resource shape.",
                "Reviewed resource source/generated equality recorded as \(sourceAndGeneratedByteEqual).",
                "Reviewed resource audit blockers: \(shapeBlockers.sorted().joined(separator: ", ")).",
            ]
        )
    }

    private static func unsupportedReviewedResourceAudit(
        _ request: ChromeMV3LocalExperimentalProgrammaticInjectionRequest
    ) -> ChromeMV3LocalExperimentalProgrammaticInjectionShapeAudit {
        ChromeMV3LocalExperimentalProgrammaticInjectionShapeAudit(
            apiUsed: "unsupportedReviewedResource",
            sourceFile: "unsupportedReviewedResource",
            sourceChunk: "unsupportedReviewedResource",
            callLocation: "unsupportedReviewedResource",
            legacyTabsInjectionPresent: false,
            internalInjectedScriptBridgePresent: false,
            contentScriptDOMInjectionPresent: false,
            otherInjectionPresent: false,
            packageOwnedFiles: false,
            packageOwnedFunction: false,
            packageShapeMatched: false,
            reviewedBootstrapSHA256: nil,
            reviewedResourceAudit: nil,
            tabID: request.tabID,
            frameIDs: request.frameIDs,
            allFrames: request.allFrames,
            world: request.world,
            files: request.files,
            functionInjected: request.functionSource?.isEmpty == false,
            argumentCount: request.arguments.count,
            injectImmediately: request.injectImmediately,
            generatedBundleFilesOnly: true,
            syntheticLoginTarget:
                request.targetURL == request.syntheticLoginURL,
            hostPermissionOrActiveTabAllowed:
                request.hostPermissionOrActiveTabAllowed,
            diagnostics: [
                "Requested generated-bundle file is not registered as a reviewed diagnostic resource.",
            ]
        )
    }

    private static func exactBitwardenDetectFillShapePresent(
        manifest: [String: Any],
        rootURL: URL
    ) -> Bool {
        guard
            let background = manifest["background"] as? [String: Any],
            background["service_worker"] as? String == "background.js",
            let contentScripts = manifest["content_scripts"] as? [[String: Any]],
            contentScripts.contains(where: {
                ($0["js"] as? [String])?.contains(bitwardenTriggerFile) == true
            }),
            let trigger =
                read(rootURL.appendingPathComponent(bitwardenTriggerFile)),
            trigger.contains("triggerAutofillScriptInjection"),
            let worker = read(rootURL.appendingPathComponent("background.js")),
            worker.contains("chrome.scripting.executeScript"),
            worker.contains("triggerAutofillScriptInjection"),
            worker.contains("bootstrap-autofill.js"),
            let bootstrap =
                read(rootURL.appendingPathComponent(bitwardenDetectFillBootstrapFile)),
            bootstrap.contains("collectPageDetailsImmediately"),
            bootstrap.contains("fillForm")
        else { return false }
        return true
    }

    private static func exactSyntheticReviewedResourceMarkerShapePresent(
        manifest: [String: Any],
        rootURL: URL
    ) -> Bool {
        guard
            let background = manifest["background"] as? [String: Any],
            background["service_worker"] as? String == "background.js",
            let worker = read(rootURL.appendingPathComponent("background.js")),
            worker.contains("chrome.scripting.executeScript"),
            worker.contains(syntheticReviewedResourceMarkerFile),
            let marker =
                read(rootURL.appendingPathComponent(syntheticReviewedResourceMarkerFile)),
            marker.contains("__sumiSyntheticReviewedResourceMarker"),
            marker.contains("__sumiSyntheticReviewedResourceDiagnostic"),
            marker.contains("sumi-login-email"),
            marker.contains("sumi-login-password")
        else { return false }
        return true
    }

    private static func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private static func readData(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    private static func sha256(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func metadata(
        fromManifestData data: Data?
    ) -> (name: String?, version: String?) {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else { return (nil, nil) }
        return (
            object["short_name"] as? String
                ?? object["name"] as? String,
            object["version"] as? String
        )
    }

    private static func contains(root: URL, candidate: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath
            || candidatePath.hasPrefix(rootPath + "/")
    }
}

private func uniqueSortedLocalExperimentalInjection(
    _ values: [String]
) -> [String] {
    Array(Set(values)).sorted()
}
