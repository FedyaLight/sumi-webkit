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
        let receipt = try await historyStore.installImportedVisits(visits, profileId: profileId)
        await refreshHistory()
        return receipt
    }

    func rollbackHistory(_ receipt: HistoryImportedVisitWriter.Receipt) async throws {
        try await historyStore.rollbackImportedVisits(receipt)
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
        profileId: UUID?
    ) async -> (installed: Set<String>, replaced: [SumiStagedCookie]) {
        guard let profileId else { return ([], []) }
        let receipt = await cookieInstaller.install(
            cookies,
            profileId: profileId,
            overwriteExisting: overwriteExistingCookies
        )
        // The replaced originals are carried as staged values so the receipt
        // stays a plain value type the coordinator can hold.
        return (
            receipt.installedIdentities,
            receipt.replaced.map { cookie in
                SumiStagedCookie(
                    name: cookie.name,
                    value: cookie.value,
                    domain: cookie.domain,
                    path: cookie.path,
                    expiresAt: cookie.expiresDate,
                    isSecure: cookie.isSecure,
                    isHTTPOnly: cookie.isHTTPOnly
                )
            }
        )
    }

    func rollbackCookies(
        identities: Set<String>,
        replaced: [SumiStagedCookie],
        profileId: UUID?
    ) async {
        guard let profileId else { return }
        await cookieInstaller.rollback(
            SumiCookieInstallationReceipt(
                installedIdentities: identities,
                replaced: replaced.compactMap(SumiProfileCookieInstallationService.makeCookie)
            ),
            profileId: profileId
        )
    }
}
