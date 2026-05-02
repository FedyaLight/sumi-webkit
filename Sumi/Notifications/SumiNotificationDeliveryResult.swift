import Foundation

enum SumiNotificationDeliveryResult: Equatable, Sendable {
    case delivered(identifier: SumiNotificationIdentifier)
    case failed(identifier: SumiNotificationIdentifier, reason: String)
}
