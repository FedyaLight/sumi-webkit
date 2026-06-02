//
//  ChromeMV3PackageIntake.swift
//  Sumi
//
//  Local package intake foundation for Chrome MV3 extension packages. This
//  layer parses and stages package files only; it does not download remote
//  packages, create WebKit runtime objects, inject page scripts, or attach
//  normal-tab runtime bridges.
//

import CryptoKit
import Foundation
import zlib

enum ChromeMV3PackageIntakeSourceKind: String, Codable, CaseIterable {
    case localUnpacked
    case localZip
    case localCrx
    case chromeWebStoreURL
    case chromeWebStoreExtensionID
}

enum ChromeMV3PackageIntakeStageStatus:
    String,
    Codable,
    CaseIterable,
    Comparable
{
    case notRun
    case passed
    case failed
    case blocked
    case deferred

    static func < (
        lhs: ChromeMV3PackageIntakeStageStatus,
        rhs: ChromeMV3PackageIntakeStageStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PackageIntakeStageResult: Codable, Equatable {
    var status: ChromeMV3PackageIntakeStageStatus
    var code: String
    var message: String
    var path: String?
    var details: [String]

    static let notRun = ChromeMV3PackageIntakeStageResult(
        status: .notRun,
        code: "notRun",
        message: "Stage was not run.",
        path: nil,
        details: []
    )

    static func passed(
        _ code: String,
        message: String,
        path: String? = nil,
        details: [String] = []
    ) -> ChromeMV3PackageIntakeStageResult {
        ChromeMV3PackageIntakeStageResult(
            status: .passed,
            code: code,
            message: message,
            path: path,
            details: details.sorted()
        )
    }

    static func failed(
        _ code: String,
        message: String,
        path: String? = nil,
        details: [String] = []
    ) -> ChromeMV3PackageIntakeStageResult {
        ChromeMV3PackageIntakeStageResult(
            status: .failed,
            code: code,
            message: message,
            path: path,
            details: details.sorted()
        )
    }

    static func blocked(
        _ code: String,
        message: String,
        path: String? = nil,
        details: [String] = []
    ) -> ChromeMV3PackageIntakeStageResult {
        ChromeMV3PackageIntakeStageResult(
            status: .blocked,
            code: code,
            message: message,
            path: path,
            details: details.sorted()
        )
    }

    static func deferred(
        _ code: String,
        message: String,
        path: String? = nil,
        details: [String] = []
    ) -> ChromeMV3PackageIntakeStageResult {
        ChromeMV3PackageIntakeStageResult(
            status: .deferred,
            code: code,
            message: message,
            path: path,
            details: details.sorted()
        )
    }
}

struct ChromeMV3PackageIntakeProductFlags: Codable, Equatable {
    var chromeWebStoreInstallAvailable: Bool
    var remoteCRXDownloadAvailable: Bool
    var crxImportAvailable: Bool
    var zipImportAvailable: Bool
    var productRuntimeAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool

    static func unavailable(
        zipImportAvailable: Bool
    ) -> ChromeMV3PackageIntakeProductFlags {
        ChromeMV3PackageIntakeProductFlags(
            chromeWebStoreInstallAvailable: false,
            remoteCRXDownloadAvailable: false,
            crxImportAvailable: false,
            zipImportAvailable: zipImportAvailable,
            productRuntimeAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false
        )
    }
}

struct ChromeMV3ZIPArchivePreflightResult: Codable, Equatable {
    var stage: ChromeMV3PackageIntakeStageResult
    var archivePath: String
    var archiveByteCount: UInt64
    var entryCount: Int
    var fileCount: Int
    var directoryCount: Int
    var totalUncompressedBytes: UInt64
    var manifestCandidatePaths: [String]
    var extensionRootRelativePath: String?
    var blockers: [String]
    var remediation: [String]

    var passed: Bool { stage.status == .passed }
}

struct ChromeMV3ZIPExtractionResult: Codable, Equatable {
    var stage: ChromeMV3PackageIntakeStageResult
    var stagingRootPath: String?
    var extractedRootPath: String?
    var extensionRootPath: String?
    var extractedFileCount: Int
    var extractedDirectoryCount: Int
    var blockers: [String]
    var remediation: [String]
}

struct ChromeMV3PackageManifestRootResult: Codable, Equatable {
    var stage: ChromeMV3PackageIntakeStageResult
    var manifestPath: String?
    var extensionRootPath: String?
    var candidateCount: Int
    var candidatePaths: [String]
    var blockers: [String]
    var remediation: [String]
}

struct ChromeMV3PackageManifestValidationResult: Codable, Equatable {
    var stage: ChromeMV3PackageIntakeStageResult
    var manifestSummary: ChromeMV3ManifestSummary?
    var warnings: [ChromeMV3InstallIssue]
    var blockers: [String]
    var remediation: [String]
}

enum ChromeMV3CRXTrustState: String, Codable, CaseIterable, Comparable {
    case notCrx
    case parsedButUnverified
    case signatureVerificationUnavailable
    case signatureVerificationFailed
    case signatureVerified
    case extensionIdDerived
    case trustPolicyMissing
    case importAllowed
    case importBlocked

    static func < (lhs: ChromeMV3CRXTrustState, rhs: ChromeMV3CRXTrustState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3CRXProofMetadata: Codable, Equatable {
    var algorithm: String
    var publicKeyByteCount: Int
    var signatureByteCount: Int
    var derivedExtensionID: String?
}

struct ChromeMV3CRX3ParserResult: Codable, Equatable {
    var stage: ChromeMV3PackageIntakeStageResult
    var crxPath: String
    var fileByteCount: UInt64
    var version: UInt32?
    var headerLength: UInt32?
    var payloadOffset: UInt64?
    var payloadByteCount: UInt64?
    var signedHeaderDataByteCount: Int?
    var declaredExtensionID: String?
    var rsaProofs: [ChromeMV3CRXProofMetadata]
    var ecdsaProofs: [ChromeMV3CRXProofMetadata]
    var verifiedContentsByteCount: Int?
    var payloadZIPPreflight: ChromeMV3ZIPArchivePreflightResult?
    var blockers: [String]
    var remediation: [String]

    var parsedCRX3: Bool { stage.status == .passed }
}

struct ChromeMV3CRXTrustResult: Codable, Equatable {
    var stage: ChromeMV3PackageIntakeStageResult
    var states: [ChromeMV3CRXTrustState]
    var extensionID: String?
    var importAllowed: Bool
    var blockers: [String]
    var remediation: [String]
}

struct ChromeMV3ChromeWebStoreDiagnostic: Codable, Equatable {
    var stage: ChromeMV3PackageIntakeStageResult
    var input: String
    var parsedExtensionID: String?
    var inputKind: ChromeMV3PackageIntakeSourceKind
    var webStoreInstallUnsupported: Bool
    var remoteCRXDownloadUnavailable: Bool
    var addToChromeInterceptionUnsupported: Bool
    var pageInjectionForbidden: Bool
    var chromeSpoofingForbidden: Bool
    var futureRequirements: [String]
    var blockers: [String]
    var remediation: [String]
}

struct ChromeMV3LifecycleImportIntakeResult: Codable, Equatable {
    var stage: ChromeMV3PackageIntakeStageResult
    var operation: ChromeMV3LifecycleOperationKind?
    var succeeded: Bool
    var profileID: String?
    var extensionID: String?
    var lifecycleState: ChromeMV3LifecycleState?
    var diagnosticsReportPath: String?
    var diagnostics: [String]
}

struct ChromeMV3PackageIntakeReport: Codable, Equatable {
    static let schemaVersion = 1
    static let reportFileName = "runtime-mv3-package-intake-report.json"

    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var generatedAt: Date
    var sourceKind: ChromeMV3PackageIntakeSourceKind
    var sourcePath: String?
    var sourceURL: String?
    var extensionIDInput: String?
    var preflightResult: ChromeMV3PackageIntakeStageResult
    var zipPreflight: ChromeMV3ZIPArchivePreflightResult?
    var extractionResult: ChromeMV3ZIPExtractionResult?
    var manifestRootResult: ChromeMV3PackageManifestRootResult
    var validationResult: ChromeMV3PackageManifestValidationResult
    var crxParserResult: ChromeMV3CRX3ParserResult?
    var trustResult: ChromeMV3CRXTrustResult
    var webStoreDiagnostic: ChromeMV3ChromeWebStoreDiagnostic?
    var lifecycleImportResult: ChromeMV3LifecycleImportIntakeResult
    var blockers: [String]
    var remediation: [String]
    var productFlags: ChromeMV3PackageIntakeProductFlags

    static func initial(
        id: String,
        generatedAt: Date,
        sourceKind: ChromeMV3PackageIntakeSourceKind,
        sourcePath: String? = nil,
        sourceURL: String? = nil,
        extensionIDInput: String? = nil,
        zipImportAvailable: Bool
    ) -> ChromeMV3PackageIntakeReport {
        ChromeMV3PackageIntakeReport(
            schemaVersion: schemaVersion,
            id: id,
            reportFileName: reportFileName,
            generatedAt: generatedAt,
            sourceKind: sourceKind,
            sourcePath: sourcePath,
            sourceURL: sourceURL,
            extensionIDInput: extensionIDInput,
            preflightResult: .notRun,
            zipPreflight: nil,
            extractionResult: nil,
            manifestRootResult: ChromeMV3PackageManifestRootResult(
                stage: .notRun,
                manifestPath: nil,
                extensionRootPath: nil,
                candidateCount: 0,
                candidatePaths: [],
                blockers: [],
                remediation: []
            ),
            validationResult: ChromeMV3PackageManifestValidationResult(
                stage: .notRun,
                manifestSummary: nil,
                warnings: [],
                blockers: [],
                remediation: []
            ),
            crxParserResult: nil,
            trustResult: ChromeMV3CRXTrustResult(
                stage: .notRun,
                states: [],
                extensionID: nil,
                importAllowed: false,
                blockers: [],
                remediation: []
            ),
            webStoreDiagnostic: nil,
            lifecycleImportResult: ChromeMV3LifecycleImportIntakeResult(
                stage: .notRun,
                operation: nil,
                succeeded: false,
                profileID: nil,
                extensionID: nil,
                lifecycleState: nil,
                diagnosticsReportPath: nil,
                diagnostics: []
            ),
            blockers: [],
            remediation: [],
            productFlags: .unavailable(zipImportAvailable: zipImportAvailable)
        )
    }
}

struct ChromeMV3PackageIntakeImportResult: Equatable {
    var actionStatus: ChromeMV3ExtensionManagerActionStatus
    var lifecycleResult: ChromeMV3LifecycleOperationResult?
    var report: ChromeMV3PackageIntakeReport
}

enum ChromeMV3PackageIntakeLimits {
    static let maxArchiveBytes: UInt64 = 50 * 1024 * 1024
    static let maxEntryCount = 2_000
    static let maxTotalUncompressedBytes: UInt64 = 100 * 1024 * 1024
    static let maxEntryUncompressedBytes: UInt64 = 25 * 1024 * 1024
    static let maxCRXHeaderBytes: UInt32 = 1 << 18
}

struct ChromeMV3PackageIntakeService {
    var rootURL: URL
    var now: () -> Date
    var fileManager: FileManager

    init(
        rootURL: URL,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.now = now
        self.fileManager = fileManager
    }

    static func latestReport(
        rootURL: URL,
        fileManager: FileManager = .default
    ) -> ChromeMV3PackageIntakeReport? {
        let url = packageIntakeReportURL(rootURL: rootURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(
            ChromeMV3PackageIntakeReport.self,
            from: Data(contentsOf: url)
        )
    }

    static func packageIntakeReportURL(rootURL: URL) -> URL {
        rootURL.standardizedFileURL
            .appendingPathComponent("package-intake", isDirectory: true)
            .appendingPathComponent(ChromeMV3PackageIntakeReport.reportFileName)
    }

    @discardableResult
    func writeLocalUnpackedReport(
        sourceURL: URL,
        lifecycleResult: ChromeMV3LifecycleOperationResult
    ) -> ChromeMV3PackageIntakeReport {
        var report = ChromeMV3PackageIntakeReport.initial(
            id: stableID(
                prefix: "mv3-package-intake-unpacked",
                parts: [sourceURL.standardizedFileURL.path]
            ),
            generatedAt: now(),
            sourceKind: .localUnpacked,
            sourcePath: sourceURL.standardizedFileURL.path,
            zipImportAvailable: true
        )
        report.preflightResult = .passed(
            "localUnpackedLifecyclePreflight",
            message: "Local unpacked directory is handled by the existing MV3 lifecycle pipeline.",
            path: sourceURL.standardizedFileURL.path
        )
        report.manifestRootResult = ChromeMV3PackageManifestRootResult(
            stage: lifecycleResult.succeeded
                ? .passed(
                    "manifestRootAccepted",
                    message: "Manifest root was accepted by lifecycle import.",
                    path: sourceURL.standardizedFileURL.path
                )
                : .failed(
                    "manifestRootRejected",
                    message: "Manifest root was rejected by lifecycle import.",
                    path: sourceURL.standardizedFileURL.path,
                    details: lifecycleResult.diagnostics
                ),
            manifestPath: sourceURL
                .appendingPathComponent("manifest.json")
                .standardizedFileURL
                .path,
            extensionRootPath: sourceURL.standardizedFileURL.path,
            candidateCount: 1,
            candidatePaths: ["manifest.json"],
            blockers: lifecycleResult.succeeded ? [] : lifecycleResult.diagnostics,
            remediation: lifecycleResult.succeeded
                ? []
                : ["Fix the local MV3 manifest/source and retry Load Unpacked."]
        )
        report.validationResult = validationResult(
            sourceURL: sourceURL,
            succeeded: lifecycleResult.succeeded,
            diagnostics: lifecycleResult.diagnostics
        )
        report.lifecycleImportResult = lifecycleIntakeResult(
            lifecycleResult,
            stageMessage: lifecycleResult.succeeded
                ? "Local unpacked import completed through the lifecycle registry."
                : "Local unpacked import failed in the lifecycle registry."
        )
        report.blockers = uniqueSorted(
            report.manifestRootResult.blockers
                + report.validationResult.blockers
                + report.lifecycleImportResult.diagnostics.filter {
                    lifecycleResult.succeeded == false && $0.isEmpty == false
                }
        )
        report.remediation = uniqueSorted(
            report.manifestRootResult.remediation
                + report.validationResult.remediation
        )
        try? write(report)
        return report
    }

    @discardableResult
    func preflightLocalZIPArchive(
        sourceURL: URL
    ) -> ChromeMV3PackageIntakeReport {
        var report = baseReport(
            sourceKind: .localZip,
            sourceURL: sourceURL
        )
        let preflight = ChromeMV3ZIPArchiveReader.preflightFile(
            at: sourceURL,
            fileManager: fileManager
        )
        report.zipPreflight = preflight
        report.preflightResult = preflight.stage
        report.manifestRootResult = manifestRootResult(
            preflight: preflight,
            absoluteRootURL: nil
        )
        report.blockers = uniqueSorted(preflight.blockers)
        report.remediation = uniqueSorted(preflight.remediation)
        try? write(report)
        return report
    }

    func importLocalZIPArchive(
        sourceURL: URL,
        profileID: String,
        enableInternal: Bool,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot
    ) -> ChromeMV3PackageIntakeImportResult {
        var report = baseReport(
            sourceKind: .localZip,
            sourceURL: sourceURL
        )
        let preflight = ChromeMV3ZIPArchiveReader.preflightFile(
            at: sourceURL,
            fileManager: fileManager
        )
        report.zipPreflight = preflight
        report.preflightResult = preflight.stage
        report.manifestRootResult = manifestRootResult(
            preflight: preflight,
            absoluteRootURL: nil
        )
        guard preflight.passed else {
            report.blockers = uniqueSorted(preflight.blockers)
            report.remediation = uniqueSorted(preflight.remediation)
            try? write(report)
            return ChromeMV3PackageIntakeImportResult(
                actionStatus: .failed,
                lifecycleResult: nil,
                report: report
            )
        }

        let candidateRoot = stagingRootURL(reportID: report.id)
        let acceptedRoot = acceptedRootURL(reportID: report.id)
        cleanup(candidateRoot)
        cleanup(acceptedRoot)

        do {
            let extraction = try ChromeMV3ZIPArchiveReader.extract(
                preflight: preflight,
                from: sourceURL,
                to: candidateRoot,
                fileManager: fileManager
            )
            report.extractionResult = extraction
            let candidateExtensionRoot = extensionRootURL(
                baseURL: candidateRoot,
                relativeRoot: preflight.extensionRootRelativePath
            )
            report.manifestRootResult = manifestRootResult(
                preflight: preflight,
                absoluteRootURL: candidateExtensionRoot
            )
            let manifest = try ChromeMV3ManifestValidator.validatePackage(
                at: candidateExtensionRoot,
                sourceKind: .unpackedDirectory
            )
            report.validationResult = ChromeMV3PackageManifestValidationResult(
                stage: .passed(
                    "manifestValidationPassed",
                    message: "Extracted package contains a valid MV3 manifest.",
                    path: candidateExtensionRoot
                        .appendingPathComponent("manifest.json")
                        .path
                ),
                manifestSummary: ChromeMV3InstallReporter
                    .report(for: manifest)
                    .manifestSummary,
                warnings: ChromeMV3InstallReporter.report(for: manifest).warnings,
                blockers: [],
                remediation: []
            )
            try fileManager.createDirectory(
                at: acceptedRoot.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: candidateRoot, to: acceptedRoot)
            let acceptedExtensionRoot = extensionRootURL(
                baseURL: acceptedRoot,
                relativeRoot: preflight.extensionRootRelativePath
            )
            report.extractionResult?.extractedRootPath = acceptedRoot.path
            report.extractionResult?.extensionRootPath =
                acceptedExtensionRoot.path
            report.manifestRootResult.extensionRootPath =
                acceptedExtensionRoot.path
            report.manifestRootResult.manifestPath = acceptedExtensionRoot
                .appendingPathComponent("manifest.json")
                .path

            let lifecycleResult = ChromeMV3ExtensionLifecycleRegistry(
                rootURL: rootURL,
                now: now,
                fileManager: fileManager
            ).installUnpackedExtension(
                at: acceptedExtensionRoot,
                profileID: profileID,
                enableInternal: enableInternal,
                installedSourceKind: .zipArchive,
                installedSourcePath: sourceURL.standardizedFileURL.path,
                installedSourceLastPathComponent: sourceURL.lastPathComponent,
                runtimeDiagnostics: runtimeDiagnostics
            )
            report.lifecycleImportResult = lifecycleIntakeResult(
                lifecycleResult,
                stageMessage: lifecycleResult.succeeded
                    ? "ZIP-imported extension was promoted through the lifecycle registry."
                    : "ZIP-imported extension failed lifecycle registry promotion."
            )
            if lifecycleResult.succeeded == false {
                cleanup(acceptedRoot)
            }
            report.blockers = uniqueSorted(
                report.zipPreflight?.blockers ?? []
                    + (report.extractionResult?.blockers ?? [])
                    + report.manifestRootResult.blockers
                    + report.validationResult.blockers
                    + (lifecycleResult.succeeded ? [] : lifecycleResult.diagnostics)
            )
            report.remediation = uniqueSorted(
                report.zipPreflight?.remediation ?? []
                    + (report.extractionResult?.remediation ?? [])
                    + report.manifestRootResult.remediation
                    + report.validationResult.remediation
                    + (lifecycleResult.succeeded
                        ? []
                        : ["Fix the package contents and retry ZIP import."])
            )
            try? write(report)
            return ChromeMV3PackageIntakeImportResult(
                actionStatus: lifecycleResult.succeeded ? .succeeded : .failed,
                lifecycleResult: lifecycleResult,
                report: report
            )
        } catch {
            cleanup(candidateRoot)
            cleanup(acceptedRoot)
            let message = packageErrorMessage(error)
            report.extractionResult = report.extractionResult
                ?? ChromeMV3ZIPExtractionResult(
                    stage: .failed(
                        "zipExtractionFailed",
                        message: message,
                        path: candidateRoot.path
                    ),
                    stagingRootPath: candidateRoot.path,
                    extractedRootPath: nil,
                    extensionRootPath: nil,
                    extractedFileCount: 0,
                    extractedDirectoryCount: 0,
                    blockers: [message],
                    remediation: [
                        "Inspect the ZIP archive entries and retry with a safe MV3 package.",
                    ]
                )
            report.validationResult = validationResult(
                sourceURL: sourceURL,
                succeeded: false,
                diagnostics: [message]
            )
            report.blockers = uniqueSorted(
                preflight.blockers
                    + (report.extractionResult?.blockers ?? [])
                    + [message]
            )
            report.remediation = uniqueSorted(
                preflight.remediation
                    + (report.extractionResult?.remediation ?? [])
                    + ["Use a ZIP with one safe MV3 extension root."]
            )
            try? write(report)
            return ChromeMV3PackageIntakeImportResult(
                actionStatus: .failed,
                lifecycleResult: nil,
                report: report
            )
        }
    }

    @discardableResult
    func preflightLocalCRXArchive(
        sourceURL: URL
    ) -> ChromeMV3PackageIntakeReport {
        var report = baseReport(
            sourceKind: .localCrx,
            sourceURL: sourceURL
        )
        let parser = ChromeMV3CRX3Parser.preflightCRX3(
            at: sourceURL,
            fileManager: fileManager
        )
        report.crxParserResult = parser
        report.preflightResult = parser.stage
        report.zipPreflight = parser.payloadZIPPreflight
        report.trustResult = ChromeMV3CRXTrustEvaluator.evaluate(parser)
        report.blockers = uniqueSorted(parser.blockers + report.trustResult.blockers)
        report.remediation = uniqueSorted(
            parser.remediation + report.trustResult.remediation
        )
        try? write(report)
        return report
    }

    func importLocalCRXArchive(
        sourceURL: URL
    ) -> ChromeMV3PackageIntakeImportResult {
        var report = preflightLocalCRXArchive(sourceURL: sourceURL)
        report.lifecycleImportResult = ChromeMV3LifecycleImportIntakeResult(
            stage: .blocked(
                "crxImportBlocked",
                message: "CRX import is blocked until CRX3 signature verification and package trust policy are implemented.",
                path: sourceURL.standardizedFileURL.path
            ),
            operation: nil,
            succeeded: false,
            profileID: nil,
            extensionID: report.trustResult.extensionID,
            lifecycleState: nil,
            diagnosticsReportPath: nil,
            diagnostics: [
                "CRX parser success is not a package trust decision.",
                "No CRX payload extraction or lifecycle promotion was attempted.",
            ]
        )
        report.blockers = uniqueSorted(
            report.blockers + report.lifecycleImportResult.diagnostics
        )
        report.remediation = uniqueSorted(
            report.remediation + [
                "Implement Chromium-equivalent CRX3 verifier semantics and an explicit trust policy before allowing CRX import.",
            ]
        )
        try? write(report)
        return ChromeMV3PackageIntakeImportResult(
            actionStatus: .blocked,
            lifecycleResult: nil,
            report: report
        )
    }

    @discardableResult
    func diagnoseChromeWebStoreInput(
        _ input: String
    ) -> ChromeMV3PackageIntakeReport {
        let diagnostic = ChromeMV3ChromeWebStoreParser.diagnose(input)
        var report = ChromeMV3PackageIntakeReport.initial(
            id: stableID(
                prefix: "mv3-package-intake-webstore",
                parts: [input]
            ),
            generatedAt: now(),
            sourceKind: diagnostic.inputKind,
            sourceURL: diagnostic.inputKind == .chromeWebStoreURL
                ? input
                : nil,
            extensionIDInput: diagnostic.inputKind == .chromeWebStoreExtensionID
                ? input
                : diagnostic.parsedExtensionID,
            zipImportAvailable: true
        )
        report.preflightResult = diagnostic.stage
        report.webStoreDiagnostic = diagnostic
        report.trustResult = ChromeMV3CRXTrustResult(
            stage: .blocked(
                "webStorePackageTrustUnavailable",
                message: "Chrome Web Store import is deferred; no remote package acquisition or CRX verification policy exists.",
                details: diagnostic.futureRequirements
            ),
            states: [
                .signatureVerificationUnavailable,
                .trustPolicyMissing,
                .importBlocked,
            ],
            extensionID: diagnostic.parsedExtensionID,
            importAllowed: false,
            blockers: diagnostic.blockers,
            remediation: diagnostic.remediation
        )
        report.lifecycleImportResult = ChromeMV3LifecycleImportIntakeResult(
            stage: .deferred(
                "chromeWebStoreImportDeferred",
                message: "Chrome Web Store import is diagnostics-only in this build."
            ),
            operation: nil,
            succeeded: false,
            profileID: nil,
            extensionID: diagnostic.parsedExtensionID,
            lifecycleState: nil,
            diagnosticsReportPath: nil,
            diagnostics: [
                "No remote CRX download occurred.",
                "No Web Store page injection or Add to Chrome interception occurred.",
            ]
        )
        report.blockers = uniqueSorted(
            diagnostic.blockers
                + report.trustResult.blockers
                + report.lifecycleImportResult.diagnostics
        )
        report.remediation = uniqueSorted(
            diagnostic.remediation + report.trustResult.remediation
        )
        try? write(report)
        return report
    }

    private func baseReport(
        sourceKind: ChromeMV3PackageIntakeSourceKind,
        sourceURL: URL
    ) -> ChromeMV3PackageIntakeReport {
        ChromeMV3PackageIntakeReport.initial(
            id: stableID(
                prefix: "mv3-package-intake-\(sourceKind.rawValue)",
                parts: [
                    sourceURL.standardizedFileURL.path,
                    sourceURL.lastPathComponent,
                ]
            ),
            generatedAt: now(),
            sourceKind: sourceKind,
            sourcePath: sourceURL.standardizedFileURL.path,
            zipImportAvailable: true
        )
    }

    private func manifestRootResult(
        preflight: ChromeMV3ZIPArchivePreflightResult,
        absoluteRootURL: URL?
    ) -> ChromeMV3PackageManifestRootResult {
        if preflight.manifestCandidatePaths.count == 1 {
            let manifestRelativePath = preflight.manifestCandidatePaths[0]
            let rootPath = absoluteRootURL?.path
            return ChromeMV3PackageManifestRootResult(
                stage: .passed(
                    "singleManifestRootFound",
                    message: "Archive contains exactly one manifest.json candidate.",
                    path: rootPath,
                    details: [manifestRelativePath]
                ),
                manifestPath: absoluteRootURL?
                    .appendingPathComponent("manifest.json")
                    .path,
                extensionRootPath: rootPath,
                candidateCount: 1,
                candidatePaths: preflight.manifestCandidatePaths,
                blockers: [],
                remediation: []
            )
        }
        let message = preflight.manifestCandidatePaths.isEmpty
            ? "Archive does not contain manifest.json."
            : "Archive contains multiple manifest.json candidates."
        return ChromeMV3PackageManifestRootResult(
            stage: .failed(
                preflight.manifestCandidatePaths.isEmpty
                    ? "manifestMissing"
                    : "manifestRootAmbiguous",
                message: message,
                details: preflight.manifestCandidatePaths
            ),
            manifestPath: nil,
            extensionRootPath: nil,
            candidateCount: preflight.manifestCandidatePaths.count,
            candidatePaths: preflight.manifestCandidatePaths,
            blockers: [message],
            remediation: [
                "Package exactly one MV3 extension root with one manifest.json.",
            ]
        )
    }

    private func validationResult(
        sourceURL: URL,
        succeeded: Bool,
        diagnostics: [String]
    ) -> ChromeMV3PackageManifestValidationResult {
        if succeeded,
           let manifest = try? ChromeMV3ManifestValidator.validatePackage(
            at: sourceURL,
            sourceKind: .unpackedDirectory
           )
        {
            let report = ChromeMV3InstallReporter.report(for: manifest)
            return ChromeMV3PackageManifestValidationResult(
                stage: .passed(
                    "manifestValidationPassed",
                    message: "Manifest validation passed.",
                    path: sourceURL
                        .appendingPathComponent("manifest.json")
                        .path
                ),
                manifestSummary: report.manifestSummary,
                warnings: report.warnings,
                blockers: [],
                remediation: []
            )
        }
        return ChromeMV3PackageManifestValidationResult(
            stage: .failed(
                "manifestValidationFailed",
                message: diagnostics.first ?? "Manifest validation failed.",
                path: sourceURL.path,
                details: diagnostics
            ),
            manifestSummary: nil,
            warnings: [],
            blockers: diagnostics,
            remediation: ["Fix manifest validation errors and retry import."]
        )
    }

    private func lifecycleIntakeResult(
        _ result: ChromeMV3LifecycleOperationResult,
        stageMessage: String
    ) -> ChromeMV3LifecycleImportIntakeResult {
        ChromeMV3LifecycleImportIntakeResult(
            stage: result.succeeded
                ? .passed(
                    "lifecycleImportSucceeded",
                    message: stageMessage,
                    path: result.record?.reportPaths.registryRecordPath
                )
                : .failed(
                    "lifecycleImportFailed",
                    message: stageMessage,
                    path: result.record?.reportPaths.registryRecordPath,
                    details: result.diagnostics
                ),
            operation: result.operation,
            succeeded: result.succeeded,
            profileID: result.record?.profileID,
            extensionID: result.record?.extensionID,
            lifecycleState: result.record?.lifecycleState,
            diagnosticsReportPath: result.record?.reportPaths
                .compatibilityReportPath,
            diagnostics: result.diagnostics
        )
    }

    private func extensionRootURL(
        baseURL: URL,
        relativeRoot: String?
    ) -> URL {
        guard let relativeRoot, relativeRoot.isEmpty == false else {
            return baseURL
        }
        return baseURL.appendingPathComponent(relativeRoot, isDirectory: true)
    }

    private func stagingRootURL(reportID: String) -> URL {
        rootURL
            .appendingPathComponent("package-intake", isDirectory: true)
            .appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent(reportID, isDirectory: true)
    }

    private func acceptedRootURL(reportID: String) -> URL {
        rootURL
            .appendingPathComponent("package-intake", isDirectory: true)
            .appendingPathComponent("accepted", isDirectory: true)
            .appendingPathComponent(reportID, isDirectory: true)
    }

    private func write(_ report: ChromeMV3PackageIntakeReport) throws {
        let url = Self.packageIntakeReportURL(rootURL: rootURL)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ChromeMV3DeterministicJSON.write(report, to: url)
    }

    private func cleanup(_ url: URL) {
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func packageErrorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

private enum ChromeMV3ZIPArchiveError: LocalizedError {
    case invalidArchive(String)
    case unsafeEntry(String)
    case unsupportedCompression(String)
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive(let reason):
            return "Invalid ZIP archive: \(reason)"
        case .unsafeEntry(let path):
            return "Unsafe ZIP archive entry: \(path)"
        case .unsupportedCompression(let path):
            return "Unsupported ZIP compression method for entry: \(path)"
        case .extractionFailed(let reason):
            return "ZIP extraction failed: \(reason)"
        }
    }
}

private struct ChromeMV3ZIPCentralDirectoryEntry {
    var normalizedPath: String
    var isDirectory: Bool
    var compressionMethod: UInt16
    var generalPurposeBitFlag: UInt16
    var crc32: UInt32
    var compressedSize: UInt64
    var uncompressedSize: UInt64
    var localHeaderOffset: UInt64
}

private struct ChromeMV3ZIPArchiveReader {
    static func preflightFile(
        at url: URL,
        fileManager: FileManager = .default
    ) -> ChromeMV3ZIPArchivePreflightResult {
        let path = url.standardizedFileURL.path
        do {
            let data = try archiveData(at: url, fileManager: fileManager)
            return try preflightArchiveData(
                data,
                archivePath: path,
                archiveByteCount: UInt64(data.count)
            )
        } catch {
            let message = packageErrorMessage(error)
            return ChromeMV3ZIPArchivePreflightResult(
                stage: .failed(
                    "zipPreflightFailed",
                    message: message,
                    path: path
                ),
                archivePath: path,
                archiveByteCount: archiveByteCount(
                    at: url,
                    fileManager: fileManager
                ),
                entryCount: 0,
                fileCount: 0,
                directoryCount: 0,
                totalUncompressedBytes: 0,
                manifestCandidatePaths: [],
                extensionRootRelativePath: nil,
                blockers: [message],
                remediation: ["Use a readable ZIP archive with safe MV3 entries."]
            )
        }
    }

    static func preflightArchiveData(
        _ data: Data,
        archivePath: String,
        archiveByteCount: UInt64
    ) throws -> ChromeMV3ZIPArchivePreflightResult {
        let entries = try centralDirectoryEntries(in: data)
        try enforceArchiveLimits(
            entries: entries,
            archiveByteCount: archiveByteCount
        )
        let manifestCandidates = entries
            .filter { $0.isDirectory == false }
            .map(\.normalizedPath)
            .filter { $0.split(separator: "/").last == "manifest.json" }
            .sorted()
        let extensionRoot = manifestCandidates.count == 1
            ? String(
                manifestCandidates[0]
                    .split(separator: "/")
                    .dropLast()
                    .joined(separator: "/")
            )
            : nil
        var blockers: [String] = []
        var remediation: [String] = []
        if manifestCandidates.isEmpty {
            blockers.append("ZIP archive does not contain manifest.json.")
            remediation.append("Package exactly one MV3 extension root.")
        } else if manifestCandidates.count > 1 {
            blockers.append("ZIP archive contains multiple manifest.json candidates.")
            remediation.append("Remove nested or unrelated extension roots.")
        } else if let manifestEntry = entries.first(where: {
            $0.normalizedPath == manifestCandidates[0]
        }) {
            do {
                try validateManifestVersionPreExtraction(
                    manifestEntry,
                    archiveData: data
                )
            } catch {
                blockers.append(packageErrorMessage(error))
                remediation.append(
                    "Package a Manifest V3 extension with manifest_version 3."
                )
            }
        }
        let fileCount = entries.filter { !$0.isDirectory }.count
        let directoryCount = entries.filter(\.isDirectory).count
        let totalUncompressed = entries.reduce(UInt64(0)) {
            $0 + $1.uncompressedSize
        }
        let stage: ChromeMV3PackageIntakeStageResult = blockers.isEmpty
            ? .passed(
                "zipPreflightPassed",
                message: "ZIP archive passed safe-entry preflight.",
                path: archivePath,
                details: manifestCandidates
            )
            : .failed(
                "zipManifestRootInvalid",
                message: blockers.first ?? "ZIP manifest root is invalid.",
                path: archivePath,
                details: manifestCandidates
            )
        return ChromeMV3ZIPArchivePreflightResult(
            stage: stage,
            archivePath: archivePath,
            archiveByteCount: archiveByteCount,
            entryCount: entries.count,
            fileCount: fileCount,
            directoryCount: directoryCount,
            totalUncompressedBytes: totalUncompressed,
            manifestCandidatePaths: manifestCandidates,
            extensionRootRelativePath: extensionRoot?.isEmpty == true
                ? nil
                : extensionRoot,
            blockers: uniqueSorted(blockers),
            remediation: uniqueSorted(remediation)
        )
    }

    static func extract(
        preflight: ChromeMV3ZIPArchivePreflightResult,
        from sourceURL: URL,
        to destinationRootURL: URL,
        fileManager: FileManager
    ) throws -> ChromeMV3ZIPExtractionResult {
        let data = try archiveData(at: sourceURL, fileManager: fileManager)
        let entries = try centralDirectoryEntries(in: data)
        try fileManager.createDirectory(
            at: destinationRootURL,
            withIntermediateDirectories: true
        )
        let rootPath = destinationRootURL.standardizedFileURL.path
            .trimmingTrailingSlash + "/"
        var extractedFiles = 0
        var extractedDirectories = 0
        for entry in entries.sorted(by: { $0.normalizedPath < $1.normalizedPath }) {
            let target = destinationRootURL
                .appendingPathComponent(entry.normalizedPath)
                .standardizedFileURL
            guard target.path == rootPath.trimmingTrailingSlash
                    || target.path.hasPrefix(rootPath)
            else {
                throw ChromeMV3ZIPArchiveError.unsafeEntry(entry.normalizedPath)
            }
            if entry.isDirectory {
                try fileManager.createDirectory(
                    at: target,
                    withIntermediateDirectories: true
                )
                extractedDirectories += 1
                continue
            }
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let bytes = try uncompressedEntryData(entry, archiveData: data)
            guard UInt64(bytes.count) == entry.uncompressedSize else {
                throw ChromeMV3ZIPArchiveError.extractionFailed(
                    "Entry \(entry.normalizedPath) expanded to an unexpected size."
                )
            }
            guard crc32(bytes) == entry.crc32 else {
                throw ChromeMV3ZIPArchiveError.extractionFailed(
                    "Entry \(entry.normalizedPath) failed CRC validation."
                )
            }
            try bytes.write(to: target, options: [.atomic])
            extractedFiles += 1
        }
        let extensionRoot = preflight.extensionRootRelativePath.map {
            destinationRootURL.appendingPathComponent($0, isDirectory: true).path
        } ?? destinationRootURL.path
        return ChromeMV3ZIPExtractionResult(
            stage: .passed(
                "zipExtractionPassed",
                message: "ZIP archive extracted under the controlled staging root.",
                path: destinationRootURL.path,
                details: [extensionRoot]
            ),
            stagingRootPath: destinationRootURL.path,
            extractedRootPath: destinationRootURL.path,
            extensionRootPath: extensionRoot,
            extractedFileCount: extractedFiles,
            extractedDirectoryCount: extractedDirectories,
            blockers: [],
            remediation: []
        )
    }

    private static func archiveData(
        at url: URL,
        fileManager: FileManager
    ) throws -> Data {
        let path = url.standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue == false
        else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Archive file does not exist or is a directory."
            )
        }
        let attributes = try fileManager.attributesOfItem(atPath: path)
        let byteCount = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard byteCount > 0 else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Archive is empty."
            )
        }
        guard byteCount <= ChromeMV3PackageIntakeLimits.maxArchiveBytes else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Archive exceeds the \(ChromeMV3PackageIntakeLimits.maxArchiveBytes) byte limit."
            )
        }
        return try Data(contentsOf: url)
    }

    private static func archiveByteCount(
        at url: URL,
        fileManager: FileManager
    ) -> UInt64 {
        let attributes = try? fileManager.attributesOfItem(
            atPath: url.standardizedFileURL.path
        )
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private static func centralDirectoryEntries(
        in data: Data
    ) throws -> [ChromeMV3ZIPCentralDirectoryEntry] {
        let eocdOffset = try findEOCD(in: data)
        let diskNumber = try data.uint16LE(at: eocdOffset + 4)
        let centralDisk = try data.uint16LE(at: eocdOffset + 6)
        let entriesOnDisk = try data.uint16LE(at: eocdOffset + 8)
        let totalEntries = try data.uint16LE(at: eocdOffset + 10)
        let centralSize = UInt64(try data.uint32LE(at: eocdOffset + 12))
        let centralOffset = UInt64(try data.uint32LE(at: eocdOffset + 16))
        guard diskNumber == 0,
              centralDisk == 0,
              entriesOnDisk == totalEntries
        else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Multi-disk ZIP archives are not supported."
            )
        }
        guard totalEntries > 0 else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Archive contains no entries."
            )
        }
        guard Int(totalEntries) <= ChromeMV3PackageIntakeLimits.maxEntryCount else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Archive exceeds the entry count limit."
            )
        }
        guard centralOffset != UInt64(UInt32.max),
              centralSize != UInt64(UInt32.max)
        else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "ZIP64 archives are not supported by this intake foundation."
            )
        }
        guard centralOffset + centralSize <= UInt64(eocdOffset) else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Central directory escapes archive bounds."
            )
        }
        var offset = Int(centralOffset)
        var entries: [ChromeMV3ZIPCentralDirectoryEntry] = []
        var seenExact: Set<String> = []
        var seenFolded: Set<String> = []
        for _ in 0..<Int(totalEntries) {
            guard try data.uint32LE(at: offset) == 0x0201_4b50 else {
                throw ChromeMV3ZIPArchiveError.invalidArchive(
                    "Central directory header is malformed."
                )
            }
            let versionMadeBy = try data.uint16LE(at: offset + 4)
            let flags = try data.uint16LE(at: offset + 8)
            let method = try data.uint16LE(at: offset + 10)
            let crc = try data.uint32LE(at: offset + 16)
            let compressedSize = UInt64(try data.uint32LE(at: offset + 20))
            let uncompressedSize = UInt64(try data.uint32LE(at: offset + 24))
            let fileNameLength = Int(try data.uint16LE(at: offset + 28))
            let extraLength = Int(try data.uint16LE(at: offset + 30))
            let commentLength = Int(try data.uint16LE(at: offset + 32))
            let diskStart = try data.uint16LE(at: offset + 34)
            let externalAttributes = try data.uint32LE(at: offset + 38)
            let localHeaderOffset = UInt64(try data.uint32LE(at: offset + 42))
            let nameStart = offset + 46
            let next = nameStart + fileNameLength + extraLength + commentLength
            guard next <= data.count else {
                throw ChromeMV3ZIPArchiveError.invalidArchive(
                    "Central directory entry exceeds archive bounds."
                )
            }
            guard diskStart == 0 else {
                throw ChromeMV3ZIPArchiveError.invalidArchive(
                    "Entry starts on an unsupported ZIP disk."
                )
            }
            guard compressedSize != UInt64(UInt32.max),
                  uncompressedSize != UInt64(UInt32.max),
                  localHeaderOffset != UInt64(UInt32.max)
            else {
                throw ChromeMV3ZIPArchiveError.invalidArchive(
                    "ZIP64 entries are not supported by this intake foundation."
                )
            }
            guard method == 0 || method == 8 else {
                let name = String(
                    data: data.subdata(in: nameStart..<(nameStart + fileNameLength)),
                    encoding: .utf8
                ) ?? "<invalid-name>"
                throw ChromeMV3ZIPArchiveError.unsupportedCompression(name)
            }
            guard flags & 0x0001 == 0 else {
                throw ChromeMV3ZIPArchiveError.invalidArchive(
                    "Encrypted ZIP entries are not supported."
                )
            }
            guard uncompressedSize
                    <= ChromeMV3PackageIntakeLimits.maxEntryUncompressedBytes
            else {
                throw ChromeMV3ZIPArchiveError.invalidArchive(
                    "An entry exceeds the per-entry uncompressed size limit."
                )
            }
            let nameData = data.subdata(in: nameStart..<(nameStart + fileNameLength))
            guard let rawName = String(data: nameData, encoding: .utf8) else {
                throw ChromeMV3ZIPArchiveError.invalidArchive(
                    "Entry name is not valid UTF-8."
                )
            }
            let isDirectory = rawName.hasSuffix("/")
            let normalized = try normalizeEntryName(rawName)
            if isSymlink(versionMadeBy: versionMadeBy, attributes: externalAttributes) {
                throw ChromeMV3ZIPArchiveError.unsafeEntry(
                    "\(normalized) is a symbolic link"
                )
            }
            guard seenExact.insert(normalized).inserted else {
                throw ChromeMV3ZIPArchiveError.unsafeEntry(
                    "\(normalized) is duplicated"
                )
            }
            let folded = normalized.lowercased()
            guard seenFolded.insert(folded).inserted else {
                throw ChromeMV3ZIPArchiveError.unsafeEntry(
                    "\(normalized) duplicates another path on case-insensitive file systems"
                )
            }
            guard localHeaderOffset + 30 <= UInt64(data.count) else {
                throw ChromeMV3ZIPArchiveError.invalidArchive(
                    "Local header offset escapes archive bounds."
                )
            }
            entries.append(
                ChromeMV3ZIPCentralDirectoryEntry(
                    normalizedPath: normalized,
                    isDirectory: isDirectory,
                    compressionMethod: method,
                    generalPurposeBitFlag: flags,
                    crc32: crc,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )
            offset = next
        }
        return entries
    }

    private static func enforceArchiveLimits(
        entries: [ChromeMV3ZIPCentralDirectoryEntry],
        archiveByteCount: UInt64
    ) throws {
        guard archiveByteCount <= ChromeMV3PackageIntakeLimits.maxArchiveBytes else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Archive exceeds the byte limit."
            )
        }
        let total = entries.reduce(UInt64(0)) { $0 + $1.uncompressedSize }
        guard total <= ChromeMV3PackageIntakeLimits.maxTotalUncompressedBytes else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Archive exceeds the total uncompressed size limit."
            )
        }
    }

    private static func findEOCD(in data: Data) throws -> Int {
        guard data.count >= 22 else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Archive is too small to contain an EOCD record."
            )
        }
        let minimum = max(0, data.count - 22 - 65_535)
        var offset = data.count - 22
        while offset >= minimum {
            if (try? data.uint32LE(at: offset)) == 0x0605_4b50 {
                let commentLength = Int(try data.uint16LE(at: offset + 20))
                if offset + 22 + commentLength == data.count {
                    return offset
                }
            }
            if offset == 0 { break }
            offset -= 1
        }
        throw ChromeMV3ZIPArchiveError.invalidArchive(
            "End of central directory was not found."
        )
    }

    private static func normalizeEntryName(_ rawName: String) throws -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ChromeMV3ZIPArchiveError.unsafeEntry(rawName)
        }
        guard trimmed.hasPrefix("/") == false,
              trimmed.hasPrefix("~") == false,
              trimmed.contains("\\") == false,
              trimmed.contains("\0") == false,
              trimmed.localizedCaseInsensitiveContains("://") == false,
              trimmed.contains(":") == false
        else {
            throw ChromeMV3ZIPArchiveError.unsafeEntry(rawName)
        }
        let withoutTrailingSlash = trimmed.hasSuffix("/")
            ? String(trimmed.dropLast())
            : trimmed
        let segments = withoutTrailingSlash.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard segments.isEmpty == false,
              segments.allSatisfy({ segment in
                segment.isEmpty == false && segment != "." && segment != ".."
              })
        else {
            throw ChromeMV3ZIPArchiveError.unsafeEntry(rawName)
        }
        for segment in segments {
            let lower = segment.lowercased()
            if lower.hasSuffix(".app") || lower.hasSuffix(".appex") {
                throw ChromeMV3ZIPArchiveError.unsafeEntry(
                    "\(rawName) contains a Safari package segment"
                )
            }
        }
        return segments.joined(separator: "/")
    }

    private static func isSymlink(
        versionMadeBy: UInt16,
        attributes: UInt32
    ) -> Bool {
        let hostSystem = versionMadeBy >> 8
        guard hostSystem == 3 || hostSystem == 19 else { return false }
        let mode = attributes >> 16
        return (mode & 0o170000) == 0o120000
    }

    private static func uncompressedEntryData(
        _ entry: ChromeMV3ZIPCentralDirectoryEntry,
        archiveData: Data
    ) throws -> Data {
        let localOffset = Int(entry.localHeaderOffset)
        guard try archiveData.uint32LE(at: localOffset) == 0x0403_4b50 else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Local file header is malformed."
            )
        }
        let nameLength = Int(try archiveData.uint16LE(at: localOffset + 26))
        let extraLength = Int(try archiveData.uint16LE(at: localOffset + 28))
        let dataStart = localOffset + 30 + nameLength + extraLength
        let dataEnd = dataStart + Int(entry.compressedSize)
        guard dataStart <= archiveData.count, dataEnd <= archiveData.count else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Entry data escapes archive bounds."
            )
        }
        let compressed = archiveData.subdata(in: dataStart..<dataEnd)
        if entry.compressionMethod == 0 {
            return compressed
        }
        guard entry.compressionMethod == 8 else {
            throw ChromeMV3ZIPArchiveError.unsupportedCompression(
                entry.normalizedPath
            )
        }
        return try inflateRawDeflate(
            compressed,
            expectedSize: Int(entry.uncompressedSize)
        )
    }

    private static func validateManifestVersionPreExtraction(
        _ entry: ChromeMV3ZIPCentralDirectoryEntry,
        archiveData: Data
    ) throws {
        let manifestData = try uncompressedEntryData(entry, archiveData: archiveData)
        let object = try JSONSerialization.jsonObject(with: manifestData)
        guard let manifest = object as? [String: Any] else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "manifest.json is not a JSON object."
            )
        }
        guard let manifestVersion = manifest["manifest_version"] as? Int else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "manifest.json is missing integer manifest_version."
            )
        }
        guard manifestVersion == 3 else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "manifest_version \(manifestVersion) is unsupported; only MV3 packages are accepted."
            )
        }
    }

    private static func inflateRawDeflate(
        _ compressedData: Data,
        expectedSize: Int
    ) throws -> Data {
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        let status: Int32 = compressedData.withUnsafeBytes { inputRaw in
            output.withUnsafeMutableBytes { outputRaw in
                var stream = z_stream()
                let initStatus = inflateInit2_(
                    &stream,
                    -MAX_WBITS,
                    ZLIB_VERSION,
                    Int32(MemoryLayout<z_stream>.size)
                )
                guard initStatus == Z_OK else { return initStatus }
                defer { inflateEnd(&stream) }
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: inputRaw.bindMemory(to: Bytef.self).baseAddress
                )
                stream.avail_in = uInt(compressedData.count)
                stream.next_out = outputRaw.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(expectedSize)
                let inflateStatus = inflate(&stream, Z_FINISH)
                guard inflateStatus == Z_STREAM_END,
                      stream.total_out == uLong(expectedSize)
                else {
                    return inflateStatus == Z_STREAM_END
                        ? Z_BUF_ERROR
                        : inflateStatus
                }
                return Z_OK
            }
        }
        guard status == Z_OK else {
            throw ChromeMV3ZIPArchiveError.extractionFailed(
                "Deflate decompression failed with zlib status \(status)."
            )
        }
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var value = zlib.crc32(0, nil, 0)
        data.withUnsafeBytes { raw in
            value = zlib.crc32(
                value,
                raw.bindMemory(to: Bytef.self).baseAddress,
                uInt(data.count)
            )
        }
        return UInt32(value)
    }

    private static func packageErrorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

private struct ChromeMV3CRX3HeaderMetadata {
    var signedHeaderData: Data?
    var declaredExtensionID: String?
    var rsaProofs: [ChromeMV3CRXProofMetadata]
    var ecdsaProofs: [ChromeMV3CRXProofMetadata]
    var verifiedContentsByteCount: Int?
}

private struct ChromeMV3CRX3Parser {
    static func preflightCRX3(
        at url: URL,
        fileManager: FileManager
    ) -> ChromeMV3CRX3ParserResult {
        let path = url.standardizedFileURL.path
        do {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue == false
            else {
                throw ChromeMV3CRX3ParserError.fileNotReadable
            }
            let attributes = try fileManager.attributesOfItem(atPath: path)
            let fileByteCount =
                (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard fileByteCount <= ChromeMV3PackageIntakeLimits.maxArchiveBytes
                    + UInt64(ChromeMV3PackageIntakeLimits.maxCRXHeaderBytes)
            else {
                throw ChromeMV3CRX3ParserError.oversizedCRX
            }
            let data = try Data(contentsOf: url)
            return try preflightCRX3Data(
                data,
                path: path,
                fileByteCount: UInt64(data.count)
            )
        } catch {
            let message = packageErrorMessage(error)
            let stageCode = (error as? ChromeMV3CRX3ParserError) == .notCRX
                ? "notCrx"
                : "crxPreflightFailed"
            return ChromeMV3CRX3ParserResult(
                stage: .failed(stageCode, message: message, path: path),
                crxPath: path,
                fileByteCount: 0,
                version: nil,
                headerLength: nil,
                payloadOffset: nil,
                payloadByteCount: nil,
                signedHeaderDataByteCount: nil,
                declaredExtensionID: nil,
                rsaProofs: [],
                ecdsaProofs: [],
                verifiedContentsByteCount: nil,
                payloadZIPPreflight: nil,
                blockers: [message],
                remediation: [
                    "Use a local CRX3 file for parser diagnostics. Import remains blocked until verifier/trust policy exists.",
                ]
            )
        }
    }

    private static func preflightCRX3Data(
        _ data: Data,
        path: String,
        fileByteCount: UInt64
    ) throws -> ChromeMV3CRX3ParserResult {
        guard data.count >= 4 else {
            throw ChromeMV3CRX3ParserError.headerInvalid("File is too small.")
        }
        let magic = data.subdata(in: 0..<4)
        guard magic == Data([0x43, 0x72, 0x32, 0x34]) else {
            throw ChromeMV3CRX3ParserError.notCRX
        }
        guard data.count >= 12 else {
            throw ChromeMV3CRX3ParserError.headerInvalid("File is too small.")
        }
        let version = try data.uint32LE(at: 4)
        guard version == 3 else {
            throw ChromeMV3CRX3ParserError.unsupportedVersion(version)
        }
        let headerLength = try data.uint32LE(at: 8)
        guard headerLength <= ChromeMV3PackageIntakeLimits.maxCRXHeaderBytes else {
            throw ChromeMV3CRX3ParserError.oversizedHeader(headerLength)
        }
        let headerStart = 12
        let headerEnd = headerStart + Int(headerLength)
        guard headerEnd <= data.count else {
            throw ChromeMV3CRX3ParserError.headerInvalid(
                "Header length exceeds file bounds."
            )
        }
        let payloadOffset = UInt64(headerEnd)
        let payloadByteCount = UInt64(data.count - headerEnd)
        guard payloadByteCount > 0 else {
            throw ChromeMV3CRX3ParserError.missingPayload
        }
        let headerData = data.subdata(in: headerStart..<headerEnd)
        let metadata = try parseHeader(headerData)
        let payloadData = data.subdata(in: headerEnd..<data.count)
        let payloadPreflight: ChromeMV3ZIPArchivePreflightResult?
        do {
            payloadPreflight = try ChromeMV3ZIPArchiveReader
                .preflightArchiveData(
                    payloadData,
                    archivePath: "\(path)#zip-payload",
                    archiveByteCount: payloadByteCount
                )
        } catch {
            throw ChromeMV3CRX3ParserError.unsafePayload(
                packageErrorMessage(error)
            )
        }
        return ChromeMV3CRX3ParserResult(
            stage: .passed(
                "crx3Parsed",
                message: "CRX3 header and ZIP payload preflight parsed.",
                path: path,
                details: [
                    "payloadOffset=\(payloadOffset)",
                    "payloadByteCount=\(payloadByteCount)",
                ]
            ),
            crxPath: path,
            fileByteCount: fileByteCount,
            version: version,
            headerLength: headerLength,
            payloadOffset: payloadOffset,
            payloadByteCount: payloadByteCount,
            signedHeaderDataByteCount: metadata.signedHeaderData?.count,
            declaredExtensionID: metadata.declaredExtensionID,
            rsaProofs: metadata.rsaProofs,
            ecdsaProofs: metadata.ecdsaProofs,
            verifiedContentsByteCount: metadata.verifiedContentsByteCount,
            payloadZIPPreflight: payloadPreflight,
            blockers: [],
            remediation: [
                "Parser success is preflight-only; require signature verification and trust policy before import.",
            ]
        )
    }

    private static func parseHeader(
        _ data: Data
    ) throws -> ChromeMV3CRX3HeaderMetadata {
        var cursor = 0
        var rsaProofs: [ChromeMV3CRXProofMetadata] = []
        var ecdsaProofs: [ChromeMV3CRXProofMetadata] = []
        var verifiedContentsByteCount: Int?
        var signedHeaderData: Data?
        var declaredExtensionID: String?
        while cursor < data.count {
            let key = try readVarint(data, cursor: &cursor)
            let field = Int(key >> 3)
            let wireType = Int(key & 0x7)
            switch (field, wireType) {
            case (2, 2), (3, 2):
                let bytes = try readLengthDelimited(data, cursor: &cursor)
                let proof = try parseProof(bytes, algorithm: field == 2 ? "rsa" : "ecdsa")
                if field == 2 {
                    rsaProofs.append(proof)
                } else {
                    ecdsaProofs.append(proof)
                }
            case (4, 2):
                verifiedContentsByteCount =
                    try readLengthDelimited(data, cursor: &cursor).count
            case (10000, 2):
                let bytes = try readLengthDelimited(data, cursor: &cursor)
                signedHeaderData = bytes
                declaredExtensionID = try parseSignedDataExtensionID(bytes)
            default:
                try skipUnknownField(wireType: wireType, data: data, cursor: &cursor)
            }
        }
        return ChromeMV3CRX3HeaderMetadata(
            signedHeaderData: signedHeaderData,
            declaredExtensionID: declaredExtensionID,
            rsaProofs: rsaProofs.sorted { $0.publicKeyByteCount < $1.publicKeyByteCount },
            ecdsaProofs: ecdsaProofs.sorted { $0.publicKeyByteCount < $1.publicKeyByteCount },
            verifiedContentsByteCount: verifiedContentsByteCount
        )
    }

    private static func parseProof(
        _ data: Data,
        algorithm: String
    ) throws -> ChromeMV3CRXProofMetadata {
        var cursor = 0
        var publicKey = Data()
        var signature = Data()
        while cursor < data.count {
            let key = try readVarint(data, cursor: &cursor)
            let field = Int(key >> 3)
            let wireType = Int(key & 0x7)
            switch (field, wireType) {
            case (1, 2):
                publicKey = try readLengthDelimited(data, cursor: &cursor)
            case (2, 2):
                signature = try readLengthDelimited(data, cursor: &cursor)
            default:
                try skipUnknownField(wireType: wireType, data: data, cursor: &cursor)
            }
        }
        return ChromeMV3CRXProofMetadata(
            algorithm: algorithm,
            publicKeyByteCount: publicKey.count,
            signatureByteCount: signature.count,
            derivedExtensionID: publicKey.isEmpty
                ? nil
                : extensionIDFromHashInput(publicKey)
        )
    }

    private static func parseSignedDataExtensionID(
        _ data: Data
    ) throws -> String? {
        var cursor = 0
        while cursor < data.count {
            let key = try readVarint(data, cursor: &cursor)
            let field = Int(key >> 3)
            let wireType = Int(key & 0x7)
            if field == 1, wireType == 2 {
                let crxID = try readLengthDelimited(data, cursor: &cursor)
                guard crxID.count == 16 else { return nil }
                return extensionIDFrom16ByteHash(crxID)
            }
            try skipUnknownField(wireType: wireType, data: data, cursor: &cursor)
        }
        return nil
    }

    private static func readVarint(
        _ data: Data,
        cursor: inout Int
    ) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while cursor < data.count, shift < 64 {
            let byte = data[cursor]
            cursor += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw ChromeMV3CRX3ParserError.malformedHeader
    }

    private static func readLengthDelimited(
        _ data: Data,
        cursor: inout Int
    ) throws -> Data {
        let length = Int(try readVarint(data, cursor: &cursor))
        guard length >= 0, cursor + length <= data.count else {
            throw ChromeMV3CRX3ParserError.malformedHeader
        }
        let result = data.subdata(in: cursor..<(cursor + length))
        cursor += length
        return result
    }

    private static func skipUnknownField(
        wireType: Int,
        data: Data,
        cursor: inout Int
    ) throws {
        switch wireType {
        case 0:
            _ = try readVarint(data, cursor: &cursor)
        case 1:
            cursor += 8
        case 2:
            _ = try readLengthDelimited(data, cursor: &cursor)
        case 5:
            cursor += 4
        default:
            throw ChromeMV3CRX3ParserError.malformedHeader
        }
        guard cursor <= data.count else {
            throw ChromeMV3CRX3ParserError.malformedHeader
        }
    }

    private static func packageErrorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

private enum ChromeMV3CRX3ParserError: LocalizedError, Equatable {
    case fileNotReadable
    case notCRX
    case unsupportedVersion(UInt32)
    case oversizedCRX
    case oversizedHeader(UInt32)
    case headerInvalid(String)
    case malformedHeader
    case missingPayload
    case unsafePayload(String)

    var errorDescription: String? {
        switch self {
        case .fileNotReadable:
            return "CRX file is not readable."
        case .notCRX:
            return "File is not a CRX archive."
        case .unsupportedVersion(let version):
            return "Unsupported CRX version \(version); only CRX3 is accepted for preflight."
        case .oversizedCRX:
            return "CRX file exceeds the package intake size limit."
        case .oversizedHeader(let size):
            return "CRX3 header length \(size) exceeds the safe parser limit."
        case .headerInvalid(let reason):
            return "CRX3 header is invalid: \(reason)"
        case .malformedHeader:
            return "CRX3 protobuf header is malformed."
        case .missingPayload:
            return "CRX3 file does not contain a ZIP payload."
        case .unsafePayload(let reason):
            return "CRX3 ZIP payload failed preflight: \(reason)"
        }
    }
}

private enum ChromeMV3CRXTrustEvaluator {
    static func evaluate(
        _ parser: ChromeMV3CRX3ParserResult
    ) -> ChromeMV3CRXTrustResult {
        guard parser.parsedCRX3 else {
            return ChromeMV3CRXTrustResult(
                stage: .blocked(
                    "crxTrustBlockedNotParsed",
                    message: "CRX trust evaluation is blocked because CRX3 parsing failed.",
                    path: parser.crxPath,
                    details: parser.blockers
                ),
                states: [.notCrx, .importBlocked],
                extensionID: nil,
                importAllowed: false,
                blockers: parser.blockers,
                remediation: parser.remediation
            )
        }
        var states: [ChromeMV3CRXTrustState] = [
            .parsedButUnverified,
            .signatureVerificationUnavailable,
            .trustPolicyMissing,
            .importBlocked,
        ]
        if parser.declaredExtensionID != nil {
            states.append(.extensionIdDerived)
        }
        let blockers = [
            "CRX3 parser success does not verify signatures.",
            "CRX3 signature verification is unavailable in this build.",
            "Package trust policy for CRX import is missing.",
        ]
        return ChromeMV3CRXTrustResult(
            stage: .blocked(
                "crxImportBlockedTrustMissing",
                message: "CRX import is blocked until verifier and trust policy are implemented.",
                path: parser.crxPath,
                details: blockers
            ),
            states: states.sorted(),
            extensionID: parser.declaredExtensionID,
            importAllowed: false,
            blockers: blockers,
            remediation: [
                "Implement Chromium-equivalent CRX3 signature verification over signed_header_data and archive bytes.",
                "Define required key hashes, publisher proof expectations, and user trust policy before extraction.",
            ]
        )
    }
}

enum ChromeMV3ChromeWebStoreParser {
    static func diagnose(
        _ input: String
    ) -> ChromeMV3ChromeWebStoreDiagnostic {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = parse(trimmed)
        let valid = parsed.extensionID != nil
        let blockers: [String] = valid
            ? [
                "Chrome Web Store install is not implemented.",
                "Remote CRX download is unavailable without an official package acquisition policy.",
                "Add to Chrome interception is unsupported.",
                "Chrome Web Store page injection and Chrome spoofing are forbidden.",
            ]
            : [
                "Input is not a valid Chrome Web Store URL or extension ID.",
                "Chrome Web Store install is not implemented.",
            ]
        let futureRequirements = [
            "official package acquisition policy",
            "CRX3 signature verification",
            "package trust policy",
            "update manifest policy",
            "user consent and trust UI",
            "legal/product review if needed",
        ]
        return ChromeMV3ChromeWebStoreDiagnostic(
            stage: valid
                ? .deferred(
                    "chromeWebStoreImportDeferred",
                    message: "Chrome Web Store input parsed; import remains deferred.",
                    details: [parsed.extensionID ?? ""].filter { !$0.isEmpty }
                )
                : .failed(
                    "invalidChromeWebStoreInput",
                    message: "Chrome Web Store input did not contain a valid extension ID."
                ),
            input: input,
            parsedExtensionID: parsed.extensionID,
            inputKind: parsed.inputKind,
            webStoreInstallUnsupported: true,
            remoteCRXDownloadUnavailable: true,
            addToChromeInterceptionUnsupported: true,
            pageInjectionForbidden: true,
            chromeSpoofingForbidden: true,
            futureRequirements: futureRequirements,
            blockers: blockers,
            remediation: [
                "Keep Web Store import diagnostics-only until the future requirements are implemented.",
                "Use local Load Unpacked or safe local ZIP import for developer-preview intake.",
            ]
        )
    }

    private static func parse(
        _ input: String
    ) -> (extensionID: String?, inputKind: ChromeMV3PackageIntakeSourceKind) {
        let lower = input.lowercased()
        if isValidExtensionID(lower) {
            return (lower, .chromeWebStoreExtensionID)
        }
        guard let components = URLComponents(string: input),
              let host = components.host?.lowercased()
        else {
            return (nil, .chromeWebStoreExtensionID)
        }
        let webStoreHosts: Set<String> = [
            "chromewebstore" + ".google.com",
            "chrome" + ".google.com",
        ]
        guard webStoreHosts.contains(host) else {
            return (nil, .chromeWebStoreURL)
        }
        let pathComponents = components.path
            .split(separator: "/")
            .map { String($0).lowercased() }
        if let id = pathComponents.last(where: isValidExtensionID) {
            return (id, .chromeWebStoreURL)
        }
        return (nil, .chromeWebStoreURL)
    }

    static func isValidExtensionID(_ value: String) -> Bool {
        guard value.count == 32 else { return false }
        return value.allSatisfy { character in
            guard let scalar = character.unicodeScalars.first,
                  character.unicodeScalars.count == 1
            else { return false }
            return scalar.value >= UnicodeScalar("a").value
                && scalar.value <= UnicodeScalar("p").value
        }
    }
}

private func stableID(prefix: String, parts: [String]) -> String {
    let joined = parts.joined(separator: "\u{1f}")
    let data = joined.data(using: .utf8) ?? Data()
    let digest = SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
    return "\(prefix)-\(digest.prefix(32))"
}

private func extensionIDFromHashInput(_ input: Data) -> String {
    let hash = SHA256.hash(data: input)
    return extensionIDFrom16ByteHash(Data(hash.prefix(16)))
}

private func extensionIDFrom16ByteHash(_ input: Data) -> String {
    let alphabet = Array("abcdefghijklmnop")
    return input.prefix(16).flatMap { byte -> [Character] in
        [
            alphabet[Int((byte >> 4) & 0x0f)],
            alphabet[Int(byte & 0x0f)],
        ]
    }
    .map(String.init)
    .joined()
}

private func uniqueSorted(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private extension String {
    var trimmingTrailingSlash: String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}

private extension Data {
    func uint16LE(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Unexpected end of binary data."
            )
        }
        return UInt16(self[offset])
            | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw ChromeMV3ZIPArchiveError.invalidArchive(
                "Unexpected end of binary data."
            )
        }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
