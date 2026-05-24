//
//  ChromeMV3GeneratedRewriteApplication.swift
//  Sumi
//
//  Explicit opt-in application of Chrome MV3 dry-run rewrite candidates into a
//  separate fixture-only generated variant. This layer does not load, register,
//  or execute extension code.
//

import CryptoKit
import Foundation

struct ChromeMV3GeneratedRewriteApplicationDecision: Codable, Equatable {
    var canApplyRewriteVariant: Bool
    var blockingReasons: [String]
    var warnings: [String]
    var deferredRuntimeReasons: [String]
    var stillRuntimeLoadable: Bool
}

struct ChromeMV3GeneratedRewriteAppliedOperation: Codable, Equatable {
    var type: ChromeMV3ManifestRewritePreviewOperationType
    var sourceManifestFields: [String]
    var artifactRelativePaths: [String]
}

struct ChromeMV3GeneratedRewriteAppliedExtensionPage: Codable, Equatable {
    var context: ChromeMV3ExtensionPageShimContext
    var sourceManifestField: String
    var originalPagePath: String
    var rewrittenPagePath: String?
    var candidateRelativePath: String?
    var injectionPlacement: ChromeMV3ExtensionPageRewriteInjectionPlacement
    var shimRelativeSrcs: [String]
    var shimTagsPresent: Bool
    var nativeHostPlanningOnly: Bool
}

struct ChromeMV3GeneratedRewriteContentScriptStatus: Codable, Equatable {
    var index: Int
    var shimPrefixPaths: [String]
    var scriptPathsAfterRewrite: [String]
}

struct ChromeMV3GeneratedRewriteRuntimeLoadabilityReport: Codable, Equatable {
    var appliedRewriteOperations: [ChromeMV3GeneratedRewriteAppliedOperation]
    var copiedOrInjectedExtensionPages: [ChromeMV3GeneratedRewriteAppliedExtensionPage]
    var serviceWorkerWrapperPathNowPresentInRewrittenManifest: String?
    var contentScriptShimPathsNowPresentInRewrittenManifest: [ChromeMV3GeneratedRewriteContentScriptStatus]
    var extensionPageShimTagsNowPresentInRewrittenHTML: [ChromeMV3GeneratedRewriteAppliedExtensionPage]
    var executableRuntimeFilesWritten: Bool
    var runtimeLoadable: Bool
    var blockers: [String]
}

struct ChromeMV3GeneratedRewriteApplicationReport: Codable, Equatable {
    var schemaVersion: Int
    var id: String
    var generatedBundleRecordID: String
    var originalGeneratedBundleRootPath: String
    var rewrittenVariantRootPath: String
    var generatedManifestSHA256BeforeRewrite: String
    var dryRunReportSHA256: String
    var candidateManifestSHA256: String
    var rewrittenManifestSHA256: String
    var appliedToOriginalGeneratedBundle: Bool
    var appliedToRewrittenVariant: Bool
    var runtimeLoadable: Bool
    var executableRuntimeFilesWritten: Bool
    var copiedGeneratedResourcePaths: [String]
    var copiedRuntimeTemplatePaths: [String]
    var unsupportedAPIs: [ChromeMV3API]
    var deferredAPIs: [ChromeMV3API]
    var gateDecision: ChromeMV3GeneratedRewriteApplicationDecision
    var runtimeLoadabilityReport: ChromeMV3GeneratedRewriteRuntimeLoadabilityReport
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
    var warnings: [String]
}

struct ChromeMV3GeneratedRewriteVariantWriteResult: Equatable {
    var variantRootURL: URL
    var manifestURL: URL
    var applicationReportURL: URL
    var report: ChromeMV3GeneratedRewriteApplicationReport
}

enum ChromeMV3GeneratedRewriteVariantWriterError: LocalizedError, CustomStringConvertible {
    case gateRefused([String])
    case missingGeneratedBundle(String)
    case unsafeRelativePath(String)
    case generatedResourceEscapedBundle(String)
    case dryRunArtifactEscapedDirectory(String)
    case symbolicLinkResource(String)
    case nonRegularResource(String)
    case invalidManifestJSON(String)
    case missingCandidateArtifact(String)

    var errorDescription: String? {
        switch self {
        case .gateRefused(let reasons):
            return "Rewrite application gate refused the generated variant: \(reasons.joined(separator: "; "))"
        case .missingGeneratedBundle(let path):
            return "Missing generated bundle root: \(path)"
        case .unsafeRelativePath(let path):
            return "Unsafe rewrite variant relative path: \(path)"
        case .generatedResourceEscapedBundle(let path):
            return "Generated resource escapes generated bundle root: \(path)"
        case .dryRunArtifactEscapedDirectory(let path):
            return "Dry-run artifact escapes dry-run directory: \(path)"
        case .symbolicLinkResource(let path):
            return "Rewrite variant refuses symbolic link resource: \(path)"
        case .nonRegularResource(let path):
            return "Rewrite variant refuses non-regular resource: \(path)"
        case .invalidManifestJSON(let reason):
            return "Invalid rewritten manifest JSON: \(reason)"
        case .missingCandidateArtifact(let path):
            return "Missing rewrite candidate artifact: \(path)"
        }
    }

    var description: String {
        errorDescription ?? String(describing: self)
    }
}

enum ChromeMV3GeneratedRewriteApplicationGate {
    static func evaluate(
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord,
        generatedBundleRootURL: URL,
        runtimeResourcePlan: ChromeMV3RuntimeResourcePlan,
        manifestRewritePreview: ChromeMV3ManifestRewritePreview,
        dryRunReport: ChromeMV3ManifestRewriteDryRunVerificationReport?,
        dryRunDirectoryURL: URL
    ) -> ChromeMV3GeneratedRewriteApplicationDecision {
        var blockingReasons: [String] = []
        var warnings: [String] = []

        let rootURL = generatedBundleRootURL.standardizedFileURL
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) == false
            || isDirectory.boolValue == false
        {
            blockingReasons.append("Generated bundle root is missing or is not a directory.")
        }

        if generatedBundleRecord.generatedBundleRootPath != rootURL.path {
            blockingReasons.append("Generated bundle metadata root path does not match the requested generated bundle root.")
        }
        if generatedBundleRecord.generatedManifestPath != rootURL.appendingPathComponent("manifest.json").path {
            blockingReasons.append("Generated bundle metadata manifest path does not match manifest.json in the generated root.")
        }
        if generatedBundleRecord.runtimeLoadable {
            blockingReasons.append("Generated bundle metadata is already marked runtime-loadable.")
        }
        if generatedBundleRecord.executableRuntimeFilesWritten {
            blockingReasons.append("Generated bundle metadata says executable runtime files were written.")
        }
        if generatedBundleRecord.installReportSummary.fatalValidationErrorCodes.isEmpty == false {
            blockingReasons.append("Generated bundle has fatal validation errors.")
        }

        if runtimeResourcePlan.templatesAreInert == false {
            blockingReasons.append("Runtime resource plan is not inert.")
        }
        if runtimeResourcePlan.executableRuntimeFilesWritten {
            blockingReasons.append("Runtime resource plan says executable runtime files were written.")
        }
        if runtimeResourcePlan.runtimeLoadable {
            blockingReasons.append("Runtime resource plan is already marked runtime-loadable.")
        }
        if runtimeResourcePlan.requiredTemplateModuleNames.sorted()
            != generatedBundleRecord.plannedRuntimeTemplateModules.sorted()
        {
            blockingReasons.append("Runtime resource plan modules do not match generated bundle metadata.")
        }

        if manifestRewritePreview.appliedNow {
            blockingReasons.append("Manifest rewrite preview was already marked applied.")
        }
        if manifestRewritePreview.runtimeLoadableAfterPreview {
            blockingReasons.append("Manifest rewrite preview is marked runtime-loadable.")
        }
        if manifestRewritePreview.generatedManifestSHA256BeforeRewrite
            != generatedBundleRecord.generatedManifestSHA256
        {
            blockingReasons.append("Manifest rewrite preview does not match the generated manifest hash.")
        }
        if manifestRewritePreview.runtimeResourcePlanSHA256
            != runtimeResourcePlanHash(runtimeResourcePlan)
        {
            blockingReasons.append("Manifest rewrite preview does not match the runtime resource plan hash.")
        }

        guard let dryRunReport else {
            return decision(
                blockingReasons: blockingReasons + ["Dry-run verification report is missing."],
                warnings: warnings,
                preview: manifestRewritePreview,
                report: nil
            )
        }

        if generatedBundleRecord.manifestRewriteDryRunDirectoryPath
            != dryRunDirectoryURL.standardizedFileURL.path
        {
            blockingReasons.append("Generated bundle metadata does not point to the requested dry-run directory.")
        }
        if dryRunReport.generatedBundleRecordID != generatedBundleRecord.id {
            blockingReasons.append("Dry-run report does not reference the generated bundle record.")
        }
        if dryRunReport.generatedBundleRootPath != generatedBundleRecord.generatedBundleRootPath {
            blockingReasons.append("Dry-run report generated root does not match generated bundle metadata.")
        }
        if dryRunReport.previewID != manifestRewritePreview.id {
            blockingReasons.append("Dry-run report does not reference the manifest rewrite preview.")
        }
        if dryRunReport.previewSHA256 != generatedBundleRecord.manifestRewritePreviewSHA256 {
            blockingReasons.append("Dry-run report preview hash does not match generated bundle metadata.")
        }
        if dryRunReport.currentGeneratedManifestSHA256 != generatedBundleRecord.generatedManifestSHA256 {
            blockingReasons.append("Dry-run report does not match the current generated manifest hash.")
        }
        if dryRunReport.runtimeResourcePlanSHA256 != runtimeResourcePlanHash(runtimeResourcePlan) {
            blockingReasons.append("Dry-run report runtime resource plan hash does not match the provided plan.")
        }
        if dryRunReport.runtimeLoadableAfterDryRun {
            blockingReasons.append("Dry-run report is marked runtime-loadable.")
        }
        if dryRunReport.appliedToGeneratedManifest {
            blockingReasons.append("Dry-run report says it was applied to the generated manifest.")
        }
        if dryRunReport.appliedToGeneratedHTML {
            blockingReasons.append("Dry-run report says it was applied to generated HTML.")
        }
        if dryRunReport.runtimeTemplateArtifactsAreInert == false {
            blockingReasons.append("Dry-run report says runtime template artifacts are not inert.")
        }

        validateDryRunArtifacts(
            report: dryRunReport,
            dryRunDirectoryURL: dryRunDirectoryURL,
            blockingReasons: &blockingReasons
        )

        if dryRunReport.unsupportedAPIs.isEmpty == false {
            warnings.append(
                "Unsupported APIs remain present; they do not block fixture-only variant creation but keep it non-loadable."
            )
        }
        if dryRunReport.deferredAPIs.isEmpty == false {
            warnings.append(
                "Deferred APIs remain present; they do not block fixture-only variant creation but keep it non-loadable."
            )
        }
        if dryRunReport.operationsSkipped.isEmpty == false {
            warnings.append(
                "Some dry-run operations were skipped; only rendered candidate artifacts can be applied to the rewritten variant."
            )
        }

        return decision(
            blockingReasons: blockingReasons,
            warnings: warnings,
            preview: manifestRewritePreview,
            report: dryRunReport
        )
    }

    private static func validateDryRunArtifacts(
        report: ChromeMV3ManifestRewriteDryRunVerificationReport,
        dryRunDirectoryURL: URL,
        blockingReasons: inout [String]
    ) {
        validateArtifact(
            relativePath: report.candidateManifestRelativePath,
            expectedSHA256: report.candidateManifestSHA256,
            rootURL: dryRunDirectoryURL,
            blockingReasons: &blockingReasons
        )
        validateArtifact(
            relativePath: report.manifestDiffRelativePath,
            expectedSHA256: report.manifestDiffSHA256,
            rootURL: dryRunDirectoryURL,
            blockingReasons: &blockingReasons
        )

        for artifact in report.extensionPageArtifacts {
            validateArtifact(
                relativePath: artifact.patchReportRelativePath,
                expectedSHA256: artifact.patchReportSHA256,
                rootURL: dryRunDirectoryURL,
                blockingReasons: &blockingReasons
            )

            if artifact.renderedHTMLCandidate {
                guard
                    let candidateRelativePath = artifact.candidateRelativePath,
                    let candidateSHA256 = artifact.candidateSHA256
                else {
                    blockingReasons.append(
                        "Rendered extension-page candidate is missing path or hash for \(artifact.sourceManifestField)."
                    )
                    continue
                }
                validateArtifact(
                    relativePath: candidateRelativePath,
                    expectedSHA256: candidateSHA256,
                    rootURL: dryRunDirectoryURL,
                    blockingReasons: &blockingReasons
                )
            } else if artifact.nativeHostPlanningOnly == false
                && artifact.context != .sidePanel
            {
                blockingReasons.append(
                    "Extension-page rewrite candidate is missing for \(artifact.sourceManifestField)."
                )
            }
        }
    }

    private static func validateArtifact(
        relativePath: String,
        expectedSHA256: String,
        rootURL: URL,
        blockingReasons: inout [String]
    ) {
        do {
            let artifactURL = try safeArtifactURL(
                relativePath: relativePath,
                rootURL: rootURL
            )
            let data = try Data(contentsOf: artifactURL)
            if sha256Hex(data) != expectedSHA256 {
                blockingReasons.append("Dry-run artifact hash mismatch: \(relativePath).")
            }
        } catch {
            blockingReasons.append("Missing or invalid dry-run artifact: \(relativePath).")
        }
    }

    private static func decision(
        blockingReasons: [String],
        warnings: [String],
        preview: ChromeMV3ManifestRewritePreview,
        report: ChromeMV3ManifestRewriteDryRunVerificationReport?
    ) -> ChromeMV3GeneratedRewriteApplicationDecision {
        let reportWarnings = report?.warnings ?? []
        return ChromeMV3GeneratedRewriteApplicationDecision(
            canApplyRewriteVariant: blockingReasons.isEmpty,
            blockingReasons: Array(Set(blockingReasons)).sorted(),
            warnings: Array(Set(warnings + preview.warnings.map(\.message) + reportWarnings)).sorted(),
            deferredRuntimeReasons: deferredRuntimeReasons(
                preview: preview,
                report: report
            ),
            stillRuntimeLoadable: false
        )
    }

    private static func deferredRuntimeReasons(
        preview: ChromeMV3ManifestRewritePreview,
        report: ChromeMV3ManifestRewriteDryRunVerificationReport?
    ) -> [String] {
        var reasons = ChromeMV3GeneratedRewriteVariantWriter.baseRuntimeBlockers
        reasons.append(contentsOf: preview.unresolvedVerificationGaps)
        if report?.unsupportedAPIs.isEmpty == false
            || preview.unsupportedAPIsBlockingRuntimeLoadability.isEmpty == false
            || report?.deferredAPIs.isEmpty == false
            || preview.deferredAPIsBlockingRuntimeLoadability.isEmpty == false
        {
            reasons.append("Deferred or unsupported APIs remain unresolved.")
        }
        return Array(Set(reasons)).sorted()
    }

    private static func runtimeResourcePlanHash(
        _ plan: ChromeMV3RuntimeResourcePlan
    ) -> String? {
        guard let data = try? ChromeMV3DeterministicJSON.encodedData(plan) else {
            return nil
        }
        return sha256Hex(data)
    }

    private static func safeArtifactURL(
        relativePath: String,
        rootURL: URL
    ) throws -> URL {
        try validateSafeRelativePath(relativePath)
        let root = rootURL.standardizedFileURL
        let artifactURL = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard artifactURL.path.hasPrefix(rootPath) else {
            throw ChromeMV3GeneratedRewriteVariantWriterError
                .dryRunArtifactEscapedDirectory(artifactURL.path)
        }
        return artifactURL
    }
}

struct ChromeMV3GeneratedRewriteVariantWriter {
    static let rewrittenBundleDirectoryName = "generated-rewritten"
    static let temporaryRewrittenBundleDirectoryName = "generated-rewritten.tmp"
    static let applicationReportFileName = "generated-rewrite-application-report.json"

    static let baseRuntimeBlockers = [
        "Content-script frame/order behavior is not fixture-verified.",
        "Extension-page CSP behavior is not fixture-verified.",
        "Runtime messaging is not implemented.",
        "Native messaging host bridge is not implemented.",
        "Service-worker wrapper lifecycle is not fixture-verified.",
        "WebKit runtime loading is not yet wired.",
    ]

    var fileManager: FileManager = .default

    func writeRewrittenVariant(
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord,
        generatedBundleRootURL: URL,
        runtimeResourcePlan: ChromeMV3RuntimeResourcePlan,
        manifestRewritePreview: ChromeMV3ManifestRewritePreview,
        dryRunReport: ChromeMV3ManifestRewriteDryRunVerificationReport
    ) throws -> ChromeMV3GeneratedRewriteVariantWriteResult {
        let generatedRootURL = generatedBundleRootURL.standardizedFileURL
        let dryRunDirectoryURL = dryRunRootURL(
            generatedBundleRecord: generatedBundleRecord,
            generatedBundleRootURL: generatedRootURL
        )
        let gateDecision = ChromeMV3GeneratedRewriteApplicationGate.evaluate(
            generatedBundleRecord: generatedBundleRecord,
            generatedBundleRootURL: generatedRootURL,
            runtimeResourcePlan: runtimeResourcePlan,
            manifestRewritePreview: manifestRewritePreview,
            dryRunReport: dryRunReport,
            dryRunDirectoryURL: dryRunDirectoryURL
        )
        guard gateDecision.canApplyRewriteVariant else {
            throw ChromeMV3GeneratedRewriteVariantWriterError
                .gateRefused(gateDecision.blockingReasons)
        }

        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(
                atPath: generatedRootURL.path,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue
        else {
            throw ChromeMV3GeneratedRewriteVariantWriterError
                .missingGeneratedBundle(generatedRootURL.path)
        }

        let recordRootURL = generatedRootURL.deletingLastPathComponent()
        let variantRootURL = recordRootURL
            .appendingPathComponent(Self.rewrittenBundleDirectoryName, isDirectory: true)
        let temporaryVariantRootURL = recordRootURL
            .appendingPathComponent(Self.temporaryRewrittenBundleDirectoryName, isDirectory: true)

        if fileManager.fileExists(atPath: temporaryVariantRootURL.path) {
            try fileManager.removeItem(at: temporaryVariantRootURL)
        }
        try fileManager.createDirectory(
            at: temporaryVariantRootURL,
            withIntermediateDirectories: true
        )

        let copyResult = try copyGeneratedResources(
            from: generatedRootURL,
            to: temporaryVariantRootURL
        )
        let manifestData = try dryRunArtifactData(
            relativePath: dryRunReport.candidateManifestRelativePath,
            dryRunDirectoryURL: dryRunDirectoryURL
        )
        try manifestData.write(
            to: temporaryVariantRootURL.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )

        let appliedExtensionPages = try writeExtensionPageCandidates(
            dryRunReport.extensionPageArtifacts,
            dryRunDirectoryURL: dryRunDirectoryURL,
            to: temporaryVariantRootURL
        )

        let manifestObject = try manifestJSONObject(from: manifestData)
        let runtimeLoadabilityReport = runtimeLoadabilityReport(
            manifestObject: manifestObject,
            dryRunReport: dryRunReport,
            appliedExtensionPages: appliedExtensionPages,
            gateDecision: gateDecision
        )
        let reportWithoutSelfHash = ChromeMV3GeneratedRewriteApplicationReport(
            schemaVersion: 1,
            id: "generated-rewrite-application-\(dryRunReport.candidateManifestSHA256.prefix(32))",
            generatedBundleRecordID: generatedBundleRecord.id,
            originalGeneratedBundleRootPath: generatedRootURL.path,
            rewrittenVariantRootPath: variantRootURL.standardizedFileURL.path,
            generatedManifestSHA256BeforeRewrite: generatedBundleRecord.generatedManifestSHA256,
            dryRunReportSHA256: try dryRunReportSHA256(
                generatedBundleRecord: generatedBundleRecord,
                dryRunDirectoryURL: dryRunDirectoryURL
            ),
            candidateManifestSHA256: dryRunReport.candidateManifestSHA256,
            rewrittenManifestSHA256: sha256Hex(manifestData),
            appliedToOriginalGeneratedBundle: false,
            appliedToRewrittenVariant: true,
            runtimeLoadable: false,
            executableRuntimeFilesWritten: false,
            copiedGeneratedResourcePaths: copyResult.copiedResourcePaths,
            copiedRuntimeTemplatePaths: copyResult.copiedRuntimeTemplatePaths,
            unsupportedAPIs: dryRunReport.unsupportedAPIs.sorted(),
            deferredAPIs: dryRunReport.deferredAPIs.sorted(),
            gateDecision: gateDecision,
            runtimeLoadabilityReport: runtimeLoadabilityReport,
            documentationSources: dryRunReport.documentationSources,
            warnings: Array(Set(gateDecision.warnings + dryRunReport.warnings)).sorted()
        )

        try ChromeMV3DeterministicJSON.write(
            reportWithoutSelfHash,
            to: temporaryVariantRootURL
                .appendingPathComponent(Self.applicationReportFileName)
        )

        if fileManager.fileExists(atPath: variantRootURL.path) {
            try fileManager.removeItem(at: variantRootURL)
        }
        try fileManager.moveItem(at: temporaryVariantRootURL, to: variantRootURL)

        try ChromeMV3RuntimeLoadabilityVerifier()
            .writeReport(forRewrittenVariantAt: variantRootURL)

        let reportURL = variantRootURL
            .appendingPathComponent(Self.applicationReportFileName)
        let report = try decodeApplicationReport(at: reportURL)

        return ChromeMV3GeneratedRewriteVariantWriteResult(
            variantRootURL: variantRootURL,
            manifestURL: variantRootURL.appendingPathComponent("manifest.json"),
            applicationReportURL: reportURL,
            report: report
        )
    }

    private func copyGeneratedResources(
        from generatedRootURL: URL,
        to variantRootURL: URL
    ) throws -> (copiedResourcePaths: [String], copiedRuntimeTemplatePaths: [String]) {
        let generatedRoot = generatedRootURL.standardizedFileURL
        guard
            let enumerator = fileManager.enumerator(
                at: generatedRoot,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ]
            )
        else {
            throw ChromeMV3GeneratedRewriteVariantWriterError
                .missingGeneratedBundle(generatedRoot.path)
        }

        var resourceURLs: [(url: URL, relativePath: String)] = []
        let rootPath = generatedRoot.path.hasSuffix("/")
            ? generatedRoot.path
            : generatedRoot.path + "/"
        for case let url as URL in enumerator {
            let standardizedURL = url.standardizedFileURL
            guard standardizedURL.path.hasPrefix(rootPath) else {
                throw ChromeMV3GeneratedRewriteVariantWriterError
                    .generatedResourceEscapedBundle(standardizedURL.path)
            }
            let relativePath = String(standardizedURL.path.dropFirst(rootPath.count))
            try validateSafeRelativePath(relativePath)
            guard shouldCopyGeneratedResource(relativePath) else { continue }

            let values = try standardizedURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            if values.isSymbolicLink == true {
                throw ChromeMV3GeneratedRewriteVariantWriterError
                    .symbolicLinkResource(relativePath)
            }
            guard values.isRegularFile == true else { continue }
            resourceURLs.append((standardizedURL, relativePath))
        }

        var copied: [String] = []
        var runtimeTemplates: [String] = []
        for resource in resourceURLs.sorted(by: { $0.relativePath < $1.relativePath }) {
            let destinationURL = variantRootURL
                .appendingPathComponent(resource.relativePath)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Data(contentsOf: resource.url)
            try data.write(to: destinationURL, options: [.atomic])
            copied.append(resource.relativePath)
            if resource.relativePath.hasPrefix(
                ChromeMV3RuntimeResourceTemplateCatalog.runtimeDirectoryName + "/"
            ) {
                runtimeTemplates.append(resource.relativePath)
            }
        }

        return (copied.sorted(), runtimeTemplates.sorted())
    }

    private func writeExtensionPageCandidates(
        _ artifacts: [ChromeMV3ExtensionPageRewriteCandidateArtifact],
        dryRunDirectoryURL: URL,
        to variantRootURL: URL
    ) throws -> [ChromeMV3GeneratedRewriteAppliedExtensionPage] {
        var applied: [ChromeMV3GeneratedRewriteAppliedExtensionPage] = []

        for artifact in artifacts.sorted(by: extensionPageArtifactSort) {
            guard artifact.renderedHTMLCandidate else {
                applied.append(
                    ChromeMV3GeneratedRewriteAppliedExtensionPage(
                        context: artifact.context,
                        sourceManifestField: artifact.sourceManifestField,
                        originalPagePath: artifact.originalPagePath,
                        rewrittenPagePath: nil,
                        candidateRelativePath: artifact.candidateRelativePath,
                        injectionPlacement: artifact.injectionPlacement,
                        shimRelativeSrcs: artifact.shimRelativeSrcs,
                        shimTagsPresent: false,
                        nativeHostPlanningOnly: artifact.nativeHostPlanningOnly
                    )
                )
                continue
            }

            guard
                let normalizedPagePath = artifact.normalizedPagePath,
                let candidateRelativePath = artifact.candidateRelativePath
            else {
                throw ChromeMV3GeneratedRewriteVariantWriterError
                    .missingCandidateArtifact(artifact.sourceManifestField)
            }
            try validateSafeRelativePath(normalizedPagePath)
            let candidateData = try dryRunArtifactData(
                relativePath: candidateRelativePath,
                dryRunDirectoryURL: dryRunDirectoryURL
            )
            let destinationURL = variantRootURL
                .appendingPathComponent(normalizedPagePath)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try candidateData.write(to: destinationURL, options: [.atomic])
            let html = String(data: candidateData, encoding: .utf8) ?? ""
            let shimTagsPresent = artifact.shimRelativeSrcs.allSatisfy {
                html.contains("<script src=\"\($0)\"></script>")
            }

            applied.append(
                ChromeMV3GeneratedRewriteAppliedExtensionPage(
                    context: artifact.context,
                    sourceManifestField: artifact.sourceManifestField,
                    originalPagePath: artifact.originalPagePath,
                    rewrittenPagePath: normalizedPagePath,
                    candidateRelativePath: candidateRelativePath,
                    injectionPlacement: artifact.injectionPlacement,
                    shimRelativeSrcs: artifact.shimRelativeSrcs,
                    shimTagsPresent: shimTagsPresent,
                    nativeHostPlanningOnly: artifact.nativeHostPlanningOnly
                )
            )
        }

        return applied.sorted {
            if $0.sourceManifestField == $1.sourceManifestField {
                return $0.originalPagePath < $1.originalPagePath
            }
            return $0.sourceManifestField < $1.sourceManifestField
        }
    }

    private func runtimeLoadabilityReport(
        manifestObject: [String: Any],
        dryRunReport: ChromeMV3ManifestRewriteDryRunVerificationReport,
        appliedExtensionPages: [ChromeMV3GeneratedRewriteAppliedExtensionPage],
        gateDecision: ChromeMV3GeneratedRewriteApplicationDecision
    ) -> ChromeMV3GeneratedRewriteRuntimeLoadabilityReport {
        let serviceWorkerWrapperPath = (manifestObject["background"] as? [String: Any])?["service_worker"] as? String
        let contentScriptStatuses = contentScriptStatuses(in: manifestObject)
        let shimmedPages = appliedExtensionPages
            .filter(\.shimTagsPresent)
            .sorted {
                if $0.sourceManifestField == $1.sourceManifestField {
                    return $0.originalPagePath < $1.originalPagePath
                }
                return $0.sourceManifestField < $1.sourceManifestField
            }
        let operations = dryRunReport.operationsRendered.map {
            ChromeMV3GeneratedRewriteAppliedOperation(
                type: $0.type,
                sourceManifestFields: $0.sourceManifestFields,
                artifactRelativePaths: $0.artifactRelativePaths
            )
        }
        .sorted {
            if $0.type == $1.type {
                return $0.sourceManifestFields.joined(separator: ".")
                    < $1.sourceManifestFields.joined(separator: ".")
            }
            return $0.type < $1.type
        }

        return ChromeMV3GeneratedRewriteRuntimeLoadabilityReport(
            appliedRewriteOperations: operations,
            copiedOrInjectedExtensionPages: appliedExtensionPages,
            serviceWorkerWrapperPathNowPresentInRewrittenManifest: serviceWorkerWrapperPath,
            contentScriptShimPathsNowPresentInRewrittenManifest: contentScriptStatuses,
            extensionPageShimTagsNowPresentInRewrittenHTML: shimmedPages,
            executableRuntimeFilesWritten: false,
            runtimeLoadable: false,
            blockers: gateDecision.deferredRuntimeReasons
        )
    }

    private func contentScriptStatuses(
        in manifestObject: [String: Any]
    ) -> [ChromeMV3GeneratedRewriteContentScriptStatus] {
        guard let scripts = manifestObject["content_scripts"] as? [[String: Any]] else {
            return []
        }

        return scripts.enumerated().map { index, script in
            let js = script["js"] as? [String] ?? []
            let shimPrefix = js.prefix {
                $0.hasPrefix(
                    ChromeMV3RuntimeResourceTemplateCatalog.runtimeDirectoryName + "/"
                )
            }
            return ChromeMV3GeneratedRewriteContentScriptStatus(
                index: index,
                shimPrefixPaths: Array(shimPrefix),
                scriptPathsAfterRewrite: js
            )
        }
        .sorted { $0.index < $1.index }
    }

    private func dryRunRootURL(
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord,
        generatedBundleRootURL: URL
    ) -> URL {
        if let path = generatedBundleRecord.manifestRewriteDryRunDirectoryPath {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        return generatedBundleRootURL
            .appendingPathComponent(
                ChromeMV3ManifestRewriteDryRunRenderer.dryRunDirectoryName,
                isDirectory: true
            )
            .standardizedFileURL
    }

    private func dryRunArtifactData(
        relativePath: String,
        dryRunDirectoryURL: URL
    ) throws -> Data {
        let artifactURL = try safeDryRunArtifactURL(
            relativePath: relativePath,
            dryRunDirectoryURL: dryRunDirectoryURL
        )
        guard fileManager.fileExists(atPath: artifactURL.path) else {
            throw ChromeMV3GeneratedRewriteVariantWriterError
                .missingCandidateArtifact(relativePath)
        }
        return try Data(contentsOf: artifactURL)
    }

    private func safeDryRunArtifactURL(
        relativePath: String,
        dryRunDirectoryURL: URL
    ) throws -> URL {
        try validateSafeRelativePath(relativePath)
        let rootURL = dryRunDirectoryURL.standardizedFileURL
        let artifactURL = rootURL
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/")
            ? rootURL.path
            : rootURL.path + "/"
        guard artifactURL.path.hasPrefix(rootPath) else {
            throw ChromeMV3GeneratedRewriteVariantWriterError
                .dryRunArtifactEscapedDirectory(artifactURL.path)
        }
        return artifactURL
    }

    private func shouldCopyGeneratedResource(_ relativePath: String) -> Bool {
        if relativePath == "manifest.json" {
            return false
        }
        if relativePath == ChromeMV3GeneratedBundleWriter.metadataFileName
            || relativePath == ChromeMV3GeneratedBundleWriter.runtimeResourcePlanFileName
            || relativePath == ChromeMV3GeneratedBundleWriter.manifestRewritePreviewFileName
            || relativePath == Self.applicationReportFileName
        {
            return false
        }
        if relativePath.hasPrefix(
            ChromeMV3ManifestRewriteDryRunRenderer.dryRunDirectoryName + "/"
        ) {
            return false
        }
        return true
    }

    private func dryRunReportSHA256(
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord,
        dryRunDirectoryURL: URL
    ) throws -> String {
        let reportURL: URL
        if let path = generatedBundleRecord.manifestRewriteDryRunReportPath {
            reportURL = URL(fileURLWithPath: path).standardizedFileURL
        } else {
            reportURL = dryRunDirectoryURL
                .appendingPathComponent(
                    ChromeMV3ManifestRewriteDryRunRenderer.verificationReportFileName
                )
        }
        let data = try Data(contentsOf: reportURL)
        return sha256Hex(data)
    }

    private func manifestJSONObject(from data: Data) throws -> [String: Any] {
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let manifest = object as? [String: Any] else {
                throw ChromeMV3GeneratedRewriteVariantWriterError
                    .invalidManifestJSON("top-level manifest value is not an object")
            }
            return manifest
        } catch let error as ChromeMV3GeneratedRewriteVariantWriterError {
            throw error
        } catch {
            throw ChromeMV3GeneratedRewriteVariantWriterError
                .invalidManifestJSON(error.localizedDescription)
        }
    }

    private func decodeApplicationReport(
        at url: URL
    ) throws -> ChromeMV3GeneratedRewriteApplicationReport {
        try JSONDecoder().decode(
            ChromeMV3GeneratedRewriteApplicationReport.self,
            from: Data(contentsOf: url)
        )
    }
}

private func validateSafeRelativePath(_ relativePath: String) throws {
    guard relativePath.isEmpty == false else {
        throw ChromeMV3GeneratedRewriteVariantWriterError.unsafeRelativePath(
            relativePath
        )
    }
    guard
        relativePath.hasPrefix("/") == false,
        relativePath.hasPrefix("~") == false,
        relativePath.contains("\\") == false,
        relativePath.contains("\0") == false,
        relativePath.localizedCaseInsensitiveContains("://") == false
    else {
        throw ChromeMV3GeneratedRewriteVariantWriterError.unsafeRelativePath(
            relativePath
        )
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
        throw ChromeMV3GeneratedRewriteVariantWriterError.unsafeRelativePath(
            relativePath
        )
    }
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func extensionPageArtifactSort(
    _ lhs: ChromeMV3ExtensionPageRewriteCandidateArtifact,
    _ rhs: ChromeMV3ExtensionPageRewriteCandidateArtifact
) -> Bool {
    if lhs.sourceManifestField == rhs.sourceManifestField {
        return lhs.originalPagePath < rhs.originalPagePath
    }
    return lhs.sourceManifestField < rhs.sourceManifestField
}
