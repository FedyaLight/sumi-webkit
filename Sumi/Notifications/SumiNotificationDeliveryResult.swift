import Foundation

enum SumiNotificationDeliveryResult: Equatable, Sendable {
    case delivered(identifier: SumiNotificationIdentifier)
    case failed(identifier: SumiNotificationIdentifier, reason: String)

    var identifier: SumiNotificationIdentifier {
        switch self {
        case .delivered(let identifier),
             .failed(let identifier, _):
            return identifier
        }
    }

    var isDelivered: Bool {
        if case .delivered = self { return true }
        return false
    }
}
