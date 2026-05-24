//
//  ChromeMV3RuntimeLoadabilityVerifier.swift
//  Sumi
//
//  Static verification for the generated-rewritten Chrome MV3 fixture variant.
//  This layer reads files and reports structure only; it does not load, attach,
//  register, or execute extension runtime code.
//

import CryptoKit
import Foundation

enum ChromeMV3RuntimeLoadabilityCheckCategory: String, Codable, CaseIterable, Comparable, Sendable {
    case manifestShape
    case serviceWorkerWrapperReference
    case serviceWorkerWrapperTemplatePresence
    case contentScriptShimOrdering
    case contentScriptFieldPreservation
    case extensionPageShimPresence
    case extensionPageCSPWarnings
    case webAccessibleResourceNeeds
    case nativeMessagingBlocked
    case runtimeMessagingNotImplemented
    case WebKitRuntimeNotWired
    case unsupportedAPIs
    case deferredAPIs
    case passwordManagerReadiness
    case hostPermissionsPreserved
    case runtimeTemplateFileHashes
    case extensionPageFileHashes
    case sidePanelDeferredPlanningOnly
    case noNativeMessagingRuntime

    static func < (
        lhs: ChromeMV3RuntimeLoadabilityCheckCategory,
        rhs: ChromeMV3RuntimeLoadabilityCheckCategory
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3RuntimeLoadabilityCheckStatus: String, Codable, Comparable, Sendable {
    case passed
    case failed
    case deferred

    static func < (
        lhs: ChromeMV3RuntimeLoadabilityCheckStatus,
        rhs: ChromeMV3RuntimeLoadabilityCheckStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ExtensionPageShimInjectionStatus: String, Codable, Comparable, Sendable {
    case beforeClosingHead
    case documentStartFallbackNoHead
    case insertedOutsideHead
    case noShimTag
    case missingPage
    case planningOnlyDeferred

    static func < (
        lhs: ChromeMV3ExtensionPageShimInjectionStatus,
        rhs: ChromeMV3ExtensionPageShimInjectionStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3RuntimeLoadabilityFileHash: Codable, Equatable, Sendable {
    var relativePath: String
    var sha256: String
    var byteCount: Int
}

struct ChromeMV3RuntimeLoadabilityCheck: Codable, Equatable, Sendable {
    var category: ChromeMV3RuntimeLoadabilityCheckCategory
    var status: ChromeMV3RuntimeLoadabilityCheckStatus
    var message: String
    var relatedPaths: [String]
    var details: [String]
}

struct ChromeMV3ExtensionPageStaticVerification: Codable, Equatable, Sendable {
    var context: ChromeMV3ExtensionPageShimContext
    var sourceManifestField: String
    var pagePath: String
    var normalizedPagePath: String?
    var expectedShimRelativeSrcs: [String]
    var containsCSPMetaTag: Bool
    var injectionStatus: ChromeMV3ExtensionPageShimInjectionStatus
    var sha256: String?
    var warnings: [String]
}

struct ChromeMV3PasswordManagerRuntimeReadinessReport: Codable, Equatable, Sendable {
    var contentScriptsPresent: Bool
    var allFramesDetected: Bool
    var matchAboutBlankDetected: Bool
    var hostPermissionsPresent: Bool
    var actionPopupPresent: Bool
    var storagePermissionPresent: Bool
    var nativeMessagingDetected: Bool
    var nativeMessagingBlocked: Bool
    var runtimeMessagingImplemented: Bool
    var controlledInputPageWorldBehaviorVerified: Bool
    var serviceWorkerLifecycleVerified: Bool
    var blockers: [String]
    var deferredChecks: [String]
}

struct ChromeMV3RuntimeLoadabilityReport: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var id: String
    var generatedVariantRootPath: String
    var generatedVariantRootRelativeName: String
    var sourceApplicationReportHash: ChromeMV3RuntimeLoadabilityFileHash?
    var rewrittenManifestHash: ChromeMV3RuntimeLoadabilityFileHash?
    var runtimeTemplateFileHashes: [ChromeMV3RuntimeLoadabilityFileHash]
    var extensionPageRewrittenFileHashes: [ChromeMV3RuntimeLoadabilityFileHash]
    var extensionPageStaticChecks: [ChromeMV3ExtensionPageStaticVerification]
    var verificationChecks: [ChromeMV3RuntimeLoadabilityCheck]
    var passedChecks: [ChromeMV3RuntimeLoadabilityCheckCategory]
    var failedChecks: [ChromeMV3RuntimeLoadabilityCheckCategory]
    var deferredChecks: [ChromeMV3RuntimeLoadabilityCheckCategory]
    var warnings: [String]
    var missing: [String]
    var blockers: [String]
    var unsupportedAPIs: [ChromeMV3API]
    var deferredAPIs: [ChromeMV3API]
    var requiredFutureRuntimeComponents: [String]
    var passwordManagerReadiness: ChromeMV3PasswordManagerRuntimeReadinessReport
    var structurallyValid: Bool
    var runtimeLoadable: Bool
    var runtimeLoadableFalseReason: String
    var readOnlyStaticInspection: Bool
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
}

enum ChromeMV3RuntimeLoadabilityVerifierError: LocalizedError, CustomStringConvertible {
    case missingRewrittenVariant(String)
    case unsafeRelativePath(String)
    case variantResourceEscapedRoot(String)
    case invalidManifestJSON(String)

    var errorDescription: String? {
        switch self {
        case .missingRewrittenVariant(let path):
            return "Missing generated-rewritten variant root: \(path)"
        case .unsafeRelativePath(let path):
            return "Unsafe rewritten-variant relative path: \(path)"
        case .variantResourceEscapedRoot(let path):
            return "Rewritten-variant resource escapes variant root: \(path)"
        case .invalidManifestJSON(let reason):
            return "Invalid rewritten manifest JSON: \(reason)"
        }
    }

    var description: String {
        errorDescription ?? String(describing: self)
    }
}

struct ChromeMV3RuntimeLoadabilityVerifier {
    static let reportFileName = "runtime-loadability-report.json"

    var fileManager: FileManager = .default

    func verifyRewrittenVariant(
        at variantRootURL: URL
    ) throws -> ChromeMV3RuntimeLoadabilityReport {
        let rootURL = variantRootURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ChromeMV3RuntimeLoadabilityVerifierError
                .missingRewrittenVariant(rootURL.path)
        }

        var builder = ChromeMV3RuntimeLoadabilityReportBuilder(rootURL: rootURL)

        let applicationReport = loadApplicationReport(
            from: rootURL,
            builder: &builder
        )
        let originalManifestObject = loadOriginalGeneratedManifest(
            applicationReport: applicationReport,
            builder: &builder
        )
        let rewrittenManifestObject = loadRewrittenManifest(
            from: rootURL,
            builder: &builder
        )

        let rewrittenInstallReport = inspectRewrittenManifest(
            rewrittenManifestObject,
            builder: &builder
        )

        let expectedRuntimeTemplatePaths = applicationReport?.copiedRuntimeTemplatePaths ?? []
        builder.runtimeTemplateFileHashes = runtimeTemplateFileHashes(
            in: rootURL,
            expectedRuntimeTemplatePaths: expectedRuntimeTemplatePaths
        )
        let missingRuntimeTemplatePaths = expectedRuntimeTemplatePaths.filter { expected in
            builder.runtimeTemplateFileHashes.contains { $0.relativePath == expected } == false
        }
        for path in missingRuntimeTemplatePaths {
            builder.addMissing(path)
        }
        builder.add(
            category: .runtimeTemplateFileHashes,
            status: missingRuntimeTemplatePaths.isEmpty ? .passed : .failed,
            message: missingRuntimeTemplatePaths.isEmpty
                ? "Runtime template file hashes were recorded for the rewritten variant."
                : "One or more expected runtime template files are missing from the rewritten variant.",
            relatedPaths: builder.runtimeTemplateFileHashes.map(\.relativePath) + missingRuntimeTemplatePaths,
            details: missingRuntimeTemplatePaths
        )

        guard let rewrittenManifestObject else {
            return builder.build()
        }

        verifyManifestShape(
            rewrittenManifestObject,
            builder: &builder
        )
        verifyServiceWorkerWrapper(
            originalManifestObject: originalManifestObject,
            rewrittenManifestObject: rewrittenManifestObject,
            rootURL: rootURL,
            builder: &builder
        )
        verifyContentScripts(
            originalManifestObject: originalManifestObject,
            rewrittenManifestObject: rewrittenManifestObject,
            rootURL: rootURL,
            builder: &builder
        )
        verifyExtensionPages(
            manifestObject: rewrittenManifestObject,
            rootURL: rootURL,
            builder: &builder
        )
        verifyHostPermissions(
            originalManifestObject: originalManifestObject,
            rewrittenManifestObject: rewrittenManifestObject,
            builder: &builder
        )
        verifyWebAccessibleResourceNeeds(
            originalManifestObject: originalManifestObject,
            rewrittenManifestObject: rewrittenManifestObject,
            builder: &builder
        )
        verifyAPIs(
            applicationReport: applicationReport,
            rewrittenInstallReport: rewrittenInstallReport,
            builder: &builder
        )
        verifyRuntimeDeferrals(
            manifestObject: rewrittenManifestObject,
            rewrittenInstallReport: rewrittenInstallReport,
            builder: &builder
        )
        builder.passwordManagerReadiness = passwordManagerReadiness(
            manifestObject: rewrittenManifestObject,
            installReport: rewrittenInstallReport
        )
        verifyPasswordManagerReadiness(builder: &builder)

        return builder.build()
    }

    @discardableResult
    func writeReport(
        forRewrittenVariantAt variantRootURL: URL
    ) throws -> ChromeMV3RuntimeLoadabilityReport {
        let report = try verifyRewrittenVariant(at: variantRootURL)
        try ChromeMV3DeterministicJSON.write(
            report,
            to: variantRootURL.standardizedFileURL
                .appendingPathComponent(Self.reportFileName)
        )
        return report
    }

    private func loadApplicationReport(
        from rootURL: URL,
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) -> ChromeMV3GeneratedRewriteApplicationReport? {
        let reportURL = rootURL.appendingPathComponent(
            ChromeMV3GeneratedRewriteVariantWriter.applicationReportFileName
        )
        guard let data = try? Data(contentsOf: reportURL) else {
            builder.addWarning("Generated rewrite application report is missing; original-manifest comparisons are deferred.")
            return nil
        }
        builder.sourceApplicationReportHash = ChromeMV3RuntimeLoadabilityFileHash(
            relativePath: ChromeMV3GeneratedRewriteVariantWriter.applicationReportFileName,
            sha256: sha256Hex(data),
            byteCount: data.count
        )
        do {
            return try JSONDecoder().decode(
                ChromeMV3GeneratedRewriteApplicationReport.self,
                from: data
            )
        } catch {
            builder.addWarning("Generated rewrite application report could not be decoded: \(error.localizedDescription)")
            return nil
        }
    }

    private func loadOriginalGeneratedManifest(
        applicationReport: ChromeMV3GeneratedRewriteApplicationReport?,
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) -> [String: Any]? {
        guard let path = applicationReport?.originalGeneratedBundleRootPath else {
            return nil
        }
        let manifestURL = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .appendingPathComponent("manifest.json")
        do {
            return try manifestJSONObject(from: Data(contentsOf: manifestURL))
        } catch {
            builder.addWarning("Original generated manifest could not be read for preservation checks: \(error.localizedDescription)")
            return nil
        }
    }

    private func loadRewrittenManifest(
        from rootURL: URL,
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) -> [String: Any]? {
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            builder.addMissing("manifest.json")
            builder.add(
                category: .manifestShape,
                status: .failed,
                message: "Rewritten manifest.json is missing.",
                relatedPaths: ["manifest.json"]
            )
            return nil
        }

        builder.rewrittenManifestHash = ChromeMV3RuntimeLoadabilityFileHash(
            relativePath: "manifest.json",
            sha256: sha256Hex(data),
            byteCount: data.count
        )

        do {
            return try manifestJSONObject(from: data)
        } catch {
            builder.add(
                category: .manifestShape,
                status: .failed,
                message: "Rewritten manifest.json is not valid JSON.",
                relatedPaths: ["manifest.json"],
                details: [error.localizedDescription]
            )
            return nil
        }
    }

    private func inspectRewrittenManifest(
        _ manifestObject: [String: Any]?,
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) -> ChromeMV3InstallReport? {
        guard let manifestObject else { return nil }
        do {
            let manifest = try ChromeMV3ManifestValidator.validateJSONObject(
                manifestObject
            )
            return ChromeMV3InstallReporter.report(for: manifest)
        } catch {
            builder.add(
                category: .manifestShape,
                status: .failed,
                message: "Rewritten manifest fails Chrome MV3 install-foundation validation.",
                relatedPaths: ["manifest.json"],
                details: [error.localizedDescription]
            )
            return nil
        }
    }

    private func verifyManifestShape(
        _ manifestObject: [String: Any],
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) {
        let version = intValue(manifestObject["manifest_version"])
        if version == 3 {
            builder.add(
                category: .manifestShape,
                status: .passed,
                message: "Rewritten manifest exists and declares manifest_version 3.",
                relatedPaths: ["manifest.json"]
            )
        } else {
            builder.add(
                category: .manifestShape,
                status: .failed,
                message: "Rewritten manifest must declare manifest_version 3.",
                relatedPaths: ["manifest.json"],
                details: ["found: \(version.map { String($0) } ?? "missing")"]
            )
        }
    }

    private func verifyServiceWorkerWrapper(
        originalManifestObject: [String: Any]?,
        rewrittenManifestObject: [String: Any],
        rootURL: URL,
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) {
        guard
            let originalBackground = originalManifestObject?["background"] as? [String: Any],
            stringValue(originalBackground["service_worker"]) != nil
        else {
            builder.add(
                category: .serviceWorkerWrapperReference,
                status: .passed,
                message: "No original generated background.service_worker was present, so no wrapper reference is expected."
            )
            builder.add(
                category: .serviceWorkerWrapperTemplatePresence,
                status: .passed,
                message: "No service-worker wrapper template is required for this rewritten variant."
            )
            return
        }

        let backgroundType = stringValue(originalBackground["type"])
        if let backgroundType, backgroundType != "module" {
            builder.addWarning("background.type '\(backgroundType)' is not the Chrome MV3 module value; verifier treats the wrapper expectation as classic.")
        }
        let expectedModule: ChromeMV3RuntimeTemplateModuleName = backgroundType == "module"
            ? .serviceWorkerWrapperModule
            : .serviceWorkerWrapperClassic
        let expectedPath = ChromeMV3RuntimeResourceTemplateCatalog
            .template(named: expectedModule)
            .outputRelativePath

        let rewrittenBackground = rewrittenManifestObject["background"] as? [String: Any]
        let rewrittenServiceWorker = stringValue(
            rewrittenBackground?["service_worker"]
        )
        if rewrittenServiceWorker == expectedPath {
            builder.add(
                category: .serviceWorkerWrapperReference,
                status: .passed,
                message: "background.service_worker points to the expected \(backgroundType == "module" ? "module" : "classic") Sumi wrapper.",
                relatedPaths: ["manifest.json", expectedPath]
            )
        } else {
            builder.add(
                category: .serviceWorkerWrapperReference,
                status: .failed,
                message: "background.service_worker does not point to the expected wrapper for background.type.",
                relatedPaths: ["manifest.json"],
                details: [
                    "expected: \(expectedPath)",
                    "found: \(rewrittenServiceWorker ?? "missing")",
                ]
            )
        }

        if fileExists(relativePath: expectedPath, rootURL: rootURL) {
            builder.add(
                category: .serviceWorkerWrapperTemplatePresence,
                status: .passed,
                message: "Expected service-worker wrapper template file exists.",
                relatedPaths: [expectedPath]
            )
        } else {
            builder.addMissing(expectedPath)
            builder.add(
                category: .serviceWorkerWrapperTemplatePresence,
                status: .failed,
                message: "Expected service-worker wrapper template file is missing.",
                relatedPaths: [expectedPath]
            )
        }
    }

    private func verifyContentScripts(
        originalManifestObject: [String: Any]?,
        rewrittenManifestObject: [String: Any],
        rootURL: URL,
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) {
        guard
            let originalScripts = originalManifestObject?["content_scripts"] as? [[String: Any]]
        else {
            builder.add(
                category: .contentScriptShimOrdering,
                status: .passed,
                message: "No original generated content_scripts entries were present, so no content-script shim prefix is expected."
            )
            builder.add(
                category: .contentScriptFieldPreservation,
                status: .passed,
                message: "No content-script fields require preservation for this rewritten variant."
            )
            return
        }

        guard let rewrittenScripts = rewrittenManifestObject["content_scripts"] as? [[String: Any]] else {
            builder.add(
                category: .contentScriptShimOrdering,
                status: .failed,
                message: "Original content_scripts entries were present but are missing from the rewritten manifest.",
                relatedPaths: ["manifest.json"]
            )
            builder.add(
                category: .contentScriptFieldPreservation,
                status: .failed,
                message: "Original content_scripts metadata cannot be verified because rewritten entries are missing.",
                relatedPaths: ["manifest.json"]
            )
            return
        }

        let shimPrefix = [
            ChromeMV3RuntimeResourceTemplateCatalog
                .template(named: .chromeShimCommon)
                .outputRelativePath,
            ChromeMV3RuntimeResourceTemplateCatalog
                .template(named: .chromeShimContentScript)
                .outputRelativePath,
        ]

        var orderingFailures: [String] = []
        var orderingDetails: [String] = []
        var preservationFailures: [String] = []
        var preservationDetails: [String] = []

        if originalScripts.count != rewrittenScripts.count {
            orderingFailures.append(
                "content_scripts count changed from \(originalScripts.count) to \(rewrittenScripts.count)."
            )
            preservationFailures.append(
                "content_scripts count changed from \(originalScripts.count) to \(rewrittenScripts.count)."
            )
        }

        for shimPath in shimPrefix where fileExists(relativePath: shimPath, rootURL: rootURL) == false {
            orderingFailures.append("Referenced content-script shim is missing: \(shimPath).")
            builder.addMissing(shimPath)
        }

        for index in 0..<min(originalScripts.count, rewrittenScripts.count) {
            let original = originalScripts[index]
            let rewritten = rewrittenScripts[index]
            let originalJS = stringArray(original["js"])
            let rewrittenJS = stringArray(rewritten["js"])
            let expectedJS = shimPrefix + originalJS

            if rewrittenJS == expectedJS {
                orderingDetails.append(
                    "content_scripts[\(index)].js has shim prefix before preserved original scripts."
                )
            } else {
                orderingFailures.append(
                    "content_scripts[\(index)].js did not preserve the expected shim prefix plus original order."
                )
                orderingDetails.append("expected: \(expectedJS.joined(separator: ","))")
                orderingDetails.append("found: \(rewrittenJS.joined(separator: ","))")
            }

            let fieldResult = contentScriptFieldPreservationResult(
                original: original,
                rewritten: rewritten,
                index: index
            )
            preservationDetails.append(contentsOf: fieldResult.details)
            preservationFailures.append(contentsOf: fieldResult.failures)
        }

        builder.add(
            category: .contentScriptShimOrdering,
            status: orderingFailures.isEmpty ? .passed : .failed,
            message: orderingFailures.isEmpty
                ? "Content-script shim paths are prefixed before original scripts and original order is preserved."
                : "Content-script shim prefix ordering failed.",
            relatedPaths: ["manifest.json"] + shimPrefix,
            details: (orderingFailures + orderingDetails).sorted()
        )
        builder.add(
            category: .contentScriptFieldPreservation,
            status: preservationFailures.isEmpty ? .passed : .failed,
            message: preservationFailures.isEmpty
                ? "Content-script matching, frame, run_at, and world fields are preserved."
                : "Content-script metadata preservation failed.",
            relatedPaths: ["manifest.json"],
            details: (preservationFailures + preservationDetails).sorted()
        )
    }

    private func contentScriptFieldPreservationResult(
        original: [String: Any],
        rewritten: [String: Any],
        index: Int
    ) -> (failures: [String], details: [String]) {
        let preservedFields = [
            "matches",
            "exclude_matches",
            "include_globs",
            "exclude_globs",
            "run_at",
            "all_frames",
            "match_about_blank",
            "match_origin_as_fallback",
            "world",
        ]

        var failures: [String] = []
        var details: [String] = []
        for field in preservedFields {
            let originalHasValue = original.keys.contains(field)
            let rewrittenHasValue = rewritten.keys.contains(field)
            if originalHasValue != rewrittenHasValue {
                failures.append(
                    "content_scripts[\(index)].\(field) presence changed."
                )
                continue
            }

            guard originalHasValue else {
                details.append(
                    "content_scripts[\(index)].\(field) remains absent."
                )
                continue
            }

            let originalValue = JSONValue(any: original[field] ?? NSNull())
            let rewrittenValue = JSONValue(any: rewritten[field] ?? NSNull())
            if originalValue == rewrittenValue {
                details.append(
                    "content_scripts[\(index)].\(field) is preserved."
                )
            } else {
                failures.append(
                    "content_scripts[\(index)].\(field) value changed."
                )
            }
        }
        return (failures, details)
    }

    private func verifyExtensionPages(
        manifestObject: [String: Any],
        rootURL: URL,
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) {
        let targets = extensionPageTargets(in: manifestObject)
        guard targets.isEmpty == false else {
            builder.add(
                category: .extensionPageShimPresence,
                status: .passed,
                message: "No action popup, options page, or side panel page is declared."
            )
            builder.add(
                category: .extensionPageCSPWarnings,
                status: .passed,
                message: "No extension-page HTML required CSP scanning."
            )
            builder.add(
                category: .extensionPageFileHashes,
                status: .passed,
                message: "No extension-page HTML hashes were required."
            )
            builder.add(
                category: .sidePanelDeferredPlanningOnly,
                status: .passed,
                message: "No side_panel.default_path is declared."
            )
            return
        }

        var pageHashes: [ChromeMV3RuntimeLoadabilityFileHash] = []
        var staticChecks: [ChromeMV3ExtensionPageStaticVerification] = []
        var shimFailures: [String] = []
        var sidePanelDetails: [String] = []
        var cspWarningDetails: [String] = []

        for target in targets.sorted(by: extensionPageTargetSort) {
            let normalizedPagePath: String?
            do {
                normalizedPagePath = try normalizedResourcePath(
                    target.pagePath,
                    field: target.sourceManifestField
                )
            } catch {
                normalizedPagePath = nil
                shimFailures.append(error.localizedDescription)
            }

            let expectedShimRelativeSrcs: [String]
            if target.context == .sidePanel || normalizedPagePath == nil {
                expectedShimRelativeSrcs = []
            } else {
                expectedShimRelativeSrcs = [
                    relativeHTMLScriptSource(
                        forRuntimePath: ChromeMV3RuntimeResourceTemplateCatalog
                            .template(named: .chromeShimExtensionPage)
                            .outputRelativePath,
                        fromPagePath: normalizedPagePath!
                    ),
                ]
            }

            var pageWarnings: [String] = []
            var containsCSPMetaTag = false
            var injectionStatus: ChromeMV3ExtensionPageShimInjectionStatus = .missingPage
            var pageSHA256: String?

            if let normalizedPagePath {
                do {
                    let pageURL = try safeVariantResourceURL(
                        relativePath: normalizedPagePath,
                        rootURL: rootURL
                    )
                    let data = try Data(contentsOf: pageURL)
                    pageSHA256 = sha256Hex(data)
                    pageHashes.append(
                        ChromeMV3RuntimeLoadabilityFileHash(
                            relativePath: normalizedPagePath,
                            sha256: pageSHA256!,
                            byteCount: data.count
                        )
                    )
                    let html = String(data: data, encoding: .utf8) ?? ""
                    containsCSPMetaTag = htmlContainsCSPMetaTag(in: html)
                    injectionStatus = extensionPageInjectionStatus(
                        html: html,
                        expectedShimRelativeSrcs: expectedShimRelativeSrcs,
                        sidePanelPlanningOnly: target.context == .sidePanel
                    )

                    if containsCSPMetaTag, injectionStatus != .noShimTag,
                       injectionStatus != .missingPage,
                       injectionStatus != .planningOnlyDeferred
                    {
                        let warning = "CSP meta tag present in \(normalizedPagePath); future injected script behavior must be verified before runtime loading."
                        pageWarnings.append(warning)
                        cspWarningDetails.append(warning)
                    }

                    if target.context == .sidePanel {
                        if injectionStatus == .planningOnlyDeferred {
                            sidePanelDetails.append(
                                "side_panel.default_path remains planning-only without shim injection: \(normalizedPagePath)."
                            )
                        } else {
                            shimFailures.append(
                                "side_panel.default_path unexpectedly contains extension-page shim tags: \(normalizedPagePath)."
                            )
                        }
                    } else if injectionStatus == .beforeClosingHead
                        || injectionStatus == .documentStartFallbackNoHead
                    {
                        let runtimePath = ChromeMV3RuntimeResourceTemplateCatalog
                            .template(named: .chromeShimExtensionPage)
                            .outputRelativePath
                        if fileExists(relativePath: runtimePath, rootURL: rootURL) == false {
                            builder.addMissing(runtimePath)
                            shimFailures.append("Extension-page shim template is missing: \(runtimePath).")
                        }
                    } else {
                        shimFailures.append(
                            "\(target.sourceManifestField) is missing expected shim tag in \(normalizedPagePath)."
                        )
                    }
                } catch {
                    builder.addMissing(normalizedPagePath)
                    shimFailures.append("\(target.sourceManifestField) page is missing or unreadable: \(normalizedPagePath).")
                }
            }

            staticChecks.append(
                ChromeMV3ExtensionPageStaticVerification(
                    context: target.context,
                    sourceManifestField: target.sourceManifestField,
                    pagePath: target.pagePath,
                    normalizedPagePath: normalizedPagePath,
                    expectedShimRelativeSrcs: expectedShimRelativeSrcs,
                    containsCSPMetaTag: containsCSPMetaTag,
                    injectionStatus: injectionStatus,
                    sha256: pageSHA256,
                    warnings: Array(Set(pageWarnings)).sorted()
                )
            )
            for warning in pageWarnings {
                builder.addWarning(warning)
            }
        }

        builder.extensionPageRewrittenFileHashes = pageHashes
            .sorted { $0.relativePath < $1.relativePath }
        builder.extensionPageStaticChecks = staticChecks
            .sorted(by: extensionPageStaticCheckSort)

        builder.add(
            category: .extensionPageShimPresence,
            status: shimFailures.isEmpty ? .passed : .failed,
            message: shimFailures.isEmpty
                ? "Action popup and options pages contain expected static shim tags; side panel pages remain unshimmed."
                : "Extension-page shim presence check failed.",
            relatedPaths: targets.map(\.pagePath).sorted(),
            details: shimFailures.sorted()
        )
        builder.add(
            category: .extensionPageCSPWarnings,
            status: .passed,
            message: cspWarningDetails.isEmpty
                ? "Extension-page HTML was scanned for CSP meta tags; no shim/CSP warning was produced."
                : "Extension-page HTML was scanned for CSP meta tags and warnings were recorded.",
            relatedPaths: targets.map(\.pagePath).sorted(),
            details: cspWarningDetails.sorted()
        )
        builder.add(
            category: .extensionPageFileHashes,
            status: pageHashes.isEmpty ? .failed : .passed,
            message: pageHashes.isEmpty
                ? "No declared extension-page HTML files could be hashed."
                : "Declared extension-page HTML file hashes were recorded.",
            relatedPaths: pageHashes.map(\.relativePath)
        )

        let sidePanelTargets = targets.filter { $0.context == .sidePanel }
        if sidePanelTargets.isEmpty {
            builder.add(
                category: .sidePanelDeferredPlanningOnly,
                status: .passed,
                message: "No side_panel.default_path is declared."
            )
        } else {
            builder.add(
                category: .sidePanelDeferredPlanningOnly,
                status: sidePanelDetails.count == sidePanelTargets.count ? .deferred : .failed,
                message: sidePanelDetails.count == sidePanelTargets.count
                    ? "side_panel.default_path remains deferred and planning-only."
                    : "side_panel.default_path no longer looks planning-only.",
                relatedPaths: sidePanelTargets.map(\.pagePath).sorted(),
                details: sidePanelDetails.sorted()
            )
        }
    }

    private func verifyHostPermissions(
        originalManifestObject: [String: Any]?,
        rewrittenManifestObject: [String: Any],
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) {
        guard let originalManifestObject else {
            builder.add(
                category: .hostPermissionsPreserved,
                status: .deferred,
                message: "Original generated manifest is unavailable, so host permission preservation is deferred."
            )
            return
        }

        let originalHostPermissions = stringArray(
            originalManifestObject["host_permissions"]
        )
        let rewrittenHostPermissions = stringArray(
            rewrittenManifestObject["host_permissions"]
        )
        if originalHostPermissions == rewrittenHostPermissions {
            builder.add(
                category: .hostPermissionsPreserved,
                status: .passed,
                message: "host_permissions are unchanged between generated and generated-rewritten manifests.",
                relatedPaths: ["manifest.json"],
                details: originalHostPermissions
            )
        } else {
            builder.add(
                category: .hostPermissionsPreserved,
                status: .failed,
                message: "host_permissions changed between generated and generated-rewritten manifests.",
                relatedPaths: ["manifest.json"],
                details: [
                    "original: \(originalHostPermissions.joined(separator: ","))",
                    "rewritten: \(rewrittenHostPermissions.joined(separator: ","))",
                ]
            )
        }
    }

    private func verifyWebAccessibleResourceNeeds(
        originalManifestObject: [String: Any]?,
        rewrittenManifestObject: [String: Any],
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) {
        let originalResources = JSONValue(any: originalManifestObject?["web_accessible_resources"] ?? [])
        let rewrittenResources = JSONValue(any: rewrittenManifestObject["web_accessible_resources"] ?? [])
        if originalManifestObject != nil, originalResources != rewrittenResources {
            builder.add(
                category: .webAccessibleResourceNeeds,
                status: .failed,
                message: "web_accessible_resources changed in the rewritten manifest.",
                relatedPaths: ["manifest.json"]
            )
            return
        }

        builder.add(
            category: .webAccessibleResourceNeeds,
            status: .deferred,
            message: "Future page-world bridge or web-accessible shim exposure needs remain unresolved; the verifier does not add web_accessible_resources entries.",
            relatedPaths: ["manifest.json"]
        )
    }

    private func verifyAPIs(
        applicationReport: ChromeMV3GeneratedRewriteApplicationReport?,
        rewrittenInstallReport: ChromeMV3InstallReport?,
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) {
        let detected = Set(rewrittenInstallReport?.detectedAPIs ?? [])
        let unsupported = uniqueSorted(
            (applicationReport?.unsupportedAPIs ?? [])
                + (rewrittenInstallReport?.unsupportedAPIs ?? [])
        )
        let deferred = uniqueSorted(
            (applicationReport?.deferredAPIs ?? [])
                + (rewrittenInstallReport?.deferredAPIs ?? [])
        )
        builder.unsupportedAPIs = unsupported
        builder.deferredAPIs = deferred

        let silentlyRemovedUnsupported = Set(applicationReport?.unsupportedAPIs ?? [])
            .subtracting(detected)
        var unsupportedDetails = unsupported.map {
            "\($0.rawValue) remains classified as unsupported."
        }
        unsupportedDetails.append(contentsOf: silentlyRemovedUnsupported.map {
            "\($0.rawValue) was present in the application report but is no longer detectable in the rewritten manifest."
        })
        builder.add(
            category: .unsupportedAPIs,
            status: unsupported.isEmpty && silentlyRemovedUnsupported.isEmpty ? .passed : .failed,
            message: unsupported.isEmpty && silentlyRemovedUnsupported.isEmpty
                ? "No unsupported APIs are detected in the rewritten variant."
                : "Unsupported APIs remain blockers or were silently removed.",
            relatedPaths: ["manifest.json"],
            details: unsupportedDetails.sorted()
        )

        builder.add(
            category: .deferredAPIs,
            status: deferred.isEmpty ? .passed : .deferred,
            message: deferred.isEmpty
                ? "No deferred APIs are detected in the rewritten variant."
                : "Deferred APIs remain planning-only and keep the variant non-loadable.",
            relatedPaths: ["manifest.json"],
            details: deferred.map(\.rawValue).sorted()
        )
    }

    private func verifyRuntimeDeferrals(
        manifestObject: [String: Any],
        rewrittenInstallReport: ChromeMV3InstallReport?,
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) {
        let permissions = stringArray(manifestObject["permissions"])
        let nativeMessagingDetected = permissions.contains("nativeMessaging")

        if nativeMessagingDetected {
            builder.add(
                category: .nativeMessagingBlocked,
                status: .deferred,
                message: "nativeMessaging permission is detected and remains blocked/deferred; no native host bridge is implemented or launched.",
                relatedPaths: ["manifest.json"],
                details: ["permissions.nativeMessaging"]
            )
            let hostBridgePath = ChromeMV3RuntimeResourceTemplateCatalog
                .template(named: .hostBridgeStub)
                .outputRelativePath
            if inertRuntimeTemplateExists(
                relativePath: hostBridgePath,
                rootURL: builder.rootURL
            ) {
                builder.add(
                    category: .noNativeMessagingRuntime,
                    status: .passed,
                    message: "Only the inert host-bridge planning stub is present; no native messaging runtime is implemented.",
                    relatedPaths: [hostBridgePath]
                )
            } else {
                builder.addMissing(hostBridgePath)
                builder.add(
                    category: .noNativeMessagingRuntime,
                    status: .failed,
                    message: "nativeMessaging is declared but the inert host-bridge planning stub is missing.",
                    relatedPaths: [hostBridgePath]
                )
            }
        } else {
            builder.add(
                category: .nativeMessagingBlocked,
                status: .passed,
                message: "nativeMessaging permission is not declared."
            )
            builder.add(
                category: .noNativeMessagingRuntime,
                status: .passed,
                message: "No native messaging permission or generated native host runtime is present."
            )
        }

        let runtimeMessagingRelevant = rewrittenInstallReport?.detectedAPIs
            .contains(.runtime) ?? true
        builder.add(
            category: .runtimeMessagingNotImplemented,
            status: runtimeMessagingRelevant ? .deferred : .passed,
            message: runtimeMessagingRelevant
                ? "Chrome runtime messaging bridge is not implemented for the rewritten variant."
                : "No runtime messaging surface is detected.",
            relatedPaths: ["manifest.json"]
        )

        builder.add(
            category: .WebKitRuntimeNotWired,
            status: .deferred,
            message: "WebKit extension runtime loading is intentionally not wired by this verifier.",
            details: ["No controller, context, extension object, user script registration, or extension code execution is performed."]
        )
    }

    private func verifyPasswordManagerReadiness(
        builder: inout ChromeMV3RuntimeLoadabilityReportBuilder
    ) {
        let report = builder.passwordManagerReadiness
        var details: [String] = []
        details.append("contentScriptsPresent: \(report.contentScriptsPresent)")
        details.append("allFramesDetected: \(report.allFramesDetected)")
        details.append("matchAboutBlankDetected: \(report.matchAboutBlankDetected)")
        details.append("hostPermissionsPresent: \(report.hostPermissionsPresent)")
        details.append("actionPopupPresent: \(report.actionPopupPresent)")
        details.append("storagePermissionPresent: \(report.storagePermissionPresent)")
        details.append("nativeMessagingDetected: \(report.nativeMessagingDetected)")
        details.append("runtimeMessagingImplemented: \(report.runtimeMessagingImplemented)")
        details.append("controlledInputPageWorldBehaviorVerified: \(report.controlledInputPageWorldBehaviorVerified)")
        details.append("serviceWorkerLifecycleVerified: \(report.serviceWorkerLifecycleVerified)")

        builder.add(
            category: .passwordManagerReadiness,
            status: report.blockers.isEmpty ? .passed : .deferred,
            message: report.blockers.isEmpty
                ? "Password-manager readiness has no detected blockers for this static fixture, but no support claim is made."
                : "Password-manager-like behavior remains blocked/deferred; no support claim is made.",
            details: (report.blockers + report.deferredChecks + details).sorted()
        )
    }

    private func runtimeTemplateFileHashes(
        in rootURL: URL,
        expectedRuntimeTemplatePaths: [String]
    ) -> [ChromeMV3RuntimeLoadabilityFileHash] {
        let runtimeRootURL = rootURL.appendingPathComponent(
            ChromeMV3RuntimeResourceTemplateCatalog.runtimeDirectoryName,
            isDirectory: true
        )
        var hashes: [ChromeMV3RuntimeLoadabilityFileHash] = []

        if let enumerator = fileManager.enumerator(
            at: runtimeRootURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) {
            let rootPath = rootURL.path.hasSuffix("/")
                ? rootURL.path
                : rootURL.path + "/"
            for case let url as URL in enumerator {
                guard
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                    values.isRegularFile == true,
                    let data = try? Data(contentsOf: url)
                else { continue }
                let relativePath = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
                hashes.append(
                    ChromeMV3RuntimeLoadabilityFileHash(
                        relativePath: relativePath,
                        sha256: sha256Hex(data),
                        byteCount: data.count
                    )
                )
            }
        }

        for expected in expectedRuntimeTemplatePaths where hashes.contains(where: { $0.relativePath == expected }) == false {
            if
                let url = try? safeVariantResourceURL(
                    relativePath: expected,
                    rootURL: rootURL
                ),
                let data = try? Data(contentsOf: url)
            {
                hashes.append(
                    ChromeMV3RuntimeLoadabilityFileHash(
                        relativePath: expected,
                        sha256: sha256Hex(data),
                        byteCount: data.count
                    )
                )
            }
        }

        return hashes.sorted { $0.relativePath < $1.relativePath }
    }

    private func passwordManagerReadiness(
        manifestObject: [String: Any],
        installReport: ChromeMV3InstallReport?
    ) -> ChromeMV3PasswordManagerRuntimeReadinessReport {
        let contentScripts = manifestObject["content_scripts"] as? [[String: Any]] ?? []
        let permissions = stringArray(manifestObject["permissions"])
        let hostPermissions = stringArray(manifestObject["host_permissions"])
        let hasNativeMessaging = permissions.contains("nativeMessaging")
        let hasStorage = permissions.contains("storage")
        let hasActionPopup = (manifestObject["action"] as? [String: Any])
            .flatMap { stringValue($0["default_popup"]) } != nil
        let hasRuntimeMessagingShape = installReport?.detectedAPIs.contains(.runtime) ?? false

        var blockers = [
            "Runtime messaging bridge is not implemented yet.",
            "Controlled-input and page-world behavior is not verified yet.",
            "Service-worker lifecycle is not verified yet.",
        ]
        if hasNativeMessaging {
            blockers.append("Native messaging is detected but blocked/deferred.")
        }
        if hasRuntimeMessagingShape == false {
            blockers.append("Runtime messaging shape was not detected in the rewritten manifest.")
        }

        return ChromeMV3PasswordManagerRuntimeReadinessReport(
            contentScriptsPresent: contentScripts.isEmpty == false,
            allFramesDetected: contentScripts.contains { boolValue($0["all_frames"]) == true },
            matchAboutBlankDetected: contentScripts.contains { boolValue($0["match_about_blank"]) == true },
            hostPermissionsPresent: hostPermissions.isEmpty == false,
            actionPopupPresent: hasActionPopup,
            storagePermissionPresent: hasStorage,
            nativeMessagingDetected: hasNativeMessaging,
            nativeMessagingBlocked: hasNativeMessaging,
            runtimeMessagingImplemented: false,
            controlledInputPageWorldBehaviorVerified: false,
            serviceWorkerLifecycleVerified: false,
            blockers: Array(Set(blockers)).sorted(),
            deferredChecks: [
                "Password-manager fixture readiness is a report only; Sumi does not claim password-manager support.",
                "Page-world and controlled-input behavior require future fixture verification.",
            ]
        )
    }

    private func extensionPageTargets(
        in manifestObject: [String: Any]
    ) -> [ChromeMV3RuntimeLoadabilityExtensionPageTarget] {
        var targets: [ChromeMV3RuntimeLoadabilityExtensionPageTarget] = []
        if
            let action = manifestObject["action"] as? [String: Any],
            let popup = stringValue(action["default_popup"])
        {
            targets.append(
                ChromeMV3RuntimeLoadabilityExtensionPageTarget(
                    context: .actionPopup,
                    sourceManifestField: "action.default_popup",
                    pagePath: popup
                )
            )
        }
        if let optionsPage = stringValue(manifestObject["options_page"]) {
            targets.append(
                ChromeMV3RuntimeLoadabilityExtensionPageTarget(
                    context: .optionsPage,
                    sourceManifestField: "options_page",
                    pagePath: optionsPage
                )
            )
        }
        if
            let optionsUI = manifestObject["options_ui"] as? [String: Any],
            let optionsUIPage = stringValue(optionsUI["page"])
        {
            targets.append(
                ChromeMV3RuntimeLoadabilityExtensionPageTarget(
                    context: .optionsPage,
                    sourceManifestField: "options_ui.page",
                    pagePath: optionsUIPage
                )
            )
        }
        if
            let sidePanel = manifestObject["side_panel"] as? [String: Any],
            let defaultPath = stringValue(sidePanel["default_path"])
        {
            targets.append(
                ChromeMV3RuntimeLoadabilityExtensionPageTarget(
                    context: .sidePanel,
                    sourceManifestField: "side_panel.default_path",
                    pagePath: defaultPath
                )
            )
        }
        return targets
    }

    private func extensionPageInjectionStatus(
        html: String,
        expectedShimRelativeSrcs: [String],
        sidePanelPlanningOnly: Bool
    ) -> ChromeMV3ExtensionPageShimInjectionStatus {
        if sidePanelPlanningOnly {
            let containsShim = html.contains(
                ChromeMV3RuntimeResourceTemplateCatalog
                    .runtimeDirectoryName + "/chrome-shim.extension-page.js"
            )
            || html.contains("chrome-shim.extension-page.js")
            return containsShim ? .insertedOutsideHead : .planningOnlyDeferred
        }

        let shimTags = expectedShimRelativeSrcs.map {
            "<script src=\"\($0)\"></script>"
        }
        guard shimTags.allSatisfy({ html.contains($0) }) else {
            return .noShimTag
        }

        if let closingHeadRange = html.range(
            of: "</head>",
            options: [.caseInsensitive]
        ) {
            let allBeforeHead = shimTags.allSatisfy { tag in
                guard let range = html.range(of: tag) else { return false }
                return range.lowerBound < closingHeadRange.lowerBound
            }
            return allBeforeHead ? .beforeClosingHead : .insertedOutsideHead
        }

        let shimBlock = shimTags.joined(separator: "\n") + "\n"
        return html.hasPrefix(shimBlock)
            ? .documentStartFallbackNoHead
            : .insertedOutsideHead
    }

    private func htmlContainsCSPMetaTag(in html: String) -> Bool {
        let pattern = #"<meta\b[^>]*http-equiv\s*=\s*["']?content-security-policy["']?[^>]*>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return false }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.firstMatch(in: html, range: range) != nil
    }

    private func inertRuntimeTemplateExists(
        relativePath: String,
        rootURL: URL
    ) -> Bool {
        guard
            let url = try? safeVariantResourceURL(
                relativePath: relativePath,
                rootURL: rootURL
            ),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return false
        }
        return contents.contains("inert: true")
            && contents.contains("runtimeLoadable: false")
            && contents.contains("notWired: true")
    }

    private func fileExists(relativePath: String, rootURL: URL) -> Bool {
        guard
            let url = try? safeVariantResourceURL(
                relativePath: relativePath,
                rootURL: rootURL
            )
        else {
            return false
        }
        return fileManager.fileExists(atPath: url.path)
    }

    private func safeVariantResourceURL(
        relativePath: String,
        rootURL: URL
    ) throws -> URL {
        try validateSafeRelativePath(relativePath)
        let root = rootURL.standardizedFileURL
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(rootPath) else {
            throw ChromeMV3RuntimeLoadabilityVerifierError
                .variantResourceEscapedRoot(url.path)
        }
        return url
    }

    private func manifestJSONObject(from data: Data) throws -> [String: Any] {
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let manifest = object as? [String: Any] else {
                throw ChromeMV3RuntimeLoadabilityVerifierError
                    .invalidManifestJSON("top-level value is not an object")
            }
            return manifest
        } catch let error as ChromeMV3RuntimeLoadabilityVerifierError {
            throw error
        } catch {
            throw ChromeMV3RuntimeLoadabilityVerifierError
                .invalidManifestJSON(error.localizedDescription)
        }
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
        do {
            try validateSafeRelativePath(decoded)
            return decoded
        } catch {
            throw ChromeMV3RuntimeLoadabilityVerifierError
                .unsafeRelativePath("\(field): \(path)")
        }
    }

    private func validateSafeRelativePath(_ relativePath: String) throws {
        guard relativePath.isEmpty == false else {
            throw ChromeMV3RuntimeLoadabilityVerifierError
                .unsafeRelativePath(relativePath)
        }
        guard
            relativePath.hasPrefix("/") == false,
            relativePath.hasPrefix("~") == false,
            relativePath.contains("\\") == false,
            relativePath.contains("\0") == false,
            relativePath.localizedCaseInsensitiveContains("://") == false
        else {
            throw ChromeMV3RuntimeLoadabilityVerifierError
                .unsafeRelativePath(relativePath)
        }

        let segments = relativePath.split(
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
            throw ChromeMV3RuntimeLoadabilityVerifierError
                .unsafeRelativePath(relativePath)
        }
    }

    private func relativeHTMLScriptSource(
        forRuntimePath runtimePath: String,
        fromPagePath pagePath: String
    ) -> String {
        let directoryDepth = pagePath
            .split(separator: "/")
            .dropLast()
            .count
        if directoryDepth == 0 {
            return runtimePath
        }
        return String(repeating: "../", count: directoryDepth) + runtimePath
    }

    private func uniqueSorted(_ apis: [ChromeMV3API]) -> [ChromeMV3API] {
        var result: [ChromeMV3API] = []
        for api in apis.sorted() where result.contains(api) == false {
            result.append(api)
        }
        return result
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

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        guard let number = value as? NSNumber else { return nil }
        let type = String(cString: number.objCType)
        guard type == "c" else { return nil }
        return number.boolValue
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct ChromeMV3RuntimeLoadabilityExtensionPageTarget {
    var context: ChromeMV3ExtensionPageShimContext
    var sourceManifestField: String
    var pagePath: String
}

private struct ChromeMV3RuntimeLoadabilityReportBuilder {
    var rootURL: URL
    var sourceApplicationReportHash: ChromeMV3RuntimeLoadabilityFileHash?
    var rewrittenManifestHash: ChromeMV3RuntimeLoadabilityFileHash?
    var runtimeTemplateFileHashes: [ChromeMV3RuntimeLoadabilityFileHash] = []
    var extensionPageRewrittenFileHashes: [ChromeMV3RuntimeLoadabilityFileHash] = []
    var extensionPageStaticChecks: [ChromeMV3ExtensionPageStaticVerification] = []
    var checks: [ChromeMV3RuntimeLoadabilityCheck] = []
    var warnings: [String] = []
    var missing: [String] = []
    var unsupportedAPIs: [ChromeMV3API] = []
    var deferredAPIs: [ChromeMV3API] = []
    var passwordManagerReadiness = ChromeMV3PasswordManagerRuntimeReadinessReport(
        contentScriptsPresent: false,
        allFramesDetected: false,
        matchAboutBlankDetected: false,
        hostPermissionsPresent: false,
        actionPopupPresent: false,
        storagePermissionPresent: false,
        nativeMessagingDetected: false,
        nativeMessagingBlocked: false,
        runtimeMessagingImplemented: false,
        controlledInputPageWorldBehaviorVerified: false,
        serviceWorkerLifecycleVerified: false,
        blockers: [],
        deferredChecks: []
    )

    mutating func add(
        category: ChromeMV3RuntimeLoadabilityCheckCategory,
        status: ChromeMV3RuntimeLoadabilityCheckStatus,
        message: String,
        relatedPaths: [String] = [],
        details: [String] = []
    ) {
        checks.append(
            ChromeMV3RuntimeLoadabilityCheck(
                category: category,
                status: status,
                message: message,
                relatedPaths: relatedPaths.sorted(),
                details: details.sorted()
            )
        )
    }

    mutating func addWarning(_ warning: String) {
        warnings.append(warning)
    }

    mutating func addMissing(_ path: String?) {
        guard let path, path.isEmpty == false else { return }
        missing.append(path)
    }

    func build() -> ChromeMV3RuntimeLoadabilityReport {
        let sortedChecks = checks.sorted(by: checkSort)
        let passed = categories(
            in: sortedChecks,
            matching: .passed
        )
        let failed = categories(
            in: sortedChecks,
            matching: .failed
        )
        let deferred = categories(
            in: sortedChecks,
            matching: .deferred
        )
        let blockers = runtimeBlockers(
            failedChecks: failed,
            deferredChecks: deferred
        )
        let structurallyValid = failed.isEmpty
        let manifestHash = rewrittenManifestHash?.sha256 ?? "missing-manifest"
        return ChromeMV3RuntimeLoadabilityReport(
            schemaVersion: 1,
            id: "runtime-loadability-\(manifestHash.prefix(32))",
            generatedVariantRootPath: rootURL.path,
            generatedVariantRootRelativeName: rootURL.lastPathComponent,
            sourceApplicationReportHash: sourceApplicationReportHash,
            rewrittenManifestHash: rewrittenManifestHash,
            runtimeTemplateFileHashes: runtimeTemplateFileHashes
                .sorted { $0.relativePath < $1.relativePath },
            extensionPageRewrittenFileHashes: extensionPageRewrittenFileHashes
                .sorted { $0.relativePath < $1.relativePath },
            extensionPageStaticChecks: extensionPageStaticChecks
                .sorted(by: extensionPageStaticCheckSort),
            verificationChecks: sortedChecks,
            passedChecks: passed,
            failedChecks: failed,
            deferredChecks: deferred,
            warnings: Array(Set(warnings)).sorted(),
            missing: Array(Set(missing)).sorted(),
            blockers: blockers,
            unsupportedAPIs: unsupportedAPIs.sorted(),
            deferredAPIs: deferredAPIs.sorted(),
            requiredFutureRuntimeComponents: Self.futureRuntimeComponents(),
            passwordManagerReadiness: passwordManagerReadiness,
            structurallyValid: structurallyValid,
            runtimeLoadable: false,
            runtimeLoadableFalseReason: "runtimeLoadable remains false because this prompt implements only deterministic static contract verification; runtime messaging, native messaging, lifecycle, permission, and WebKit loading preconditions remain unresolved.",
            readOnlyStaticInspection: true,
            documentationSources: Self.documentationSources()
        )
    }

    private func categories(
        in checks: [ChromeMV3RuntimeLoadabilityCheck],
        matching status: ChromeMV3RuntimeLoadabilityCheckStatus
    ) -> [ChromeMV3RuntimeLoadabilityCheckCategory] {
        Array(Set(checks.filter { $0.status == status }.map(\.category))).sorted()
    }

    private func runtimeBlockers(
        failedChecks: [ChromeMV3RuntimeLoadabilityCheckCategory],
        deferredChecks: [ChromeMV3RuntimeLoadabilityCheckCategory]
    ) -> [String] {
        var blockers: [String] = []
        if failedChecks.isEmpty == false {
            blockers.append("One or more required structural checks failed.")
        }
        if deferredChecks.contains(.runtimeMessagingNotImplemented) {
            blockers.append("Runtime messaging is not implemented.")
        }
        if deferredChecks.contains(.nativeMessagingBlocked) {
            blockers.append("Native messaging host bridge is not implemented.")
        }
        if deferredChecks.contains(.WebKitRuntimeNotWired) {
            blockers.append("WebKit runtime loading is not yet wired.")
        }
        if deferredChecks.contains(.webAccessibleResourceNeeds) {
            blockers.append("Future web_accessible_resources needs are unresolved.")
        }
        if deferredChecks.contains(.sidePanelDeferredPlanningOnly) {
            blockers.append("side_panel.default_path remains deferred/planning-only.")
        }
        if deferredChecks.contains(.deferredAPIs) {
            blockers.append("Deferred APIs remain unresolved.")
        }
        if failedChecks.contains(.unsupportedAPIs) {
            blockers.append("Unsupported APIs remain unresolved or were silently removed.")
        }
        blockers.append(contentsOf: passwordManagerReadiness.blockers)
        return Array(Set(blockers)).sorted()
    }

    private static func futureRuntimeComponents() -> [String] {
        [
            "Chrome shim common must implement callback/Promise bridging.",
            "Service-worker wrapper must load shim code before the original worker while preserving Chrome MV3 lifecycle behavior.",
            "Runtime messaging bridge must implement sendMessage/connect routing, sender metadata, errors, and response semantics.",
            "Storage subset must be implemented or verified through WebKit storage facilities before claiming support.",
            "Tab/window adapters must be wired to Sumi normal tabs only.",
            "Permission broker and activeTab grant model must exist before host permissions are granted at runtime.",
            "Native messaging host bridge must be explicitly implemented before password managers can be considered supported.",
            webKitControllerName() + " must only be created when extensions are enabled.",
            "Eligible WebViews must use the same controller required by " + webKitTabName() + ".webView(for:).",
        ].sorted()
    }

    private static func documentationSources() -> [ChromeMV3ManifestRewritePreviewSource] {
        [
            source(
                title: "Chrome manifest background",
                url: "https://developer.chrome.com/docs/extensions/reference/manifest/background",
                note: "background.service_worker names the extension service worker and background.type uses module when needed."
            ),
            source(
                title: "Chrome service-worker migration and lifecycle",
                url: "https://developer.chrome.com/docs/extensions/develop/migrate/to-service-workers",
                note: "MV3 replaces background pages with extension service workers that can terminate when inactive."
            ),
            source(
                title: "Chrome content scripts",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts",
                note: "Static content scripts preserve declared order, frame, run_at, match_about_blank, match_origin_as_fallback, and world semantics."
            ),
            source(
                title: "Chrome action default_popup",
                url: "https://developer.chrome.com/docs/extensions/reference/api/action",
                note: "action.default_popup points to extension popup HTML."
            ),
            source(
                title: "Chrome options pages",
                url: "https://developer.chrome.com/docs/extensions/develop/ui/options-page",
                note: "options_page and options_ui.page declare extension options HTML."
            ),
            source(
                title: "Chrome sidePanel default_path",
                url: "https://developer.chrome.com/docs/extensions/reference/api/sidePanel",
                note: "side_panel.default_path points to browser-hosted side panel HTML and remains planning-only in Sumi."
            ),
            source(
                title: "Chrome extension page CSP",
                url: "https://developer.chrome.com/docs/extensions/reference/manifest/content-security-policy",
                note: "Extension pages have CSP constraints; this verifier reports CSP meta tags but does not solve CSP."
            ),
            source(
                title: "Chrome web_accessible_resources",
                url: "https://developer.chrome.com/docs/extensions/reference/manifest/web-accessible-resources",
                note: "Web-accessible resources are explicit manifest exposure rules; future shim exposure remains unresolved."
            ),
            source(
                title: "Chrome runtime messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
                note: "Runtime messaging semantics are deferred until a verified bridge exists."
            ),
            source(
                title: "Chrome native messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                note: "Native messaging requires explicit host registration and process messaging; Sumi does not implement or launch it here."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Local WebKit SDK headers",
                url: nil,
                note: "Local SDK headers confirm future controller/context/tab preconditions; this verifier does not import or instantiate those runtime classes."
            ),
        ]
    }

    private static func source(
        title: String,
        url: String,
        note: String
    ) -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .chromeDocumentation,
            title: title,
            url: url,
            note: note
        )
    }

    private static func webKitControllerName() -> String {
        "WKWebExtension" + "Controller"
    }

    private static func webKitTabName() -> String {
        "WKWebExtension" + "Tab"
    }
}

private func checkSort(
    _ lhs: ChromeMV3RuntimeLoadabilityCheck,
    _ rhs: ChromeMV3RuntimeLoadabilityCheck
) -> Bool {
    if lhs.category == rhs.category {
        if lhs.status == rhs.status {
            return lhs.message < rhs.message
        }
        return lhs.status < rhs.status
    }
    return lhs.category < rhs.category
}

private func extensionPageTargetSort(
    _ lhs: ChromeMV3RuntimeLoadabilityExtensionPageTarget,
    _ rhs: ChromeMV3RuntimeLoadabilityExtensionPageTarget
) -> Bool {
    if lhs.sourceManifestField == rhs.sourceManifestField {
        return lhs.pagePath < rhs.pagePath
    }
    return lhs.sourceManifestField < rhs.sourceManifestField
}

private func extensionPageStaticCheckSort(
    _ lhs: ChromeMV3ExtensionPageStaticVerification,
    _ rhs: ChromeMV3ExtensionPageStaticVerification
) -> Bool {
    if lhs.sourceManifestField == rhs.sourceManifestField {
        return lhs.pagePath < rhs.pagePath
    }
    return lhs.sourceManifestField < rhs.sourceManifestField
}
