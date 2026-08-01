import AppKit
import Combine
import Foundation
import SumiDomain

@MainActor
struct ProfileSettingsInventory {
    let snapshot: () -> [UUID: ProfileUsage]
    let updates: AnyPublisher<Void, Never>
}

/// Browser capabilities consumed by the standalone Settings window.
/// Built by `WebsiteViewContextFactory`; Settings UI must not reach into the browser composition root.
@MainActor
struct SettingsBrowserContext {
    let profileManager: ProfileManager
    let profileInventory: ProfileSettingsInventory
    let extensionsModule: SumiExtensionsModule
    let extensionSurfaceStore: BrowserExtensionSurfaceStore
    let moduleRegistry: SumiModuleRegistry
    let protectionCoordinator: SumiProtectionCoordinator
    let boostsModule: SumiBoostsModule

    let currentProfile: () -> Profile?
    let currentProfileUpdates: AnyPublisher<Profile?, Never>
    let requestProfileDeletion: (Profile, String, NSWindow?) -> Void
    let makePermissionRepository: () -> SumiPermissionSettingsRepository
    let dataRecoveryActions: SumiDataRecoveryActions
}
