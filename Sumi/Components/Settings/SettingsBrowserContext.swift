import Combine
import Foundation
import SumiDomain

@MainActor
struct ProfileSettingsInventory {
    let usage: (UUID) -> ProfileUsage
    let updates: AnyPublisher<Void, Never>
}

/// Browser projection consumed by the in-tab Settings surface.
/// Built by `WebsiteViewContextFactory`; Settings UI must not reach into the browser composition root.
@MainActor
struct SettingsBrowserContext {
    let profileManager: ProfileManager
    let profileInventory: ProfileSettingsInventory
    let extensionsModule: SumiExtensionsModule
    let extensionSurfaceStore: BrowserExtensionSurfaceStore

    let currentProfile: () -> Profile?
    let currentProfileUpdates: AnyPublisher<Profile?, Never>
    let currentTab: (BrowserWindowState) -> Tab?
    let deleteProfile: (Profile) -> Void
    let scheduleRuntimeStatePersistence: (Tab) -> Void
    let makePermissionRepository: () -> SumiPermissionSettingsRepository
    let dataRecoveryActions: SumiDataRecoveryActions
}
