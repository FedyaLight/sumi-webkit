import Foundation
import SumiDomain

enum SumiProtectionApplyError: LocalizedError {
    case requiredGenerationUnavailable(profileId: String, detail: String)
    case applyFailed(String)

    var errorDescription: String? {
        switch self {
        case .requiredGenerationUnavailable(let profileId, let detail):
            return "Required Adblock generation profile \(profileId) is unavailable. \(detail)"
        case .applyFailed(let message):
            return message
        }
    }
}
