import Foundation

enum SumiPermissionState: String, Codable, CaseIterable, Hashable, Sendable {
    case ask
    case allow
    case deny
}
