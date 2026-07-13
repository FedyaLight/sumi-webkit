//
//  ExtensionSettingsScanSession.swift
//  Sumi
//

import Foundation
import Observation

struct ExtensionSettingsScanAttempt: Equatable, Hashable, Sendable {
    let generation: UInt64
}

struct ExtensionSettingsScanDiscovery: Equatable, Sendable {
    let candidates: [DiscoveredSafariExtensionCandidate]
    let issues: [SafariExtensionScannerIssue]
}

struct ExtensionSettingsImportResult: Equatable, Sendable {
    let importedExtensionCount: Int
    let failedMessages: [String]
    let skippedUnreadableCount: Int
}

struct ExtensionSettingsScanSummary: Equatable, Sendable {
    let discoveredCandidateCount: Int
    let importedExtensionCount: Int
    let scannerIssues: [SafariExtensionScannerIssue]
    let failedMessages: [String]
    let skippedUnreadableCount: Int

    var hasIssues: Bool {
        scannerIssues.isEmpty == false
            || failedMessages.isEmpty == false
            || skippedUnreadableCount > 0
    }
}

struct ExtensionSettingsScanSnapshot: Equatable, Sendable {
    let contentBlockerCandidates: [DiscoveredSafariExtensionCandidate]
    let unsupportedCandidates: [DiscoveredSafariExtensionCandidate]
    var contentBlockerRecords: [InstalledSafariContentBlockerRecord]

    static let empty = ExtensionSettingsScanSnapshot(
        contentBlockerCandidates: [],
        unsupportedCandidates: [],
        contentBlockerRecords: []
    )
}

enum ExtensionSettingsScanState: Equatable, Sendable {
    case inert
    case scanning(ExtensionSettingsScanAttempt)
    case completed(ExtensionSettingsScanAttempt, ExtensionSettingsScanSummary)
    case failed(ExtensionSettingsScanAttempt, message: String)
    case cancelled(ExtensionSettingsScanAttempt)

    var isScanning: Bool {
        if case .scanning = self {
            return true
        }
        return false
    }
}

enum ExtensionSettingsCapabilityError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Extension settings are no longer available."
        }
    }
}

enum ExtensionSettingsSafariScanner {
    static func scanInstalledExtensions() async throws -> ExtensionSettingsScanDiscovery {
        let worker = Task.detached(priority: .userInitiated) {
            var issues: [SafariExtensionScannerIssue] = []
            let candidates = SafariExtensionScanner()
                .scanInstalledExtensions(issues: &issues)
            return ExtensionSettingsScanDiscovery(
                candidates: candidates,
                issues: issues
            )
        }

        return try await withTaskCancellationHandler {
            let result = await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }
}

@MainActor
@Observable
final class ExtensionSettingsScanSession {
    typealias Scan = @Sendable () async throws -> ExtensionSettingsScanDiscovery
    typealias Synchronize = @MainActor @Sendable (
        [DiscoveredSafariExtensionCandidate]
    ) async throws -> ExtensionSettingsImportResult
    typealias LoadContentBlockers = @MainActor @Sendable () throws -> [
        InstalledSafariContentBlockerRecord
    ]

    private(set) var state: ExtensionSettingsScanState = .inert
    private(set) var snapshot: ExtensionSettingsScanSnapshot = .empty

    private let scan: Scan
    private let synchronize: Synchronize
    private let loadContentBlockers: LoadContentBlockers

    @ObservationIgnored private var nextGeneration: UInt64 = 0
    @ObservationIgnored private var activeAttempt: ExtensionSettingsScanAttempt?
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init(
        scan: @escaping Scan,
        synchronize: @escaping Synchronize,
        loadContentBlockers: @escaping LoadContentBlockers
    ) {
        self.scan = scan
        self.synchronize = synchronize
        self.loadContentBlockers = loadContentBlockers
    }

    deinit {
        scanTask?.cancel()
    }

    func beginIfNeeded() {
        switch state {
        case .inert, .cancelled:
            refresh()
        case .scanning, .completed, .failed:
            return
        }
    }

    func refresh() {
        scanTask?.cancel()
        nextGeneration &+= 1
        let attempt = ExtensionSettingsScanAttempt(generation: nextGeneration)
        activeAttempt = attempt
        state = .scanning(attempt)

        let scan = scan
        let synchronize = synchronize
        let loadContentBlockers = loadContentBlockers
        scanTask = Task { @MainActor [weak self] in
            do {
                let discovery = try await scan()
                try Task.checkCancellation()

                let importResult = try await synchronize(discovery.candidates)
                try Task.checkCancellation()

                let contentBlockerRecords = try loadContentBlockers()
                try Task.checkCancellation()

                self?.complete(
                    attempt: attempt,
                    discovery: discovery,
                    importResult: importResult,
                    contentBlockerRecords: contentBlockerRecords
                )
            } catch is CancellationError {
                self?.finishCancellation(for: attempt)
            } catch {
                self?.finishFailure(
                    for: attempt,
                    message: error.localizedDescription
                )
            }
        }
    }

    func cancel() {
        guard let activeAttempt else { return }
        scanTask?.cancel()
        scanTask = nil
        self.activeAttempt = nil
        state = .cancelled(activeAttempt)
    }

    func updateContentBlockerRecord(_ record: InstalledSafariContentBlockerRecord) {
        if let index = snapshot.contentBlockerRecords.firstIndex(where: {
            $0.extensionBundleIdentifier == record.extensionBundleIdentifier
        }) {
            snapshot.contentBlockerRecords[index] = record
        } else {
            snapshot.contentBlockerRecords.append(record)
        }
    }

    private func complete(
        attempt: ExtensionSettingsScanAttempt,
        discovery: ExtensionSettingsScanDiscovery,
        importResult: ExtensionSettingsImportResult,
        contentBlockerRecords: [InstalledSafariContentBlockerRecord]
    ) {
        guard activeAttempt == attempt else { return }

        let contentBlockerCandidates = discovery.candidates.filter {
            $0.bundleKind == .contentBlocker
        }
        let unsupportedCandidates = discovery.candidates.filter {
            $0.bundleKind == .legacySafariAppExtension
        }
        let summary = ExtensionSettingsScanSummary(
            discoveredCandidateCount: discovery.candidates.count,
            importedExtensionCount: importResult.importedExtensionCount,
            scannerIssues: discovery.issues,
            failedMessages: importResult.failedMessages,
            skippedUnreadableCount: importResult.skippedUnreadableCount
        )

        snapshot = ExtensionSettingsScanSnapshot(
            contentBlockerCandidates: contentBlockerCandidates,
            unsupportedCandidates: unsupportedCandidates,
            contentBlockerRecords: contentBlockerRecords
        )
        scanTask = nil
        activeAttempt = nil
        state = .completed(attempt, summary)
    }

    private func finishCancellation(for attempt: ExtensionSettingsScanAttempt) {
        guard activeAttempt == attempt else { return }
        scanTask = nil
        activeAttempt = nil
        state = .cancelled(attempt)
    }

    private func finishFailure(
        for attempt: ExtensionSettingsScanAttempt,
        message: String
    ) {
        guard activeAttempt == attempt else { return }
        scanTask = nil
        activeAttempt = nil
        state = .failed(attempt, message: message)
    }
}
