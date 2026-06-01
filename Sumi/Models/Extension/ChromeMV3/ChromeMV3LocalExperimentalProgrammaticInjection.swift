//
//  ChromeMV3LocalExperimentalProgrammaticInjection.swift
//  Sumi
//
//  Narrow local-only modeled programmatic injection for the reviewed Bitwarden
//  detect/fill bootstrap shape. This does not expose arbitrary script execution.
//

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
    var teardownPolicy: String

    static let bitwardenDetectFill = Self(
        programmaticInjectionAvailableInLocalExperimentalGate: true,
        programmaticInjectionAvailableByDefault: false,
        generatedBundleFilesOnly: true,
        allowedGeneratedBundleFiles: [
            ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
                .bitwardenDetectFillBootstrapFile,
        ],
        arbitraryFunctionInjectionAllowed: false,
        argumentsAllowed: false,
        mainWorldAllowed: false,
        multiFrameAllowed: false,
        fileSchemeAllowed: false,
        remoteScriptAllowed: false,
        productNormalTabsAllowed: false,
        requiresHostPermissionOrActiveTab: true,
        teardownPolicy:
            "Remove the modeled attachment on navigation, extension disable, profile teardown, or smoke completion."
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

struct ChromeMV3LocalExperimentalProgrammaticInjectionResourceResolution:
    Codable,
    Equatable,
    Sendable
{
    var requestedPath: String
    var resolvedPath: String?
    var status: ChromeMV3LocalExperimentalProgrammaticInjectionResourceStatus
    var blockers: [ChromeMV3LocalExperimentalProgrammaticInjectionBlocker]
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
        if request.files != policy.allowedGeneratedBundleFiles {
            blockers.append(.unsupportedTargetShape)
        }
        if audit.packageShapeMatched == false {
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

    static func reviewedGeneratedBundleResourcePaths(
        manifest: [String: Any],
        originalRootURL: URL
    ) -> [String] {
        guard exactBitwardenDetectFillShapePresent(
            manifest: manifest,
            rootURL: originalRootURL
        ) else { return [] }
        return [bitwardenDetectFillBootstrapFile]
    }

    static func audit(
        _ request: ChromeMV3LocalExperimentalProgrammaticInjectionRequest
    ) -> ChromeMV3LocalExperimentalProgrammaticInjectionShapeAudit {
        let root = request.packageRootPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let background = root.flatMap {
            read($0.appendingPathComponent("background.js"))
        } ?? ""
        let contentMessageHandler = root.flatMap {
            read($0.appendingPathComponent("content/content-message-handler.js"))
        } ?? ""
        let bootstrap = root.flatMap {
            read($0.appendingPathComponent(bitwardenDetectFillBootstrapFile))
        } ?? ""
        let packageOwnedFiles =
            request.files == [bitwardenDetectFillBootstrapFile]
            && bootstrap.isEmpty == false
        let packageShapeMatched =
            background.contains("chrome.scripting.executeScript")
            && background.contains("triggerAutofillScriptInjection")
            && background.contains("bootstrap-autofill.js")
            && bootstrap.contains("collectPageDetailsImmediately")
            && bootstrap.contains("fillForm")
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
            packageShapeMatched: packageShapeMatched,
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
                packageShapeMatched
                    ? "Matched the reviewed local Bitwarden worker-triggered bootstrap injection shape."
                    : "Did not match the reviewed local Bitwarden worker-triggered bootstrap injection shape.",
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

    private static func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}

private func uniqueSortedLocalExperimentalInjection(
    _ values: [String]
) -> [String] {
    Array(Set(values)).sorted()
}
