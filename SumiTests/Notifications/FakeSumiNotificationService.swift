import Foundation
@testable import Sumi

actor FakeSumiNotificationService: SumiNotificationServicing {
    private(set) var postedPayloads: [SumiNotificationPayload] = []
    private(set) var closedIdentifiers: [SumiNotificationIdentifier] = []
    var nextFailureReason: String?

    func setNextFailureReason(_ reason: String?) {
        nextFailureReason = reason
    }

    func post(_ payload: SumiNotificationPayload) async -> SumiNotificationDeliveryResult {
        postedPayloads.append(payload)
        if let nextFailureReason {
            self.nextFailureReason = nil
            return .failed(identifier: payload.identifier, reason: nextFailureReason)
        }
        return .delivered(identifier: payload.identifier)
    }

    func close(identifier: SumiNotificationIdentifier) async {
        closedIdentifiers.append(identifier)
    }

    func postedCount() -> Int {
        postedPayloads.count
    }

    func lastPayload() -> SumiNotificationPayload? {
        postedPayloads.last
    }
}
