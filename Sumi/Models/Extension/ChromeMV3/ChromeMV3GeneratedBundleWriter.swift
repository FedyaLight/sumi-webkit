//
//  ChromeMV3GeneratedBundleWriter.swift
//  Sumi
//
//  Deterministic generated-bundle draft writer for staged Chrome MV3 originals.
//  This layer copies manifest-referenced files and manifest locale catalogs;
//  it does not generate, load, register, or execute extension runtime code.
//

import CryptoKit
import Foundation

enum ChromeMV3GeneratedBundleWriterError: LocalizedError, CustomStringConvertible {
    case recordMismatch(String)
    case missingOriginalBundle(String)
    case invalidManifestJSON(String)
    case unsafeResourcePath(field: String, path: String)
    case sourceEscapedOriginalRoot(String)
    case missingReferencedResource(String)
    case nonRegularReferencedResource(String)
    case symbolicLinkReferencedResource(String)

    var errorDescription: String? {
        switch self {
        case .recordMismatch(let reason):
            return "Generated bundle records do not match: \(reason)"
        case .missingOriginalBundle(let path):
            return "Missing staged original bundle root: \(path)"
        case .invalidManifestJSON(let reason):
            return "Invalid manifest snapshot JSON: \(reason)"
        case .unsafeResourcePath(let field, let path):
            return "Unsafe generated-bundle resource path '\(path)' in \(field)"
        case .sourceEscapedOriginalRoot(let path):
            return "Generated-bundle resource escapes staged original root: \(path)"
        case .missingReferencedResource(let path):
            return "Missing manifest-referenced resource: \(path)"
        case .nonRegularReferencedResource(let path):
            return "Manifest-referenced resource is not a regular file: \(path)"
        case .symbolicLinkReferencedResource(let path):
            return "Manifest-referenced resource is a symbolic link: \(path)"
        }
    }

    var description: String {
        errorDescription ?? String(describing: self)
    }
}

struct ChromeMV3GeneratedBundleInstallReportSummary: Codable, Equatable {
    var manifestSummary: ChromeMV3ManifestSummary?
    var capabilitySummary: ChromeMV3CapabilityClassificationSummary
    var warningCodes: [String]
    var fatalValidationErrorCodes: [String]
}

enum ChromeMV3GeneratedBundleResourceWarningCode: String, Codable {
    case missingReferencedResource
    case unsupportedWebAccessibleResourcePattern
}

struct ChromeMV3GeneratedBundleResourceWarning: Codable, Equatable {
    var code: ChromeMV3GeneratedBundleResourceWarningCode
    var field: String
    var path: String
    var message: String
}

enum ChromeMV3GeneratedBundleServiceWorkerFetchResourceStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blocked
    case copied
    case missing

    static func < (
        lhs: ChromeMV3GeneratedBundleServiceWorkerFetchResourceStatus,
        rhs: ChromeMV3GeneratedBundleServiceWorkerFetchResourceStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord:
    Codable,
    Equatable,
    Sendable
{
    var sourceScriptPath: String
    var requestedPath: String
    var resolvedResourcePath: String?
    var resourceExtension: String?
    var status: ChromeMV3GeneratedBundleServiceWorkerFetchResourceStatus
    var blocker: String
    var diagnostics: [String]
}

struct ChromeMV3WrittenRuntimeTemplateResource: Codable, Equatable {
    var moduleName: ChromeMV3RuntimeTemplateModuleName
    var outputRelativePath: String
    var sha256: String
    var byteCount: Int
    var inert: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3GeneratedBundleRecord: Codable, Equatable {
    var schemaVersion: Int
    var id: String
    var createdAt: Date
    var generatedBundleRootPath: String
    var generatedManifestPath: String
    var generatedMetadataPath: String
    var runtimeResourcePlanPath: String
    var manifestRewritePreviewPath: String
    var manifestRewritePreviewSHA256: String
    var manifestRewriteDryRunDirectoryPath: String?
    var manifestRewriteDryRunReportPath: String?
    var manifestRewriteDryRunReportSHA256: String?
    var generatorVersion: String
    var originalBundleRecordID: String
    var originalBundleContentSHA256: String
    var originalBundleRootPath: String
    var manifestSHA256: String
    var generatedManifestSHA256: String
    var installReportSummary: ChromeMV3GeneratedBundleInstallReportSummary
    var plannedManifestRewriteNeeded: Bool
    var plannedServiceWorkerWrapperNeeded: Bool
    var plannedShimModules: [String]
    var plannedRuntimeTemplateModules: [ChromeMV3RuntimeTemplateModuleName]
    var plannedNativeHostAPIs: [ChromeMV3API]
    var deferredAPIs: [ChromeMV3API]
    var unsupportedAPIs: [ChromeMV3API]
    var needsVerificationAPIs: [ChromeMV3API]
    var copiedResourcePaths: [String]
    var serviceWorkerFetchResourceRecords:
        [ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord]?
    var resourceWarnings: [ChromeMV3GeneratedBundleResourceWarning]
    var writtenInertRuntimeTemplateResources: [ChromeMV3WrittenRuntimeTemplateResource]
    var inertRuntimeTemplatesWritten: Bool
    var executableRuntimeFilesWritten: Bool
    var generatedRuntimeFilesWritten: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3GeneratedBundleWriteResult: Equatable {
    var record: ChromeMV3GeneratedBundleRecord
    var generatedBundleRootURL: URL
    var generatedManifestURL: URL
    var generatedMetadataURL: URL
    var manifestRewritePreviewURL: URL
    var manifestRewriteDryRunReportURL: URL
}

struct ChromeMV3GeneratedBundleWriter {
    static let generatedDirectoryName = "generated"
    static let generatedBundleDirectoryName = "generated"
    static let temporaryGeneratedBundleDirectoryName = "generated.tmp"
    static let metadataFileName = "generated-bundle-metadata.json"
    static let runtimeResourcePlanFileName = "runtime-resource-plan.json"
    static let manifestRewritePreviewFileName = "manifest-rewrite-preview.json"

    var rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func writeGeneratedBundle(
        originalBundleRecord: ChromeMV3OriginalBundleRecord,
        manifestSnapshot: ChromeMV3ManifestSnapshotRecord,
        planningRecord: ChromeMV3GeneratedBundlePlanningRecord
    ) throws -> ChromeMV3GeneratedBundleWriteResult {
        try validateRecordLinks(
            originalBundleRecord: originalBundleRecord,
            manifestSnapshot: manifestSnapshot,
            planningRecord: planningRecord
        )

        let fileManager = FileManager.default
        let originalRootURL = URL(
            fileURLWithPath: originalBundleRecord.storedPaths.originalBundleRootPath,
            isDirectory: true
        ).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(
                atPath: originalRootURL.path,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue
        else {
            throw ChromeMV3GeneratedBundleWriterError.missingOriginalBundle(
                originalRootURL.path
            )
        }

        let generatedRecordRootURL = rootURL
            .standardizedFileURL
            .appendingPathComponent(Self.generatedDirectoryName, isDirectory: true)
            .appendingPathComponent(originalBundleRecord.id, isDirectory: true)
        let generatedBundleRootURL = generatedRecordRootURL
            .appendingPathComponent(Self.generatedBundleDirectoryName, isDirectory: true)
        let temporaryBundleRootURL = generatedRecordRootURL
            .appendingPathComponent(
                Self.temporaryGeneratedBundleDirectoryName,
                isDirectory: true
            )
        let generatedManifestURL = generatedBundleRootURL
            .appendingPathComponent("manifest.json")
        let generatedMetadataURL = generatedBundleRootURL
            .appendingPathComponent(Self.metadataFileName)
        let runtimeResourcePlanURL = generatedBundleRootURL
            .appendingPathComponent(Self.runtimeResourcePlanFileName)
        let manifestRewritePreviewURL = generatedBundleRootURL
            .appendingPathComponent(Self.manifestRewritePreviewFileName)

        let manifestObject = try manifestJSONObject(
            from: manifestSnapshot.canonicalManifestJSON
        )
        let generatedManifestData = try canonicalJSONData(manifestObject)
        let generatedManifestSHA256 = sha256Hex(generatedManifestData)
        let resourceDiscovery = try manifestReferencedResources(
            in: manifestObject,
            originalRootURL: originalRootURL
        )

        if fileManager.fileExists(atPath: temporaryBundleRootURL.path) {
            try fileManager.removeItem(at: temporaryBundleRootURL)
        }
        try fileManager.createDirectory(
            at: temporaryBundleRootURL,
            withIntermediateDirectories: true
        )

        let temporaryManifestURL = temporaryBundleRootURL
            .appendingPathComponent("manifest.json")
        try generatedManifestData.write(to: temporaryManifestURL, options: [.atomic])

        let copyResult = try copyResources(
            resourceDiscovery.resources,
            preflightServiceWorkerFetchResourceRecords:
                resourceDiscovery.serviceWorkerFetchResourceRecords,
            from: originalRootURL,
            to: temporaryBundleRootURL
        )
        let runtimeResourcePlan = planningRecord.runtimeResourcePlan
        let writtenRuntimeTemplateResources = try writeInertRuntimeTemplates(
            for: runtimeResourcePlan,
            to: temporaryBundleRootURL
        )
        try ChromeMV3DeterministicJSON.write(
            runtimeResourcePlan,
            to: temporaryBundleRootURL
                .appendingPathComponent(Self.runtimeResourcePlanFileName)
        )
        let manifestRewritePreview = ChromeMV3ManifestRewritePreviewPlanner.preview(
            originalManifestSHA256: manifestSnapshot.manifestSHA256,
            generatedManifestSHA256BeforeRewrite: generatedManifestSHA256,
            manifest: manifestSnapshot.normalizedManifest,
            manifestJSONObject: manifestObject,
            installReport: manifestSnapshot.installReport,
            runtimeResourcePlan: runtimeResourcePlan
        )
        let manifestRewritePreviewData = try ChromeMV3DeterministicJSON
            .encodedData(manifestRewritePreview)
        try manifestRewritePreviewData.write(
            to: temporaryBundleRootURL
                .appendingPathComponent(Self.manifestRewritePreviewFileName),
            options: [.atomic]
        )

        var record = ChromeMV3GeneratedBundleRecord(
            schemaVersion: 4,
            id: "generated-\(originalBundleRecord.sourceMetadata.contentSHA256.prefix(32))",
            createdAt: planningRecord.createdAt,
            generatedBundleRootPath: generatedBundleRootURL.standardizedFileURL.path,
            generatedManifestPath: generatedManifestURL.standardizedFileURL.path,
            generatedMetadataPath: generatedMetadataURL.standardizedFileURL.path,
            runtimeResourcePlanPath: runtimeResourcePlanURL.standardizedFileURL.path,
            manifestRewritePreviewPath: manifestRewritePreviewURL
                .standardizedFileURL
                .path,
            manifestRewritePreviewSHA256: sha256Hex(manifestRewritePreviewData),
            manifestRewriteDryRunDirectoryPath: nil,
            manifestRewriteDryRunReportPath: nil,
            manifestRewriteDryRunReportSHA256: nil,
            generatorVersion: planningRecord.generatorVersion,
            originalBundleRecordID: originalBundleRecord.id,
            originalBundleContentSHA256: originalBundleRecord.sourceMetadata.contentSHA256,
            originalBundleRootPath: originalRootURL.path,
            manifestSHA256: manifestSnapshot.manifestSHA256,
            generatedManifestSHA256: generatedManifestSHA256,
            installReportSummary: ChromeMV3GeneratedBundleInstallReportSummary(
                manifestSummary: manifestSnapshot.installReport.manifestSummary,
                capabilitySummary: ChromeMV3CapabilityClassificationSummary(
                    report: manifestSnapshot.installReport
                ),
                warningCodes: manifestSnapshot.installReport.warnings
                    .map(\.code)
                    .sorted(),
                fatalValidationErrorCodes: manifestSnapshot.installReport
                    .fatalValidationErrors
                    .map(\.code)
                    .sorted()
            ),
            plannedManifestRewriteNeeded: planningRecord.plannedManifestRewriteNeeded,
            plannedServiceWorkerWrapperNeeded: planningRecord
                .plannedServiceWorkerWrapperNeeded,
            plannedShimModules: planningRecord.plannedJSShimModules.sorted(),
            plannedRuntimeTemplateModules: runtimeResourcePlan
                .requiredTemplateModuleNames
                .sorted(),
            plannedNativeHostAPIs: planningRecord.plannedNativeHostAPIs.sorted(),
            deferredAPIs: planningRecord.deferredAPIs.sorted(),
            unsupportedAPIs: planningRecord.unsupportedAPIs.sorted(),
            needsVerificationAPIs: planningRecord.needsVerificationAPIs.sorted(),
            copiedResourcePaths: copyResult.copiedRelativePaths.sorted(),
            serviceWorkerFetchResourceRecords:
                copyResult.serviceWorkerFetchResourceRecords
                    .sorted(by: serviceWorkerFetchResourceRecordSort),
            resourceWarnings: copyResult.warnings.sorted(by: resourceWarningSort),
            writtenInertRuntimeTemplateResources: writtenRuntimeTemplateResources,
            inertRuntimeTemplatesWritten: writtenRuntimeTemplateResources
                .isEmpty == false,
            executableRuntimeFilesWritten: false,
            generatedRuntimeFilesWritten: false,
            runtimeLoadable: false
        )

        let dryRunResult = try ChromeMV3ManifestRewriteDryRunRenderer()
            .renderDryRun(
                generatedBundleRecord: record,
                generatedBundleRootURL: temporaryBundleRootURL,
                manifestRewritePreview: manifestRewritePreview,
                manifestRewritePreviewData: manifestRewritePreviewData,
                runtimeResourcePlan: runtimeResourcePlan,
                currentGeneratedManifestURL: temporaryManifestURL
            )
        record.manifestRewriteDryRunDirectoryPath = generatedBundleRootURL
            .appendingPathComponent(
                ChromeMV3ManifestRewriteDryRunRenderer.dryRunDirectoryName,
                isDirectory: true
            )
            .standardizedFileURL
            .path
        record.manifestRewriteDryRunReportPath = generatedBundleRootURL
            .appendingPathComponent(
                ChromeMV3ManifestRewriteDryRunRenderer.dryRunDirectoryName,
                isDirectory: true
            )
            .appendingPathComponent(
                ChromeMV3ManifestRewriteDryRunRenderer.verificationReportFileName
            )
            .standardizedFileURL
            .path
        record.manifestRewriteDryRunReportSHA256 = dryRunResult
            .verificationReportSHA256

        try ChromeMV3DeterministicJSON.write(
            record,
            to: temporaryBundleRootURL.appendingPathComponent(Self.metadataFileName)
        )

        if fileManager.fileExists(atPath: generatedBundleRootURL.path) {
            try fileManager.removeItem(at: generatedBundleRootURL)
        }
        try fileManager.createDirectory(
            at: generatedRecordRootURL,
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(
            at: temporaryBundleRootURL,
            to: generatedBundleRootURL
        )

        return ChromeMV3GeneratedBundleWriteResult(
            record: record,
            generatedBundleRootURL: generatedBundleRootURL,
            generatedManifestURL: generatedManifestURL,
            generatedMetadataURL: generatedMetadataURL,
            manifestRewritePreviewURL: manifestRewritePreviewURL,
            manifestRewriteDryRunReportURL: generatedBundleRootURL
                .appendingPathComponent(
                    ChromeMV3ManifestRewriteDryRunRenderer.dryRunDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(
                    ChromeMV3ManifestRewriteDryRunRenderer
                        .verificationReportFileName
                )
        )
    }

    private func validateRecordLinks(
        originalBundleRecord: ChromeMV3OriginalBundleRecord,
        manifestSnapshot: ChromeMV3ManifestSnapshotRecord,
        planningRecord: ChromeMV3GeneratedBundlePlanningRecord
    ) throws {
        guard manifestSnapshot.originalBundleRecordID == originalBundleRecord.id else {
            throw ChromeMV3GeneratedBundleWriterError.recordMismatch(
                "manifest snapshot references \(manifestSnapshot.originalBundleRecordID), expected \(originalBundleRecord.id)"
            )
        }
        guard planningRecord.originalBundleRecordID == originalBundleRecord.id else {
            throw ChromeMV3GeneratedBundleWriterError.recordMismatch(
                "planning record references \(planningRecord.originalBundleRecordID), expected \(originalBundleRecord.id)"
            )
        }
        guard
            planningRecord.originalBundleContentSHA256
                == originalBundleRecord.sourceMetadata.contentSHA256
        else {
            throw ChromeMV3GeneratedBundleWriterError.recordMismatch(
                "planning record content hash does not match original bundle record"
            )
        }
        guard manifestSnapshot.manifestSHA256 == originalBundleRecord.sourceMetadata.manifestSHA256 else {
            throw ChromeMV3GeneratedBundleWriterError.recordMismatch(
                "manifest snapshot hash does not match original bundle record"
            )
        }
    }

    private func manifestJSONObject(from json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8) else {
            throw ChromeMV3GeneratedBundleWriterError.invalidManifestJSON(
                "snapshot is not UTF-8"
            )
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let manifest = object as? [String: Any] else {
                throw ChromeMV3GeneratedBundleWriterError.invalidManifestJSON(
                    "top-level manifest snapshot value is not an object"
                )
            }
            return manifest
        } catch let error as ChromeMV3GeneratedBundleWriterError {
            throw error
        } catch {
            throw ChromeMV3GeneratedBundleWriterError.invalidManifestJSON(
                error.localizedDescription
            )
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

    private func manifestReferencedResources(
        in manifest: [String: Any],
        originalRootURL: URL
    ) throws -> ResourceDiscoveryResult {
        var resources: [ManifestResourceReference] = [
            ManifestResourceReference(
                field: "manifest",
                path: "manifest.json",
                policy: .exactRequired
            )
        ]
        var serviceWorkerFetchResourceRecords:
            [ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord] = []

        if let background = manifest["background"] as? [String: Any] {
            try appendExactPath(
                background["service_worker"],
                field: "background.service_worker",
                to: &resources
            )
            if let serviceWorker = background["service_worker"] as? String,
               let normalized = try? normalizedResourcePath(
                    serviceWorker,
                    field: "background.service_worker"
                )
            {
                appendServiceWorkerGeneratedBundleDependencies(
                    startingAt: normalized,
                    originalRootURL: originalRootURL,
                    to: &resources,
                    serviceWorkerFetchResourceRecords:
                        &serviceWorkerFetchResourceRecords
                )
            }
        }

        if let contentScripts = manifest["content_scripts"] as? [[String: Any]] {
            for (index, script) in contentScripts.enumerated() {
                try appendExactPaths(
                    script["js"],
                    field: "content_scripts[\(index)].js",
                    to: &resources
                )
                try appendExactPaths(
                    script["css"],
                    field: "content_scripts[\(index)].css",
                    to: &resources
                )
            }
        }

        try appendExactPath(
            manifest["options_page"],
            field: "options_page",
            to: &resources
        )

        if let optionsUI = manifest["options_ui"] as? [String: Any] {
            try appendExactPath(
                optionsUI["page"],
                field: "options_ui.page",
                to: &resources
            )
        }

        if let action = manifest["action"] as? [String: Any] {
            try appendExactPath(
                action["default_popup"],
                field: "action.default_popup",
                to: &resources
            )
            try appendIconPaths(
                action["default_icon"],
                field: "action.default_icon",
                to: &resources
            )
        }

        try appendIconPaths(manifest["icons"], field: "icons", to: &resources)
        try appendLocaleCatalogPaths(
            manifest["default_locale"],
            originalRootURL: originalRootURL,
            to: &resources
        )

        if let entries = manifest["web_accessible_resources"] as? [[String: Any]] {
            for (index, entry) in entries.enumerated() {
                try appendWebAccessibleResourcePaths(
                    entry["resources"],
                    field: "web_accessible_resources[\(index)].resources",
                    to: &resources
                )
            }
        }

        if let dnr = manifest["declarative_net_request"] as? [String: Any],
           let ruleResources = dnr["rule_resources"] as? [[String: Any]]
        {
            for (index, ruleResource) in ruleResources.enumerated() {
                try appendExactPath(
                    ruleResource["path"],
                    field: "declarative_net_request.rule_resources[\(index)].path",
                    to: &resources
                )
            }
        }

        if let sidePanel = manifest["side_panel"] as? [String: Any] {
            try appendExactPath(
                sidePanel["default_path"],
                field: "side_panel.default_path",
                to: &resources
            )
        }

        try appendExactPath(
            manifest["devtools_page"],
            field: "devtools_page",
            to: &resources
        )

        return ResourceDiscoveryResult(
            resources: resources.sorted(),
            serviceWorkerFetchResourceRecords:
                serviceWorkerFetchResourceRecords
                    .sorted(by: serviceWorkerFetchResourceRecordSort)
        )
    }

    private func appendLocaleCatalogPaths(
        _ defaultLocaleValue: Any?,
        originalRootURL: URL,
        to resources: inout [ManifestResourceReference]
    ) throws {
        guard let defaultLocale = defaultLocaleValue as? String,
              normalizedLocaleDirectoryGeneratedBundleWriter(defaultLocale)
                != nil
        else { return }
        let localesRoot = originalRootURL
            .appendingPathComponent("_locales", isDirectory: true)
            .standardizedFileURL
        guard containsGeneratedBundleWriter(
            root: originalRootURL,
            candidate: localesRoot
        ),
              directoryExistsGeneratedBundleWriter(localesRoot)
        else { return }
        guard
            let localeDirectories = try? FileManager.default
                .contentsOfDirectory(
                    at: localesRoot,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                    ],
                    options: [.skipsHiddenFiles]
                )
        else { return }
        for directory in localeDirectories.sorted(by: { $0.path < $1.path }) {
            let directory = directory.standardizedFileURL
            guard containsGeneratedBundleWriter(
                root: originalRootURL,
                candidate: directory
            ) else { continue }
            let locale = directory.lastPathComponent
            guard normalizedLocaleDirectoryGeneratedBundleWriter(locale)
                != nil
            else { continue }
            let values = try directory.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard values.isSymbolicLink != true,
                  values.isDirectory == true
            else { continue }
            let messages = directory.appendingPathComponent("messages.json")
            let messageValues = try? messages.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard messageValues?.isSymbolicLink != true,
                  messageValues?.isRegularFile == true
            else { continue }
            let relative = "_locales/\(locale)/messages.json"
            _ = try normalizedResourcePath(
                relative,
                field: "_locales.messages"
            )
            resources.append(
                ManifestResourceReference(
                    field: "_locales.messages",
                    path: relative,
                    policy: .exactRequired
                )
            )
        }
    }

    private func appendServiceWorkerGeneratedBundleDependencies(
        startingAt serviceWorkerPath: String,
        originalRootURL: URL,
        to resources: inout [ManifestResourceReference],
        serviceWorkerFetchResourceRecords:
            inout [ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord]
    ) {
        var scanned: Set<String> = []
        appendServiceWorkerGeneratedBundleDependencies(
            parentPath: serviceWorkerPath,
            originalRootURL: originalRootURL,
            scanned: &scanned,
            to: &resources,
            serviceWorkerFetchResourceRecords:
                &serviceWorkerFetchResourceRecords
        )
    }

    private func appendServiceWorkerGeneratedBundleDependencies(
        parentPath: String,
        originalRootURL: URL,
        scanned: inout Set<String>,
        to resources: inout [ManifestResourceReference],
        serviceWorkerFetchResourceRecords:
            inout [ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord]
    ) {
        guard scanned.insert(parentPath).inserted else { return }
        guard
            let sourceURL = try? safeSourceURL(
                relativePath: parentPath,
                rootURL: originalRootURL,
                field: "background.service_worker.importScripts.scan"
            ),
            let source = try? String(contentsOf: sourceURL, encoding: .utf8)
        else { return }

        appendServiceWorkerFetchDependencies(
            in: source,
            parentPath: parentPath,
            originalRootURL: originalRootURL,
            to: &resources,
            serviceWorkerFetchResourceRecords:
                &serviceWorkerFetchResourceRecords
        )

        for literal in importScriptsStringLiteralArguments(in: source) {
            guard let resolved = resolveImportScriptsDependencyPath(
                literal,
                parentPath: parentPath
            ) else { continue }
            guard
                let dependencyURL = try? safeSourceURL(
                    relativePath: resolved,
                    rootURL: originalRootURL,
                    field: "background.service_worker.importScripts"
                ),
                regularFile(at: dependencyURL)
            else { continue }
            resources.append(
                ManifestResourceReference(
                    field: "background.service_worker.importScripts",
                    path: resolved,
                    policy: .exactRequired
                )
            )
            appendServiceWorkerGeneratedBundleDependencies(
                parentPath: resolved,
                originalRootURL: originalRootURL,
                scanned: &scanned,
                to: &resources,
                serviceWorkerFetchResourceRecords:
                    &serviceWorkerFetchResourceRecords
            )
        }
    }

    private func appendServiceWorkerFetchDependencies(
        in source: String,
        parentPath: String,
        originalRootURL: URL,
        to resources: inout [ManifestResourceReference],
        serviceWorkerFetchResourceRecords:
            inout [ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord]
    ) {
        for argument in serviceWorkerFetchFirstArgumentSourcesGeneratedBundleWriter(
            in: source
        ) {
            let candidates = serviceWorkerFetchCandidates(
                from: argument,
                parentPath: parentPath,
                originalRootURL: originalRootURL
            )
            for candidate in candidates {
                if let resolvedPath = candidate.resolvedResourcePath {
                    resources.append(
                        ManifestResourceReference(
                            field: "background.service_worker.fetch",
                            path: resolvedPath,
                            policy: .serviceWorkerFetchCandidate,
                            sourceScriptPath: parentPath,
                            requestedPath: candidate.requestedPath
                        )
                    )
                } else {
                    serviceWorkerFetchResourceRecords.append(
                        ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord(
                            sourceScriptPath: parentPath,
                            requestedPath: candidate.requestedPath,
                            resolvedResourcePath: nil,
                            resourceExtension: nil,
                            status: .blocked,
                            blocker: candidate.blocker
                                ?? "unsupportedRequestShape",
                            diagnostics: candidate.diagnostics
                        )
                    )
                }
            }
        }
    }

    private func serviceWorkerFetchCandidates(
        from argument: String,
        parentPath: String,
        originalRootURL: URL
    ) -> [ServiceWorkerFetchCandidate] {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }
        let unwrapped = unwrapFetchURLExpressionGeneratedBundleWriter(trimmed)
        if let staticPath = staticServiceWorkerFetchStringGeneratedBundleWriter(
            unwrapped
        ) {
            return [
                serviceWorkerFetchCandidate(
                    requestedPath: staticPath,
                    parentPath: parentPath
                ),
            ]
        }
        if let boundedWasm =
            boundedWebpackPublicPathWasmFetchGeneratedBundleWriter(
                unwrapped,
                parentPath: parentPath,
                originalRootURL: originalRootURL
            )
        {
            return boundedWasm
        }
        return []
    }

    private func serviceWorkerFetchCandidate(
        requestedPath: String,
        parentPath: String
    ) -> ServiceWorkerFetchCandidate {
        let normalized = resolveServiceWorkerFetchResourcePath(
            requestedPath,
            parentPath: parentPath
        )
        if let resolvedPath = normalized.path {
            return ServiceWorkerFetchCandidate(
                requestedPath: requestedPath,
                resolvedResourcePath: resolvedPath,
                blocker: nil,
                diagnostics: [
                    "Service-worker fetch target was statically resolved to a package-local generated-bundle resource.",
                ]
            )
        }
        return ServiceWorkerFetchCandidate(
            requestedPath: requestedPath,
            resolvedResourcePath: nil,
            blocker: normalized.blocker,
            diagnostics: [
                normalized.message,
                "No network, data/blob/file URL, absolute filesystem path, path traversal, or wildcard fetch target is copied into the generated bundle.",
            ]
        )
    }

    private func boundedWebpackPublicPathWasmFetchGeneratedBundleWriter(
        _ expression: String,
        parentPath: String,
        originalRootURL: URL
    ) -> [ServiceWorkerFetchCandidate]? {
        let parts = splitTopLevelGeneratedBundleWriter(
            expression,
            separator: "+"
        )
        guard parts.count > 2,
              parts[0].range(
                of: #"^[A-Za-z_$][\w$]*\.p$"#,
                options: .regularExpression
              ) != nil
        else { return nil }

        var staticPrefix = ""
        var staticSuffix = ""
        var dynamicPartCount = 0
        var suffixStarted = false
        for part in parts.dropFirst() {
            if let literal = staticServiceWorkerFetchStringGeneratedBundleWriter(
                part
            ) {
                if suffixStarted {
                    staticSuffix += literal
                } else {
                    staticPrefix += literal
                }
            } else {
                dynamicPartCount += 1
                suffixStarted = true
            }
        }
        guard dynamicPartCount > 0,
              staticSuffix.lowercased().hasSuffix(".wasm"),
              staticPrefix.contains("*") == false,
              staticSuffix.contains("*") == false
        else { return nil }

        let directoryRequest =
            (staticPrefix as NSString).deletingLastPathComponent
        let filePrefix =
            (staticPrefix as NSString).lastPathComponent == staticPrefix
                ? staticPrefix
                : (staticPrefix as NSString).lastPathComponent
        let directoryRelative = directoryRequest == "."
            ? ""
            : directoryRequest
        let resolvedDirectory = resolveServiceWorkerFetchResourcePath(
            directoryRelative.isEmpty ? "." : directoryRelative,
            parentPath: parentPath,
            allowDirectory: true
        )
        guard let directoryPath = resolvedDirectory.path else {
            return [
                ServiceWorkerFetchCandidate(
                    requestedPath: expression,
                    resolvedResourcePath: nil,
                    blocker: resolvedDirectory.blocker,
                    diagnostics: [
                        resolvedDirectory.message,
                        "Bounded Webpack WASM fetch expansion was rejected before enumerating files.",
                    ]
                ),
            ]
        }

        let sourceDirectory = originalRootURL
            .appendingPathComponent(directoryPath)
            .standardizedFileURL
        guard containsGeneratedBundleWriter(
            root: originalRootURL,
            candidate: sourceDirectory
        ),
              directoryExistsGeneratedBundleWriter(sourceDirectory)
        else {
            return [
                ServiceWorkerFetchCandidate(
                    requestedPath: expression,
                    resolvedResourcePath: nil,
                    blocker: "missingResource",
                    diagnostics: [
                        "Bounded Webpack WASM fetch directory is missing from the original package.",
                    ]
                ),
            ]
        }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsHiddenFiles]
        )) ?? []
        let candidates = children.compactMap { child -> String? in
            guard child.lastPathComponent.hasPrefix(filePrefix),
                  child.lastPathComponent.hasSuffix(staticSuffix),
                  regularFile(at: child),
                  isSymbolicLink(at: child) == false
            else { return nil }
            if directoryPath.isEmpty {
                return child.lastPathComponent
            }
            return "\(directoryPath)/\(child.lastPathComponent)"
        }.sorted()

        guard candidates.isEmpty == false else {
            return [
                ServiceWorkerFetchCandidate(
                    requestedPath: expression,
                    resolvedResourcePath: nil,
                    blocker: "missingResource",
                    diagnostics: [
                        "No regular files matched the bounded Webpack WASM fetch pattern in the original package.",
                    ]
                ),
            ]
        }
        return candidates.map { path in
            ServiceWorkerFetchCandidate(
                requestedPath: "\(filePrefix)*\(staticSuffix)",
                resolvedResourcePath: path,
                blocker: nil,
                diagnostics: [
                    "Service-worker fetch target was copied from a bounded Webpack publicPath WASM filename pattern.",
                    "Only direct regular files matching the static prefix and .wasm suffix were considered.",
                ]
            )
        }
    }

    private func resolveServiceWorkerFetchResourcePath(
        _ requestedPath: String,
        parentPath: String,
        allowDirectory: Bool = false
    ) -> (path: String?, blocker: String, message: String) {
        let trimmed = requestedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return (nil, "unsupportedRequestShape", "fetch target is empty.")
        }
        let withoutFragment = trimmed.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? trimmed
        let withoutQuery = withoutFragment.split(
            separator: "?",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? withoutFragment
        let decoded = withoutQuery.removingPercentEncoding ?? withoutQuery
        let lower = decoded.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return (nil, "networkFetchDisabled", "remote fetch target is not copied.")
        }
        if lower.hasPrefix("file:") {
            return (nil, "fileURLFetchBlocked", "file: fetch target is not copied.")
        }
        if lower.hasPrefix("data:") {
            return (nil, "dataURLFetchBlocked", "data: fetch target is not copied.")
        }
        if lower.hasPrefix("blob:") {
            return (nil, "blobURLFetchBlocked", "blob: fetch target is not copied.")
        }
        if decoded.hasPrefix("//") || decoded.contains("://") {
            return (
                nil,
                "fetchSchemeOrInputUnsupported",
                "unsupported absolute fetch target is not copied."
            )
        }
        if looksLikeAbsoluteFilesystemFetchPathGeneratedBundleWriter(decoded) {
            return (
                nil,
                "absoluteFilesystemFetchBlocked",
                "absolute filesystem fetch target is not copied."
            )
        }
        guard decoded.hasPrefix("~") == false,
              decoded.contains("\\") == false,
              decoded.contains("\0") == false,
              decoded.contains("*") == false
        else {
            return (
                nil,
                "unsupportedRequestShape",
                "fetch target contains unsupported path material."
            )
        }

        var segments: [String] =
            decoded.hasPrefix("/")
                ? []
                : parentDirectoryComponentsGeneratedBundleWriter(parentPath)
        let rawPath =
            decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded
        let rawSegments =
            rawPath.split(separator: "/", omittingEmptySubsequences: false)
        if rawSegments.isEmpty && allowDirectory {
            return (segments.joined(separator: "/"), "none", "fetch path normalized.")
        }
        for raw in rawSegments {
            let segment = String(raw)
            if segment == "." {
                continue
            }
            if segment == ".." {
                return (
                    nil,
                    "pathTraversalBlocked",
                    "fetch target contains parent-directory traversal."
                )
            }
            if segment.isEmpty {
                return (
                    nil,
                    "unsupportedRequestShape",
                    "fetch target contains an empty path segment."
                )
            }
            segments.append(segment)
        }
        guard segments.isEmpty == false || allowDirectory else {
            return (
                nil,
                "missingResource",
                "fetch target does not name a generated-bundle file."
            )
        }
        return (segments.joined(separator: "/"), "none", "fetch path normalized.")
    }

    private func resolveImportScriptsDependencyPath(
        _ importPath: String,
        parentPath: String
    ) -> String? {
        let trimmed = importPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.hasPrefix("/") == false,
              trimmed.hasPrefix("~") == false,
              trimmed.contains("\\") == false,
              trimmed.contains("\0") == false,
              trimmed.contains("?") == false,
              trimmed.contains("#") == false,
              URLComponents(string: trimmed)?.scheme == nil
        else { return nil }
        var components: [String] = []
        for component in trimmed.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init) {
            if component == "." { continue }
            guard component != "..", component.isEmpty == false else {
                return nil
            }
            components.append(component)
        }
        guard components.isEmpty == false else { return nil }
        let parentDirectory = (parentPath as NSString).deletingLastPathComponent
        let resolved =
            parentDirectory.isEmpty
                ? components.joined(separator: "/")
                : "\(parentDirectory)/\(components.joined(separator: "/"))"
        return try? normalizedResourcePath(
            resolved,
            field: "background.service_worker.importScripts"
        )
    }

    private func importScriptsStringLiteralArguments(
        in source: String
    ) -> [String] {
        staticallyBoundedImportScriptsCandidatesServiceWorkerJS(in: source)
    }

    private func appendExactPath(
        _ value: Any?,
        field: String,
        to resources: inout [ManifestResourceReference]
    ) throws {
        guard let path = value as? String else { return }
        let normalized = try normalizedResourcePath(path, field: field)
        resources.append(
            ManifestResourceReference(
                field: field,
                path: normalized,
                policy: .exactRequired
            )
        )
    }

    private func appendExactPaths(
        _ value: Any?,
        field: String,
        to resources: inout [ManifestResourceReference]
    ) throws {
        guard let paths = value as? [String] else { return }
        for path in paths {
            let normalized = try normalizedResourcePath(path, field: field)
            resources.append(
                ManifestResourceReference(
                    field: field,
                    path: normalized,
                    policy: .exactRequired
                )
            )
        }
    }

    private func appendIconPaths(
        _ value: Any?,
        field: String,
        to resources: inout [ManifestResourceReference]
    ) throws {
        if let path = value as? String {
            let normalized = try normalizedResourcePath(path, field: field)
            resources.append(
                ManifestResourceReference(
                    field: field,
                    path: normalized,
                    policy: .exactRequired
                )
            )
            return
        }

        guard let iconMap = value as? [String: Any] else { return }
        for key in iconMap.keys.sorted() {
            guard let path = iconMap[key] as? String else { continue }
            let normalized = try normalizedResourcePath(
                path,
                field: "\(field).\(key)"
            )
            resources.append(
                ManifestResourceReference(
                    field: "\(field).\(key)",
                    path: normalized,
                    policy: .exactRequired
                )
            )
        }
    }

    private func appendWebAccessibleResourcePaths(
        _ value: Any?,
        field: String,
        to resources: inout [ManifestResourceReference]
    ) throws {
        guard let paths = value as? [String] else { return }
        for path in paths {
            let normalized = try normalizedResourcePath(
                path,
                field: field,
                allowsGlob: true
            )
            if normalized.hasSuffix("/*") {
                let directoryPath = String(normalized.dropLast(2))
                resources.append(
                    ManifestResourceReference(
                        field: field,
                        path: directoryPath,
                        policy: .recursiveDirectory
                    )
                )
            } else if normalized.contains("*") {
                resources.append(
                    ManifestResourceReference(
                        field: field,
                        path: normalized,
                        policy: .unsupportedWildcard
                    )
                )
            } else {
                resources.append(
                    ManifestResourceReference(
                        field: field,
                        path: normalized,
                        policy: .exactRequired
                    )
                )
            }
        }
    }

    private func normalizedResourcePath(
        _ path: String,
        field: String,
        allowsGlob: Bool = false
    ) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ChromeMV3GeneratedBundleWriterError.unsafeResourcePath(
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
        let normalizedDecoded =
            decoded.hasPrefix("/") && decoded.hasPrefix("//") == false
            ? String(decoded.dropFirst())
            : decoded

        let isUnsafe = decoded.hasPrefix("//")
            || decoded.hasPrefix("~")
            || decoded.contains("\\")
            || decoded.contains("\0")
            || decoded.localizedCaseInsensitiveContains("://")
            || (!allowsGlob && normalizedDecoded.contains("*"))

        guard isUnsafe == false else {
            throw ChromeMV3GeneratedBundleWriterError.unsafeResourcePath(
                field: field,
                path: path
            )
        }

        let segments = normalizedDecoded.split(
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
            throw ChromeMV3GeneratedBundleWriterError.unsafeResourcePath(
                field: field,
                path: path
            )
        }

        return normalizedDecoded
    }

    private func copyResources(
        _ resources: [ManifestResourceReference],
        preflightServiceWorkerFetchResourceRecords:
            [ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord],
        from originalRootURL: URL,
        to generatedBundleRootURL: URL
    ) throws -> ResourceCopyResult {
        var copiedPaths = Set<String>()
        var warnings: [ChromeMV3GeneratedBundleResourceWarning] = []
        var serviceWorkerFetchResourceRecords =
            preflightServiceWorkerFetchResourceRecords

        for resource in resources {
            switch resource.policy {
            case .exactRequired:
                try copyExactResource(
                    resource,
                    from: originalRootURL,
                    to: generatedBundleRootURL,
                    copiedPaths: &copiedPaths
                )
            case .recursiveDirectory:
                try copyRecursiveDirectory(
                    resource,
                    from: originalRootURL,
                    to: generatedBundleRootURL,
                    copiedPaths: &copiedPaths,
                    warnings: &warnings
                )
            case .unsupportedWildcard:
                warnings.append(
                    ChromeMV3GeneratedBundleResourceWarning(
                        code: .unsupportedWebAccessibleResourcePattern,
                        field: resource.field,
                        path: resource.path,
                        message: "Skipped unsupported web_accessible_resources wildcard pattern in generated-bundle draft."
                    )
                )
            case .serviceWorkerFetchCandidate:
                serviceWorkerFetchResourceRecords.append(
                    copyServiceWorkerFetchResource(
                        resource,
                        from: originalRootURL,
                        to: generatedBundleRootURL,
                        copiedPaths: &copiedPaths
                    )
                )
            }
        }

        return ResourceCopyResult(
            copiedRelativePaths: copiedPaths.sorted(),
            warnings: warnings,
            serviceWorkerFetchResourceRecords:
                uniqueServiceWorkerFetchResourceRecords(
                    serviceWorkerFetchResourceRecords
                )
        )
    }

    private func writeInertRuntimeTemplates(
        for runtimeResourcePlan: ChromeMV3RuntimeResourcePlan,
        to generatedBundleRootURL: URL
    ) throws -> [ChromeMV3WrittenRuntimeTemplateResource] {
        guard runtimeResourcePlan.requiredTemplateModuleNames.isEmpty == false else {
            return []
        }

        let runtimeDirectoryURL = generatedBundleRootURL
            .appendingPathComponent(
                ChromeMV3RuntimeResourceTemplateCatalog.runtimeDirectoryName,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: runtimeDirectoryURL,
            withIntermediateDirectories: true
        )

        var written: [ChromeMV3WrittenRuntimeTemplateResource] = []
        for moduleName in runtimeResourcePlan.requiredTemplateModuleNames.sorted() {
            let template = ChromeMV3RuntimeResourceTemplateCatalog.template(
                named: moduleName
            )
            let data = Data(template.contents.utf8)
            let destinationURL = generatedBundleRootURL
                .appendingPathComponent(template.outputRelativePath)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: [.atomic])

            written.append(
                ChromeMV3WrittenRuntimeTemplateResource(
                    moduleName: moduleName,
                    outputRelativePath: template.outputRelativePath,
                    sha256: sha256Hex(data),
                    byteCount: data.count,
                    inert: template.inert,
                    runtimeLoadable: template.runtimeLoadable
                )
            )
        }

        return written.sorted { lhs, rhs in
            lhs.outputRelativePath < rhs.outputRelativePath
        }
    }

    private func copyExactResource(
        _ resource: ManifestResourceReference,
        from originalRootURL: URL,
        to generatedBundleRootURL: URL,
        copiedPaths: inout Set<String>
    ) throws {
        guard resource.path != "manifest.json" else { return }
        let sourceURL = try safeSourceURL(
            relativePath: resource.path,
            rootURL: originalRootURL,
            field: resource.field
        )
        let values = try sourceURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        if values.isSymbolicLink == true {
            throw ChromeMV3GeneratedBundleWriterError
                .symbolicLinkReferencedResource(resource.path)
        }
        guard values.isRegularFile == true else {
            throw ChromeMV3GeneratedBundleWriterError
                .nonRegularReferencedResource(resource.path)
        }

        let data = try Data(contentsOf: sourceURL)
        let destinationURL = generatedBundleRootURL
            .appendingPathComponent(resource.path)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL, options: [.atomic])
        copiedPaths.insert(resource.path)
    }

    private func copyRecursiveDirectory(
        _ resource: ManifestResourceReference,
        from originalRootURL: URL,
        to generatedBundleRootURL: URL,
        copiedPaths: inout Set<String>,
        warnings: inout [ChromeMV3GeneratedBundleResourceWarning]
    ) throws {
        let sourceDirectoryURL = try safeSourceURL(
            relativePath: resource.path,
            rootURL: originalRootURL,
            field: resource.field
        )
        let values = try sourceDirectoryURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        if values.isSymbolicLink == true {
            throw ChromeMV3GeneratedBundleWriterError
                .symbolicLinkReferencedResource(resource.path)
        }
        guard values.isDirectory == true else {
            warnings.append(
                ChromeMV3GeneratedBundleResourceWarning(
                    code: .missingReferencedResource,
                    field: resource.field,
                    path: resource.path,
                    message: "Skipped missing web_accessible_resources directory in generated-bundle draft."
                )
            )
            return
        }

        guard
            let enumerator = FileManager.default.enumerator(
                at: sourceDirectoryURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ],
                options: []
            )
        else {
            warnings.append(
                ChromeMV3GeneratedBundleResourceWarning(
                    code: .missingReferencedResource,
                    field: resource.field,
                    path: resource.path,
                    message: "Skipped unreadable web_accessible_resources directory in generated-bundle draft."
                )
            )
            return
        }

        for case let itemURL as URL in enumerator {
            let itemURL = itemURL.standardizedFileURL
            let relativePath = try relativePath(
                for: itemURL,
                under: originalRootURL
            )
            _ = try normalizedResourcePath(relativePath, field: resource.field)

            let itemValues = try itemURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            if itemValues.isSymbolicLink == true {
                throw ChromeMV3GeneratedBundleWriterError
                    .symbolicLinkReferencedResource(relativePath)
            }
            if itemValues.isDirectory == true {
                continue
            }
            guard itemValues.isRegularFile == true else {
                throw ChromeMV3GeneratedBundleWriterError
                    .nonRegularReferencedResource(relativePath)
            }

            let data = try Data(contentsOf: itemURL)
            let destinationURL = generatedBundleRootURL
                .appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: [.atomic])
            copiedPaths.insert(relativePath)
        }
    }

    private func copyServiceWorkerFetchResource(
        _ resource: ManifestResourceReference,
        from originalRootURL: URL,
        to generatedBundleRootURL: URL,
        copiedPaths: inout Set<String>
    ) -> ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord {
        let requestedPath = resource.requestedPath ?? resource.path
        let sourceScriptPath = resource.sourceScriptPath ?? "unknown-service-worker"
        guard resource.path != "manifest.json" else {
            return serviceWorkerFetchResourceRecord(
                sourceScriptPath: sourceScriptPath,
                requestedPath: requestedPath,
                resolvedResourcePath: resource.path,
                status: .blocked,
                blocker: "manifestResourceReserved",
                diagnostics: [
                    "manifest.json is written from the generated manifest snapshot and is not copied as a service-worker fetch closure resource.",
                ]
            )
        }

        let sourceURL: URL
        do {
            sourceURL = try safeSourceURL(
                relativePath: resource.path,
                rootURL: originalRootURL,
                field: resource.field
            )
        } catch {
            return serviceWorkerFetchResourceRecord(
                sourceScriptPath: sourceScriptPath,
                requestedPath: requestedPath,
                resolvedResourcePath: resource.path,
                status:
                    serviceWorkerFetchResourceStatus(forCopyError: error),
                blocker: serviceWorkerFetchResourceBlocker(forCopyError: error),
                diagnostics: [
                    serviceWorkerFetchResourceMessage(
                        forCopyError: error
                    ),
                    "No fallback outside the staged original extension root was attempted.",
                ]
            )
        }

        do {
            let values = try sourceURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            if values.isSymbolicLink == true {
                return serviceWorkerFetchResourceRecord(
                    sourceScriptPath: sourceScriptPath,
                    requestedPath: requestedPath,
                    resolvedResourcePath: resource.path,
                    status: .blocked,
                    blocker: "symlinkEscapeBlocked",
                    diagnostics: [
                        "Service-worker fetch resource contains a symbolic link and was not copied.",
                    ]
                )
            }
            guard values.isRegularFile == true else {
                return serviceWorkerFetchResourceRecord(
                    sourceScriptPath: sourceScriptPath,
                    requestedPath: requestedPath,
                    resolvedResourcePath: resource.path,
                    status: .blocked,
                    blocker: "nonRegularResource",
                    diagnostics: [
                        "Service-worker fetch resource is not a regular file and was not copied.",
                    ]
                )
            }
            let data = try Data(contentsOf: sourceURL)
            let destinationURL = generatedBundleRootURL
                .appendingPathComponent(resource.path)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: [.atomic])
            copiedPaths.insert(resource.path)
            return serviceWorkerFetchResourceRecord(
                sourceScriptPath: sourceScriptPath,
                requestedPath: requestedPath,
                resolvedResourcePath: resource.path,
                status: .copied,
                blocker: "none",
                diagnostics: [
                    "Service-worker fetch resource was copied into the generated bundle after original-root containment checks.",
                ]
            )
        } catch {
            return serviceWorkerFetchResourceRecord(
                sourceScriptPath: sourceScriptPath,
                requestedPath: requestedPath,
                resolvedResourcePath: resource.path,
                status: .blocked,
                blocker: "resourceReadFailed",
                diagnostics: [
                    "Service-worker fetch resource could not be read or written: \(error.localizedDescription)",
                ]
            )
        }
    }

    private func serviceWorkerFetchResourceRecord(
        sourceScriptPath: String,
        requestedPath: String,
        resolvedResourcePath: String?,
        status: ChromeMV3GeneratedBundleServiceWorkerFetchResourceStatus,
        blocker: String,
        diagnostics: [String]
    ) -> ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord {
        ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord(
            sourceScriptPath: sourceScriptPath,
            requestedPath: requestedPath,
            resolvedResourcePath: resolvedResourcePath,
            resourceExtension:
                resolvedResourcePath.map {
                    URL(fileURLWithPath: $0).pathExtension.lowercased()
                },
            status: status,
            blocker: blocker,
            diagnostics: uniqueSortedGeneratedBundleWriter(diagnostics)
        )
    }

    private func serviceWorkerFetchResourceStatus(
        forCopyError error: Error
    ) -> ChromeMV3GeneratedBundleServiceWorkerFetchResourceStatus {
        if case ChromeMV3GeneratedBundleWriterError
            .missingReferencedResource(_) = error
        {
            return .missing
        }
        return .blocked
    }

    private func serviceWorkerFetchResourceBlocker(forCopyError error: Error)
        -> String
    {
        switch error {
        case ChromeMV3GeneratedBundleWriterError.missingReferencedResource(_):
            return "missingResource"
        case ChromeMV3GeneratedBundleWriterError.symbolicLinkReferencedResource(_):
            return "symlinkEscapeBlocked"
        case ChromeMV3GeneratedBundleWriterError.sourceEscapedOriginalRoot(_),
             ChromeMV3GeneratedBundleWriterError.unsafeResourcePath(_, _):
            return "pathTraversalBlocked"
        case ChromeMV3GeneratedBundleWriterError.nonRegularReferencedResource(_):
            return "nonRegularResource"
        default:
            return "resourceCopyBlocked"
        }
    }

    private func serviceWorkerFetchResourceMessage(forCopyError error: Error)
        -> String
    {
        if let writerError = error as? ChromeMV3GeneratedBundleWriterError {
            return writerError.description
        }
        return error.localizedDescription
    }

    private func safeSourceURL(
        relativePath: String,
        rootURL: URL,
        field: String
    ) throws -> URL {
        _ = try normalizedResourcePath(relativePath, field: field)

        let sourceURL = rootURL
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard sourceURL.path.hasPrefix(rootPath) else {
            throw ChromeMV3GeneratedBundleWriterError
                .sourceEscapedOriginalRoot(sourceURL.path)
        }

        var currentURL = rootURL
        for segment in relativePath.split(separator: "/").map(String.init) {
            currentURL = currentURL.appendingPathComponent(segment)
            if isSymbolicLink(at: currentURL) {
                throw ChromeMV3GeneratedBundleWriterError
                    .symbolicLinkReferencedResource(relativePath)
            }
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ChromeMV3GeneratedBundleWriterError
                .missingReferencedResource(relativePath)
        }

        let resolvedRootPath = rootURL.resolvingSymlinksInPath().path
        let resolvedSourcePath = sourceURL.resolvingSymlinksInPath().path
        let resolvedRootPrefix = resolvedRootPath.hasSuffix("/")
            ? resolvedRootPath
            : resolvedRootPath + "/"
        guard resolvedSourcePath.hasPrefix(resolvedRootPrefix) else {
            throw ChromeMV3GeneratedBundleWriterError
                .sourceEscapedOriginalRoot(resolvedSourcePath)
        }

        return sourceURL
    }

    private func isSymbolicLink(at url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func regularFile(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))
            .flatMap(\.isRegularFile) == true
    }

    private func relativePath(for url: URL, under rootURL: URL) throws -> String {
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard url.path.hasPrefix(rootPath) else {
            throw ChromeMV3GeneratedBundleWriterError
                .sourceEscapedOriginalRoot(url.path)
        }
        return String(url.path.dropFirst(rootPath.count))
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func resourceWarningSort(
        _ lhs: ChromeMV3GeneratedBundleResourceWarning,
        _ rhs: ChromeMV3GeneratedBundleResourceWarning
    ) -> Bool {
        if lhs.path == rhs.path {
            if lhs.field == rhs.field {
                return lhs.code.rawValue < rhs.code.rawValue
            }
            return lhs.field < rhs.field
        }
        return lhs.path < rhs.path
    }

    private func serviceWorkerFetchResourceRecordSort(
        _ lhs: ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord,
        _ rhs: ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord
    ) -> Bool {
        if lhs.sourceScriptPath != rhs.sourceScriptPath {
            return lhs.sourceScriptPath < rhs.sourceScriptPath
        }
        if lhs.requestedPath != rhs.requestedPath {
            return lhs.requestedPath < rhs.requestedPath
        }
        if lhs.resolvedResourcePath != rhs.resolvedResourcePath {
            return (lhs.resolvedResourcePath ?? "")
                < (rhs.resolvedResourcePath ?? "")
        }
        if lhs.status != rhs.status {
            return lhs.status < rhs.status
        }
        return lhs.blocker < rhs.blocker
    }
}

private enum ResourceCopyPolicy: Comparable {
    case exactRequired
    case recursiveDirectory
    case serviceWorkerFetchCandidate
    case unsupportedWildcard
}

private struct ManifestResourceReference: Comparable {
    var field: String
    var path: String
    var policy: ResourceCopyPolicy
    var sourceScriptPath: String?
    var requestedPath: String?

    init(
        field: String,
        path: String,
        policy: ResourceCopyPolicy,
        sourceScriptPath: String? = nil,
        requestedPath: String? = nil
    ) {
        self.field = field
        self.path = path
        self.policy = policy
        self.sourceScriptPath = sourceScriptPath
        self.requestedPath = requestedPath
    }

    static func < (
        lhs: ManifestResourceReference,
        rhs: ManifestResourceReference
    ) -> Bool {
        if lhs.path == rhs.path {
            if lhs.field == rhs.field {
                if lhs.policy == rhs.policy {
                    if lhs.sourceScriptPath == rhs.sourceScriptPath {
                        return (lhs.requestedPath ?? "")
                            < (rhs.requestedPath ?? "")
                    }
                    return (lhs.sourceScriptPath ?? "")
                        < (rhs.sourceScriptPath ?? "")
                }
                return lhs.policy < rhs.policy
            }
            return lhs.field < rhs.field
        }
        return lhs.path < rhs.path
    }
}

private struct ResourceDiscoveryResult {
    var resources: [ManifestResourceReference]
    var serviceWorkerFetchResourceRecords:
        [ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord]
}

private struct ResourceCopyResult {
    var copiedRelativePaths: [String]
    var warnings: [ChromeMV3GeneratedBundleResourceWarning]
    var serviceWorkerFetchResourceRecords:
        [ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord]
}

private struct ServiceWorkerFetchCandidate {
    var requestedPath: String
    var resolvedResourcePath: String?
    var blocker: String?
    var diagnostics: [String]
}

private func serviceWorkerFetchFirstArgumentSourcesGeneratedBundleWriter(
    in source: String
) -> [String] {
    let bytes = Array(source.utf8)
    var results: [String] = []
    var index = 0
    while index < bytes.count {
        if bytes[index] == 34 || bytes[index] == 39 || bytes[index] == 96 {
            index = skipQuotedGeneratedBundleWriter(bytes, start: index)
            continue
        }
        if bytes[index] == 47,
           let regexClose = skipRegexLiteralGeneratedBundleWriter(
                bytes,
                start: index
           )
        {
            index = regexClose
            continue
        }
        if bytes[index] == 47, index + 1 < bytes.count,
           bytes[index + 1] == 47
        {
            index += 2
            while index < bytes.count, bytes[index] != 10 { index += 1 }
            continue
        }
        if bytes[index] == 47, index + 1 < bytes.count,
           bytes[index + 1] == 42
        {
            index += 2
            while index + 1 < bytes.count,
                  !(bytes[index] == 42 && bytes[index + 1] == 47)
            {
                index += 1
            }
            index = min(bytes.count, index + 2)
            continue
        }
        guard isIdentifierStartGeneratedBundleWriter(bytes[index]) else {
            index += 1
            continue
        }
        let start = index
        index += 1
        while index < bytes.count,
              isIdentifierPartGeneratedBundleWriter(bytes[index])
        {
            index += 1
        }
        guard String(decoding: bytes[start..<index], as: UTF8.self) == "fetch",
              previousSignificantByteGeneratedBundleWriter(
                bytes,
                before: start
              ) != 46
        else { continue }
        var open = index
        while open < bytes.count, isWhitespaceGeneratedBundleWriter(bytes[open]) {
            open += 1
        }
        guard open < bytes.count, bytes[open] == 40,
              let close = matchingParenCloseGeneratedBundleWriter(
                bytes,
                open: open
              )
        else { continue }
        let arguments = splitTopLevelGeneratedBundleWriter(
            String(decoding: bytes[(open + 1)..<close], as: UTF8.self),
            separator: ","
        )
        if let first = arguments.first,
           first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            results.append(first)
        }
        index = close + 1
    }
    return results
}

private func unwrapFetchURLExpressionGeneratedBundleWriter(
    _ expression: String
) -> String {
    let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in [
        "chrome.runtime.getURL",
        "browser.runtime.getURL",
        "new Request",
        "Request",
    ] {
        guard trimmed.hasPrefix(prefix) else { continue }
        var open = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
        while open < trimmed.endIndex,
              trimmed[open].isWhitespace
        {
            open = trimmed.index(after: open)
        }
        guard open < trimmed.endIndex, trimmed[open] == "(" else { continue }
        let bytes = Array(trimmed.utf8)
        let byteOffset = trimmed[..<open].utf8.count
        guard let close = matchingParenCloseGeneratedBundleWriter(
                bytes,
                open: byteOffset
        )
        else { continue }
        let inner = String(
            decoding: bytes[(byteOffset + 1)..<close],
            as: UTF8.self
        )
        return splitTopLevelGeneratedBundleWriter(
            inner,
            separator: ","
        ).first ?? inner
    }
    return trimmed
}

private func staticServiceWorkerFetchStringGeneratedBundleWriter(
    _ expression: String
) -> String? {
    let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return nil }
    if let first = trimmed.first, let last = trimmed.last,
       (first == "'" || first == "\""), last == first
    {
        let value = String(trimmed.dropFirst().dropLast())
        if value.contains("\\") == false,
           value.contains(first) == false
        {
            return value
        }
    }
    if trimmed.first == "`", trimmed.last == "`" {
        let value = String(trimmed.dropFirst().dropLast())
        guard value.contains("${") == false,
              value.contains("\\") == false
        else { return nil }
        return value
    }
    let parts = splitTopLevelGeneratedBundleWriter(trimmed, separator: "+")
    guard parts.count > 1 else { return nil }
    var result = ""
    for part in parts {
        guard let value =
            staticServiceWorkerFetchStringGeneratedBundleWriter(part)
        else { return nil }
        result += value
    }
    return result
}

private func splitTopLevelGeneratedBundleWriter(
    _ source: String,
    separator: Character
) -> [String] {
    let bytes = Array(source.utf8)
    guard let needle = String(separator).utf8.first else { return [source] }
    var results: [String] = []
    var start = 0
    var index = 0
    var parenDepth = 0
    var braceDepth = 0
    var bracketDepth = 0
    while index < bytes.count {
        if bytes[index] == 34 || bytes[index] == 39 || bytes[index] == 96 {
            index = skipQuotedGeneratedBundleWriter(bytes, start: index)
            continue
        }
        switch bytes[index] {
        case 40: parenDepth += 1
        case 41: parenDepth = max(0, parenDepth - 1)
        case 123: braceDepth += 1
        case 125: braceDepth = max(0, braceDepth - 1)
        case 91: bracketDepth += 1
        case 93: bracketDepth = max(0, bracketDepth - 1)
        default:
            if bytes[index] == needle,
               parenDepth == 0, braceDepth == 0, bracketDepth == 0
            {
                results.append(
                    String(decoding: bytes[start..<index], as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
                start = index + 1
            }
        }
        index += 1
    }
    results.append(
        String(decoding: bytes[start...], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    )
    return results
}

private func matchingParenCloseGeneratedBundleWriter(
    _ bytes: [UInt8],
    open: Int
) -> Int? {
    var depth = 1
    var index = open + 1
    while index < bytes.count {
        if bytes[index] == 34 || bytes[index] == 39 || bytes[index] == 96 {
            index = skipQuotedGeneratedBundleWriter(bytes, start: index)
            continue
        }
        if bytes[index] == 40 {
            depth += 1
        } else if bytes[index] == 41 {
            depth -= 1
            if depth == 0 { return index }
        }
        index += 1
    }
    return nil
}

private func skipQuotedGeneratedBundleWriter(
    _ bytes: [UInt8],
    start: Int
) -> Int {
    let quote = bytes[start]
    var index = start + 1
    var escaped = false
    while index < bytes.count {
        if escaped {
            escaped = false
        } else if bytes[index] == 92 {
            escaped = true
        } else if bytes[index] == quote {
            return index + 1
        }
        index += 1
    }
    return index
}

private func skipRegexLiteralGeneratedBundleWriter(
    _ bytes: [UInt8],
    start: Int
) -> Int? {
    guard bytes[start] == 47,
          start + 1 < bytes.count,
          bytes[start + 1] != 47,
          bytes[start + 1] != 42
    else { return nil }
    if let previous = previousSignificantByteGeneratedBundleWriter(
        bytes,
        before: start
    ),
       regexLiteralCanFollowGeneratedBundleWriter(previous) == false
    {
        return nil
    }

    var index = start + 1
    var escaped = false
    var inCharacterClass = false
    while index < bytes.count {
        let byte = bytes[index]
        if escaped {
            escaped = false
        } else if byte == 92 {
            escaped = true
        } else if byte == 91 {
            inCharacterClass = true
        } else if byte == 93 {
            inCharacterClass = false
        } else if byte == 47, inCharacterClass == false {
            index += 1
            while index < bytes.count,
                  isIdentifierPartGeneratedBundleWriter(bytes[index])
            {
                index += 1
            }
            return index
        } else if byte == 10 || byte == 13 {
            return nil
        }
        index += 1
    }
    return nil
}

private func regexLiteralCanFollowGeneratedBundleWriter(_ byte: UInt8) -> Bool {
    switch byte {
    case 33, 37, 38, 40, 42, 43, 44, 45, 58, 59, 60, 61, 62,
         63, 91, 94, 123, 124, 126:
        return true
    default:
        return false
    }
}

private func previousSignificantByteGeneratedBundleWriter(
    _ bytes: [UInt8],
    before index: Int
) -> UInt8? {
    guard index > 0 else { return nil }
    var cursor = index - 1
    while cursor >= 0 {
        if isWhitespaceGeneratedBundleWriter(bytes[cursor]) == false {
            return bytes[cursor]
        }
        if cursor == 0 { break }
        cursor -= 1
    }
    return nil
}

private func parentDirectoryComponentsGeneratedBundleWriter(
    _ path: String
) -> [String] {
    let parent = (path as NSString).deletingLastPathComponent
    guard parent.isEmpty == false, parent != "." else { return [] }
    return parent.split(separator: "/").map(String.init)
}

private func looksLikeAbsoluteFilesystemFetchPathGeneratedBundleWriter(
    _ path: String
) -> Bool {
    let lower = path.lowercased()
    guard lower.hasPrefix("file:") == false else { return false }
    for prefix in [
        "/applications/",
        "/etc/",
        "/library/",
        "/opt/",
        "/private/",
        "/system/",
        "/tmp/",
        "/users/",
        "/usr/",
        "/var/",
        "/volumes/",
    ] where lower.hasPrefix(prefix) {
        return true
    }
    return false
}

private func containsGeneratedBundleWriter(root: URL, candidate: URL) -> Bool {
    let resolvedRoot =
        root.resolvingSymlinksInPath().standardizedFileURL.path
    let resolvedCandidate =
        candidate.resolvingSymlinksInPath().standardizedFileURL.path
    return resolvedCandidate == resolvedRoot
        || resolvedCandidate.hasPrefix(resolvedRoot + "/")
}

private func normalizedLocaleDirectoryGeneratedBundleWriter(
    _ value: String
) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "-", with: "_")
    guard trimmed.isEmpty == false else { return nil }
    let parts = trimmed.split(separator: "_", omittingEmptySubsequences: true)
    guard let language = parts.first,
          language.range(
            of: #"^[A-Za-z]{2,3}$"#,
            options: .regularExpression
          ) != nil
    else { return nil }
    let normalizedLanguage = language.lowercased()
    guard parts.count > 1 else { return normalizedLanguage }
    guard parts.count == 2,
          let region = parts.dropFirst().first,
          region.range(
            of: #"^(?:[A-Za-z]{2}|\d{3})$"#,
            options: .regularExpression
          ) != nil
    else { return nil }
    return "\(normalizedLanguage)_\(region.uppercased())"
}

private func directoryExistsGeneratedBundleWriter(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(
        atPath: url.path,
        isDirectory: &isDirectory
    ) && isDirectory.boolValue
}

private func uniqueServiceWorkerFetchResourceRecords(
    _ records: [ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord]
) -> [ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord] {
    var seen: Set<String> = []
    var result: [ChromeMV3GeneratedBundleServiceWorkerFetchResourceRecord] = []
    for record in records {
        let key = [
            record.sourceScriptPath,
            record.requestedPath,
            record.resolvedResourcePath ?? "",
            record.status.rawValue,
            record.blocker,
        ].joined(separator: "\u{1f}")
        guard seen.insert(key).inserted else { continue }
        result.append(record)
    }
    return result
}

private func uniqueSortedGeneratedBundleWriter(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}

private func isIdentifierStartGeneratedBundleWriter(_ byte: UInt8) -> Bool {
    (byte >= 65 && byte <= 90)
        || (byte >= 97 && byte <= 122)
        || byte == 95
        || byte == 36
}

private func isIdentifierPartGeneratedBundleWriter(_ byte: UInt8) -> Bool {
    isIdentifierStartGeneratedBundleWriter(byte)
        || (byte >= 48 && byte <= 57)
}

private func isWhitespaceGeneratedBundleWriter(_ byte: UInt8) -> Bool {
    byte == 9 || byte == 10 || byte == 11 || byte == 12
        || byte == 13 || byte == 32
}
