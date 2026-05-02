import Foundation

actor InMemoryPermissionStore: SumiPermissionStore {
    private struct MemoryKey: Hashable, Sendable {
        let ownerKind: OwnerKind
        let ownerId: String
    }

    private enum OwnerKind: String, Sendable {
        case page
        case session
    }

    private var records: [MemoryKey: SumiPermissionStoreRecord] = [:]

    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord? {
        try await getDecision(for: key, sessionOwnerId: nil)
    }

    func getDecision(
        for key: SumiPermissionKey,
        sessionOwnerId: String?
    ) async throws -> SumiPermissionStoreRecord? {
        try await expireDecisions(now: Date())

        if let pageMemoryKey = oneTimeMemoryKey(for: key),
           let record = records[pageMemoryKey]
        {
            return record
        }

        return records[sessionMemoryKey(for: key, sessionOwnerId: sessionOwnerId)]
    }

    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async throws {
        try await setDecision(for: key, decision: decision, sessionOwnerId: nil)
    }

    func setDecision(
        for key: SumiPermissionKey,
        decision: SumiPermissionDecision,
        sessionOwnerId: String?
    ) async throws {
        guard decision.persistence != .persistent else {
            throw SumiPermissionStoreError.unsupportedPersistence(.persistent)
        }
        if key.permissionType.isOneTimeOnly, decision.persistence != .oneTime {
            throw SumiPermissionStoreError.unsupportedPersistence(decision.persistence)
        }

        let memoryKey: MemoryKey
        switch decision.persistence {
        case .oneTime:
            guard let resolvedKey = oneTimeMemoryKey(for: key) else {
                throw SumiPermissionStoreError.oneTimeDecisionRequiresPageId
            }
            memoryKey = resolvedKey
        case .session:
            memoryKey = sessionMemoryKey(for: key, sessionOwnerId: sessionOwnerId)
        case .persistent:
            throw SumiPermissionStoreError.unsupportedPersistence(.persistent)
        }

        records[memoryKey] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func resetDecision(for key: SumiPermissionKey) async throws {
        if let pageMemoryKey = oneTimeMemoryKey(for: key) {
            records.removeValue(forKey: pageMemoryKey)
        }
        records.removeValue(forKey: sessionMemoryKey(for: key, sessionOwnerId: nil))
    }

    func resetDecision(for key: SumiPermissionKey, sessionOwnerId: String?) async throws {
        if let pageMemoryKey = oneTimeMemoryKey(for: key) {
            records.removeValue(forKey: pageMemoryKey)
        }
        records.removeValue(forKey: sessionMemoryKey(for: key, sessionOwnerId: sessionOwnerId))
    }

    func listDecisions(profilePartitionId: String) async throws -> [SumiPermissionStoreRecord] {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return records.values
            .filter { $0.key.profilePartitionId == profileId }
            .sorted(by: recordSort)
    }

    func listDecisions(
        profilePartitionId: String,
        includingPersistences persistences: Set<SumiPermissionPersistence>
    ) async throws -> [SumiPermissionStoreRecord] {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return records.values
            .filter {
                $0.key.profilePartitionId == profileId
                    && persistences.contains($0.decision.persistence)
            }
            .sorted(by: recordSort)
    }

    func listOneTimeDecisions(
        profilePartitionId: String,
        pageId: String
    ) async throws -> [SumiPermissionStoreRecord] {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        let ownerId = normalizedOwnerId(pageId)
        return records
            .filter { memoryKey, record in
                memoryKey.ownerKind == .page
                    && memoryKey.ownerId == ownerId
                    && record.key.profilePartitionId == profileId
                    && record.decision.persistence == .oneTime
            }
            .map(\.value)
            .sorted(by: recordSort)
    }

    @discardableResult
    func expireDecisions(now: Date) async throws -> Int {
        let beforeCount = records.count
        records = records.filter { _, record in
            !record.decision.isExpired(now: now)
        }
        return beforeCount - records.count
    }

    func recordLastUsed(for key: SumiPermissionKey, at date: Date) async throws {
        try await recordLastUsed(for: key, at: date, sessionOwnerId: nil)
    }

    func recordLastUsed(
        for key: SumiPermissionKey,
        at date: Date,
        sessionOwnerId: String?
    ) async throws {
        var keysToUpdate: [MemoryKey] = []
        if let pageMemoryKey = oneTimeMemoryKey(for: key), records[pageMemoryKey] != nil {
            keysToUpdate.append(pageMemoryKey)
        }
        let sessionKey = sessionMemoryKey(for: key, sessionOwnerId: sessionOwnerId)
        if records[sessionKey] != nil {
            keysToUpdate.append(sessionKey)
        }

        for memoryKey in keysToUpdate {
            guard let record = records[memoryKey] else { continue }
            records[memoryKey] = SumiPermissionStoreRecord(
                key: record.key,
                decision: record.decision.recordingLastUsed(at: date),
                displayDomain: record.displayDomain
            )
        }
    }

    @discardableResult
    func clearForPageId(_ pageId: String) async -> Int {
        let ownerId = normalizedOwnerId(pageId)
        return removeRecords { memoryKey, _ in
            memoryKey.ownerKind == .page && memoryKey.ownerId == ownerId
        }
    }

    func clearOneTimeDecisions(forTabId tabId: String) async -> Int {
        let ownerId = normalizedOwnerId(tabId)
        guard !ownerId.isEmpty else { return 0 }
        return removeRecords { memoryKey, record in
            memoryKey.ownerKind == .page
                && record.decision.persistence == .oneTime
                && (memoryKey.ownerId == ownerId || memoryKey.ownerId.hasPrefix("\(ownerId):"))
        }
    }

    @discardableResult
    func clearForNavigation(pageId: String) async -> Int {
        await clearForPageId(pageId)
    }

    @discardableResult
    func clearForSession(ownerId: String) async -> Int {
        let normalized = normalizedOwnerId(ownerId)
        return removeRecords { memoryKey, _ in
            memoryKey.ownerKind == .session && memoryKey.ownerId == normalized
        }
    }

    @discardableResult
    func clearForProfile(profilePartitionId: String) async -> Int {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return removeRecords { _, record in
            record.key.profilePartitionId == profileId
        }
    }

    @discardableResult
    func clearTransientDecisions(
        profilePartitionId: String,
        pageId: String?,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin
    ) async -> Int {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        let ownerId = pageId.map(normalizedOwnerId)
        return removeRecords { memoryKey, record in
            guard record.key.profilePartitionId == profileId,
                  record.key.requestingOrigin.identity == requestingOrigin.identity,
                  record.key.topOrigin.identity == topOrigin.identity
            else {
                return false
            }

            switch record.decision.persistence {
            case .oneTime:
                guard let ownerId else { return false }
                return memoryKey.ownerKind == .page && memoryKey.ownerId == ownerId
            case .session:
                return memoryKey.ownerKind == .session
            case .persistent:
                return false
            }
        }
    }

    private func removeRecords(
        matching predicate: (MemoryKey, SumiPermissionStoreRecord) -> Bool
    ) -> Int {
        let beforeCount = records.count
        records = records.filter { memoryKey, record in
            !predicate(memoryKey, record)
        }
        return beforeCount - records.count
    }

    private func oneTimeMemoryKey(for key: SumiPermissionKey) -> MemoryKey? {
        guard let transientPageId = key.transientPageId else { return nil }
        return MemoryKey(
            ownerKind: .page,
            ownerId: normalizedOwnerId(transientPageId)
        )
    }

    private func sessionMemoryKey(
        for key: SumiPermissionKey,
        sessionOwnerId: String?
    ) -> MemoryKey {
        MemoryKey(
            ownerKind: .session,
            ownerId: normalizedOwnerId(sessionOwnerId ?? key.profilePartitionId)
        )
    }

    private func normalizedOwnerId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func recordSort(
        lhs: SumiPermissionStoreRecord,
        rhs: SumiPermissionStoreRecord
    ) -> Bool {
        if lhs.displayDomain != rhs.displayDomain {
            return lhs.displayDomain < rhs.displayDomain
        }
        return lhs.key.permissionType.identity < rhs.key.permissionType.identity
    }
}
