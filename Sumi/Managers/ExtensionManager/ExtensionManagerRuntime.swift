import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerRuntime {
    typealias CurrentProfileProvider = @MainActor () -> Profile?
    typealias ProfileProvider = @MainActor (_ profileId: UUID) -> Profile?
    typealias EphemeralProfileProvider = @MainActor (_ profileId: UUID) -> Profile?
    typealias WindowStateProvider = @MainActor (_ windowId: UUID) -> BrowserWindowState?
    typealias ModuleEnabledProvider = @MainActor () -> Bool?

    let currentProfile: CurrentProfileProvider
    let profile: ProfileProvider
    let ephemeralProfile: EphemeralProfileProvider
    let windowState: WindowStateProvider
    let extensionsModuleEnabled: ModuleEnabledProvider

    static let inactive = ExtensionManagerRuntime(
        currentProfile: { nil },
        profile: { _ in nil },
        ephemeralProfile: { _ in nil },
        windowState: { _ in nil },
        extensionsModuleEnabled: { nil }
    )
}
