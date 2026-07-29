import Foundation
import WebKit

/// Connects the bulk apply coordinator to Sumi's real stores.
///
/// Each kind writes through the surface that already owns it — history through
/// the history store's imported-visit writer, icons through the favicon
/// ingestion seam, cookies through the profile cookie installer — rather than
/// reaching into any of them directly.
@MainActor
struct SumiImportBulkInstaller: SumiImportBulkInstalling {
    var historyStore: HistoryStore
    var refreshHistory: @MainActor () async -> Void
    var faviconIngestion: (any BrowserFaviconLocalIconIngesting)?
    var cookieInstaller: SumiProfileCookieInstallationService
    var overwriteExistingCookies: Bool

    func installHistory(
        _ visits: [HistoryImportedVisit],
        profileId: UUID?
    ) async throws -> HistoryImportedVisitWriter.Receipt {
        try await historyStore.installImportedVisits(visits, profileId: profileId)
    }

    func rollbackHistory(_ receipt: HistoryImportedVisitWriter.Receipt) async throws {
        try await historyStore.rollbackImportedVisits(receipt)
    }

    func didMutateHistory() async {
        await refreshHistory()
    }

    func installFavicons(_ favicons: [SumiImportFaviconPayload], profileId: UUID?) async {
        guard let faviconIngestion else { return }
        let partition = SumiFaviconPartition.regular(profileId)
        for favicon in favicons {
            await faviconIngestion.ingestImportedIcon(
                payload: favicon.payload,
                iconURL: favicon.iconURL,
                documentURL: favicon.pageURL,
                partition: partition
            )
        }
    }

    func installCookies(
        _ cookies: [SumiStagedCookie],
        profileId: UUID
    ) async throws -> SumiCookieInstallationReceipt {
        try await cookieInstaller.install(
            cookies,
            profileId: profileId,
            overwriteExisting: overwriteExistingCookies
        )
    }

    func rollbackCookies(
        _ receipt: SumiCookieInstallationReceipt,
        profileId: UUID
    ) async {
        await cookieInstaller.rollback(receipt, profileId: profileId)
    }
}
