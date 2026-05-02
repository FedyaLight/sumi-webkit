import Combine
import Foundation

struct SumiPermissionRecentActivityRecord: Identifiable, Equatable, Sendable {
    enum Action: String, Codable, CaseIterable, Hashable, Sendable {
        case allowed
        case blocked
        case denied
        case asked
        case systemBlocked
        case reset
        case openedExternalApp
        case blockedPopup
        case reloadRequired
        case autoRevoked

        var displayLabel: String {
            switch self {
            case .allowed:
                return "allowed"
            case .blocked:
                return "blocked"
            case .denied:
                return "denied"
            case .asked:
                return "asked"
            case .systemBlocked:
                return "blocked by macOS settings"
            case .reset:
                return "reset"
            case .openedExternalApp:
                return "opened external app"
            case .blockedPopup:
                return "blocked popup"
            case .reloadRequired:
                return "reload required"
            case .autoRevoked:
                return "removed automatically"
            }
        }
    }

    let id: String
    let displayDomain: String
    let requestingOrigin: SumiPermissionOrigin
    let topOrigin: SumiPermissionOrigin
    let profilePartitionId: String
    let isEphemeralProfile: Bool
    let permissionType: SumiPermissionType
    let action: Action
    let createdAt: Date
    let count: Int

    init(
        id: String = UUID().uuidString,
        displayDomain: String,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        permissionType: SumiPermissionType,
        action: Action,
        createdAt: Date = Date(),
        count: Int = 1
    ) {
        self.id = id
        self.displayDomain = SumiPermissionStoreRecord.normalizedDisplayDomain(displayDomain)
        self.requestingOrigin = requestingOrigin
        self.topOrigin = topOrigin
        self.profilePartitionId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        self.isEphemeralProfile = isEphemeralProfile
        self.permissionType = permissionType
        self.action = action
        self.createdAt = createdAt
        self.count = max(1, count)
    }
}

@MainActor
final class SumiPermissionRecentActivityStore: ObservableObject {
    @Published private(set) var records: [SumiPermissionRecentActivityRecord] = []

    private let limit: Int

    init(limit: Int = 100) {
        self.limit = max(10, limit)
    }

    func record(_ record: SumiPermissionRecentActivityRecord) {
        records.insert(record, at: 0)
        if records.count > limit {
            records.removeLast(records.count - limit)
        }
    }

    func record(_ event: SumiPermissionCoordinatorEvent, now: Date = Date()) {
        switch event {
        case .queryActivated(let query), .queryPromoted(let query):
            for permissionType in query.permissionTypes {
                record(
                    SumiPermissionRecentActivityRecord(
                        id: "\(query.id)-\(permissionType.identity)-asked",
                        displayDomain: query.displayDomain,
                        requestingOrigin: query.requestingOrigin,
                        topOrigin: query.topOrigin,
                        profilePartitionId: query.profilePartitionId,
                        isEphemeralProfile: query.isEphemeralProfile,
                        permissionType: permissionType,
                        action: .asked,
                        createdAt: query.createdAt,
                        count: 1
                    )
                )
            }
        case .querySettled(_, let decision),
             .requestCancelled(_, let decision),
             .pageCancelled(_, let decision),
             .sessionCancelled(_, let decision),
             .systemBlocked(let decision):
            record(decision: decision, fallbackAction: action(for: decision), now: now)
        case .profileCancelled:
            break
        case .queryQueued, .queryCoalesced, .promptSuppressed:
            break
        }
    }

    func recordSettingsChange(
        displayDomain: String,
        key: SumiPermissionKey,
        state: SumiPermissionState?,
        now: Date = Date()
    ) {
        let action: SumiPermissionRecentActivityRecord.Action
        switch state {
        case .allow:
            action = .allowed
        case .deny:
            action = .denied
        case .ask:
            action = .asked
        case nil:
            action = .reset
        }
        record(
            SumiPermissionRecentActivityRecord(
                displayDomain: displayDomain,
                requestingOrigin: key.requestingOrigin,
                topOrigin: key.topOrigin,
                profilePartitionId: key.profilePartitionId,
                isEphemeralProfile: key.isEphemeralProfile,
                permissionType: key.permissionType,
                action: action,
                createdAt: now
            )
        )
    }

    func recordAutoRevoked(_ event: SumiPermissionAutoRevokedEvent) {
        record(
            SumiPermissionRecentActivityRecord(
                id: event.id,
                displayDomain: event.displayDomain,
                requestingOrigin: event.key.requestingOrigin,
                topOrigin: event.key.topOrigin,
                profilePartitionId: event.key.profilePartitionId,
                isEphemeralProfile: event.key.isEphemeralProfile,
                permissionType: event.key.permissionType,
                action: .autoRevoked,
                createdAt: event.revokedAt
            )
        )
    }

    func records(
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        limit requestedLimit: Int = 20
    ) -> [SumiPermissionRecentActivityRecord] {
        let normalizedProfileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return records
            .filter {
                $0.profilePartitionId == normalizedProfileId
                    && $0.isEphemeralProfile == isEphemeralProfile
            }
            .prefix(max(0, requestedLimit))
            .map { $0 }
    }

    private func record(
        decision: SumiPermissionCoordinatorDecision,
        fallbackAction: SumiPermissionRecentActivityRecord.Action,
        now: Date
    ) {
        for key in decision.keys {
            record(
                SumiPermissionRecentActivityRecord(
                    displayDomain: key.displayDomain,
                    requestingOrigin: key.requestingOrigin,
                    topOrigin: key.topOrigin,
                    profilePartitionId: key.profilePartitionId,
                    isEphemeralProfile: key.isEphemeralProfile,
                    permissionType: key.permissionType,
                    action: fallbackAction,
                    createdAt: now
                )
            )
        }
    }

    private func action(
        for decision: SumiPermissionCoordinatorDecision
    ) -> SumiPermissionRecentActivityRecord.Action {
        switch decision.outcome {
        case .granted:
            return .allowed
        case .denied:
            return .denied
        case .promptRequired:
            return .asked
        case .systemBlocked:
            return .systemBlocked
        case .suppressed:
            return .blocked
        case .unsupported, .requiresUserActivation, .cancelled, .dismissed, .expired:
            return .blocked
        case .ignored:
            return .blocked
        }
    }
}
