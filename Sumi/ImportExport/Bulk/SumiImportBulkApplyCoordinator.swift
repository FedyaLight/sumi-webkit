import Foundation
import OSLog

/// What a bulk apply changed, kept so an aborted import can be undone.
struct SumiImportBulkReceipt: Sendable {
    var history: [HistoryImportedVisitWriter.Receipt] = []
    var faviconCount: Int = 0
    var cookiesByProfile: [UUID: SumiCookieInstallationReceipt] = [:]

    var isEmpty: Bool {
        history.isEmpty && faviconCount == 0 && cookiesByProfile.isEmpty
    }
}

/// The Sumi-side write surfaces bulk import needs. Injected so the coordinator
/// can be exercised without a live browser.
@MainActor
protocol SumiImportBulkInstalling {
    func installHistory(
        _ visits: [HistoryImportedVisit],
        profileId: UUID?
    ) async throws -> HistoryImportedVisitWriter.Receipt

    func rollbackHistory(_ receipt: HistoryImportedVisitWriter.Receipt) async throws

    func didMutateHistory() async

    func installFavicons(_ favicons: [SumiImportFaviconPayload], profileId: UUID?) async

    func installCookies(
        _ cookies: [SumiStagedCookie],
        profileId: UUID
    ) async throws -> SumiCookieInstallationReceipt

    func rollbackCookies(
        _ receipt: SumiCookieInstallationReceipt,
        profileId: UUID
    ) async
}

struct SumiImportFaviconPayload: Sendable {
    var pageURL: URL
    var iconURL: URL
    var payload: Data
}

/// Applies staged history, favicons, and cookies after the structural import
/// has committed.
///
/// Work is chunked so progress is observable and cancellation lands promptly,
/// and so a failure part-way through leaves a receipt describing exactly what
/// must be undone rather than an unknown amount of half-applied data.
@MainActor
final class SumiImportBulkApplyCoordinator {
    private static let log = Logger.sumi(category: "ImportBulk")
    static let chunkSize = 500

    private let staging: SumiImportBulkStagingStore
    private let installer: any SumiImportBulkInstalling
    private let onProgress: @MainActor (SumiImportBulkProgress) -> Void

    init(
        staging: SumiImportBulkStagingStore,
        installer: any SumiImportBulkInstalling,
        onProgress: @escaping @MainActor (SumiImportBulkProgress) -> Void = { _ in }
    ) {
        self.staging = staging
        self.installer = installer
        self.onProgress = onProgress
    }

    /// Applies the selected kinds in increasing order of irreversibility.
    /// `profileIDsBySourceKey` maps each source browser profile onto the Sumi
    /// profile the structural import created for it.
    func apply(
        manifest: SumiImportBulkStagingManifest,
        kinds: Set<SumiImportBulkKind>,
        profileIDsBySourceKey: [String: UUID],
        into receipt: inout SumiImportBulkReceipt
    ) async throws {
        let directory = staging.directory(for: manifest.stagingID)

        for kind in SumiImportBulkKind.applyOrder where kinds.contains(kind) {
            var mutatedHistory = false
            for entry in manifest.entries where entry.kind == kind {
                try Task.checkCancellation()
                let fileURL = directory.appendingPathComponent(entry.fileName)
                let profileId = profileIDsBySourceKey[entry.sourceProfileKey]
                var completed = 0

                switch kind {
                case .history:
                    let stream = staging.chunkStream(
                        SumiStagedHistoryVisit.self,
                        from: fileURL,
                        chunkSize: Self.chunkSize
                    )
                    for try await chunk in stream {
                        let visits = chunk.compactMap { staged -> HistoryImportedVisit? in
                            guard let url = URL(string: staged.urlString) else { return nil }
                            return HistoryImportedVisit(
                                url: url,
                                title: staged.title,
                                visitedAt: staged.visitedAt
                            )
                        }
                        receipt.history.append(
                            try await installer.installHistory(visits, profileId: profileId)
                        )
                        mutatedHistory = true
                        completed += chunk.count
                        report(kind, completed, entry.recordCount)
                        try Task.checkCancellation()
                    }

                case .favicons:
                    let blobs = entry.blobDirectoryName.map(directory.appendingPathComponent)
                    let stream = staging.chunkStream(
                        SumiStagedFavicon.self,
                        from: fileURL,
                        chunkSize: Self.chunkSize
                    )
                    for try await chunk in stream {
                        let payloads = chunk.compactMap { staged -> SumiImportFaviconPayload? in
                            guard let blobs,
                                  let pageURL = URL(string: staged.pageURLString),
                                  let iconURL = URL(string: staged.iconURLString),
                                  let data = try? Data(
                                      contentsOf: blobs.appendingPathComponent(staged.blobFileName)
                                  )
                            else { return nil }
                            return SumiImportFaviconPayload(pageURL: pageURL, iconURL: iconURL, payload: data)
                        }
                        await installer.installFavicons(payloads, profileId: profileId)
                        receipt.faviconCount += payloads.count
                        completed += chunk.count
                        report(kind, completed, entry.recordCount)
                        try Task.checkCancellation()
                    }

                case .cookies:
                    let stream = staging.chunkStream(
                        SumiStagedCookie.self,
                        from: fileURL,
                        chunkSize: Self.chunkSize
                    )
                    for try await chunk in stream {
                        let cookiesBySourceKey = Dictionary(
                            grouping: chunk,
                            by: { $0.sourceProfileKey ?? entry.sourceProfileKey }
                        )
                        for (sourceKey, cookies) in cookiesBySourceKey {
                            guard let cookieProfileId = profileIDsBySourceKey[sourceKey] else {
                                throw SumiImportExportError.importFailed(
                                    "No target profile exists for cookie jar \(sourceKey)."
                                )
                            }
                            let outcome = try await installer.installCookies(
                                cookies,
                                profileId: cookieProfileId
                            )
                            receipt.cookiesByProfile[cookieProfileId, default: .init()]
                                .merge(outcome)
                        }
                        completed += chunk.count
                        report(kind, completed, entry.recordCount)
                        try Task.checkCancellation()
                    }
                }
            }
            if mutatedHistory {
                await installer.didMutateHistory()
            }
        }
    }

    /// Undoes an applied bulk import as far as each kind allows. Favicons are
    /// deliberately not undone: the favicon store is a documented cache that
    /// rebuilds itself, and deleting entries would evict icons Sumi fetched on
    /// its own.
    func rollback(_ receipt: SumiImportBulkReceipt) async -> [Error] {
        var errors: [Error] = []

        var rolledBackHistory = false
        for historyReceipt in receipt.history.reversed() {
            do {
                try await installer.rollbackHistory(historyReceipt)
                rolledBackHistory = true
            } catch {
                errors.append(error)
            }
        }
        if rolledBackHistory {
            await installer.didMutateHistory()
        }

        for (profileId, cookieReceipt) in receipt.cookiesByProfile {
            await installer.rollbackCookies(cookieReceipt, profileId: profileId)
        }

        if receipt.faviconCount > 0 {
            Self.log.info("Left \(receipt.faviconCount, privacy: .public) imported site icons in the cache after rollback")
        }
        return errors
    }

    private func report(_ kind: SumiImportBulkKind, _ completed: Int, _ total: Int) {
        onProgress(SumiImportBulkProgress(kind: kind, completed: completed, total: total))
    }
}
