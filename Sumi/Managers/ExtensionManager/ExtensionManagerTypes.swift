import Foundation

@available(macOS 15.5, *)
extension ExtensionManager {
    enum ExtensionBackgroundWakeReason: String, Codable, CaseIterable {
        case startup
        case install
        case enable
        case actionPopup
        case toolbarAction
        case nativeMessaging
    }

    enum BackgroundRuntimeState: String, Codable, CaseIterable {
        case neverLoaded
        case wakeInFlight
        case loaded
        case loadFailed
    }

    struct ExtensionRuntimeMetrics: Codable, Equatable {
        var manifestValidationDuration: TimeInterval = 0
        var webExtensionCreationDuration: TimeInterval = 0
        var contextLoadDuration: TimeInterval = 0
        var backgroundWakeDuration: TimeInterval = 0
        var backgroundWakeCount: Int = 0
        var lastBackgroundWakeReason: ExtensionBackgroundWakeReason?
        var lastBackgroundWakeFailed = false
        var errorUpdateDuration: TimeInterval = 0
    }

    enum ExtensionRuntimeState: String, Codable, CaseIterable {
        case idle
        case loading
        case ready
        case unavailable
        case failed
    }

    enum ExtensionPermissionPromptDecision {
        case allow(expirationDate: Date?)
        case deny
    }

    enum ExtensionPermissionTargetKind: String, Codable {
        case permission
        case matchPattern
    }

    enum ExtensionStoredPermissionState: String, Codable {
        case allowed
        case denied
    }

    struct ExtensionStoredPermissionDecision: Codable, Equatable {
        var profileId: String
        var extensionId: String
        var targetKind: ExtensionPermissionTargetKind
        var target: String
        var state: ExtensionStoredPermissionState
        var expiresAt: Date?
        var updatedAt: Date

        func isExpired(now: Date = Date()) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt <= now
        }
    }
}
