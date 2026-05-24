//
//  ChromeMV3WebKitObjectAcceptanceReport.swift
//  Sumi
//
//  Deterministic static diagnostics for WKWebExtension object acceptance.
//  This layer reads generated-rewritten bundle files and classifies the
//  object probe result only; it does not create contexts, load controllers,
//  register scripts, launch native messaging, or execute extension code.
//

import CryptoKit
import Foundation

enum ChromeMV3WebKitObjectAcceptanceCategory:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notAttempted
    case blockedByGate
    case objectCreated
    case missingGeneratedBundle
    case missingManifest
    case manifestJSONInvalid
    case manifestRejectedByWebKit
    case missingReferencedResource
    case unsupportedManifestKey
    case unsupportedBackgroundShape
    case serviceWorkerWrapperRejected
    case contentScriptResourceRejected
    case extensionPageResourceRejected
    case webAccessibleResourceRejected
    case declarativeNetRequestResourceRejected
    case unknownWebKitError
    case runtimeContextStillBlocked

    static func < (
        lhs: ChromeMV3WebKitObjectAcceptanceCategory,
        rhs: ChromeMV3WebKitObjectAcceptanceCategory
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3WebKitObjectAcceptanceSeverity:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case info
    case warning
    case objectBlocking
    case contextBlocking
    case runtimeBlocking

    static func < (
        lhs: ChromeMV3WebKitObjectAcceptanceSeverity,
        rhs: ChromeMV3WebKitObjectAcceptanceSeverity
    ) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .info:
            return 0
        case .warning:
            return 1
        case .objectBlocking:
            return 2
        case .contextBlocking:
            return 3
        case .runtimeBlocking:
            return 4
        }
    }
}

enum ChromeMV3WebKitObjectAcceptanceSource:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case webKitError
    case sumiStaticValidation
    case generatedBundleInspection
    case capabilityClassifier
    case unknown

    static func < (
        lhs: ChromeMV3WebKitObjectAcceptanceSource,
        rhs: ChromeMV3WebKitObjectAcceptanceSource
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3WebKitObjectAcceptanceFinding:
    Codable,
    Equatable,
    Sendable
{
    var category: ChromeMV3WebKitObjectAcceptanceCategory
    var severity: ChromeMV3WebKitObjectAcceptanceSeverity
    var source: ChromeMV3WebKitObjectAcceptanceSource
    var message: String
    var relatedPaths: [String]
    var remediationHint: String
    var generatedBundleRewriteCanFix: Bool
    var futureRuntimeContextLayerNeeded: Bool
}

struct ChromeMV3WebKitObjectAcceptanceStaticInspection:
    Codable,
    Equatable,
    Sendable
{
    var rewrittenBundleRootPath: String
    var generatedBundleExists: Bool
    var manifestPath: String
    var manifestExists: Bool
    var manifestJSONValid: Bool
    var manifestVersion: Int?
    var inspectedResourcePaths: [String]
    var missingResourcePaths: [String]
    var unsafeResourcePaths: [String]
    var symlinkResourcePaths: [String]
    var installReportUnsupportedAPIs: [ChromeMV3API]
    var installReportDeferredAPIs: [ChromeMV3API]
    var findings: [ChromeMV3WebKitObjectAcceptanceFinding]
}

struct ChromeMV3WebKitObjectAcceptanceDocumentationSource:
    Codable,
    Equatable,
    Sendable
{
    var kind: String
    var title: String
    var url: String?
    var note: String
}

struct ChromeMV3WebKitObjectAcceptanceReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var generatedBundleID: String?
    var generatedBundleHash: String?
    var rewrittenBundleRootPath: String
    var generatedBundleExists: Bool
    var probeAttempted: Bool
    var probeResult: ChromeMV3ExtensionObjectProbeState
    var objectAcceptedByWebKit: Bool
    var webKitErrors: [ChromeMV3ExtensionObjectProbeErrorDiagnostic]
    var webKitWarnings: [ChromeMV3ExtensionObjectProbeErrorDiagnostic]
    var staticInspection: ChromeMV3WebKitObjectAcceptanceStaticInspection
    var classificationFindings: [ChromeMV3WebKitObjectAcceptanceFinding]
    var classificationCategories: [ChromeMV3WebKitObjectAcceptanceCategory]
    var objectAcceptanceLikelyFixableByGenerator: Bool
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var blockers: [String]
    var remediationHints: [String]
    var remainingRuntimeContextBlockers: [String]
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
}

enum ChromeMV3WebKitObjectAcceptanceReportWriter {
    static let reportFileName = "webkit-object-acceptance-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3WebKitObjectAcceptanceReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3WebKitObjectAcceptanceReport {
        guard directoryExists(rootURL.standardizedFileURL) else {
            return report
        }
        try ChromeMV3DeterministicJSON.write(
            report,
            to: rootURL.standardizedFileURL
                .appendingPathComponent(Self.reportFileName)
        )
        return report
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

enum ChromeMV3WebKitObjectAcceptanceReportGenerator {
    static func makeReport(
        candidate: ChromeMV3RewrittenVariantCandidate,
        gateDecision: ChromeMV3ExtensionObjectProbeGateDecision,
        probeDiagnostics: ChromeMV3ExtensionObjectProbeDiagnostics?,
        runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?
    ) -> ChromeMV3WebKitObjectAcceptanceReport {
        let rootPath = gateDecision.input.resourceBaseURLPath
            ?? candidate.rewrittenVariantRootPath
        let rootURL = URL(
            fileURLWithPath: rootPath,
            isDirectory: true
        ).standardizedFileURL
        let staticInspection =
            ChromeMV3WebKitObjectAcceptanceInspector().inspect(
                rewrittenBundleRootURL: rootURL,
                runtimeLoadabilityReport: runtimeLoadabilityReport
            )
        let diagnostics = probeDiagnostics ?? diagnosticsBeforeProbe(
            gateDecision: gateDecision
        )
        let classificationFindings =
            ChromeMV3WebKitObjectProbeResultClassifier.classify(
                probeDiagnostics: diagnostics,
                staticInspection: staticInspection,
                runtimeLoadabilityReport: runtimeLoadabilityReport
            )
        let categories = uniqueSorted(classificationFindings.map(\.category))
        let objectBlockingFindings = classificationFindings.filter {
            $0.severity == .objectBlocking
        }
        let contextRuntimeFindings = classificationFindings.filter {
            $0.severity == .contextBlocking || $0.severity == .runtimeBlocking
        }
        let webKitErrors = [diagnostics.error].compactMap { $0 }
        let webKitWarnings = diagnostics.webExtensionParseErrors

        return ChromeMV3WebKitObjectAcceptanceReport(
            schemaVersion: 1,
            id: reportID(
                candidate: candidate,
                rootPath: rootURL.path,
                staticInspection: staticInspection
            ),
            reportFileName: ChromeMV3WebKitObjectAcceptanceReportWriter
                .reportFileName,
            generatedBundleID: gateDecision.input.generatedBundleID
                ?? candidate.id,
            generatedBundleHash: gateDecision.input.generatedBundleHash
                ?? candidate.rewrittenManifestSHA256,
            rewrittenBundleRootPath: rootURL.path,
            generatedBundleExists: staticInspection.generatedBundleExists,
            probeAttempted: diagnostics.attempted,
            probeResult: diagnostics.state,
            objectAcceptedByWebKit: diagnostics.extensionObjectCreated,
            webKitErrors: webKitErrors,
            webKitWarnings: webKitWarnings,
            staticInspection: staticInspection,
            classificationFindings: classificationFindings,
            classificationCategories: categories,
            objectAcceptanceLikelyFixableByGenerator:
                objectBlockingFindings.contains {
                    $0.generatedBundleRewriteCanFix
                }
                && categories.contains(.unknownWebKitError) == false,
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            blockers: uniqueSorted(
                (objectBlockingFindings + contextRuntimeFindings).map {
                    $0.message
                }
            ),
            remediationHints: uniqueSorted(
                classificationFindings.map(\.remediationHint)
            ),
            remainingRuntimeContextBlockers: remainingRuntimeContextBlockers(
                runtimeLoadabilityReport: runtimeLoadabilityReport,
                findings: classificationFindings
            ),
            documentationSources: documentationSources()
        )
    }

    private static func diagnosticsBeforeProbe(
        gateDecision: ChromeMV3ExtensionObjectProbeGateDecision
    ) -> ChromeMV3ExtensionObjectProbeDiagnostics {
        gateDecision.canCreateExtensionObjectNow
            ? .notAttempted(gateDecision: gateDecision)
            : .blocked(gateDecision: gateDecision)
    }

    private static func reportID(
        candidate: ChromeMV3RewrittenVariantCandidate,
        rootPath: String,
        staticInspection: ChromeMV3WebKitObjectAcceptanceStaticInspection
    ) -> String {
        let seed = [
            candidate.id,
            candidate.rewrittenManifestSHA256 ?? "missing-manifest-hash",
            staticInspection.manifestVersion.map(String.init)
                ?? "missing-manifest-version",
            rootPath,
        ].joined(separator: "|")
        return "webkit-object-acceptance-\(sha256Hex(Data(seed.utf8)).prefix(32))"
    }

    private static func remainingRuntimeContextBlockers(
        runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?,
        findings: [ChromeMV3WebKitObjectAcceptanceFinding]
    ) -> [String] {
        uniqueSorted(
            [
                "WKWebExtensionContext creation is not enabled by this task.",
                "WKWebExtensionController loading is not enabled by this task.",
                "runtimeLoadable remains false until a future verified runtime/context layer exists.",
            ]
            + (runtimeLoadabilityReport?.blockers ?? [])
            + findings
                .filter(\.futureRuntimeContextLayerNeeded)
                .map(\.message)
        )
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtension init(resourceBaseURL:)",
                url: "https://developer.apple.com/documentation/webkit/wkwebextension/init%28resourcebaseurl%3A%29",
                note: "Object creation reads a file URL directory or archive containing manifest.json and returns errors for missing or invalid manifests/resources."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtension.Error",
                url: "https://developer.apple.com/documentation/webkit/wkwebextension/error",
                note: "The documented object-processing error domain includes invalid manifest, unsupported manifest version, invalid manifest entry, missing resource, invalid DNR entry, and unknown errors."
            ),
            source(
                kind: "localAppleSDKHeaders",
                title: "MacOSX26.5 WebKit WKWebExtension headers",
                url: nil,
                note: "Local SDK headers confirm object parsing, parse-time errors, controller loading behavior, and context runtime boundaries."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome manifest background",
                url: "https://developer.chrome.com/docs/extensions/reference/manifest/background",
                note: "Chrome MV3 background.service_worker points to the extension service worker and background.type may declare module."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome manifest content scripts",
                url: "https://developer.chrome.com/docs/extensions/reference/manifest/content-scripts",
                note: "Content script js/css entries are relative extension-root resources."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome web_accessible_resources",
                url: "https://developer.chrome.com/docs/extensions/reference/manifest/web-accessible-resources",
                note: "MV3 web-accessible resource entries map bundled resources to matches or extension IDs."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome declarativeNetRequest",
                url: "https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest",
                note: "DNR rule_resources reference bundled ruleset files; Sumi keeps runtime DNR behavior deferred."
            ),
        ]
    }

    private static func source(
        kind: String,
        title: String,
        url: String?,
        note: String
    ) -> ChromeMV3WebKitObjectAcceptanceDocumentationSource {
        ChromeMV3WebKitObjectAcceptanceDocumentationSource(
            kind: kind,
            title: title,
            url: url,
            note: note
        )
    }

    private static func uniqueSorted<T: Comparable & Hashable>(
        _ values: [T]
    ) -> [T] {
        Array(Set(values)).sorted()
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

enum ChromeMV3WebKitObjectProbeResultClassifier {
    static func classify(
        probeDiagnostics: ChromeMV3ExtensionObjectProbeDiagnostics,
        staticInspection: ChromeMV3WebKitObjectAcceptanceStaticInspection,
        runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?
    ) -> [ChromeMV3WebKitObjectAcceptanceFinding] {
        var findings = staticInspection.findings

        switch probeDiagnostics.state {
        case .notAttempted:
            findings.append(
                finding(
                    category: .notAttempted,
                    severity: .info,
                    source: .sumiStaticValidation,
                    message: "WKWebExtension object probe has not run for this generated-rewritten bundle.",
                    paths: [staticInspection.rewrittenBundleRootPath],
                    hint: "Run the DEBUG/internal object probe only after the explicit object-probe gate passes.",
                    generatorFixable: false,
                    futureLayerNeeded: false
                )
            )
        case .blocked:
            findings.append(
                finding(
                    category: .blockedByGate,
                    severity: .warning,
                    source: .sumiStaticValidation,
                    message: "WKWebExtension object probe was blocked before WebKit object creation.",
                    paths: [staticInspection.rewrittenBundleRootPath],
                    hint: probeDiagnostics.blockingReasons.joined(separator: "; "),
                    generatorFixable: false,
                    futureLayerNeeded: false
                )
            )
            if probeDiagnostics.gateDecision.blockers.contains(
                .generatedRewrittenBundleMissing
            ) {
                findings.append(
                    finding(
                        category: .missingGeneratedBundle,
                        severity: .objectBlocking,
                        source: .generatedBundleInspection,
                        message: "Generated-rewritten bundle root is missing before object probing.",
                        paths: [staticInspection.rewrittenBundleRootPath],
                        hint: "Create the generated-rewritten bundle before running the object probe.",
                        generatorFixable: true,
                        futureLayerNeeded: false
                    )
                )
            }
        case .created:
            findings.append(
                finding(
                    category: .objectCreated,
                    severity: .info,
                    source: .webKitError,
                    message: "WKWebExtension object creation succeeded for the generated-rewritten bundle.",
                    paths: [staticInspection.rewrittenBundleRootPath],
                    hint: "Keep this as object acceptance only; context creation and loading remain disabled.",
                    generatorFixable: false,
                    futureLayerNeeded: false
                )
            )
            for parseError in probeDiagnostics.webExtensionParseErrors {
                findings.append(
                    webKitFinding(
                        for: parseError,
                        staticInspection: staticInspection,
                        objectCreationFailed: false
                    )
                )
            }
        case .failed:
            if let error = probeDiagnostics.error {
                findings.append(
                    webKitFinding(
                        for: error,
                        staticInspection: staticInspection,
                        objectCreationFailed: true
                    )
                )
            } else {
                findings.append(
                    unknownWebKitFinding(
                        message: "WKWebExtension object creation failed without a captured error.",
                        paths: [staticInspection.rewrittenBundleRootPath]
                    )
                )
            }
        case .released:
            if let error = probeDiagnostics.error {
                findings.append(
                    webKitFinding(
                        for: error,
                        staticInspection: staticInspection,
                        objectCreationFailed: true
                    )
                )
            } else {
                findings.append(
                    finding(
                        category: .notAttempted,
                        severity: .info,
                        source: .sumiStaticValidation,
                        message: "The previously probed WKWebExtension object has been released.",
                        paths: [staticInspection.rewrittenBundleRootPath],
                        hint: "Re-run the object probe if fresh object acceptance diagnostics are needed.",
                        generatorFixable: false,
                        futureLayerNeeded: false
                    )
                )
            }
        }

        findings.append(
            finding(
                category: .runtimeContextStillBlocked,
                severity: .contextBlocking,
                source: .sumiStaticValidation,
                message: "Context creation and controller loading remain disabled even if object creation succeeds.",
                paths: [],
                hint: "A future prompt must add and test an explicit context-creation gate before any runtime loading can be considered.",
                generatorFixable: false,
                futureLayerNeeded: true
            )
        )

        for blocker in runtimeLoadabilityReport?.blockers ?? [] {
            findings.append(
                finding(
                    category: .runtimeContextStillBlocked,
                    severity: .runtimeBlocking,
                    source: .capabilityClassifier,
                    message: blocker,
                    paths: [],
                    hint: "Keep this blocker separate from WebKit object acceptance; it belongs to the future runtime/context layer.",
                    generatorFixable: false,
                    futureLayerNeeded: true
                )
            )
        }

        return uniqueSorted(findings)
    }

    private static func webKitFinding(
        for error: ChromeMV3ExtensionObjectProbeErrorDiagnostic,
        staticInspection: ChromeMV3WebKitObjectAcceptanceStaticInspection,
        objectCreationFailed: Bool
    ) -> ChromeMV3WebKitObjectAcceptanceFinding {
        let fallbackPaths = [staticInspection.rewrittenBundleRootPath]
        let severity: ChromeMV3WebKitObjectAcceptanceSeverity =
            objectCreationFailed ? .objectBlocking : .warning
        let messageSuffix = "\(error.domain)#\(error.code): \(error.message)"

        if let staticCategory = dominantStaticCategory(in: staticInspection) {
            return finding(
                category: staticCategory,
                severity: severity,
                source: .webKitError,
                message: "WebKit reported an error matching static inspection: \(messageSuffix)",
                paths: paths(for: staticCategory, in: staticInspection),
                hint: hint(for: staticCategory),
                generatorFixable: generatorFixable(for: staticCategory),
                futureLayerNeeded: false
            )
        }

        let category: ChromeMV3WebKitObjectAcceptanceCategory
        switch normalizedWebKitErrorCode(error) {
        case 2:
            category = .missingReferencedResource
        case 4, 5:
            category = .manifestRejectedByWebKit
        case 6:
            category = .unsupportedManifestKey
        case 7:
            category = .declarativeNetRequestResourceRejected
        case 8:
            category = .unsupportedBackgroundShape
        default:
            category = inferredCategory(from: error)
        }

        return finding(
            category: category,
            severity: severity,
            source: .webKitError,
            message: "WebKit object processing reported \(messageSuffix)",
            paths: fallbackPaths,
            hint: hint(for: category),
            generatorFixable: generatorFixable(for: category),
            futureLayerNeeded: false
        )
    }

    private static func normalizedWebKitErrorCode(
        _ error: ChromeMV3ExtensionObjectProbeErrorDiagnostic
    ) -> Int? {
        guard error.domain.localizedCaseInsensitiveContains(
            "WKWebExtension"
        ) else {
            return nil
        }
        return error.code
    }

    private static func inferredCategory(
        from error: ChromeMV3ExtensionObjectProbeErrorDiagnostic
    ) -> ChromeMV3WebKitObjectAcceptanceCategory {
        let text = [
            error.message,
            error.failureReason,
            error.recoverySuggestion,
            error.debugDescription,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        if text.contains("manifest") {
            return .manifestRejectedByWebKit
        }
        if text.contains("declarative") || text.contains("dnr") {
            return .declarativeNetRequestResourceRejected
        }
        if text.contains("background") || text.contains("service worker") {
            return .unsupportedBackgroundShape
        }
        if text.contains("resource") || text.contains("file") {
            return .missingReferencedResource
        }
        return .unknownWebKitError
    }

    private static func dominantStaticCategory(
        in inspection: ChromeMV3WebKitObjectAcceptanceStaticInspection
    ) -> ChromeMV3WebKitObjectAcceptanceCategory? {
        let priority: [ChromeMV3WebKitObjectAcceptanceCategory] = [
            .missingGeneratedBundle,
            .missingManifest,
            .manifestJSONInvalid,
            .serviceWorkerWrapperRejected,
            .contentScriptResourceRejected,
            .extensionPageResourceRejected,
            .declarativeNetRequestResourceRejected,
            .webAccessibleResourceRejected,
            .missingReferencedResource,
            .unsupportedBackgroundShape,
            .unsupportedManifestKey,
        ]
        let categories = Set(inspection.findings.map(\.category))
        return priority.first { categories.contains($0) }
    }

    private static func paths(
        for category: ChromeMV3WebKitObjectAcceptanceCategory,
        in inspection: ChromeMV3WebKitObjectAcceptanceStaticInspection
    ) -> [String] {
        let matches = inspection.findings
            .filter { $0.category == category }
            .flatMap(\.relatedPaths)
        if matches.isEmpty == false {
            return Array(Set(matches)).sorted()
        }
        if category == .missingManifest || category == .manifestJSONInvalid {
            return ["manifest.json"]
        }
        return [inspection.rewrittenBundleRootPath]
    }

    private static func unknownWebKitFinding(
        message: String,
        paths: [String]
    ) -> ChromeMV3WebKitObjectAcceptanceFinding {
        finding(
            category: .unknownWebKitError,
            severity: .objectBlocking,
            source: .unknown,
            message: message,
            paths: paths,
            hint: "Keep the original WebKit error visible and add a narrower classifier once the WebKit failure shape is understood.",
            generatorFixable: false,
            futureLayerNeeded: false
        )
    }

    static func hint(
        for category: ChromeMV3WebKitObjectAcceptanceCategory
    ) -> String {
        switch category {
        case .notAttempted:
            return "Run the object probe only after the explicit gate passes."
        case .blockedByGate:
            return "Resolve the probe gate blocker without enabling context creation or runtime loading."
        case .objectCreated:
            return "Treat success as object acceptance only."
        case .missingGeneratedBundle:
            return "Write the generated-rewritten bundle root before probing."
        case .missingManifest:
            return "Ensure generated-rewritten manifest.json exists at the bundle root."
        case .manifestJSONInvalid:
            return "Emit deterministic valid JSON for the rewritten manifest."
        case .manifestRejectedByWebKit:
            return "Compare the rewritten manifest against WebKit's accepted manifest subset and preserve the WebKit error."
        case .missingReferencedResource:
            return "Copy every manifest-referenced resource into the generated-rewritten bundle."
        case .unsupportedManifestKey:
            return "Keep unsupported/deferred keys visible in the report and avoid claiming runtime support."
        case .unsupportedBackgroundShape:
            return "Keep MV3 background.service_worker shape and align background.type with the wrapper path."
        case .serviceWorkerWrapperRejected:
            return "Write the selected service-worker wrapper file and point background.service_worker at it."
        case .contentScriptResourceRejected:
            return "Copy content script JS/CSS files and inert shim files referenced by content_scripts."
        case .extensionPageResourceRejected:
            return "Copy or render declared extension page HTML files referenced by action/options/side panel manifest keys."
        case .webAccessibleResourceRejected:
            return "Copy exact web_accessible_resources entries and supported trailing-directory resources; leave unsupported wildcard patterns reported."
        case .declarativeNetRequestResourceRejected:
            return "Copy declared DNR rule_resources files and keep DNR runtime behavior deferred."
        case .unknownWebKitError:
            return "Keep the WebKit NSError details visible; add a narrower category after observing a stable failure."
        case .runtimeContextStillBlocked:
            return "Add a future context/runtime gate and tests before creating contexts or loading controllers."
        }
    }

    private static func generatorFixable(
        for category: ChromeMV3WebKitObjectAcceptanceCategory
    ) -> Bool {
        switch category {
        case .missingGeneratedBundle,
             .missingManifest,
             .manifestJSONInvalid,
             .missingReferencedResource,
             .unsupportedBackgroundShape,
             .serviceWorkerWrapperRejected,
             .contentScriptResourceRejected,
             .extensionPageResourceRejected,
             .webAccessibleResourceRejected,
             .declarativeNetRequestResourceRejected:
            return true
        case .notAttempted,
             .blockedByGate,
             .objectCreated,
             .manifestRejectedByWebKit,
             .unsupportedManifestKey,
             .unknownWebKitError,
             .runtimeContextStillBlocked:
            return false
        }
    }

}

struct ChromeMV3WebKitObjectAcceptanceInspector {
    var fileManager: FileManager = .default

    func inspect(
        rewrittenBundleRootURL: URL,
        runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?
    ) -> ChromeMV3WebKitObjectAcceptanceStaticInspection {
        let rootURL = rewrittenBundleRootURL.standardizedFileURL
        var builder = ChromeMV3WebKitObjectAcceptanceInspectionBuilder(
            rootURL: rootURL
        )

        guard directoryExists(rootURL) else {
            builder.add(
                category: .missingGeneratedBundle,
                severity: .objectBlocking,
                source: .generatedBundleInspection,
                message: "Generated-rewritten bundle root is missing.",
                paths: [rootURL.path],
                hint: "Create generated-rewritten artifacts before WebKit object probing.",
                generatorFixable: true
            )
            return builder.build()
        }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        guard let manifestData = regularFileData(
            at: manifestURL,
            relativePath: "manifest.json",
            builder: &builder
        ) else {
            builder.add(
                category: .missingManifest,
                severity: .objectBlocking,
                source: .generatedBundleInspection,
                message: "manifest.json is missing from the generated-rewritten bundle root.",
                paths: ["manifest.json"],
                hint: "Write manifest.json at the generated-rewritten root before probing.",
                generatorFixable: true
            )
            return builder.build()
        }

        builder.manifestExists = true
        let manifestObject: [String: Any]
        do {
            manifestObject = try manifestJSONObject(from: manifestData)
            builder.manifestJSONValid = true
            builder.manifestVersion = intValue(
                manifestObject["manifest_version"]
            )
        } catch {
            builder.add(
                category: .manifestJSONInvalid,
                severity: .objectBlocking,
                source: .sumiStaticValidation,
                message: "manifest.json is not valid JSON for WebKit object processing.",
                paths: ["manifest.json"],
                hint: "Emit valid deterministic JSON for the rewritten manifest.",
                generatorFixable: true
            )
            return builder.build()
        }

        inspectManifestVersion(manifestObject, builder: &builder)
        inspectBackground(manifestObject, rootURL: rootURL, builder: &builder)
        inspectContentScripts(manifestObject, rootURL: rootURL, builder: &builder)
        inspectExtensionPages(manifestObject, rootURL: rootURL, builder: &builder)
        inspectWebAccessibleResources(
            manifestObject,
            rootURL: rootURL,
            builder: &builder
        )
        inspectDeclarativeNetRequest(
            manifestObject,
            rootURL: rootURL,
            builder: &builder
        )
        inspectIcons(manifestObject, rootURL: rootURL, builder: &builder)
        inspectRuntimeLoadabilityReport(
            runtimeLoadabilityReport,
            builder: &builder
        )
        inspectInstallReport(rootURL: rootURL, builder: &builder)

        return builder.build()
    }

    private func inspectManifestVersion(
        _ manifestObject: [String: Any],
        builder: inout ChromeMV3WebKitObjectAcceptanceInspectionBuilder
    ) {
        guard builder.manifestVersion == 3 else {
            builder.add(
                category: .manifestRejectedByWebKit,
                severity: .objectBlocking,
                source: .sumiStaticValidation,
                message: "Generated-rewritten manifest must declare manifest_version 3.",
                paths: ["manifest.json"],
                hint: "Keep generated artifacts Chrome Manifest V3 only.",
                generatorFixable: true
            )
            return
        }

        builder.add(
            category: .objectCreated,
            severity: .info,
            source: .sumiStaticValidation,
            message: "Static inspection found manifest.json with manifest_version 3.",
            paths: ["manifest.json"],
            hint: "Manifest version shape is compatible with the object-acceptance probe.",
            generatorFixable: false
        )
    }

    private func inspectBackground(
        _ manifestObject: [String: Any],
        rootURL: URL,
        builder: inout ChromeMV3WebKitObjectAcceptanceInspectionBuilder
    ) {
        guard let background = manifestObject["background"] as? [String: Any] else {
            return
        }
        let serviceWorker = stringValue(background["service_worker"])
        let backgroundType = stringValue(background["type"])

        if background.keys.contains("page")
            || background.keys.contains("scripts")
            || background.keys.contains("persistent")
        {
            builder.add(
                category: .unsupportedBackgroundShape,
                severity: .objectBlocking,
                source: .sumiStaticValidation,
                message: "Generated-rewritten manifest contains a non-MV3 background shape.",
                paths: ["manifest.json"],
                hint: "Keep only background.service_worker and optional background.type for Chrome MV3 generated artifacts.",
                generatorFixable: true
            )
        }

        if let backgroundType, backgroundType != "module" {
            builder.add(
                category: .unsupportedBackgroundShape,
                severity: .warning,
                source: .sumiStaticValidation,
                message: "background.type has a non-module value; Chrome MV3 omits the key for classic workers.",
                paths: ["manifest.json"],
                hint: "Omit background.type for classic worker wrappers or set it to module for module wrappers.",
                generatorFixable: true
            )
        }

        guard let serviceWorker else { return }
        inspectResource(
            serviceWorker,
            field: "background.service_worker",
            rootURL: rootURL,
            missingCategory: serviceWorker.hasPrefix("_sumi_runtime/")
                ? .serviceWorkerWrapperRejected
                : .missingReferencedResource,
            builder: &builder
        )

        if serviceWorker.contains("service-worker-wrapper.module.js"),
           backgroundType != "module"
        {
            builder.add(
                category: .unsupportedBackgroundShape,
                severity: .objectBlocking,
                source: .generatedBundleInspection,
                message: "Module service-worker wrapper is referenced without background.type module.",
                paths: ["manifest.json", serviceWorker],
                hint: "Set background.type to module when the module wrapper is used.",
                generatorFixable: true
            )
        }

        if serviceWorker.contains("service-worker-wrapper.classic.js"),
           backgroundType == "module"
        {
            builder.add(
                category: .unsupportedBackgroundShape,
                severity: .objectBlocking,
                source: .generatedBundleInspection,
                message: "Classic service-worker wrapper is referenced while background.type is module.",
                paths: ["manifest.json", serviceWorker],
                hint: "Use the module wrapper for module backgrounds or omit background.type for classic wrappers.",
                generatorFixable: true
            )
        }
    }

    private func inspectContentScripts(
        _ manifestObject: [String: Any],
        rootURL: URL,
        builder: inout ChromeMV3WebKitObjectAcceptanceInspectionBuilder
    ) {
        guard let scripts = manifestObject["content_scripts"] as? [[String: Any]] else {
            return
        }

        for (index, script) in scripts.enumerated() {
            for path in stringArray(script["js"]) {
                inspectResource(
                    path,
                    field: "content_scripts[\(index)].js",
                    rootURL: rootURL,
                    missingCategory: .contentScriptResourceRejected,
                    builder: &builder
                )
            }
            for path in stringArray(script["css"]) {
                inspectResource(
                    path,
                    field: "content_scripts[\(index)].css",
                    rootURL: rootURL,
                    missingCategory: .contentScriptResourceRejected,
                    builder: &builder
                )
            }
        }
    }

    private func inspectExtensionPages(
        _ manifestObject: [String: Any],
        rootURL: URL,
        builder: inout ChromeMV3WebKitObjectAcceptanceInspectionBuilder
    ) {
        if
            let action = manifestObject["action"] as? [String: Any],
            let popup = stringValue(action["default_popup"])
        {
            inspectResource(
                popup,
                field: "action.default_popup",
                rootURL: rootURL,
                missingCategory: .extensionPageResourceRejected,
                builder: &builder
            )
        }

        if let optionsPage = stringValue(manifestObject["options_page"]) {
            inspectResource(
                optionsPage,
                field: "options_page",
                rootURL: rootURL,
                missingCategory: .extensionPageResourceRejected,
                builder: &builder
            )
        }

        if
            let optionsUI = manifestObject["options_ui"] as? [String: Any],
            let optionsUIPage = stringValue(optionsUI["page"])
        {
            inspectResource(
                optionsUIPage,
                field: "options_ui.page",
                rootURL: rootURL,
                missingCategory: .extensionPageResourceRejected,
                builder: &builder
            )
        }

        if
            let sidePanel = manifestObject["side_panel"] as? [String: Any],
            let defaultPath = stringValue(sidePanel["default_path"])
        {
            inspectResource(
                defaultPath,
                field: "side_panel.default_path",
                rootURL: rootURL,
                missingCategory: .extensionPageResourceRejected,
                builder: &builder
            )
            builder.add(
                category: .runtimeContextStillBlocked,
                severity: .runtimeBlocking,
                source: .capabilityClassifier,
                message: "side_panel.default_path is present but side panel runtime/UI support remains deferred.",
                paths: ["manifest.json", defaultPath],
                hint: "Keep side panel as reported/deferred until a future native host layer exists.",
                generatorFixable: false,
                futureLayerNeeded: true
            )
        }
    }

    private func inspectWebAccessibleResources(
        _ manifestObject: [String: Any],
        rootURL: URL,
        builder: inout ChromeMV3WebKitObjectAcceptanceInspectionBuilder
    ) {
        guard let entries = manifestObject["web_accessible_resources"] as? [[String: Any]] else {
            return
        }

        for (index, entry) in entries.enumerated() {
            for path in stringArray(entry["resources"]) {
                if path.hasSuffix("/*") {
                    inspectDirectory(
                        String(path.dropLast(2)),
                        field: "web_accessible_resources[\(index)].resources",
                        rootURL: rootURL,
                        category: .webAccessibleResourceRejected,
                        builder: &builder
                    )
                } else if path.contains("*") {
                    builder.add(
                        category: .webAccessibleResourceRejected,
                        severity: .warning,
                        source: .generatedBundleInspection,
                        message: "web_accessible_resources wildcard pattern is reported but not statically expanded by Sumi.",
                        paths: ["manifest.json", path],
                        hint: "Prefer exact resources or trailing-directory patterns when object-acceptance diagnostics need resource existence checks.",
                        generatorFixable: true
                    )
                } else {
                    inspectResource(
                        path,
                        field: "web_accessible_resources[\(index)].resources",
                        rootURL: rootURL,
                        missingCategory: .webAccessibleResourceRejected,
                        builder: &builder
                    )
                }
            }
        }
    }

    private func inspectDeclarativeNetRequest(
        _ manifestObject: [String: Any],
        rootURL: URL,
        builder: inout ChromeMV3WebKitObjectAcceptanceInspectionBuilder
    ) {
        guard
            let dnr = manifestObject["declarative_net_request"] as? [String: Any],
            let ruleResources = dnr["rule_resources"] as? [[String: Any]]
        else {
            return
        }

        for (index, ruleResource) in ruleResources.enumerated() {
            guard let path = stringValue(ruleResource["path"]) else { continue }
            inspectResource(
                path,
                field: "declarative_net_request.rule_resources[\(index)].path",
                rootURL: rootURL,
                missingCategory: .declarativeNetRequestResourceRejected,
                builder: &builder
            )
        }

        builder.add(
            category: .runtimeContextStillBlocked,
            severity: .runtimeBlocking,
            source: .capabilityClassifier,
            message: "declarative_net_request is present but DNR runtime behavior remains deferred.",
            paths: ["manifest.json"],
            hint: "Keep ruleset resource existence separate from future DNR runtime semantics.",
            generatorFixable: false,
            futureLayerNeeded: true
        )
    }

    private func inspectIcons(
        _ manifestObject: [String: Any],
        rootURL: URL,
        builder: inout ChromeMV3WebKitObjectAcceptanceInspectionBuilder
    ) {
        for path in iconPaths(from: manifestObject["icons"]) {
            inspectResource(
                path,
                field: "icons",
                rootURL: rootURL,
                missingCategory: .missingReferencedResource,
                builder: &builder
            )
        }

        if let action = manifestObject["action"] as? [String: Any] {
            for path in iconPaths(from: action["default_icon"]) {
                inspectResource(
                    path,
                    field: "action.default_icon",
                    rootURL: rootURL,
                    missingCategory: .missingReferencedResource,
                    builder: &builder
                )
            }
        }
    }

    private func inspectRuntimeLoadabilityReport(
        _ report: ChromeMV3RuntimeLoadabilityReport?,
        builder: inout ChromeMV3WebKitObjectAcceptanceInspectionBuilder
    ) {
        guard let report else {
            builder.add(
                category: .runtimeContextStillBlocked,
                severity: .runtimeBlocking,
                source: .sumiStaticValidation,
                message: "runtime-loadability report is missing from object-acceptance classification.",
                paths: [],
                hint: "Generate runtime-loadability metadata before claiming readiness for any future context layer.",
                generatorFixable: false,
                futureLayerNeeded: true
            )
            return
        }

        for missing in report.missing {
            builder.addMissing(missing)
            builder.add(
                category: category(forRuntimeMissingPath: missing),
                severity: .objectBlocking,
                source: .sumiStaticValidation,
                message: "runtime-loadability report lists a missing artifact: \(missing).",
                paths: [missing],
                hint: "Fix the generated-rewritten artifact list before object probing.",
                generatorFixable: true
            )
        }

        for unsupportedAPI in report.unsupportedAPIs {
            builder.add(
                category: .runtimeContextStillBlocked,
                severity: .runtimeBlocking,
                source: .capabilityClassifier,
                message: "\(unsupportedAPI.rawValue) remains unsupported and blocks runtime/context support.",
                paths: ["manifest.json"],
                hint: "Keep unsupported API reporting separate from WebKit object acceptance.",
                generatorFixable: false,
                futureLayerNeeded: true
            )
        }

        for deferredAPI in report.deferredAPIs {
            builder.add(
                category: .runtimeContextStillBlocked,
                severity: .runtimeBlocking,
                source: .capabilityClassifier,
                message: "\(deferredAPI.rawValue) remains deferred and blocks runtime/context support.",
                paths: ["manifest.json"],
                hint: "Keep deferred API reporting separate from WebKit object acceptance.",
                generatorFixable: false,
                futureLayerNeeded: true
            )
        }
    }

    private func inspectInstallReport(
        rootURL: URL,
        builder: inout ChromeMV3WebKitObjectAcceptanceInspectionBuilder
    ) {
        let report = ChromeMV3InstallInspector.inspectUnpackedDirectory(
            at: rootURL
        )
        builder.installReportUnsupportedAPIs = report.unsupportedAPIs.sorted()
        builder.installReportDeferredAPIs = report.deferredAPIs.sorted()

        for issue in report.fatalValidationErrors {
            builder.add(
                category: category(forFatalInstallIssue: issue.code),
                severity: .objectBlocking,
                source: .sumiStaticValidation,
                message: issue.message,
                paths: issue.field.map { ["manifest.json", $0] }
                    ?? ["manifest.json"],
                hint: "Fix Chrome MV3 install-foundation validation before WebKit object probing.",
                generatorFixable: true
            )
        }

        for api in report.unsupportedAPIs {
            builder.add(
                category: .runtimeContextStillBlocked,
                severity: .runtimeBlocking,
                source: .capabilityClassifier,
                message: "\(api.rawValue) is detected as unsupported by Sumi capability classification.",
                paths: ["manifest.json"],
                hint: "Report unsupported APIs without treating them as proven WebKit object blockers.",
                generatorFixable: false,
                futureLayerNeeded: true
            )
        }

        for api in report.deferredAPIs {
            builder.add(
                category: .runtimeContextStillBlocked,
                severity: .runtimeBlocking,
                source: .capabilityClassifier,
                message: "\(api.rawValue) is detected as deferred by Sumi capability classification.",
                paths: ["manifest.json"],
                hint: "Report deferred APIs without treating them as proven WebKit object blockers.",
                generatorFixable: false,
                futureLayerNeeded: true
            )
        }
    }

    private func inspectResource(
        _ rawPath: String,
        field: String,
        rootURL: URL,
        missingCategory: ChromeMV3WebKitObjectAcceptanceCategory,
        builder: inout ChromeMV3WebKitObjectAcceptanceInspectionBuilder
    ) {
        let normalizedPath: String
        do {
            normalizedPath = try normalizedResourcePath(rawPath, field: field)
            builder.addInspected(normalizedPath)
        } catch {
            builder.addUnsafe(rawPath)
            builder.add(
                category: missingCategory,
                severity: .objectBlocking,
                source: .sumiStaticValidation,
                message: "Unsafe manifest resource path in \(field): \(rawPath).",
                paths: ["manifest.json", rawPath],
                hint: "Use bundle-relative resource paths without traversal, absolute paths, schemes, or empty segments.",
                generatorFixable: true
            )
            return
        }

        guard let url = safeResourceURL(normalizedPath, rootURL: rootURL) else {
            builder.addUnsafe(normalizedPath)
            builder.add(
                category: missingCategory,
                severity: .objectBlocking,
                source: .sumiStaticValidation,
                message: "Manifest resource path escapes generated-rewritten bundle: \(normalizedPath).",
                paths: ["manifest.json", normalizedPath],
                hint: "Keep all manifest resources inside the generated-rewritten root.",
                generatorFixable: true
            )
            return
        }

        guard regularFileData(
            at: url,
            relativePath: normalizedPath,
            builder: &builder
        ) != nil
        else {
            builder.addMissing(normalizedPath)
            builder.add(
                category: missingCategory,
                severity: .objectBlocking,
                source: .generatedBundleInspection,
                message: "Manifest-referenced resource is missing or not a regular file: \(normalizedPath).",
                paths: ["manifest.json", normalizedPath],
                hint: ChromeMV3WebKitObjectProbeResultClassifier
                    .hint(for: missingCategory),
                generatorFixable: true
            )
            return
        }
    }

    private func inspectDirectory(
        _ rawPath: String,
        field: String,
        rootURL: URL,
        category: ChromeMV3WebKitObjectAcceptanceCategory,
        builder: inout ChromeMV3WebKitObjectAcceptanceInspectionBuilder
    ) {
        let normalizedPath: String
        do {
            normalizedPath = try normalizedResourcePath(rawPath, field: field)
            builder.addInspected(normalizedPath)
        } catch {
            builder.addUnsafe(rawPath)
            builder.add(
                category: category,
                severity: .objectBlocking,
                source: .sumiStaticValidation,
                message: "Unsafe manifest resource directory in \(field): \(rawPath).",
                paths: ["manifest.json", rawPath],
                hint: "Use bundle-relative directories without traversal, schemes, or empty segments.",
                generatorFixable: true
            )
            return
        }

        guard let url = safeResourceURL(normalizedPath, rootURL: rootURL),
              directoryExists(url)
        else {
            builder.addMissing(normalizedPath)
            builder.add(
                category: category,
                severity: .objectBlocking,
                source: .generatedBundleInspection,
                message: "Manifest-referenced resource directory is missing: \(normalizedPath).",
                paths: ["manifest.json", normalizedPath],
                hint: ChromeMV3WebKitObjectProbeResultClassifier
                    .hint(for: category),
                generatorFixable: true
            )
            return
        }
    }

    private func category(
        forRuntimeMissingPath path: String
    ) -> ChromeMV3WebKitObjectAcceptanceCategory {
        if path.contains("service-worker-wrapper") {
            return .serviceWorkerWrapperRejected
        }
        if path.contains("content-script")
            || path.hasSuffix(".js")
            || path.hasSuffix(".css")
        {
            return .contentScriptResourceRejected
        }
        if path.contains("rules") || path.hasSuffix(".json") {
            return .declarativeNetRequestResourceRejected
        }
        if path.hasSuffix(".html") || path.hasSuffix(".htm") {
            return .extensionPageResourceRejected
        }
        return .missingReferencedResource
    }

    private func category(
        forFatalInstallIssue code: String
    ) -> ChromeMV3WebKitObjectAcceptanceCategory {
        switch code {
        case "missingManifest":
            return .missingManifest
        case "invalidJSON", "invalidJSONStructure":
            return .manifestJSONInvalid
        case "backgroundPageUnsupported",
             "backgroundScriptsUnsupported",
             "backgroundPersistenceUnsupported":
            return .unsupportedBackgroundShape
        case "unsafeResourcePath":
            return .missingReferencedResource
        default:
            return .manifestRejectedByWebKit
        }
    }

    private func iconPaths(from value: Any?) -> [String] {
        if let path = value as? String {
            return [path]
        }
        if let dictionary = value as? [String: String] {
            return dictionary.values.sorted()
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.compactMap { $0 as? String }.sorted()
        }
        return []
    }

    private func regularFileData(
        at url: URL,
        relativePath: String,
        builder: inout ChromeMV3WebKitObjectAcceptanceInspectionBuilder
    ) -> Data? {
        guard
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
        else {
            return nil
        }
        if values.isSymbolicLink == true {
            builder.addSymlink(relativePath)
            return nil
        }
        guard values.isRegularFile == true else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func safeResourceURL(_ relativePath: String, rootURL: URL) -> URL? {
        let root = rootURL.standardizedFileURL
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(rootPath) else {
            return nil
        }
        return url
    }

    private func manifestJSONObject(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let manifestObject = object as? [String: Any] else {
            throw ChromeMV3WebKitObjectAcceptanceInspectorError
                .invalidManifestJSON
        }
        return manifestObject
    }

    private func normalizedResourcePath(
        _ path: String,
        field: String
    ) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathBeforeFragment = trimmed.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? trimmed
        let pathOnly = pathBeforeFragment.split(
            separator: "?",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? pathBeforeFragment
        let decoded = pathOnly.removingPercentEncoding ?? pathOnly
        guard decoded.isEmpty == false,
              decoded.hasPrefix("/") == false,
              decoded.hasPrefix("~") == false,
              decoded.contains("\\") == false,
              decoded.contains("\0") == false,
              decoded.localizedCaseInsensitiveContains("://") == false
        else {
            throw ChromeMV3WebKitObjectAcceptanceInspectorError
                .unsafeResourcePath(field: field, path: path)
        }

        let segments = decoded.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard
            segments.isEmpty == false,
            segments.allSatisfy({ segment in
                segment.isEmpty == false
                    && segment != "."
                    && segment != ".."
            })
        else {
            throw ChromeMV3WebKitObjectAcceptanceInspectorError
                .unsafeResourcePath(field: field, path: path)
        }
        return decoded
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        guard let number = value as? NSNumber else { return nil }
        let type = String(cString: number.objCType)
        guard type != "c" else { return nil }
        return number.intValue
    }

    private func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private func stringArray(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }
}

private enum ChromeMV3WebKitObjectAcceptanceInspectorError: Error {
    case invalidManifestJSON
    case unsafeResourcePath(field: String, path: String)
}

private struct ChromeMV3WebKitObjectAcceptanceInspectionBuilder {
    var rootURL: URL
    var generatedBundleExists = false
    var manifestExists = false
    var manifestJSONValid = false
    var manifestVersion: Int?
    var inspectedResourcePaths: [String] = []
    var missingResourcePaths: [String] = []
    var unsafeResourcePaths: [String] = []
    var symlinkResourcePaths: [String] = []
    var installReportUnsupportedAPIs: [ChromeMV3API] = []
    var installReportDeferredAPIs: [ChromeMV3API] = []
    var findings: [ChromeMV3WebKitObjectAcceptanceFinding] = []

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        generatedBundleExists = FileManager.default.fileExists(
            atPath: self.rootURL.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    mutating func add(
        category: ChromeMV3WebKitObjectAcceptanceCategory,
        severity: ChromeMV3WebKitObjectAcceptanceSeverity,
        source: ChromeMV3WebKitObjectAcceptanceSource,
        message: String,
        paths: [String],
        hint: String,
        generatorFixable: Bool,
        futureLayerNeeded: Bool = false
    ) {
        findings.append(
            ChromeMV3WebKitObjectProbeResultClassifier.finding(
                category: category,
                severity: severity,
                source: source,
                message: message,
                paths: paths,
                hint: hint,
                generatorFixable: generatorFixable,
                futureLayerNeeded: futureLayerNeeded
            )
        )
    }

    mutating func addInspected(_ path: String) {
        inspectedResourcePaths.append(path)
    }

    mutating func addMissing(_ path: String) {
        missingResourcePaths.append(path)
    }

    mutating func addUnsafe(_ path: String) {
        unsafeResourcePaths.append(path)
    }

    mutating func addSymlink(_ path: String) {
        symlinkResourcePaths.append(path)
    }

    func build() -> ChromeMV3WebKitObjectAcceptanceStaticInspection {
        ChromeMV3WebKitObjectAcceptanceStaticInspection(
            rewrittenBundleRootPath: rootURL.path,
            generatedBundleExists: generatedBundleExists,
            manifestPath: rootURL.appendingPathComponent("manifest.json").path,
            manifestExists: manifestExists,
            manifestJSONValid: manifestJSONValid,
            manifestVersion: manifestVersion,
            inspectedResourcePaths: uniqueSorted(inspectedResourcePaths),
            missingResourcePaths: uniqueSorted(missingResourcePaths),
            unsafeResourcePaths: uniqueSorted(unsafeResourcePaths),
            symlinkResourcePaths: uniqueSorted(symlinkResourcePaths),
            installReportUnsupportedAPIs: installReportUnsupportedAPIs
                .sorted(),
            installReportDeferredAPIs: installReportDeferredAPIs.sorted(),
            findings: ChromeMV3WebKitObjectProbeResultClassifier.uniqueSorted(
                findings
            )
        )
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

private func findingSort(
    _ lhs: ChromeMV3WebKitObjectAcceptanceFinding,
    _ rhs: ChromeMV3WebKitObjectAcceptanceFinding
) -> Bool {
    if lhs.category == rhs.category {
        if lhs.severity == rhs.severity {
            if lhs.source == rhs.source {
                if lhs.message == rhs.message {
                    return lhs.relatedPaths.joined(separator: "\u{1f}")
                        < rhs.relatedPaths.joined(separator: "\u{1f}")
                }
                return lhs.message < rhs.message
            }
            return lhs.source < rhs.source
        }
        return lhs.severity < rhs.severity
    }
    return lhs.category < rhs.category
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

extension ChromeMV3WebKitObjectProbeResultClassifier {
    static func finding(
        category: ChromeMV3WebKitObjectAcceptanceCategory,
        severity: ChromeMV3WebKitObjectAcceptanceSeverity,
        source: ChromeMV3WebKitObjectAcceptanceSource,
        message: String,
        paths: [String],
        hint: String,
        generatorFixable: Bool,
        futureLayerNeeded: Bool
    ) -> ChromeMV3WebKitObjectAcceptanceFinding {
        ChromeMV3WebKitObjectAcceptanceFinding(
            category: category,
            severity: severity,
            source: source,
            message: message,
            relatedPaths: Array(Set(paths.filter { $0.isEmpty == false }))
                .sorted(),
            remediationHint: hint,
            generatedBundleRewriteCanFix: generatorFixable,
            futureRuntimeContextLayerNeeded: futureLayerNeeded
        )
    }

    static func uniqueSorted(
        _ findings: [ChromeMV3WebKitObjectAcceptanceFinding]
    ) -> [ChromeMV3WebKitObjectAcceptanceFinding] {
        var seen = Set<String>()
        var result: [ChromeMV3WebKitObjectAcceptanceFinding] = []
        for finding in findings.sorted(by: findingSort) {
            let key = [
                finding.category.rawValue,
                finding.severity.rawValue,
                finding.source.rawValue,
                finding.message,
                finding.relatedPaths.joined(separator: "\u{1f}"),
            ].joined(separator: "\u{1e}")
            guard seen.contains(key) == false else { continue }
            seen.insert(key)
            result.append(finding)
        }
        return result
    }
}
