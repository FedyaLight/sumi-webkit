//
//  ChromeMV3ManifestRewriteDryRunRenderer.swift
//  Sumi
//
//  Deterministic dry-run rendering for Chrome MV3 manifest/HTML rewrite
//  candidates. This file writes separate candidate artifacts only; it does not
//  apply rewrites to generated runtime files, load extensions, or execute code.
//

import CryptoKit
import Foundation

enum ChromeMV3ManifestRewriteDryRunRendererError: LocalizedError, CustomStringConvertible {
    case invalidManifestJSON(String)
    case unsafePagePath(field: String, path: String)
    case generatedPageEscapesBundle(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifestJSON(let reason):
            return "Invalid generated manifest JSON for rewrite dry run: \(reason)"
        case .unsafePagePath(let field, let path):
            return "Unsafe extension-page path '\(path)' in \(field)"
        case .generatedPageEscapesBundle(let path):
            return "Extension-page dry-run input escapes generated bundle root: \(path)"
        }
    }

    var description: String {
        errorDescription ?? String(describing: self)
    }
}

enum ChromeMV3ManifestRewriteDryRunArtifactKind: String, Codable, Comparable {
    case extensionPageHTMLCandidate
    case extensionPagePatchReport
    case manifestCandidate
    case manifestDiff
    case verificationReport

    static func < (
        lhs: ChromeMV3ManifestRewriteDryRunArtifactKind,
        rhs: ChromeMV3ManifestRewriteDryRunArtifactKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ManifestRewriteDryRunArtifactHash: Codable, Equatable {
    var kind: ChromeMV3ManifestRewriteDryRunArtifactKind
    var relativePath: String
    var sha256: String
    var byteCount: Int
}

enum ChromeMV3ManifestRewriteDryRunPatchOperation: String, Codable {
    case prependArrayItems
    case recordMetadata
    case replaceValue
}

struct ChromeMV3ManifestRewriteDryRunManifestDiffEntry: Codable, Equatable {
    var operation: ChromeMV3ManifestRewriteDryRunPatchOperation
    var previewOperationType: ChromeMV3ManifestRewritePreviewOperationType
    var sourceManifestField: String
    var jsonPointer: String
    var previousValue: JSONValue?
    var candidateValue: JSONValue?
    var insertedValues: [JSONValue]
    var preservedFields: [String]
    var note: String
}

struct ChromeMV3ManifestRewriteDryRunManifestDiff: Codable, Equatable {
    var schemaVersion: Int
    var previewID: String
    var originalGeneratedManifestSHA256: String
    var candidateManifestSHA256: String
    var appliedToGeneratedManifest: Bool
    var entries: [ChromeMV3ManifestRewriteDryRunManifestDiffEntry]
}

enum ChromeMV3ExtensionPageRewriteInjectionPlacement: String, Codable, Comparable {
    case beforeClosingHead
    case documentStartFallbackNoHead
    case planningOnlyDeferred
    case skippedMissingGeneratedHTML
    case skippedUnsafePagePath

    static func < (
        lhs: ChromeMV3ExtensionPageRewriteInjectionPlacement,
        rhs: ChromeMV3ExtensionPageRewriteInjectionPlacement
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ExtensionPageRewritePatchDescription: Codable, Equatable {
    var schemaVersion: Int
    var context: ChromeMV3ExtensionPageShimContext
    var sourceManifestField: String
    var originalPagePath: String
    var normalizedPagePath: String?
    var candidateRelativePath: String?
    var injectionPlacement: ChromeMV3ExtensionPageRewriteInjectionPlacement
    var plannedShimPaths: [String]
    var shimRelativeSrcs: [String]
    var nativeHostPlanningOnly: Bool
    var renderedHTMLCandidate: Bool
    var appliedToGeneratedHTML: Bool
    var warnings: [String]
}

struct ChromeMV3ExtensionPageRewriteCandidateArtifact: Codable, Equatable {
    var context: ChromeMV3ExtensionPageShimContext
    var sourceManifestField: String
    var originalPagePath: String
    var normalizedPagePath: String?
    var candidateRelativePath: String?
    var candidateSHA256: String?
    var patchReportRelativePath: String
    var patchReportSHA256: String
    var injectionPlacement: ChromeMV3ExtensionPageRewriteInjectionPlacement
    var shimPaths: [String]
    var shimRelativeSrcs: [String]
    var nativeHostPlanningOnly: Bool
    var renderedHTMLCandidate: Bool
    var appliedToGeneratedHTML: Bool
    var warnings: [String]
}

struct ChromeMV3ManifestRewriteDryRunRenderedOperation: Codable, Equatable {
    var order: Int
    var type: ChromeMV3ManifestRewritePreviewOperationType
    var sourceManifestFields: [String]
    var renderedSurface: String
    var artifactRelativePaths: [String]
}

struct ChromeMV3ManifestRewriteDryRunSkippedOperation: Codable, Equatable {
    var order: Int
    var type: ChromeMV3ManifestRewritePreviewOperationType
    var sourceManifestFields: [String]
    var reason: String
}

struct ChromeMV3ManifestRewriteDryRunVerificationReport: Codable, Equatable {
    var schemaVersion: Int
    var id: String
    var generatedBundleRecordID: String
    var generatedBundleRootPath: String
    var previewID: String
    var previewSHA256: String
    var runtimeResourcePlanSHA256: String?
    var currentGeneratedManifestSHA256: String
    var candidateManifestRelativePath: String
    var candidateManifestSHA256: String
    var manifestDiffRelativePath: String
    var manifestDiffSHA256: String
    var extensionPageArtifacts: [ChromeMV3ExtensionPageRewriteCandidateArtifact]
    var artifactHashes: [ChromeMV3ManifestRewriteDryRunArtifactHash]
    var operationsRendered: [ChromeMV3ManifestRewriteDryRunRenderedOperation]
    var operationsSkipped: [ChromeMV3ManifestRewriteDryRunSkippedOperation]
    var warnings: [String]
    var unsupportedAPIs: [ChromeMV3API]
    var deferredAPIs: [ChromeMV3API]
    var unresolvedFixtureVerificationGaps: [String]
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
    var runtimeTemplateArtifactsAreInert: Bool
    var runtimeLoadableAfterDryRun: Bool
    var appliedToGeneratedManifest: Bool
    var appliedToGeneratedHTML: Bool
}

struct ChromeMV3ManifestRewriteDryRunResult: Equatable {
    var dryRunDirectoryURL: URL
    var manifestCandidateURL: URL
    var manifestDiffURL: URL
    var verificationReportURL: URL
    var verificationReportSHA256: String
    var artifactHashes: [ChromeMV3ManifestRewriteDryRunArtifactHash]
}

struct ChromeMV3ManifestRewriteDryRunRenderer {
    static let dryRunDirectoryName = "_sumi_rewrite_dry_run"
    static let extensionPagesDirectoryName = "extension-pages"
    static let manifestCandidateFileName = "manifest.rewrite-candidate.json"
    static let manifestDiffFileName = "manifest.rewrite-diff.json"
    static let verificationReportFileName = "rewrite-verification-report.json"

    var fileManager: FileManager = .default

    func renderDryRun(
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord,
        generatedBundleRootURL: URL,
        manifestRewritePreview: ChromeMV3ManifestRewritePreview,
        manifestRewritePreviewData: Data,
        runtimeResourcePlan: ChromeMV3RuntimeResourcePlan,
        currentGeneratedManifestURL: URL
    ) throws -> ChromeMV3ManifestRewriteDryRunResult {
        let dryRunRootURL = generatedBundleRootURL
            .appendingPathComponent(Self.dryRunDirectoryName, isDirectory: true)
        let extensionPagesURL = dryRunRootURL
            .appendingPathComponent(Self.extensionPagesDirectoryName, isDirectory: true)

        if fileManager.fileExists(atPath: dryRunRootURL.path) {
            try fileManager.removeItem(at: dryRunRootURL)
        }
        try fileManager.createDirectory(
            at: extensionPagesURL,
            withIntermediateDirectories: true
        )

        let generatedManifestData = try Data(contentsOf: currentGeneratedManifestURL)
        let generatedManifestObject = try manifestJSONObject(from: generatedManifestData)
        let currentGeneratedManifestSHA256 = sha256Hex(generatedManifestData)

        var renderedOperations: [ChromeMV3ManifestRewriteDryRunRenderedOperation] = []
        var skippedOperations: [ChromeMV3ManifestRewriteDryRunSkippedOperation] = []
        var warnings: [String] = manifestRewritePreview.warnings.map(\.message)

        let manifestCandidate = renderManifestCandidate(
            from: generatedManifestObject,
            preview: manifestRewritePreview,
            renderedOperations: &renderedOperations,
            skippedOperations: &skippedOperations,
            warnings: &warnings
        )
        let manifestCandidateData = try canonicalJSONData(manifestCandidate.object)
        let manifestCandidateURL = dryRunRootURL
            .appendingPathComponent(Self.manifestCandidateFileName)
        try manifestCandidateData.write(to: manifestCandidateURL, options: [.atomic])
        let manifestCandidateSHA256 = sha256Hex(manifestCandidateData)

        let manifestDiff = ChromeMV3ManifestRewriteDryRunManifestDiff(
            schemaVersion: 1,
            previewID: manifestRewritePreview.id,
            originalGeneratedManifestSHA256: currentGeneratedManifestSHA256,
            candidateManifestSHA256: manifestCandidateSHA256,
            appliedToGeneratedManifest: false,
            entries: manifestCandidate.diffEntries
        )
        let manifestDiffURL = dryRunRootURL
            .appendingPathComponent(Self.manifestDiffFileName)
        try ChromeMV3DeterministicJSON.write(manifestDiff, to: manifestDiffURL)
        let manifestDiffData = try Data(contentsOf: manifestDiffURL)
        let manifestDiffSHA256 = sha256Hex(manifestDiffData)

        let extensionPageOutput = try renderExtensionPageCandidates(
            preview: manifestRewritePreview,
            generatedBundleRootURL: generatedBundleRootURL,
            extensionPagesURL: extensionPagesURL,
            renderedOperations: &renderedOperations,
            skippedOperations: &skippedOperations,
            warnings: &warnings
        )

        appendReportOnlyOperations(
            preview: manifestRewritePreview,
            renderedOperations: &renderedOperations
        )

        var artifactHashes = [
            artifactHash(
                kind: .manifestCandidate,
                relativePath: Self.manifestCandidateFileName,
                data: manifestCandidateData
            ),
            artifactHash(
                kind: .manifestDiff,
                relativePath: Self.manifestDiffFileName,
                data: manifestDiffData
            ),
        ]
        artifactHashes.append(contentsOf: extensionPageOutput.artifactHashes)
        artifactHashes.sort(by: artifactHashSort)

        let reportWithoutSelf = ChromeMV3ManifestRewriteDryRunVerificationReport(
            schemaVersion: 1,
            id: "rewrite-dry-run-\(manifestCandidateSHA256.prefix(32))",
            generatedBundleRecordID: generatedBundleRecord.id,
            generatedBundleRootPath: generatedBundleRecord.generatedBundleRootPath,
            previewID: manifestRewritePreview.id,
            previewSHA256: sha256Hex(manifestRewritePreviewData),
            runtimeResourcePlanSHA256: manifestRewritePreview.runtimeResourcePlanSHA256,
            currentGeneratedManifestSHA256: currentGeneratedManifestSHA256,
            candidateManifestRelativePath: Self.manifestCandidateFileName,
            candidateManifestSHA256: manifestCandidateSHA256,
            manifestDiffRelativePath: Self.manifestDiffFileName,
            manifestDiffSHA256: manifestDiffSHA256,
            extensionPageArtifacts: extensionPageOutput.artifacts.sorted(
                by: extensionPageArtifactSort
            ),
            artifactHashes: artifactHashes,
            operationsRendered: renderedOperations.sorted(by: renderedOperationSort),
            operationsSkipped: skippedOperations.sorted(by: skippedOperationSort),
            warnings: Array(Set(warnings)).sorted(),
            unsupportedAPIs: manifestRewritePreview
                .unsupportedAPIsBlockingRuntimeLoadability
                .sorted(),
            deferredAPIs: manifestRewritePreview
                .deferredAPIsBlockingRuntimeLoadability
                .sorted(),
            unresolvedFixtureVerificationGaps: manifestRewritePreview
                .unresolvedVerificationGaps
                .sorted(),
            documentationSources: documentationSources(from: manifestRewritePreview),
            runtimeTemplateArtifactsAreInert: runtimeResourcePlan.templatesAreInert,
            runtimeLoadableAfterDryRun: false,
            appliedToGeneratedManifest: false,
            appliedToGeneratedHTML: false
        )
        let verificationReportURL = dryRunRootURL
            .appendingPathComponent(Self.verificationReportFileName)
        try ChromeMV3DeterministicJSON.write(
            reportWithoutSelf,
            to: verificationReportURL
        )
        let verificationReportData = try Data(contentsOf: verificationReportURL)
        let verificationReportSHA256 = sha256Hex(verificationReportData)
        artifactHashes.append(
            artifactHash(
                kind: .verificationReport,
                relativePath: Self.verificationReportFileName,
                data: verificationReportData
            )
        )
        artifactHashes.sort(by: artifactHashSort)

        return ChromeMV3ManifestRewriteDryRunResult(
            dryRunDirectoryURL: dryRunRootURL,
            manifestCandidateURL: manifestCandidateURL,
            manifestDiffURL: manifestDiffURL,
            verificationReportURL: verificationReportURL,
            verificationReportSHA256: verificationReportSHA256,
            artifactHashes: artifactHashes
        )
    }

    private func renderManifestCandidate(
        from manifestObject: [String: Any],
        preview: ChromeMV3ManifestRewritePreview,
        renderedOperations: inout [ChromeMV3ManifestRewriteDryRunRenderedOperation],
        skippedOperations: inout [ChromeMV3ManifestRewriteDryRunSkippedOperation],
        warnings: inout [String]
    ) -> (object: [String: Any], diffEntries: [ChromeMV3ManifestRewriteDryRunManifestDiffEntry]) {
        var candidate = manifestObject
        var diffEntries: [ChromeMV3ManifestRewriteDryRunManifestDiffEntry] = []

        for operation in preview.plannedOperations.sorted(by: previewOperationSort) {
            switch operation.type {
            case .replaceServiceWorkerWithWrapper:
                guard
                    let serviceWorker = operation.serviceWorker,
                    var background = candidate["background"] as? [String: Any]
                else {
                    skippedOperations.append(skipped(operation, reason: "Missing background.service_worker preview metadata."))
                    continue
                }

                let previousValue = background["service_worker"]
                background["service_worker"] = serviceWorker.futureWrapperPath
                candidate["background"] = background
                diffEntries.append(
                    ChromeMV3ManifestRewriteDryRunManifestDiffEntry(
                        operation: .replaceValue,
                        previewOperationType: operation.type,
                        sourceManifestField: "background.service_worker",
                        jsonPointer: "/background/service_worker",
                        previousValue: previousValue.map(JSONValue.init(any:)),
                        candidateValue: JSONValue.string(serviceWorker.futureWrapperPath),
                        insertedValues: [],
                        preservedFields: background["type"] == nil ? [] : ["background.type"],
                        note: "Candidate-only service worker wrapper path; generated manifest is not changed."
                    )
                )
                renderedOperations.append(
                    rendered(
                        operation,
                        surface: "manifest-candidate",
                        artifacts: [Self.manifestCandidateFileName]
                    )
                )

            case .preserveOriginalServiceWorkerPath:
                guard let serviceWorker = operation.serviceWorker else {
                    skippedOperations.append(skipped(operation, reason: "Missing original service worker preview metadata."))
                    continue
                }
                diffEntries.append(
                    ChromeMV3ManifestRewriteDryRunManifestDiffEntry(
                        operation: .recordMetadata,
                        previewOperationType: operation.type,
                        sourceManifestField: "background.service_worker",
                        jsonPointer: "/background/service_worker",
                        previousValue: JSONValue.string(serviceWorker.originalServiceWorkerPath),
                        candidateValue: nil,
                        insertedValues: [],
                        preservedFields: ["manifest.background.service_worker not annotated"],
                        note: "Original service worker path is recorded in dry-run reports only."
                    )
                )
                renderedOperations.append(
                    rendered(
                        operation,
                        surface: "manifest-diff",
                        artifacts: [Self.manifestDiffFileName]
                    )
                )

            case .prependContentScriptShims:
                guard
                    let contentScript = operation.contentScript,
                    var scripts = candidate["content_scripts"] as? [[String: Any]],
                    scripts.indices.contains(contentScript.index)
                else {
                    skippedOperations.append(skipped(operation, reason: "Missing content_scripts entry for planned shim prepend."))
                    continue
                }

                var script = scripts[contentScript.index]
                let previousScripts = stringArray(script["js"])
                let plannedScripts = contentScript.plannedShimPrefix + previousScripts
                script["js"] = plannedScripts
                scripts[contentScript.index] = script
                candidate["content_scripts"] = scripts
                diffEntries.append(
                    ChromeMV3ManifestRewriteDryRunManifestDiffEntry(
                        operation: .prependArrayItems,
                        previewOperationType: operation.type,
                        sourceManifestField: contentScript.sourceManifestField + ".js",
                        jsonPointer: "/content_scripts/\(contentScript.index)/js",
                        previousValue: JSONValue.array(previousScripts.map(JSONValue.string)),
                        candidateValue: JSONValue.array(plannedScripts.map(JSONValue.string)),
                        insertedValues: contentScript.plannedShimPrefix.map(JSONValue.string),
                        preservedFields: preservedContentScriptFields(in: script),
                        note: "Candidate-only shim prefix; original content script order follows the prefix unchanged."
                    )
                )
                renderedOperations.append(
                    rendered(
                        operation,
                        surface: "manifest-candidate",
                        artifacts: [Self.manifestCandidateFileName]
                    )
                )

            case .injectExtensionPageShimMetadata,
                 .recordHostBridgeDeferred,
                 .recordUnsupportedAPIs,
                 .recordDeferredNativeHostAPIs,
                 .recordFixtureVerificationRequired:
                continue
            }
        }

        if preview.unsupportedAPIsBlockingRuntimeLoadability.isEmpty == false {
            warnings.append("Unsupported APIs remain present in the candidate manifest and keep the dry run not runtime-loadable.")
        }
        if preview.deferredAPIsBlockingRuntimeLoadability.isEmpty == false {
            warnings.append("Deferred APIs remain present in the candidate manifest and keep the dry run not runtime-loadable.")
        }

        return (candidate, diffEntries.sorted(by: diffEntrySort))
    }

    private func renderExtensionPageCandidates(
        preview: ChromeMV3ManifestRewritePreview,
        generatedBundleRootURL: URL,
        extensionPagesURL: URL,
        renderedOperations: inout [ChromeMV3ManifestRewriteDryRunRenderedOperation],
        skippedOperations: inout [ChromeMV3ManifestRewriteDryRunSkippedOperation],
        warnings: inout [String]
    ) throws -> (artifacts: [ChromeMV3ExtensionPageRewriteCandidateArtifact], artifactHashes: [ChromeMV3ManifestRewriteDryRunArtifactHash]) {
        var artifacts: [ChromeMV3ExtensionPageRewriteCandidateArtifact] = []
        var artifactHashes: [ChromeMV3ManifestRewriteDryRunArtifactHash] = []

        for operation in preview.plannedOperations.sorted(by: previewOperationSort) {
            guard
                operation.type == .injectExtensionPageShimMetadata,
                let target = operation.extensionPage
            else { continue }

            let baseName = extensionPageArtifactBaseName(for: target)
            let patchReportRelativePath = Self.extensionPagesDirectoryName
                + "/"
                + baseName
                + ".rewrite-patch.json"
            let patchReportURL = extensionPagesURL
                .appendingPathComponent(baseName + ".rewrite-patch.json")

            if target.nativeHostPlanningOnly || target.context == .sidePanel {
                let patch = extensionPagePatchDescription(
                    target: target,
                    normalizedPagePath: nil,
                    candidateRelativePath: nil,
                    placement: .planningOnlyDeferred,
                    shimRelativeSrcs: [],
                    renderedHTMLCandidate: false,
                    warnings: [
                        "Side panel remains deferred/native-host planning only; no HTML candidate is rendered.",
                        cspWarning,
                    ]
                )
                try ChromeMV3DeterministicJSON.write(patch, to: patchReportURL)
                let patchData = try Data(contentsOf: patchReportURL)
                let patchSHA256 = sha256Hex(patchData)
                artifacts.append(
                    extensionPageArtifact(
                        target: target,
                        normalizedPagePath: nil,
                        candidateRelativePath: nil,
                        candidateSHA256: nil,
                        patchReportRelativePath: patchReportRelativePath,
                        patchReportSHA256: patchSHA256,
                        placement: .planningOnlyDeferred,
                        shimRelativeSrcs: [],
                        renderedHTMLCandidate: false,
                        warnings: patch.warnings
                    )
                )
                artifactHashes.append(
                    artifactHash(
                        kind: .extensionPagePatchReport,
                        relativePath: patchReportRelativePath,
                        data: patchData
                    )
                )
                renderedOperations.append(
                    rendered(
                        operation,
                        surface: "extension-page-patch-report",
                        artifacts: [patchReportRelativePath]
                    )
                )
                skippedOperations.append(
                    skipped(
                        operation,
                        reason: "HTML candidate skipped because sidePanel.default_path is deferred/native-host planning only."
                    )
                )
                warnings.append(contentsOf: patch.warnings)
                continue
            }

            let normalizedPagePath: String
            let pageURL: URL
            do {
                normalizedPagePath = try normalizedResourcePath(
                    target.pagePath,
                    field: target.sourceManifestField
                )
                pageURL = try safeGeneratedResourceURL(
                    relativePath: normalizedPagePath,
                    rootURL: generatedBundleRootURL,
                    field: target.sourceManifestField
                )
            } catch let error as ChromeMV3ManifestRewriteDryRunRendererError {
                let patch = extensionPagePatchDescription(
                    target: target,
                    normalizedPagePath: nil,
                    candidateRelativePath: nil,
                    placement: .skippedUnsafePagePath,
                    shimRelativeSrcs: [],
                    renderedHTMLCandidate: false,
                    warnings: [error.description, cspWarning]
                )
                try ChromeMV3DeterministicJSON.write(patch, to: patchReportURL)
                let patchData = try Data(contentsOf: patchReportURL)
                let patchSHA256 = sha256Hex(patchData)
                artifacts.append(
                    extensionPageArtifact(
                        target: target,
                        normalizedPagePath: nil,
                        candidateRelativePath: nil,
                        candidateSHA256: nil,
                        patchReportRelativePath: patchReportRelativePath,
                        patchReportSHA256: patchSHA256,
                        placement: .skippedUnsafePagePath,
                        shimRelativeSrcs: [],
                        renderedHTMLCandidate: false,
                        warnings: patch.warnings
                    )
                )
                artifactHashes.append(
                    artifactHash(
                        kind: .extensionPagePatchReport,
                        relativePath: patchReportRelativePath,
                        data: patchData
                    )
                )
                skippedOperations.append(skipped(operation, reason: error.description))
                warnings.append(contentsOf: patch.warnings)
                continue
            }

            guard
                fileManager.fileExists(atPath: pageURL.path),
                let html = try? String(contentsOf: pageURL, encoding: .utf8)
            else {
                let patch = extensionPagePatchDescription(
                    target: target,
                    normalizedPagePath: normalizedPagePath,
                    candidateRelativePath: nil,
                    placement: .skippedMissingGeneratedHTML,
                    shimRelativeSrcs: [],
                    renderedHTMLCandidate: false,
                    warnings: [
                        "Copied extension-page HTML was not available as UTF-8 for dry-run rendering.",
                        cspWarning,
                    ]
                )
                try ChromeMV3DeterministicJSON.write(patch, to: patchReportURL)
                let patchData = try Data(contentsOf: patchReportURL)
                let patchSHA256 = sha256Hex(patchData)
                artifacts.append(
                    extensionPageArtifact(
                        target: target,
                        normalizedPagePath: normalizedPagePath,
                        candidateRelativePath: nil,
                        candidateSHA256: nil,
                        patchReportRelativePath: patchReportRelativePath,
                        patchReportSHA256: patchSHA256,
                        placement: .skippedMissingGeneratedHTML,
                        shimRelativeSrcs: [],
                        renderedHTMLCandidate: false,
                        warnings: patch.warnings
                    )
                )
                artifactHashes.append(
                    artifactHash(
                        kind: .extensionPagePatchReport,
                        relativePath: patchReportRelativePath,
                        data: patchData
                    )
                )
                skippedOperations.append(
                    skipped(
                        operation,
                        reason: "Copied extension-page HTML was not available as UTF-8."
                    )
                )
                warnings.append(contentsOf: patch.warnings)
                continue
            }

            let shimRelativeSrcs = target.futureShimPaths.map {
                relativeHTMLScriptSource(
                    forRuntimePath: $0,
                    fromPagePath: normalizedPagePath
                )
            }
            let htmlCandidate = renderHTMLCandidate(
                originalHTML: html,
                shimRelativeSrcs: shimRelativeSrcs
            )
            let candidateRelativePath = Self.extensionPagesDirectoryName
                + "/"
                + baseName
                + ".rewrite-candidate.html"
            let candidateURL = extensionPagesURL
                .appendingPathComponent(baseName + ".rewrite-candidate.html")
            let candidateData = Data(htmlCandidate.html.utf8)
            try candidateData.write(to: candidateURL, options: [.atomic])
            let candidateSHA256 = sha256Hex(candidateData)

            var pageWarnings = [cspWarning]
            if htmlCandidate.placement == .documentStartFallbackNoHead {
                pageWarnings.append("No closing </head> was found; dry-run shim tags use document-start fallback placement.")
            }
            let patch = extensionPagePatchDescription(
                target: target,
                normalizedPagePath: normalizedPagePath,
                candidateRelativePath: candidateRelativePath,
                placement: htmlCandidate.placement,
                shimRelativeSrcs: shimRelativeSrcs,
                renderedHTMLCandidate: true,
                warnings: pageWarnings
            )
            try ChromeMV3DeterministicJSON.write(patch, to: patchReportURL)
            let patchData = try Data(contentsOf: patchReportURL)
            let patchSHA256 = sha256Hex(patchData)

            artifacts.append(
                extensionPageArtifact(
                    target: target,
                    normalizedPagePath: normalizedPagePath,
                    candidateRelativePath: candidateRelativePath,
                    candidateSHA256: candidateSHA256,
                    patchReportRelativePath: patchReportRelativePath,
                    patchReportSHA256: patchSHA256,
                    placement: htmlCandidate.placement,
                    shimRelativeSrcs: shimRelativeSrcs,
                    renderedHTMLCandidate: true,
                    warnings: pageWarnings
                )
            )
            artifactHashes.append(
                artifactHash(
                    kind: .extensionPageHTMLCandidate,
                    relativePath: candidateRelativePath,
                    data: candidateData
                )
            )
            artifactHashes.append(
                artifactHash(
                    kind: .extensionPagePatchReport,
                    relativePath: patchReportRelativePath,
                    data: patchData
                )
            )
            renderedOperations.append(
                rendered(
                    operation,
                    surface: "extension-page-html-candidate",
                    artifacts: [candidateRelativePath, patchReportRelativePath]
                )
            )
            warnings.append(contentsOf: pageWarnings)
        }

        return (
            artifacts.sorted(by: extensionPageArtifactSort),
            artifactHashes.sorted(by: artifactHashSort)
        )
    }

    private func appendReportOnlyOperations(
        preview: ChromeMV3ManifestRewritePreview,
        renderedOperations: inout [ChromeMV3ManifestRewriteDryRunRenderedOperation]
    ) {
        for operation in preview.plannedOperations.sorted(by: previewOperationSort) {
            switch operation.type {
            case .recordHostBridgeDeferred,
                 .recordUnsupportedAPIs,
                 .recordDeferredNativeHostAPIs,
                 .recordFixtureVerificationRequired:
                renderedOperations.append(
                    rendered(
                        operation,
                        surface: "rewrite-verification-report",
                        artifacts: [Self.verificationReportFileName]
                    )
                )
            case .replaceServiceWorkerWithWrapper,
                 .preserveOriginalServiceWorkerPath,
                 .prependContentScriptShims,
                 .injectExtensionPageShimMetadata:
                continue
            }
        }
    }

    private func renderHTMLCandidate(
        originalHTML: String,
        shimRelativeSrcs: [String]
    ) -> (html: String, placement: ChromeMV3ExtensionPageRewriteInjectionPlacement) {
        let shimBlock = shimRelativeSrcs
            .map { "<script src=\"\($0)\"></script>" }
            .joined(separator: "\n")
            + "\n"

        guard
            let range = originalHTML.range(
                of: "</head>",
                options: [.caseInsensitive]
            )
        else {
            return (shimBlock + originalHTML, .documentStartFallbackNoHead)
        }

        var candidate = originalHTML
        candidate.insert(contentsOf: shimBlock, at: range.lowerBound)
        return (candidate, .beforeClosingHead)
    }

    private func extensionPagePatchDescription(
        target: ChromeMV3ExtensionPageShimInjectionPreview,
        normalizedPagePath: String?,
        candidateRelativePath: String?,
        placement: ChromeMV3ExtensionPageRewriteInjectionPlacement,
        shimRelativeSrcs: [String],
        renderedHTMLCandidate: Bool,
        warnings: [String]
    ) -> ChromeMV3ExtensionPageRewritePatchDescription {
        ChromeMV3ExtensionPageRewritePatchDescription(
            schemaVersion: 1,
            context: target.context,
            sourceManifestField: target.sourceManifestField,
            originalPagePath: target.pagePath,
            normalizedPagePath: normalizedPagePath,
            candidateRelativePath: candidateRelativePath,
            injectionPlacement: placement,
            plannedShimPaths: target.futureShimPaths.sorted(),
            shimRelativeSrcs: shimRelativeSrcs,
            nativeHostPlanningOnly: target.nativeHostPlanningOnly,
            renderedHTMLCandidate: renderedHTMLCandidate,
            appliedToGeneratedHTML: false,
            warnings: Array(Set(warnings)).sorted()
        )
    }

    private func extensionPageArtifact(
        target: ChromeMV3ExtensionPageShimInjectionPreview,
        normalizedPagePath: String?,
        candidateRelativePath: String?,
        candidateSHA256: String?,
        patchReportRelativePath: String,
        patchReportSHA256: String,
        placement: ChromeMV3ExtensionPageRewriteInjectionPlacement,
        shimRelativeSrcs: [String],
        renderedHTMLCandidate: Bool,
        warnings: [String]
    ) -> ChromeMV3ExtensionPageRewriteCandidateArtifact {
        ChromeMV3ExtensionPageRewriteCandidateArtifact(
            context: target.context,
            sourceManifestField: target.sourceManifestField,
            originalPagePath: target.pagePath,
            normalizedPagePath: normalizedPagePath,
            candidateRelativePath: candidateRelativePath,
            candidateSHA256: candidateSHA256,
            patchReportRelativePath: patchReportRelativePath,
            patchReportSHA256: patchReportSHA256,
            injectionPlacement: placement,
            shimPaths: target.futureShimPaths.sorted(),
            shimRelativeSrcs: shimRelativeSrcs,
            nativeHostPlanningOnly: target.nativeHostPlanningOnly,
            renderedHTMLCandidate: renderedHTMLCandidate,
            appliedToGeneratedHTML: false,
            warnings: Array(Set(warnings)).sorted()
        )
    }

    private func extensionPageArtifactBaseName(
        for target: ChromeMV3ExtensionPageShimInjectionPreview
    ) -> String {
        let prefix: String
        switch target.sourceManifestField {
        case "action.default_popup":
            prefix = "action-popup"
        case "options_page":
            prefix = "options-page"
        case "options_ui.page":
            prefix = "options-ui"
        case "side_panel.default_path":
            prefix = "side-panel"
        default:
            prefix = target.context.rawValue
        }

        let digest = sha256Hex(
            Data("\(target.sourceManifestField)\n\(target.pagePath)".utf8)
        )
        return "\(prefix).\(digest.prefix(12))"
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

    private func preservedContentScriptFields(in script: [String: Any]) -> [String] {
        [
            "matches",
            "exclude_matches",
            "include_globs",
            "exclude_globs",
            "css",
            "run_at",
            "all_frames",
            "match_about_blank",
            "match_origin_as_fallback",
            "world",
        ]
        .filter { script[$0] != nil }
        .map { "content_scripts[].\($0)" }
        .sorted()
    }

    private func manifestJSONObject(from data: Data) throws -> [String: Any] {
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let manifest = object as? [String: Any] else {
                throw ChromeMV3ManifestRewriteDryRunRendererError
                    .invalidManifestJSON("top-level value is not an object")
            }
            return manifest
        } catch let error as ChromeMV3ManifestRewriteDryRunRendererError {
            throw error
        } catch {
            throw ChromeMV3ManifestRewriteDryRunRendererError
                .invalidManifestJSON(error.localizedDescription)
        }
    }

    private func canonicalJSONData(_ object: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        var output = data
        output.append(0x0A)
        return output
    }

    private func normalizedResourcePath(
        _ path: String,
        field: String
    ) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ChromeMV3ManifestRewriteDryRunRendererError.unsafePagePath(
                field: field,
                path: path
            )
        }

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

        let isUnsafe = decoded.hasPrefix("/")
            || decoded.hasPrefix("~")
            || decoded.contains("\\")
            || decoded.contains("\0")
            || decoded.localizedCaseInsensitiveContains("://")
            || decoded.contains("*")

        guard isUnsafe == false else {
            throw ChromeMV3ManifestRewriteDryRunRendererError.unsafePagePath(
                field: field,
                path: path
            )
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
            throw ChromeMV3ManifestRewriteDryRunRendererError.unsafePagePath(
                field: field,
                path: path
            )
        }

        return decoded
    }

    private func safeGeneratedResourceURL(
        relativePath: String,
        rootURL: URL,
        field: String
    ) throws -> URL {
        _ = try normalizedResourcePath(relativePath, field: field)
        let resourceURL = rootURL
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path.hasSuffix("/")
            ? rootURL.standardizedFileURL.path
            : rootURL.standardizedFileURL.path + "/"
        guard resourceURL.path.hasPrefix(rootPath) else {
            throw ChromeMV3ManifestRewriteDryRunRendererError
                .generatedPageEscapesBundle(resourceURL.path)
        }
        return resourceURL
    }

    private func rendered(
        _ operation: ChromeMV3ManifestRewritePreviewOperation,
        surface: String,
        artifacts: [String]
    ) -> ChromeMV3ManifestRewriteDryRunRenderedOperation {
        ChromeMV3ManifestRewriteDryRunRenderedOperation(
            order: operation.order,
            type: operation.type,
            sourceManifestFields: operation.sourceManifestFields.sorted(),
            renderedSurface: surface,
            artifactRelativePaths: artifacts.sorted()
        )
    }

    private func skipped(
        _ operation: ChromeMV3ManifestRewritePreviewOperation,
        reason: String
    ) -> ChromeMV3ManifestRewriteDryRunSkippedOperation {
        ChromeMV3ManifestRewriteDryRunSkippedOperation(
            order: operation.order,
            type: operation.type,
            sourceManifestFields: operation.sourceManifestFields.sorted(),
            reason: reason
        )
    }

    private func artifactHash(
        kind: ChromeMV3ManifestRewriteDryRunArtifactKind,
        relativePath: String,
        data: Data
    ) -> ChromeMV3ManifestRewriteDryRunArtifactHash {
        ChromeMV3ManifestRewriteDryRunArtifactHash(
            kind: kind,
            relativePath: relativePath,
            sha256: sha256Hex(data),
            byteCount: data.count
        )
    }

    private func documentationSources(
        from preview: ChromeMV3ManifestRewritePreview
    ) -> [ChromeMV3ManifestRewritePreviewSource] {
        var sourcesByKey: [String: ChromeMV3ManifestRewritePreviewSource] = [:]
        for source in preview.plannedOperations.flatMap(\.sources)
            where source.kind == .chromeDocumentation
        {
            let key = "\(source.title)\n\(source.url ?? "")"
            sourcesByKey[key] = source
        }
        return sourcesByKey.values.sorted {
            if $0.title == $1.title {
                return ($0.url ?? "") < ($1.url ?? "")
            }
            return $0.title < $1.title
        }
    }

    private func stringArray(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private var cspWarning: String {
        "Dry-run uses external script tags only; inline script injection remains unsafe/deferred and requires fixture verification before any applied rewrite."
    }
}

private func previewOperationSort(
    _ lhs: ChromeMV3ManifestRewritePreviewOperation,
    _ rhs: ChromeMV3ManifestRewritePreviewOperation
) -> Bool {
    if lhs.order == rhs.order {
        return lhs.type < rhs.type
    }
    return lhs.order < rhs.order
}

private func diffEntrySort(
    _ lhs: ChromeMV3ManifestRewriteDryRunManifestDiffEntry,
    _ rhs: ChromeMV3ManifestRewriteDryRunManifestDiffEntry
) -> Bool {
    if lhs.jsonPointer == rhs.jsonPointer {
        return lhs.operation.rawValue < rhs.operation.rawValue
    }
    return lhs.jsonPointer < rhs.jsonPointer
}

private func renderedOperationSort(
    _ lhs: ChromeMV3ManifestRewriteDryRunRenderedOperation,
    _ rhs: ChromeMV3ManifestRewriteDryRunRenderedOperation
) -> Bool {
    if lhs.order == rhs.order {
        return lhs.renderedSurface < rhs.renderedSurface
    }
    return lhs.order < rhs.order
}

private func skippedOperationSort(
    _ lhs: ChromeMV3ManifestRewriteDryRunSkippedOperation,
    _ rhs: ChromeMV3ManifestRewriteDryRunSkippedOperation
) -> Bool {
    if lhs.order == rhs.order {
        return lhs.reason < rhs.reason
    }
    return lhs.order < rhs.order
}

private func artifactHashSort(
    _ lhs: ChromeMV3ManifestRewriteDryRunArtifactHash,
    _ rhs: ChromeMV3ManifestRewriteDryRunArtifactHash
) -> Bool {
    if lhs.relativePath == rhs.relativePath {
        return lhs.kind < rhs.kind
    }
    return lhs.relativePath < rhs.relativePath
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
