import Combine
import Foundation

enum SumiExternalSchemeAttemptResult: String, Codable, Equatable, Sendable {
    case opened
    case blockedByDefault
    case blockedByStoredDeny
    case blockedPendingUI
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
    let appDisplayName: String?
    let createdAt: Date
    var lastAttemptAt: Date
    let userActivation: SumiExternalSchemeUserActivationState
    let result: SumiExternalSchemeAttemptResult
    let reason: String
    let navigationActionMetadata: [String: String]
    var attemptCount: Int

    var duplicateIdentity: String {
        [
            pageId,
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
