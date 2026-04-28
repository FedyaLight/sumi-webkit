import Combine
import Foundation

struct SumiPermissionIndicatorEventRecord: Identifiable, Equatable, Sendable {
    let id: String
    let tabId: String
    let pageId: String
    let displayDomain: String
    let permissionTypes: [SumiPermissionType]
    let category: SumiPermissionIndicatorCategory
    let visualStyle: SumiPermissionIndicatorVisualStyle
    let priority: SumiPermissionIndicatorPriority
    let reason: String?
    let requestingOrigin: SumiPermissionOrigin?
    let topOrigin: SumiPermissionOrigin?
    let profilePartitionId: String
    let isEphemeralProfile: Bool
    let createdAt: Date
    let expiresAt: Date?
    var attemptCount: Int

    var primaryPermissionType: SumiPermissionType {
        SumiPermissionIndicatorEventRecord.primaryPermissionType(from: permissionTypes)
    }

    var duplicateIdentity: String {
        [
            pageId,
            profilePartitionId,
            isEphemeralProfile ? "ephemeral" : "persistent",
            requestingOrigin?.identity ?? "",
            topOrigin?.identity ?? "",
            permissionTypes.map(\.identity).sorted().joined(separator: ","),
            category.rawValue,
            visualStyle.rawValue,
            priority.rawValue.description,
            reason ?? "",
        ].joined(separator: "|")
    }

    init(
        id: String = UUID().uuidString,
        tabId: String,
        pageId: String,
        displayDomain: String,
        permissionTypes: [SumiPermissionType],
        category: SumiPermissionIndicatorCategory,
        visualStyle: SumiPermissionIndicatorVisualStyle,
        priority: SumiPermissionIndicatorPriority,
        reason: String? = nil,
        requestingOrigin: SumiPermissionOrigin? = nil,
        topOrigin: SumiPermissionOrigin? = nil,
        profilePartitionId: String = "",
        isEphemeralProfile: Bool = false,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        attemptCount: Int = 1
    ) {
        self.id = id
        self.tabId = Self.normalizedId(tabId)
        self.pageId = Self.normalizedId(pageId)
        self.displayDomain = Self.normalizedDisplayDomain(displayDomain)
        self.permissionTypes = Self.uniquePermissionTypes(permissionTypes)
        self.category = category
        self.visualStyle = visualStyle
        self.priority = priority
        self.reason = reason
        self.requestingOrigin = requestingOrigin
        self.topOrigin = topOrigin
        self.profilePartitionId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        self.isEphemeralProfile = isEphemeralProfile
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.attemptCount = max(1, attemptCount)
    }

    private static func primaryPermissionType(
        from permissionTypes: [SumiPermissionType]
    ) -> SumiPermissionType {
        let identities = Set(permissionTypes.map(\.identity))
        if identities.contains(SumiPermissionType.camera.identity),
           identities.contains(SumiPermissionType.microphone.identity)
        {
            return .cameraAndMicrophone
        }
        return permissionTypes.first ?? .notifications
    }

    private static func uniquePermissionTypes(
        _ permissionTypes: [SumiPermissionType]
    ) -> [SumiPermissionType] {
        var seen = Set<String>()
        var result: [SumiPermissionType] = []
        for permissionType in permissionTypes {
            guard seen.insert(permissionType.identity).inserted else { continue }
            result.append(permissionType)
        }
        return result
    }

    private static func normalizedId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedDisplayDomain(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Current site" : trimmed
    }
}

@MainActor
final class SumiPermissionIndicatorEventStore: ObservableObject {
    @Published private(set) var recordsByPageId: [String: [SumiPermissionIndicatorEventRecord]] = [:]

    private var duplicateIndexByPageId: [String: [String: String]] = [:]

    @discardableResult
    func record(
        _ record: SumiPermissionIndicatorEventRecord
    ) -> SumiPermissionIndicatorEventRecord {
        pruneExpired(now: Date())

        let pageId = normalizedId(record.pageId)
        let duplicateIdentity = record.duplicateIdentity
        if let existingId = duplicateIndexByPageId[pageId]?[duplicateIdentity],
           var pageRecords = recordsByPageId[pageId],
           let index = pageRecords.firstIndex(where: { $0.id == existingId }) {
            pageRecords[index].attemptCount += record.attemptCount
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

    func records(forPageId pageId: String, now: Date = Date()) -> [SumiPermissionIndicatorEventRecord] {
        pruneExpired(now: now)
        return recordsByPageId[normalizedId(pageId)] ?? []
    }

    func allRecords(now: Date = Date()) -> [SumiPermissionIndicatorEventRecord] {
        pruneExpired(now: now)
        return recordsByPageId.values.flatMap { $0 }
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

    @discardableResult
    func clear(eventId: String, pageId: String) -> Int {
        let pageId = normalizedId(pageId)
        guard var pageRecords = recordsByPageId[pageId] else { return 0 }
        let originalCount = pageRecords.count
        pageRecords.removeAll { $0.id == eventId }
        recordsByPageId[pageId] = pageRecords.isEmpty ? nil : pageRecords
        rebuildDuplicateIndex(forPageId: pageId)
        return originalCount - pageRecords.count
    }

    func pruneExpired(now: Date = Date()) {
        for pageId in Array(recordsByPageId.keys) {
            guard var pageRecords = recordsByPageId[pageId] else { continue }
            pageRecords.removeAll { record in
                guard let expiresAt = record.expiresAt else { return false }
                return expiresAt <= now
            }
            recordsByPageId[pageId] = pageRecords.isEmpty ? nil : pageRecords
            rebuildDuplicateIndex(forPageId: pageId)
        }
    }

    private func rebuildDuplicateIndex(forPageId pageId: String) {
        guard let pageRecords = recordsByPageId[pageId] else {
            duplicateIndexByPageId.removeValue(forKey: pageId)
            return
        }
        duplicateIndexByPageId[pageId] = Dictionary(
            uniqueKeysWithValues: pageRecords.map { ($0.duplicateIdentity, $0.id) }
        )
    }

    private func normalizedId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
