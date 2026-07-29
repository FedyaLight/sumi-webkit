import Foundation
import UserNotifications

protocol SumiNotificationServicing: Sendable {
    func post(_ payload: SumiNotificationPayload) async -> SumiNotificationDeliveryResult
    func close(identifier: SumiNotificationIdentifier) async
    func retireProfile(profilePartitionId: String) async -> Bool
    func rehydrateRetiredProfile(profilePartitionId: String) async
}

struct SumiNotificationCenterRecord: Equatable, Sendable {
    let identifier: String
    let logicalIdentifier: String?
    let profilePartitionId: String?
}

protocol SumiNotificationCenterGateway: Sendable {
    func add(
        _ payload: SumiNotificationPayload,
        physicalIdentifier: String
    ) async throws
    func deliveredRecords() async -> [SumiNotificationCenterRecord]
    func pendingRecords() async -> [SumiNotificationCenterRecord]
    func removeDelivered(identifiers: [String]) async
    func removePending(identifiers: [String]) async
}

actor SumiSystemNotificationCenterGateway: SumiNotificationCenterGateway {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func add(
        _ payload: SumiNotificationPayload,
        physicalIdentifier: String
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = payload.isSilent ? nil : .default
        content.threadIdentifier = payload.tag ?? payload.identifier.rawValue

        var userInfo = payload.userInfo
        userInfo["sumiNotificationIdentifier"] = payload.identifier.rawValue
        userInfo["sumiNotificationKind"] = payload.kind.rawValue
        if let iconURL = payload.iconURL {
            userInfo["iconURL"] = iconURL.absoluteString
        }
        if let imageURL = payload.imageURL {
            userInfo["imageURL"] = imageURL.absoluteString
        }
        content.userInfo = userInfo
        try await center.add(
            UNNotificationRequest(
                identifier: physicalIdentifier,
                content: content,
                trigger: nil
            )
        )
    }

    func deliveredRecords() async -> [SumiNotificationCenterRecord] {
        await center.deliveredNotifications().map {
            Self.record(
                identifier: $0.request.identifier,
                userInfo: $0.request.content.userInfo
            )
        }
    }

    func pendingRecords() async -> [SumiNotificationCenterRecord] {
        await center.pendingNotificationRequests().map {
            Self.record(identifier: $0.identifier, userInfo: $0.content.userInfo)
        }
    }

    func removeDelivered(identifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func removePending(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func record(
        identifier: String,
        userInfo: [AnyHashable: Any]
    ) -> SumiNotificationCenterRecord {
        SumiNotificationCenterRecord(
            identifier: identifier,
            logicalIdentifier: userInfo["sumiNotificationIdentifier"] as? String,
            profilePartitionId: userInfo["profilePartitionId"] as? String
        )
    }
}

actor SumiNotificationService: SumiNotificationServicing {
    private let gateway: any SumiNotificationCenterGateway
    private var retiredProfileIDs: Set<String> = []
    private var inFlightPostsByProfileID: [String: Int] = [:]
    private var postDrainWaitersByProfileID: [String: [CheckedContinuation<Void, Never>]] = [:]

    init(
        gateway: any SumiNotificationCenterGateway =
            SumiSystemNotificationCenterGateway()
    ) {
        self.gateway = gateway
    }

    func post(_ payload: SumiNotificationPayload) async -> SumiNotificationDeliveryResult {
        guard let profileID = profileID(in: payload.userInfo),
              profileID.isEmpty == false,
              retiredProfileIDs.contains(profileID) == false
        else {
            return .failed(
                identifier: payload.identifier,
                reason: "notification-profile-unavailable"
            )
        }
        inFlightPostsByProfileID[profileID, default: 0] += 1
        let physicalIdentifier = physicalIdentifier(
            for: payload.identifier,
            profileID: profileID
        )

        do {
            try await gateway.add(
                payload,
                physicalIdentifier: physicalIdentifier
            )
            guard retiredProfileIDs.contains(profileID) == false else {
                await gateway.removeDelivered(identifiers: [physicalIdentifier])
                await gateway.removePending(identifiers: [physicalIdentifier])
                finishPost(for: profileID)
                return .failed(
                    identifier: payload.identifier,
                    reason: "notification-profile-retired"
                )
            }
            finishPost(for: profileID)
            return .delivered(identifier: payload.identifier)
        } catch {
            finishPost(for: profileID)
            return .failed(
                identifier: payload.identifier,
                reason: error.localizedDescription
            )
        }
    }

    func close(identifier: SumiNotificationIdentifier) async {
        let deliveredIdentifiers = await gateway.deliveredRecords().compactMap {
            $0.logicalIdentifier == identifier.rawValue ? $0.identifier : nil
        }
        let pendingIdentifiers = await gateway.pendingRecords().compactMap {
            $0.logicalIdentifier == identifier.rawValue ? $0.identifier : nil
        }
        await gateway.removeDelivered(identifiers: deliveredIdentifiers)
        await gateway.removePending(identifiers: pendingIdentifiers)
    }

    func retireProfile(profilePartitionId: String) async -> Bool {
        let profileID = normalizedProfileID(profilePartitionId)
        guard profileID.isEmpty == false else { return false }

        retiredProfileIDs.insert(profileID)
        await waitForPostsToDrain(for: profileID)

        let deliveredIdentifiers = await gateway.deliveredRecords()
            .compactMap { record in
                normalizedProfileID(record.profilePartitionId ?? "") == profileID
                    ? record.identifier
                    : nil
            }
        let pendingIdentifiers = await gateway.pendingRecords()
            .compactMap { record in
                normalizedProfileID(record.profilePartitionId ?? "") == profileID
                    ? record.identifier
                    : nil
            }
        await gateway.removeDelivered(identifiers: deliveredIdentifiers)
        await gateway.removePending(identifiers: pendingIdentifiers)

        let deliveredStillPresent = await gateway.deliveredRecords().contains {
            normalizedProfileID($0.profilePartitionId ?? "") == profileID
        }
        let pendingStillPresent = await gateway.pendingRecords().contains {
            normalizedProfileID($0.profilePartitionId ?? "") == profileID
        }
        return deliveredStillPresent == false && pendingStillPresent == false
    }

    func rehydrateRetiredProfile(profilePartitionId: String) {
        let profileID = normalizedProfileID(profilePartitionId)
        guard profileID.isEmpty == false else { return }
        retiredProfileIDs.insert(profileID)
    }

    #if DEBUG
        func isProfileRetiredForTesting(_ profilePartitionId: String) -> Bool {
            retiredProfileIDs.contains(normalizedProfileID(profilePartitionId))
        }
    #endif

    private func finishPost(for profileID: String) {
        let remaining = (inFlightPostsByProfileID[profileID] ?? 1) - 1
        if remaining > 0 {
            inFlightPostsByProfileID[profileID] = remaining
            return
        }
        inFlightPostsByProfileID.removeValue(forKey: profileID)
        let waiters = postDrainWaitersByProfileID.removeValue(forKey: profileID) ?? []
        waiters.forEach { $0.resume() }
    }

    private func waitForPostsToDrain(for profileID: String) async {
        guard inFlightPostsByProfileID[profileID, default: 0] > 0 else { return }
        await withCheckedContinuation { continuation in
            postDrainWaitersByProfileID[profileID, default: []].append(continuation)
        }
    }

    private func profileID(in userInfo: [String: String]) -> String? {
        userInfo["profilePartitionId"].map(normalizedProfileID)
    }

    private func normalizedProfileID(_ profileID: String) -> String {
        profileID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func physicalIdentifier(
        for logicalIdentifier: SumiNotificationIdentifier,
        profileID: String
    ) -> String {
        "sumi-profile:\(profileID.utf8.count):\(profileID):\(logicalIdentifier.rawValue)"
    }
}
