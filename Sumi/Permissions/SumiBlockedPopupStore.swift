import Combine
import Foundation

struct SumiBlockedPopupURLSummary: Equatable, Sendable {
    let origin: SumiPermissionOrigin
    let displayDomain: String
    let registrableDomain: String?

    init?(
        url: URL?,
        registrableDomainResolver: any SumiRegistrableDomainResolving = SumiRegistrableDomainResolver()
    ) {
        guard let url else { return nil }

        let origin = SumiPermissionOrigin(url: url)
        self.origin = origin
        self.displayDomain = origin.displayDomain
        self.registrableDomain = registrableDomainResolver.registrableDomain(forHost: origin.host)
    }

    var duplicateIdentity: String {
        [
            origin.identity,
            displayDomain,
            registrableDomain ?? "",
        ].joined(separator: "|")
    }
}

struct SumiBlockedPopupRecord: Identifiable, Equatable, Sendable {
    enum Reason: String, Codable, Equatable, Sendable {
        case blockedByDefault
        case blockedByStoredDeny
        case blockedByPolicy
        case blockedByInvalidOrigin
        case blockedByUnsupportedSurface
        case blockedByBackgroundPromptUnavailable
    }

    let id: String
    let tabId: String
    let pageId: String
    let requestingOrigin: SumiPermissionOrigin
    let topOrigin: SumiPermissionOrigin
    let targetURLSummary: SumiBlockedPopupURLSummary?
    let sourceURLSummary: SumiBlockedPopupURLSummary?
    var lastBlockedAt: Date
    let reason: Reason
    let profilePartitionId: String
    let isEphemeralProfile: Bool
    var attemptCount: Int

    init(
        id: String,
        tabId: String,
        pageId: String,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        targetURL: URL?,
        sourceURL: URL?,
        lastBlockedAt: Date,
        reason: Reason,
        profilePartitionId: String = "",
        isEphemeralProfile: Bool = false,
        attemptCount: Int
    ) {
        self.id = id
        self.tabId = tabId
        self.pageId = pageId
        self.requestingOrigin = requestingOrigin
        self.topOrigin = topOrigin
        self.targetURLSummary = SumiBlockedPopupURLSummary(url: targetURL)
        self.sourceURLSummary = SumiBlockedPopupURLSummary(url: sourceURL)
        self.lastBlockedAt = lastBlockedAt
        self.reason = reason
        self.profilePartitionId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        self.isEphemeralProfile = isEphemeralProfile
        self.attemptCount = max(1, attemptCount)
    }

    var duplicateIdentity: String {
        [
            pageId,
            profilePartitionId,
            isEphemeralProfile ? "ephemeral" : "persistent",
            requestingOrigin.identity,
            topOrigin.identity,
            targetURLSummary?.duplicateIdentity ?? "<nil>",
            sourceURLSummary?.duplicateIdentity ?? "<nil>",
            reason.rawValue,
        ].joined(separator: "|")
    }
}

@MainActor
final class SumiBlockedPopupStore: ObservableObject {
    @Published private(set) var recordsByPageId: [String: [SumiBlockedPopupRecord]] = [:]

    private var duplicateIndexByPageId: [String: [String: String]] = [:]

    @discardableResult
    func record(_ record: SumiBlockedPopupRecord) -> SumiBlockedPopupRecord {
        let pageId = normalizedId(record.pageId)
        let duplicateIdentity = record.duplicateIdentity
        if let existingId = duplicateIndexByPageId[pageId]?[duplicateIdentity],
           var pageRecords = recordsByPageId[pageId],
           let index = pageRecords.firstIndex(where: { $0.id == existingId }) {
            pageRecords[index].attemptCount += 1
            pageRecords[index].lastBlockedAt = record.lastBlockedAt
            recordsByPageId[pageId] = pageRecords
            return pageRecords[index]
        }

        var pageRecords = recordsByPageId[pageId] ?? []
        pageRecords.append(record)
        recordsByPageId[pageId] = pageRecords

        var pageIndex = duplicateIndexByPageId[pageId] ?? [:]
        pageIndex[duplicateIdentity] = record.id
        duplicateIndexByPageId[pageId] = pageIndex
        return record
    }

    func records(forPageId pageId: String) -> [SumiBlockedPopupRecord] {
        recordsByPageId[normalizedId(pageId)] ?? []
    }

    func allRecords() -> [SumiBlockedPopupRecord] {
        recordsByPageId.values.flatMap { $0 }
    }

    @discardableResult
    func clear(pageId: String) -> Int {
        let pageId = normalizedId(pageId)
        let removed = recordsByPageId.removeValue(forKey: pageId)?.count ?? 0
        duplicateIndexByPageId.removeValue(forKey: pageId)
        return removed
    }

    @discardableResult
    func clear(tabId: String) -> Int {
        let tabId = normalizedId(tabId)
        let pageIds = recordsByPageId.keys.filter { pageId in
            recordsByPageId[pageId]?.contains { $0.tabId == tabId } == true
        }
        var removed = 0
        for pageId in pageIds {
            removed += clear(pageId: pageId)
        }
        return removed
    }

    private func normalizedId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
