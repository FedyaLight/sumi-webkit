import Combine
import Foundation
import SumiDomain

/// Browser projection consumed by the in-tab Settings surface.
/// Built by `WebsiteViewContextFactory`; Settings UI must not reach into the browser composition root.
@MainActor
struct SettingsBrowserContext {
    let profileManager: ProfileManager
    let tabManager: TabManager
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
