import Foundation
import SumiDomain

struct SumiProtectionApplyOutcome: Equatable, Sendable {
    let selectedLevel: SumiProtectionLevel
    let previousAppliedLevel: SumiProtectionLevel
    let appliedLevel: SumiProtectionLevel
    let installedBundleProfileId: String?
    let summary: String
}

enum SumiProtectionApplyError: LocalizedError {
    case requiredPreparedBundleUnavailable(profileId: String, detail: String)
    case applyFailed(String)

    var errorDescription: String? {
        switch self {
        case .requiredPreparedBundleUnavailable(let profileId, let detail):
            return "Required prepared bundle profile \(profileId) is unavailable. \(detail)"
        case .applyFailed(let message):
            return message
        }
    }
}
