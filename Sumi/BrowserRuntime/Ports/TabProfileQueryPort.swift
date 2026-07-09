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
    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    var currentProfileId: UUID? {
        browserManager?.currentProfile?.id
    }

    var defaultProfileId: UUID? {
        browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
    }

    var settings: SumiSettingsService? {
        browserManager?.sumiSettings
    }

    func profileExists(_ profileId: UUID) -> Bool {
        guard let browserManager else { return true }
        return browserManager.profileManager.profiles.contains { $0.id == profileId }
    }

    func profile(with profileId: UUID) -> Profile? {
        browserManager?.profileManager.profiles.first { $0.id == profileId }
    }
}
