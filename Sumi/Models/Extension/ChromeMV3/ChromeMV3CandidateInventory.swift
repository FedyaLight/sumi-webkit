//
//  ChromeMV3CandidateInventory.swift
//  Sumi
//
//  Read-only inventory for generated Chrome MV3 artifacts. It reads only the
//  explicit root supplied by tests or future profile code and never loads or
//  executes extension resources.
//

import CryptoKit
import Foundation

enum ChromeMV3InventoryArtifactKind: String, Codable, CaseIterable, Sendable {
    case stagedOriginalRecord
    case manifestSnapshot
    case installReport
    case generatedBundlePlan
    case generatedBundleMetadata
    case runtimeResourcePlan
    case manifestRewritePreview
    case manifestRewriteDryRunReport
    case generatedRewriteApplicationReport
    case runtimeLoadabilityReport
    case rewrittenManifest
}

struct ChromeMV3InventoryArtifactSummary: Codable, Equatable, Sendable {
    var kind: ChromeMV3InventoryArtifactKind
    var id: String?
    var path: String
    var sha256: String?
    var byteCount: Int?
    var exists: Bool
    var warning: String?
}

struct ChromeMV3InventoryCandidateArtifacts: Codable, Equatable, Sendable {
    var generatedBundleMetadataPath: String?
    var runtimeResourcePlanPath: String?
    var manifestRewritePreviewPath: String?
    var manifestRewriteDryRunReportPath: String?
    var generatedRewriteApplicationReportPath: String?
    var runtimeLoadabilityReportPath: String?
    var rewrittenManifestPath: String?
}

struct ChromeMV3InventoryPasswordManagerReadinessSummary: Codable, Equatable, Sendable {
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

struct ChromeMV3CandidateInventoryEntry: Codable, Equatable, Sendable {
    var id: String
    var generatedRootPath: String?
    var rewrittenRootPath: String
    var manifestHash: String?
    var reportHash: String?
    var runtimeLoadable: Bool?
    var blockers: [String]
    var deferredAPIs: [ChromeMV3API]
    var unsupportedAPIs: [ChromeMV3API]
    var passwordManagerReadinessSummary:
        ChromeMV3InventoryPasswordManagerReadinessSummary?
    var missingArtifactWarnings: [String]
    var artifacts: ChromeMV3InventoryCandidateArtifacts
    var runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?
    var manifestVersion: Int?

    var profileHostCandidate: ChromeMV3RewrittenVariantCandidate {
        ChromeMV3RewrittenVariantCandidate(
            id: id,
            generatedVariantRootPath: generatedRootPath,
            rewrittenVariantRootPath: rewrittenRootPath,
            runtimeLoadabilityReportPath: artifacts.runtimeLoadabilityReportPath,
            rewrittenManifestSHA256: manifestHash,
            runtimeLoadabilityReportSHA256: reportHash,
            manifestVersion: manifestVersion,
            rewrittenVariantExists: true
        )
    }
}

struct ChromeMV3CandidateInventory: Codable, Equatable, Sendable {
    var rootPath: String
    var stagedOriginalRecords: [ChromeMV3InventoryArtifactSummary]
    var generatedBundleRecords: [ChromeMV3InventoryArtifactSummary]
    var manifestRewritePreviewReports: [ChromeMV3InventoryArtifactSummary]
    var manifestRewriteDryRunReports: [ChromeMV3InventoryArtifactSummary]
    var generatedRewriteApplicationReports: [ChromeMV3InventoryArtifactSummary]
    var runtimeLoadabilityReports: [ChromeMV3InventoryArtifactSummary]
    var candidates: [ChromeMV3CandidateInventoryEntry]
    var warnings: [String]
}

struct ChromeMV3CandidateInventoryReader {
    var fileManager: FileManager = .default

    func readInventory(rootURL: URL) -> ChromeMV3CandidateInventory {
        let root = rootURL.standardizedFileURL
        var warnings: [String] = []

        guard directoryExists(root) else {
            return ChromeMV3CandidateInventory(
                rootPath: root.path,
                stagedOriginalRecords: [],
                generatedBundleRecords: [],
                manifestRewritePreviewReports: [],
                manifestRewriteDryRunReports: [],
                generatedRewriteApplicationReports: [],
                runtimeLoadabilityReports: [],
                candidates: [],
                warnings: [
                    "Inventory root does not exist or is not a directory: \(root.path)",
                ]
            )
        }

        let stagedOriginalRecords = discoverOriginalRecords(rootURL: root)
        let generated = discoverGeneratedBundleRecords(rootURL: root)
        let candidates = discoverCandidates(
            rootURL: root,
            generatedRecords: generated.records,
            warnings: &warnings
        )

        return ChromeMV3CandidateInventory(
            rootPath: root.path,
            stagedOriginalRecords: stagedOriginalRecords,
            generatedBundleRecords: generated.records.map(\.artifact),
            manifestRewritePreviewReports: generated.previewReports,
            manifestRewriteDryRunReports: generated.dryRunReports,
            generatedRewriteApplicationReports: candidates
                .compactMap(\.applicationReportArtifact),
            runtimeLoadabilityReports: candidates
                .compactMap(\.runtimeReportArtifact),
            candidates: candidates
                .map(\.entry)
                .sorted { $0.id < $1.id },
            warnings: uniqueSorted(warnings)
        )
    }

    private func discoverOriginalRecords(
        rootURL: URL
    ) -> [ChromeMV3InventoryArtifactSummary] {
        let originalsURL = rootURL.appendingPathComponent(
            "originals",
            isDirectory: true
        )
        guard directoryExists(originalsURL) else { return [] }

        return immediateChildDirectories(of: originalsURL).map { recordRoot in
            let recordURL = recordRoot.appendingPathComponent("record.json")
            let record = decodeOptional(
                ChromeMV3OriginalBundleRecord.self,
                at: recordURL
            )
            return artifactSummary(
                kind: .stagedOriginalRecord,
                url: recordURL,
                id: record?.id
            )
        }
        .sorted { $0.path < $1.path }
    }

    private func discoverGeneratedBundleRecords(
        rootURL: URL
    ) -> GeneratedBundleDiscovery {
        let generatedRootURL = rootURL.appendingPathComponent(
            ChromeMV3GeneratedBundleWriter.generatedDirectoryName,
            isDirectory: true
        )
        guard directoryExists(generatedRootURL) else {
            return GeneratedBundleDiscovery(
                records: [],
                previewReports: [],
                dryRunReports: []
            )
        }

        var records: [GeneratedRecordSummary] = []
        var previewReports: [ChromeMV3InventoryArtifactSummary] = []
        var dryRunReports: [ChromeMV3InventoryArtifactSummary] = []

        for recordRoot in immediateChildDirectories(of: generatedRootURL) {
            let generatedBundleRootURL = recordRoot
                .appendingPathComponent(
                    ChromeMV3GeneratedBundleWriter.generatedBundleDirectoryName,
                    isDirectory: true
                )
            let metadataURL = generatedBundleRootURL
                .appendingPathComponent(
                    ChromeMV3GeneratedBundleWriter.metadataFileName
                )
            let record = decodeOptional(
                ChromeMV3GeneratedBundleRecord.self,
                at: metadataURL
            )
            let artifact = artifactSummary(
                kind: .generatedBundleMetadata,
                url: metadataURL,
                id: record?.id
            )
            records.append(
                GeneratedRecordSummary(
                    recordRootPath: recordRoot.path,
                    generatedRootPath: generatedBundleRootURL.path,
                    record: record,
                    artifact: artifact
                )
            )

            let previewURL = record.map {
                URL(fileURLWithPath: $0.manifestRewritePreviewPath)
            }
                ?? generatedBundleRootURL.appendingPathComponent(
                    ChromeMV3GeneratedBundleWriter.manifestRewritePreviewFileName
                )
            previewReports.append(
                artifactSummary(
                    kind: .manifestRewritePreview,
                    url: previewURL,
                    id: record?.manifestRewritePreviewSHA256
                )
            )

            let dryRunURL = record?.manifestRewriteDryRunReportPath.map {
                URL(fileURLWithPath: $0)
            }
                ?? generatedBundleRootURL
                    .appendingPathComponent(
                        ChromeMV3ManifestRewriteDryRunRenderer
                            .dryRunDirectoryName,
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        ChromeMV3ManifestRewriteDryRunRenderer
                            .verificationReportFileName
                    )
            dryRunReports.append(
                artifactSummary(
                    kind: .manifestRewriteDryRunReport,
                    url: dryRunURL,
                    id: record?.manifestRewriteDryRunReportSHA256
                )
            )
        }

        return GeneratedBundleDiscovery(
            records: records.sorted { $0.recordRootPath < $1.recordRootPath },
            previewReports: previewReports.sorted { $0.path < $1.path },
            dryRunReports: dryRunReports.sorted { $0.path < $1.path }
        )
    }

    private func discoverCandidates(
        rootURL: URL,
        generatedRecords: [GeneratedRecordSummary],
        warnings: inout [String]
    ) -> [CandidateDiscovery] {
        let generatedRootURL = rootURL.appendingPathComponent(
            ChromeMV3GeneratedBundleWriter.generatedDirectoryName,
            isDirectory: true
        )
        guard directoryExists(generatedRootURL) else { return [] }

        let generatedByRootPath = Dictionary(
            uniqueKeysWithValues: generatedRecords.map {
                ($0.recordRootPath, $0)
            }
        )

        var candidates: [CandidateDiscovery] = []
        for recordRoot in immediateChildDirectories(of: generatedRootURL) {
            let rewrittenRootURL = recordRoot.appendingPathComponent(
                ChromeMV3GeneratedRewriteVariantWriter
                    .rewrittenBundleDirectoryName,
                isDirectory: true
            )
            guard directoryExists(rewrittenRootURL) else { continue }

            let generated = generatedByRootPath[recordRoot.path]
            candidates.append(
                candidate(
                    rewrittenRootURL: rewrittenRootURL,
                    generated: generated,
                    warnings: &warnings
                )
            )
        }
        return candidates
    }

    private func candidate(
        rewrittenRootURL: URL,
        generated: GeneratedRecordSummary?,
        warnings: inout [String]
    ) -> CandidateDiscovery {
        var missingArtifactWarnings: [String] = []
        let applicationReportURL = rewrittenRootURL.appendingPathComponent(
            ChromeMV3GeneratedRewriteVariantWriter.applicationReportFileName
        )
        let runtimeReportURL = rewrittenRootURL.appendingPathComponent(
            ChromeMV3RuntimeLoadabilityVerifier.reportFileName
        )
        let rewrittenManifestURL = rewrittenRootURL.appendingPathComponent(
            "manifest.json"
        )
        let applicationReport = decodeOptional(
            ChromeMV3GeneratedRewriteApplicationReport.self,
            at: applicationReportURL
        )
        let runtimeReport = decodeOptional(
            ChromeMV3RuntimeLoadabilityReport.self,
            at: runtimeReportURL
        )

        let applicationArtifact = artifactSummary(
            kind: .generatedRewriteApplicationReport,
            url: applicationReportURL,
            id: applicationReport?.id
        )
        let runtimeArtifact = artifactSummary(
            kind: .runtimeLoadabilityReport,
            url: runtimeReportURL,
            id: runtimeReport?.id
        )
        let rewrittenManifestArtifact = artifactSummary(
            kind: .rewrittenManifest,
            url: rewrittenManifestURL,
            id: nil
        )

        appendMissingWarning(
            artifact: applicationArtifact,
            label: "generated rewrite application report",
            to: &missingArtifactWarnings
        )
        appendMissingWarning(
            artifact: runtimeArtifact,
            label: "runtime-loadability report",
            to: &missingArtifactWarnings
        )
        appendMissingWarning(
            artifact: rewrittenManifestArtifact,
            label: "rewritten manifest",
            to: &missingArtifactWarnings
        )
        if runtimeReport?.missing.isEmpty == false {
            missingArtifactWarnings.append(
                contentsOf: runtimeReport?.missing.map {
                    "Runtime-loadability report lists missing artifact: \($0)"
                } ?? []
            )
        }

        let generatedRootPath = applicationReport?.originalGeneratedBundleRootPath
            ?? generated?.generatedRootPath
        let candidateID = applicationReport?.id
            ?? runtimeReport?.id
            ?? generated?.record?.id
            ?? rewrittenRootURL.lastPathComponent

        let manifestHash = runtimeReport?.rewrittenManifestHash?.sha256
            ?? rewrittenManifestArtifact.sha256
        let runtimeLoadable = runtimeReport?.runtimeLoadable
            ?? applicationReport?.runtimeLoadable
        let manifestVersion = manifestVersion(at: rewrittenManifestURL)
            ?? generated?.record?.installReportSummary.manifestSummary?
                .manifestVersion

        let inventorySaysLoadable = runtimeLoadable == .some(
            true
        )
        if inventorySaysLoadable {
            warnings.append(
                "Inventory candidate \(candidateID) is marked runtime-loadable; this diagnostics layer must not load it."
            )
        }

        let artifacts = ChromeMV3InventoryCandidateArtifacts(
            generatedBundleMetadataPath: generated?.artifact.exists == true
                ? generated?.artifact.path
                : nil,
            runtimeResourcePlanPath: generated?.record?.runtimeResourcePlanPath
                ?? generated.map {
                    URL(fileURLWithPath: $0.generatedRootPath)
                        .appendingPathComponent(
                            ChromeMV3GeneratedBundleWriter
                                .runtimeResourcePlanFileName
                        )
                        .path
                },
            manifestRewritePreviewPath: generated?.record?
                .manifestRewritePreviewPath,
            manifestRewriteDryRunReportPath: generated?.record?
                .manifestRewriteDryRunReportPath,
            generatedRewriteApplicationReportPath: applicationArtifact.exists
                ? applicationArtifact.path
                : nil,
            runtimeLoadabilityReportPath: runtimeArtifact.exists
                ? runtimeArtifact.path
                : nil,
            rewrittenManifestPath: rewrittenManifestArtifact.exists
                ? rewrittenManifestArtifact.path
                : nil
        )

        let entry = ChromeMV3CandidateInventoryEntry(
            id: candidateID,
            generatedRootPath: generatedRootPath,
            rewrittenRootPath: rewrittenRootURL.path,
            manifestHash: manifestHash,
            reportHash: runtimeArtifact.sha256,
            runtimeLoadable: runtimeLoadable,
            blockers: uniqueSorted(
                (runtimeReport?.blockers ?? [])
                    + (applicationReport?.gateDecision.blockingReasons ?? [])
                    + (applicationReport?.gateDecision.deferredRuntimeReasons
                        ?? [])
                    + (applicationReport?.runtimeLoadabilityReport.blockers
                        ?? [])
            ),
            deferredAPIs: uniqueSortedAPIs(
                (runtimeReport?.deferredAPIs ?? [])
                    + (applicationReport?.deferredAPIs ?? [])
                    + (generated?.record?.deferredAPIs ?? [])
            ),
            unsupportedAPIs: uniqueSortedAPIs(
                (runtimeReport?.unsupportedAPIs ?? [])
                    + (applicationReport?.unsupportedAPIs ?? [])
                    + (generated?.record?.unsupportedAPIs ?? [])
            ),
            passwordManagerReadinessSummary: runtimeReport
                .map(passwordManagerReadinessSummary),
            missingArtifactWarnings: uniqueSorted(missingArtifactWarnings),
            artifacts: artifacts,
            runtimeLoadabilityReport: runtimeReport,
            manifestVersion: manifestVersion
        )

        return CandidateDiscovery(
            entry: entry,
            applicationReportArtifact: applicationArtifact,
            runtimeReportArtifact: runtimeArtifact
        )
    }

    private func passwordManagerReadinessSummary(
        _ report: ChromeMV3RuntimeLoadabilityReport
    ) -> ChromeMV3InventoryPasswordManagerReadinessSummary {
        let readiness = report.passwordManagerReadiness
        return ChromeMV3InventoryPasswordManagerReadinessSummary(
            contentScriptsPresent: readiness.contentScriptsPresent,
            allFramesDetected: readiness.allFramesDetected,
            matchAboutBlankDetected: readiness.matchAboutBlankDetected,
            hostPermissionsPresent: readiness.hostPermissionsPresent,
            actionPopupPresent: readiness.actionPopupPresent,
            storagePermissionPresent: readiness.storagePermissionPresent,
            nativeMessagingDetected: readiness.nativeMessagingDetected,
            nativeMessagingBlocked: readiness.nativeMessagingBlocked,
            runtimeMessagingImplemented: readiness.runtimeMessagingImplemented,
            controlledInputPageWorldBehaviorVerified: readiness
                .controlledInputPageWorldBehaviorVerified,
            serviceWorkerLifecycleVerified: readiness
                .serviceWorkerLifecycleVerified,
            blockers: readiness.blockers.sorted(),
            deferredChecks: readiness.deferredChecks.sorted()
        )
    }

    private func artifactSummary(
        kind: ChromeMV3InventoryArtifactKind,
        url: URL,
        id: String?
    ) -> ChromeMV3InventoryArtifactSummary {
        let standardizedURL = url.standardizedFileURL
        guard let data = regularFileData(at: standardizedURL) else {
            return ChromeMV3InventoryArtifactSummary(
                kind: kind,
                id: id,
                path: standardizedURL.path,
                sha256: nil,
                byteCount: nil,
                exists: false,
                warning: "Missing artifact: \(standardizedURL.path)"
            )
        }
        return ChromeMV3InventoryArtifactSummary(
            kind: kind,
            id: id,
            path: standardizedURL.path,
            sha256: sha256Hex(data),
            byteCount: data.count,
            exists: true,
            warning: nil
        )
    }

    private func appendMissingWarning(
        artifact: ChromeMV3InventoryArtifactSummary,
        label: String,
        to warnings: inout [String]
    ) {
        guard artifact.exists == false else { return }
        warnings.append("Missing \(label): \(artifact.path)")
    }

    private func manifestVersion(at url: URL) -> Int? {
        guard let data = regularFileData(at: url),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            return nil
        }
        return object["manifest_version"] as? Int
    }

    private func regularFileData(at url: URL) -> Data? {
        guard
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func decodeOptional<T: Decodable>(
        _ type: T.Type,
        at url: URL
    ) -> T? {
        guard let data = regularFileData(at: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func immediateChildDirectories(of url: URL) -> [URL] {
        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        return urls.filter { child in
            guard
                let values = try? child.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ])
            else {
                return false
            }
            return values.isDirectory == true && values.isSymbolicLink != true
        }
        .map(\.standardizedFileURL)
        .sorted { $0.path < $1.path }
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }

    private func uniqueSortedAPIs(_ values: [ChromeMV3API]) -> [ChromeMV3API] {
        Array(Set(values)).sorted()
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct GeneratedBundleDiscovery {
    var records: [GeneratedRecordSummary]
    var previewReports: [ChromeMV3InventoryArtifactSummary]
    var dryRunReports: [ChromeMV3InventoryArtifactSummary]
}

private struct GeneratedRecordSummary {
    var recordRootPath: String
    var generatedRootPath: String
    var record: ChromeMV3GeneratedBundleRecord?
    var artifact: ChromeMV3InventoryArtifactSummary
}

private struct CandidateDiscovery {
    var entry: ChromeMV3CandidateInventoryEntry
    var applicationReportArtifact: ChromeMV3InventoryArtifactSummary?
    var runtimeReportArtifact: ChromeMV3InventoryArtifactSummary?
}
