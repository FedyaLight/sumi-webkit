import Combine
import Foundation

struct SumiBlockedPopupRecord: Identifiable, Equatable, Sendable {
    enum Reason: String, Codable, Equatable, Sendable {
        case blockedByDefault
        case blockedByStoredDeny
        case blockedByPolicy
        case blockedByInvalidOrigin
        case blockedByUnsupportedSurface
        case blockedByPromptUIUnavailable
    }

    let id: String
    let tabId: String
    let pageId: String
    let requestingOrigin: SumiPermissionOrigin
    let topOrigin: SumiPermissionOrigin
    let targetURL: URL?
    let sourceURL: URL?
    let createdAt: Date
    var lastBlockedAt: Date
    let userActivation: SumiPopupUserActivationState
    let reason: Reason
    let canOpenLater: Bool
    let navigationActionMetadata: [String: String]
    var attemptCount: Int

    var duplicateIdentity: String {
        [
            pageId,
            requestingOrigin.identity,
            topOrigin.identity,
            targetURL?.absoluteString ?? "<nil>",
            sourceURL?.absoluteString ?? "<nil>",
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

    func record(id: String, pageId: String) -> SumiBlockedPopupRecord? {
        records(forPageId: pageId).first { $0.id == id }
    }

    func reopenableRecord(id: String, pageId: String) -> SumiBlockedPopupRecord? {
        guard let record = record(id: id, pageId: pageId),
              record.canOpenLater,
              record.targetURL != nil
        else {
            return nil
        }
        return record
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

