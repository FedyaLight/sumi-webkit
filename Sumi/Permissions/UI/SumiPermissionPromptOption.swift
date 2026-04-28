import Foundation

struct SumiPermissionPromptOption: Identifiable, Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case normal
        case primary
        case destructive
        case cancel
    }

    let id: String
    let action: SumiPermissionPromptAction
    let title: String
    let accessibilityLabel: String
    let role: Role
    let isEnabled: Bool

    init(
        action: SumiPermissionPromptAction,
        title: String,
        accessibilityLabel: String? = nil,
        role: Role = .normal,
        isEnabled: Bool = true
    ) {
        self.id = action.rawValue
        self.action = action
        self.title = title
        self.accessibilityLabel = accessibilityLabel ?? title
        self.role = role
        self.isEnabled = isEnabled
    }
}
