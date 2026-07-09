import Foundation
import SumiDomain

/// Owns the automatic permission cleanup preference and the scheduling of
/// cleanup runs through `SumiPermissionCleanupService`.
@MainActor
final class SumiPermissionCleanupSettingsOwner {
    private enum Constants {
        static let cleanupPreferenceKey = "permissions.cleanup.automatic.enabled"
    }

    private let permissionCleanupService: SumiPermissionCleanupService?
    private let userDefaults: UserDefaults
    private let now: () -> Date

    init(
        permissionCleanupService: SumiPermissionCleanupService?,
        userDefaults: UserDefaults,
        now: @escaping () -> Date
    ) {
        self.permissionCleanupService = permissionCleanupService
        self.userDefaults = userDefaults
        self.now = now
    }

    var cleanupSettings: SumiPermissionCleanupSettings {
        get {
            SumiPermissionCleanupSettings(
                isAutomaticCleanupEnabled: isAutomaticCleanupEnabled()
            )
        }
        set {
            userDefaults.set(
                newValue.isAutomaticCleanupEnabled,
                forKey: Constants.cleanupPreferenceKey
            )
        }
    }

    func cleanupSettings(profile: SumiPermissionSettingsProfileContext) -> SumiPermissionCleanupSettings {
        let enabled = isAutomaticCleanupEnabled()
        guard let permissionCleanupService else {
            return SumiPermissionCleanupSettings(isAutomaticCleanupEnabled: enabled)
        }
        return permissionCleanupService.settings(
            isAutomaticCleanupEnabled: enabled,
            profilePartitionId: profile.profilePartitionId
        )
    }

    func setAutomaticCleanupEnabled(
        _ isEnabled: Bool,
        profile: SumiPermissionSettingsProfileContext
    ) {
        userDefaults.set(isEnabled, forKey: Constants.cleanupPreferenceKey)
        cleanupSettings = SumiPermissionCleanupSettings(isAutomaticCleanupEnabled: isEnabled)
        _ = profile
    }

    @discardableResult
    func runAutomaticCleanupIfNeeded(
        profile: SumiPermissionSettingsProfileContext
    ) async -> SumiPermissionCleanupResult {
        guard let permissionCleanupService else {
            return .disabled(profilePartitionId: profile.profilePartitionId, now: now())
        }
        return await permissionCleanupService.runIfNeeded(
            profile: profile,
            settings: cleanupSettings(profile: profile)
        )
    }

    private func isAutomaticCleanupEnabled() -> Bool {
        userDefaults.bool(forKey: Constants.cleanupPreferenceKey)
    }
}
