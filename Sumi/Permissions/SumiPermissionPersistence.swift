import Foundation

enum SumiPermissionPersistence: String, Codable, CaseIterable, Hashable, Sendable {
    case oneTime
    case session
    case persistent
}
