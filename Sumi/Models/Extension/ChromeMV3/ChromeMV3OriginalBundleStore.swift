//
//  ChromeMV3OriginalBundleStore.swift
//  Sumi
//
//  Pure install-foundation staging for Chrome MV3 originals. This layer stores
//  deterministic records only; it does not load or execute extension code.
//

import CryptoKit
import Foundation

enum ChromeMV3OriginalBundleStoreError: LocalizedError, CustomStringConvertible {
    case unsupportedSourceKind(ChromeMV3PackageSourceKind)
    case unsafeBundlePath(String)
    case sourceEscapedStoreRoot(String)
    case nonDirectorySource(String)
    case unreadableSource(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSourceKind(let kind):
            return "Unsupported extension source kind for staging: \(kind.rawValue)"
        case .unsafeBundlePath(let path):
            return "Unsafe extension bundle path: \(path)"
        case .sourceEscapedStoreRoot(let path):
            return "Unsafe extension bundle path escapes source root: \(path)"
        case .nonDirectorySource(let path):
            return "Unpacked extension source must be a directory: \(path)"
        case .unreadableSource(let path):
            return "Unable to read extension source: \(path)"
        }
    }

    var description: String {
        errorDescription ?? String(describing: self)
    }
}

struct ChromeMV3OriginalBundleSourceMetadata: Codable, Equatable {
    var sourceKind: ChromeMV3PackageSourceKind
    var originalSourcePath: String
    var originalSourceLastPathComponent: String
    var fileCount: Int
    var directoryCount: Int
    var totalBytes: Int64
    var contentSHA256: String
    var manifestSHA256: String
}

struct ChromeMV3OriginalBundleStoredPaths: Codable, Equatable {
    var recordRootPath: String
    var originalBundleRootPath: String
    var manifestSnapshotPath: String
    var installReportPath: String
    var generatedBundlePlanPath: String
}

struct ChromeMV3ValidationResultRecord: Codable, Equatable {
    var isValid: Bool
    var warnings: [ChromeMV3InstallIssue]
    var fatalValidationErrors: [ChromeMV3InstallIssue]
}

struct ChromeMV3OriginalBundleRecord: Codable, Equatable {
    var schemaVersion: Int
    var id: String
    var extensionIdentity: ChromeMV3ExtensionIdentity
    var manifestName: String
    var manifestVersion: String
    var manifestFormatVersion: Int
    var installDate: Date
    var readOnlyByConvention: Bool
    var sourceMetadata: ChromeMV3OriginalBundleSourceMetadata
    var packageMetadata: ChromeMV3PackageMetadata
    var validationResult: ChromeMV3ValidationResultRecord
    var installReport: ChromeMV3InstallReport
    var storedPaths: ChromeMV3OriginalBundleStoredPaths
}

struct ChromeMV3CapabilityClassificationSummary: Codable, Equatable {
    var detectedAPIs: [ChromeMV3API]
    var supportedAPIs: [ChromeMV3API]
    var shimmedAPIs: [ChromeMV3API]
    var nativeHostAPIs: [ChromeMV3API]
    var deferredAPIs: [ChromeMV3API]
    var unsupportedAPIs: [ChromeMV3API]
    var needsVerificationAPIs: [ChromeMV3API]

    init(report: ChromeMV3InstallReport) {
        detectedAPIs = report.detectedAPIs
        supportedAPIs = report.supportedAPIs
        shimmedAPIs = report.shimmedAPIs
        nativeHostAPIs = report.nativeHostAPIs
        deferredAPIs = report.deferredAPIs
        unsupportedAPIs = report.unsupportedAPIs
        needsVerificationAPIs = report.needsVerificationAPIs
    }
}

struct ChromeMV3ManifestSnapshotRecord: Codable, Equatable {
    var schemaVersion: Int
    var id: String
    var originalBundleRecordID: String
    var createdAt: Date
    var normalizedManifest: ChromeMV3Manifest
    var canonicalManifestJSON: String
    var manifestSHA256: String
    var installReport: ChromeMV3InstallReport
    var capabilitySummary: ChromeMV3CapabilityClassificationSummary
    var passwordManagerFeatures: ChromeMV3PasswordManagerFeatureReport
    var validationWarnings: [ChromeMV3InstallIssue]
    var validationErrors: [ChromeMV3InstallIssue]
    var sourceMetadata: ChromeMV3OriginalBundleSourceMetadata
}

struct ChromeMV3GeneratedBundlePlanningRecord: Codable, Equatable {
    var schemaVersion: Int
    var id: String
    var createdAt: Date
    var generatorVersion: String
    var originalBundleRecordID: String
    var originalBundleContentSHA256: String
    var generatedBundleRootPlaceholderPath: String
    var plannedManifestRewriteNeeded: Bool
    var plannedServiceWorkerWrapperNeeded: Bool
    var plannedJSShimModules: [String]
    var runtimeResourcePlan: ChromeMV3RuntimeResourcePlan
    var plannedNativeHostAPIs: [ChromeMV3API]
    var unsupportedAPIs: [ChromeMV3API]
    var deferredAPIs: [ChromeMV3API]
    var needsVerificationAPIs: [ChromeMV3API]
    var inertRuntimeTemplatesWritten: Bool
    var executableRuntimeFilesWritten: Bool
    var generatedRuntimeFilesWritten: Bool
}

struct ChromeMV3OriginalBundleStageResult: Equatable {
    var originalBundleRecord: ChromeMV3OriginalBundleRecord
    var manifestSnapshot: ChromeMV3ManifestSnapshotRecord
    var generatedBundlePlan: ChromeMV3GeneratedBundlePlanningRecord
}

struct ChromeMV3OriginalBundleStore {
    static let currentGeneratorVersion = "sumi-chrome-mv3-generated-bundle-plan-v2"

    var rootURL: URL
    var now: () -> Date

    init(rootURL: URL, now: @escaping () -> Date = Date.init) {
        self.rootURL = rootURL
        self.now = now
    }

    func stageUnpackedDirectory(at sourceURL: URL) throws -> ChromeMV3OriginalBundleStageResult {
        try stageSource(at: sourceURL, sourceKind: .unpackedDirectory)
    }

    func stageSource(
        at sourceURL: URL,
        sourceKind: ChromeMV3PackageSourceKind
    ) throws -> ChromeMV3OriginalBundleStageResult {
        guard sourceKind == .unpackedDirectory else {
            throw ChromeMV3OriginalBundleStoreError.unsupportedSourceKind(sourceKind)
        }

        let manifest = try ChromeMV3ManifestValidator.validatePackage(
            at: sourceURL,
            sourceKind: sourceKind
        )
        let manifestURL = sourceURL.appendingPathComponent("manifest.json")

        let digest = try ChromeMV3OriginalBundleDigest.digestUnpackedDirectory(
            at: sourceURL
        )
        let installedAt = now()
        let recordID = "unpacked-\(digest.contentSHA256.prefix(32))"
        let recordRootURL = rootURL
            .appendingPathComponent("originals", isDirectory: true)
            .appendingPathComponent(recordID, isDirectory: true)
        let originalBundleURL = recordRootURL
            .appendingPathComponent("original", isDirectory: true)
        let manifestSnapshotURL = recordRootURL
            .appendingPathComponent("manifest-snapshot.json")
        let installReportURL = recordRootURL
            .appendingPathComponent("install-report.json")
        let planURL = recordRootURL
            .appendingPathComponent("generated-bundle-plan.json")

        let sourceMetadata = ChromeMV3OriginalBundleSourceMetadata(
            sourceKind: sourceKind,
            originalSourcePath: sourceURL.standardizedFileURL.path,
            originalSourceLastPathComponent: sourceURL.lastPathComponent,
            fileCount: digest.fileCount,
            directoryCount: digest.directoryCount,
            totalBytes: digest.totalBytes,
            contentSHA256: digest.contentSHA256,
            manifestSHA256: digest.manifestSHA256
        )

        let packageMetadata = ChromeMV3PackageMetadata(
            extensionIdentity: ChromeMV3ExtensionIdentity(
                id: nil,
                derivationInput: "\(sourceKind.rawValue):\(digest.contentSHA256)"
            ),
            originalBundlePath: originalBundleURL.standardizedFileURL.path,
            originalBundleLastPathComponent: originalBundleURL.lastPathComponent,
            sourceKind: sourceKind,
            generatedBundlePath: nil,
            installDate: installedAt,
            installedVersion: manifest.version,
            sourceSHA256: digest.contentSHA256,
            manifestSHA256: digest.manifestSHA256
        )

        let installReport = ChromeMV3InstallReporter.report(
            for: manifest,
            packageMetadata: packageMetadata
        )
        let validationResult = ChromeMV3ValidationResultRecord(
            isValid: installReport.isValid,
            warnings: installReport.warnings,
            fatalValidationErrors: installReport.fatalValidationErrors
        )
        let storedPaths = ChromeMV3OriginalBundleStoredPaths(
            recordRootPath: recordRootURL.standardizedFileURL.path,
            originalBundleRootPath: originalBundleURL.standardizedFileURL.path,
            manifestSnapshotPath: manifestSnapshotURL.standardizedFileURL.path,
            installReportPath: installReportURL.standardizedFileURL.path,
            generatedBundlePlanPath: planURL.standardizedFileURL.path
        )

        let record = ChromeMV3OriginalBundleRecord(
            schemaVersion: 1,
            id: recordID,
            extensionIdentity: packageMetadata.extensionIdentity,
            manifestName: manifest.name,
            manifestVersion: manifest.version,
            manifestFormatVersion: manifest.manifestVersion,
            installDate: installedAt,
            readOnlyByConvention: true,
            sourceMetadata: sourceMetadata,
            packageMetadata: packageMetadata,
            validationResult: validationResult,
            installReport: installReport,
            storedPaths: storedPaths
        )

        let canonicalManifestJSON = try ChromeMV3DeterministicJSON
            .canonicalJSONString(fromJSONFileAt: manifestURL)
        let manifestSnapshot = ChromeMV3ManifestSnapshotRecord(
            schemaVersion: 1,
            id: "manifest-\(digest.manifestSHA256)",
            originalBundleRecordID: recordID,
            createdAt: installedAt,
            normalizedManifest: manifest,
            canonicalManifestJSON: canonicalManifestJSON,
            manifestSHA256: digest.manifestSHA256,
            installReport: installReport,
            capabilitySummary: ChromeMV3CapabilityClassificationSummary(
                report: installReport
            ),
            passwordManagerFeatures: installReport.passwordManagerFeatures,
            validationWarnings: installReport.warnings,
            validationErrors: installReport.fatalValidationErrors,
            sourceMetadata: sourceMetadata
        )

        let planningRecord = ChromeMV3GeneratedBundlePlanner.plan(
            for: record,
            manifest: manifest,
            report: installReport,
            generatedBundleRootURL: rootURL
                .appendingPathComponent("generated-bundles", isDirectory: true)
                .appendingPathComponent(recordID, isDirectory: true),
            createdAt: installedAt,
            generatorVersion: Self.currentGeneratorVersion
        )

        try writeStage(
            sourceURL: sourceURL,
            recordRootURL: recordRootURL,
            originalBundleURL: originalBundleURL,
            record: record,
            manifestSnapshot: manifestSnapshot,
            installReport: installReport,
            planningRecord: planningRecord
        )

        return ChromeMV3OriginalBundleStageResult(
            originalBundleRecord: record,
            manifestSnapshot: manifestSnapshot,
            generatedBundlePlan: planningRecord
        )
    }

    private func writeStage(
        sourceURL: URL,
        recordRootURL: URL,
        originalBundleURL: URL,
        record: ChromeMV3OriginalBundleRecord,
        manifestSnapshot: ChromeMV3ManifestSnapshotRecord,
        installReport: ChromeMV3InstallReport,
        planningRecord: ChromeMV3GeneratedBundlePlanningRecord
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: recordRootURL.path) {
            try fileManager.removeItem(at: recordRootURL)
        }
        try fileManager.createDirectory(
            at: recordRootURL,
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceURL, to: originalBundleURL)
        try ChromeMV3DeterministicJSON.write(
            record,
            to: recordRootURL.appendingPathComponent("record.json")
        )
        try ChromeMV3DeterministicJSON.write(
            manifestSnapshot,
            to: recordRootURL.appendingPathComponent("manifest-snapshot.json")
        )
        try ChromeMV3DeterministicJSON.write(
            installReport,
            to: recordRootURL.appendingPathComponent("install-report.json")
        )
        try ChromeMV3DeterministicJSON.write(
            planningRecord,
            to: recordRootURL.appendingPathComponent("generated-bundle-plan.json")
        )
    }
}

enum ChromeMV3GeneratedBundlePlanner {
    static func plan(
        for record: ChromeMV3OriginalBundleRecord,
        manifest: ChromeMV3Manifest,
        report: ChromeMV3InstallReport,
        generatedBundleRootURL: URL,
        createdAt: Date,
        generatorVersion: String
    ) -> ChromeMV3GeneratedBundlePlanningRecord {
        let runtimeResourcePlan = ChromeMV3RuntimeResourcePlanner.plan(
            manifest: manifest,
            installReport: report
        )
        let plannedJSShimModules = report.shimmedAPIs
            .map { "chrome.\($0.rawValue)" }
            .sorted()
        let serviceWorkerWrapperNeeded = runtimeResourcePlan
            .requires(.serviceWorkerWrapperClassic)
            || runtimeResourcePlan.requires(.serviceWorkerWrapperModule)
        let manifestRewriteNeeded = runtimeResourcePlan
            .manifestRewriteRequiredLater
            || plannedJSShimModules.isEmpty == false
            || report.nativeHostAPIs.isEmpty == false

        return ChromeMV3GeneratedBundlePlanningRecord(
            schemaVersion: 2,
            id: "generated-plan-\(record.sourceMetadata.contentSHA256.prefix(32))",
            createdAt: createdAt,
            generatorVersion: generatorVersion,
            originalBundleRecordID: record.id,
            originalBundleContentSHA256: record.sourceMetadata.contentSHA256,
            generatedBundleRootPlaceholderPath: generatedBundleRootURL
                .standardizedFileURL
                .path,
            plannedManifestRewriteNeeded: manifestRewriteNeeded,
            plannedServiceWorkerWrapperNeeded: serviceWorkerWrapperNeeded,
            plannedJSShimModules: plannedJSShimModules,
            runtimeResourcePlan: runtimeResourcePlan,
            plannedNativeHostAPIs: report.nativeHostAPIs,
            unsupportedAPIs: report.unsupportedAPIs,
            deferredAPIs: report.deferredAPIs,
            needsVerificationAPIs: report.needsVerificationAPIs,
            inertRuntimeTemplatesWritten: false,
            executableRuntimeFilesWritten: false,
            generatedRuntimeFilesWritten: false
        )
    }
}

private struct ChromeMV3OriginalBundleDigest {
    var contentSHA256: String
    var manifestSHA256: String
    var fileCount: Int
    var directoryCount: Int
    var totalBytes: Int64

    static func digestUnpackedDirectory(
        at sourceURL: URL
    ) throws -> ChromeMV3OriginalBundleDigest {
        let fileManager = FileManager.default
        let standardizedSourceURL = sourceURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(
                atPath: standardizedSourceURL.path,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue
        else {
            throw ChromeMV3OriginalBundleStoreError.nonDirectorySource(
                standardizedSourceURL.path
            )
        }

        try validateSafeRelativePath(
            standardizedSourceURL.lastPathComponent,
            originalPath: standardizedSourceURL.path
        )

        let rootPath = standardizedSourceURL.path.hasSuffix("/")
            ? standardizedSourceURL.path
            : standardizedSourceURL.path + "/"
        guard
            let enumerator = fileManager.enumerator(
                at: standardizedSourceURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ],
                options: []
            )
        else {
            throw ChromeMV3OriginalBundleStoreError.unreadableSource(
                standardizedSourceURL.path
            )
        }

        var entries: [String] = []
        var fileCount = 0
        var directoryCount = 0
        var totalBytes: Int64 = 0
        var manifestSHA256: String?

        for case let itemURL as URL in enumerator {
            let itemURL = itemURL.standardizedFileURL
            guard itemURL.path.hasPrefix(rootPath) else {
                throw ChromeMV3OriginalBundleStoreError.sourceEscapedStoreRoot(
                    itemURL.path
                )
            }

            let relativePath = String(itemURL.path.dropFirst(rootPath.count))
            try validateSafeRelativePath(relativePath, originalPath: itemURL.path)

            let values = try itemURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
            if values.isSymbolicLink == true {
                throw ChromeMV3OriginalBundleStoreError.unsafeBundlePath(
                    relativePath
                )
            }

            if values.isDirectory == true {
                directoryCount += 1
                entries.append("D \(relativePath)\n")
            } else if values.isRegularFile == true {
                let data = try Data(contentsOf: itemURL)
                let fileSHA256 = sha256Hex(data)
                let byteCount = Int64(data.count)
                fileCount += 1
                totalBytes += byteCount
                entries.append("F \(relativePath) \(byteCount) \(fileSHA256)\n")
                if relativePath == "manifest.json" {
                    manifestSHA256 = fileSHA256
                }
            } else {
                throw ChromeMV3OriginalBundleStoreError.unsafeBundlePath(
                    relativePath
                )
            }
        }

        let digestData = entries.sorted().joined().data(using: .utf8) ?? Data()
        return ChromeMV3OriginalBundleDigest(
            contentSHA256: sha256Hex(digestData),
            manifestSHA256: try manifestSHA256 ?? sha256File(
                at: standardizedSourceURL.appendingPathComponent("manifest.json")
            ),
            fileCount: fileCount,
            directoryCount: directoryCount,
            totalBytes: totalBytes
        )
    }

    private static func validateSafeRelativePath(
        _ relativePath: String,
        originalPath: String
    ) throws {
        guard relativePath.isEmpty == false else {
            throw ChromeMV3OriginalBundleStoreError.unsafeBundlePath(originalPath)
        }
        guard
            relativePath.hasPrefix("/") == false,
            relativePath.hasPrefix("~") == false,
            relativePath.contains("\\") == false,
            relativePath.contains("\0") == false,
            relativePath.localizedCaseInsensitiveContains("://") == false
        else {
            throw ChromeMV3OriginalBundleStoreError.unsafeBundlePath(relativePath)
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
            throw ChromeMV3OriginalBundleStoreError.unsafeBundlePath(relativePath)
        }
    }

    private static func sha256File(at url: URL) throws -> String {
        sha256Hex(try Data(contentsOf: url))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum ChromeMV3DeterministicJSON {
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encodedData(value)
        try data.write(to: url, options: [.atomic])
    }

    static func encodedString<T: Encodable>(_ value: T) throws -> String {
        let data = try encodedData(value)
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func canonicalJSONString(fromJSONFileAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        let canonicalData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return String(data: canonicalData, encoding: .utf8) ?? ""
    }

    private static func encodedData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}
