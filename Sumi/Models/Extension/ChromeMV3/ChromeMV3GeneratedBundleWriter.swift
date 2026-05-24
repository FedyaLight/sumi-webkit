//
//  ChromeMV3GeneratedBundleWriter.swift
//  Sumi
//
//  Deterministic generated-bundle draft writer for staged Chrome MV3 originals.
//  This layer copies manifest-referenced files only; it does not generate,
//  load, register, or execute extension runtime code.
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
        let resources = try manifestReferencedResources(in: manifestObject)

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
            resources,
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
        in manifest: [String: Any]
    ) throws -> [ManifestResourceReference] {
        var resources: [ManifestResourceReference] = [
            ManifestResourceReference(
                field: "manifest",
                path: "manifest.json",
                policy: .exactRequired
            )
        ]

        if let background = manifest["background"] as? [String: Any] {
            try appendExactPath(
                background["service_worker"],
                field: "background.service_worker",
                to: &resources
            )
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

        return resources.sorted()
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

        let isUnsafe = decoded.hasPrefix("/")
            || decoded.hasPrefix("~")
            || decoded.contains("\\")
            || decoded.contains("\0")
            || decoded.localizedCaseInsensitiveContains("://")
            || (!allowsGlob && decoded.contains("*"))

        guard isUnsafe == false else {
            throw ChromeMV3GeneratedBundleWriterError.unsafeResourcePath(
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
            throw ChromeMV3GeneratedBundleWriterError.unsafeResourcePath(
                field: field,
                path: path
            )
        }

        return decoded
    }

    private func copyResources(
        _ resources: [ManifestResourceReference],
        from originalRootURL: URL,
        to generatedBundleRootURL: URL
    ) throws -> ResourceCopyResult {
        var copiedPaths = Set<String>()
        var warnings: [ChromeMV3GeneratedBundleResourceWarning] = []

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
            }
        }

        return ResourceCopyResult(
            copiedRelativePaths: copiedPaths.sorted(),
            warnings: warnings
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
}

private enum ResourceCopyPolicy: Comparable {
    case exactRequired
    case recursiveDirectory
    case unsupportedWildcard
}

private struct ManifestResourceReference: Comparable {
    var field: String
    var path: String
    var policy: ResourceCopyPolicy

    static func < (
        lhs: ManifestResourceReference,
        rhs: ManifestResourceReference
    ) -> Bool {
        if lhs.path == rhs.path {
            if lhs.field == rhs.field {
                return lhs.policy < rhs.policy
            }
            return lhs.field < rhs.field
        }
        return lhs.path < rhs.path
    }
}

private struct ResourceCopyResult {
    var copiedRelativePaths: [String]
    var warnings: [ChromeMV3GeneratedBundleResourceWarning]
}
