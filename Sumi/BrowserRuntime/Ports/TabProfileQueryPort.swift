import Foundation

@MainActor
protocol TabProfileQueryPort {
    var currentProfileId: UUID? { get }
    var defaultProfileId: UUID? { get }
    var settings: SumiSettingsService? { get }

    func profileExists(_ profileId: UUID) -> Bool
    func profile(with profileId: UUID) -> Profile?
}

@MainActor
struct LiveTabProfileQueryPort: TabProfileQueryPort {
    private let runtime: BrowserManagerRuntimeReference

    init(runtime: BrowserManagerRuntimeReference) {
        self.runtime = runtime
    }

    var currentProfileId: UUID? {
        runtime.require().currentProfile?.id
    }

    var defaultProfileId: UUID? {
        let browserManager = runtime.require()
        return browserManager.currentProfile?.id ?? browserManager.profileManager.profiles.first?.id
    }

    var settings: SumiSettingsService? {
        runtime.require().sumiSettings
    }

    func profileExists(_ profileId: UUID) -> Bool {
        runtime.require().profileManager.profiles.contains { $0.id == profileId }
    }

    func profile(with profileId: UUID) -> Profile? {
        runtime.require().profileManager.profiles.first { $0.id == profileId }
    }
}
