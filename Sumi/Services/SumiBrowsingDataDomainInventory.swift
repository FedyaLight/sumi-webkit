import Foundation
import WebKit

@MainActor
final class SumiBrowsingDataDomainInventory {
    private let websiteDataCleanupService: any SumiWebsiteDataCleanupServicing

    init(websiteDataCleanupService: any SumiWebsiteDataCleanupServicing) {
        self.websiteDataCleanupService = websiteDataCleanupService
    }

    func countVisits(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        historyManager: HistoryManager
    ) async -> Int {
        do {
            return try await historyManager.store.countVisits(
                matching: query,
                profileId: profileId,
                referenceDate: referenceDate,
                calendar: .autoupdatingCurrent
            )
        } catch {
            RuntimeDiagnostics.emit("Error counting browsing history: \(error)")
            return 0
        }
    }

    func visitDomains(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        historyManager: HistoryManager
    ) async -> Set<String> {
        do {
            return try await historyManager.store.domains(
                matching: query,
                profileId: profileId,
                referenceDate: referenceDate,
                calendar: .autoupdatingCurrent
            )
        } catch {
            RuntimeDiagnostics.emit("Error loading browsing history domains: \(error)")
            return []
        }
    }

    func normalizeDomains(_ domains: Set<String>) -> Set<String> {
        Set(
            domains
                .map(siteDomain)
                .filter { !$0.isEmpty }
        )
    }

    func websiteDataDomains(
        ofTypes dataTypes: Set<String>,
        includeCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async -> Set<String> {
        let records = await websiteDataCleanupService.fetchWebsiteDataRecords(
            ofTypes: dataTypes,
            in: dataStore
        )
        var domains = Set(
            records
                .map(\.displayName)
                .map { siteDomain(for: $0) }
                .filter { !$0.isEmpty }
        )

        if includeCookies {
            let cookies = await websiteDataCleanupService.fetchCookies(in: dataStore)
            domains.formUnion(
                cookies
                    .map(\.domain)
                    .map { siteDomain(for: $0) }
                    .filter { !$0.isEmpty }
            )
        }

        return domains
    }

    private func siteDomain(for domain: String) -> String {
        HistoryDomainResolver.siteDomain(forDomain: domain) ?? ""
    }
}
