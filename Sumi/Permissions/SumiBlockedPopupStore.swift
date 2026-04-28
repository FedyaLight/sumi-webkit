import Combine
import Foundation

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
    let targetURL: URL?
    let sourceURL: URL?
    let createdAt: Date
    var lastBlockedAt: Date
    let userActivation: SumiPopupUserActivationState
    let reason: Reason
    let canOpenLater: Bool
    let navigationActionMetadata: [String: String]
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
        createdAt: Date,
        lastBlockedAt: Date,
        userActivation: SumiPopupUserActivationState,
        reason: Reason,
        canOpenLater: Bool,
        navigationActionMetadata: [String: String],
        profilePartitionId: String = "",
        isEphemeralProfile: Bool = false,
        attemptCount: Int
    ) {
        self.id = id
        self.tabId = tabId
        self.pageId = pageId
        self.requestingOrigin = requestingOrigin
        self.topOrigin = topOrigin
        self.targetURL = targetURL
        self.sourceURL = sourceURL
        self.createdAt = createdAt
        self.lastBlockedAt = lastBlockedAt
        self.userActivation = userActivation
        self.reason = reason
        self.canOpenLater = canOpenLater
        self.navigationActionMetadata = navigationActionMetadata
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

    func allRecords() -> [SumiBlockedPopupRecord] {
        recordsByPageId.values.flatMap { $0 }
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
