import Combine
import Foundation

enum SumiExternalSchemeAttemptResult: String, Codable, Equatable, Sendable {
    case opened
    case blockedByDefault
    case blockedByStoredDeny
    case blockedPromptPresenterUnavailable
    case unsupportedScheme
    case openFailed
}

struct SumiExternalSchemeAttemptRecord: Identifiable, Equatable, Sendable {
    let id: String
    let tabId: String
    let pageId: String
    let requestingOrigin: SumiPermissionOrigin
    let topOrigin: SumiPermissionOrigin
    let scheme: String
    let redactedTargetURLString: String?
    var lastAttemptAt: Date
    let result: SumiExternalSchemeAttemptResult
    let reason: String
    let profilePartitionId: String
    let isEphemeralProfile: Bool
    var attemptCount: Int

    init(
        id: String,
        tabId: String,
        pageId: String,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        scheme: String,
        redactedTargetURLString: String?,
        lastAttemptAt: Date,
        result: SumiExternalSchemeAttemptResult,
        reason: String,
        profilePartitionId: String = "",
        isEphemeralProfile: Bool = false,
        attemptCount: Int
    ) {
        self.id = id
        self.tabId = tabId
        self.pageId = pageId
        self.requestingOrigin = requestingOrigin
        self.topOrigin = topOrigin
        self.scheme = SumiPermissionType.normalizedExternalScheme(scheme)
        self.redactedTargetURLString = redactedTargetURLString
        self.lastAttemptAt = lastAttemptAt
        self.result = result
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
            scheme,
            redactedTargetURLString ?? "<nil>",
            result.rawValue,
            reason,
        ].joined(separator: "|")
    }
}

@MainActor
final class SumiExternalSchemeSessionStore: ObservableObject {
    @Published private(set) var recordsByPageId: [String: [SumiExternalSchemeAttemptRecord]] = [:]

    private var duplicateIndexByPageId: [String: [String: String]] = [:]

    @discardableResult
    func record(_ record: SumiExternalSchemeAttemptRecord) -> SumiExternalSchemeAttemptRecord {
        let pageId = normalizedId(record.pageId)
        let duplicateIdentity = record.duplicateIdentity
        if let existingId = duplicateIndexByPageId[pageId]?[duplicateIdentity],
           var pageRecords = recordsByPageId[pageId],
           let index = pageRecords.firstIndex(where: { $0.id == existingId }) {
            pageRecords[index].attemptCount += 1
            pageRecords[index].lastAttemptAt = record.lastAttemptAt
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

    func records(forPageId pageId: String) -> [SumiExternalSchemeAttemptRecord] {
        recordsByPageId[normalizedId(pageId)] ?? []
    }

    func allRecords() -> [SumiExternalSchemeAttemptRecord] {
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
