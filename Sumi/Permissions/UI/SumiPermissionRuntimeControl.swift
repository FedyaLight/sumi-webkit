import Foundation

struct SumiPermissionRuntimeControl: Equatable, Identifiable, Sendable {
    struct Action: Equatable, Identifiable, Sendable {
        enum Kind: String, Codable, CaseIterable, Sendable {
            case muteCamera
            case unmuteCamera
            case stopCamera
            case muteMicrophone
            case unmuteMicrophone
            case stopMicrophone
            case pauseGeolocation
            case resumeGeolocation
            case stopGeolocationForVisit
            case reloadAutoplay
        }

        let kind: Kind
        let title: String
        let accessibilityLabel: String
        let isDestructive: Bool

        var id: Kind { kind }
    }

    let id: String
    let permissionType: SumiPermissionType
    let runtimeStateDescription: String
    let title: String
    let subtitle: String
    let iconName: String?
    let fallbackSystemName: String
    let actions: [Action]
    let disabledReason: String?
    let inProgressActionKind: Action.Kind?
    let lastResult: SumiPermissionRuntimeControlResult?
    let accessibilityLabel: String

    var isOperationInProgress: Bool {
        inProgressActionKind != nil
    }
}
