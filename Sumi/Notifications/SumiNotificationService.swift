import Foundation
import UserNotifications

protocol SumiNotificationServicing: Sendable {
    func post(_ payload: SumiNotificationPayload) async -> SumiNotificationDeliveryResult
    func close(identifier: SumiNotificationIdentifier) async
}

actor SumiNotificationService: SumiNotificationServicing {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func post(_ payload: SumiNotificationPayload) async -> SumiNotificationDeliveryResult {
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

        let request = UNNotificationRequest(
            identifier: payload.identifier.rawValue,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            return .delivered(identifier: payload.identifier)
        } catch {
            return .failed(
                identifier: payload.identifier,
                reason: error.localizedDescription
            )
        }
    }

    func close(identifier: SumiNotificationIdentifier) async {
        center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
        center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
    }
}
