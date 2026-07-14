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
    private let currentProfileAuthority: BrowserCurrentProfileAuthority
    private let profileManager: ProfileManager
    private let settingsAttachment: BrowserSettingsAttachmentCoordinator

    init(
        currentProfileAuthority: BrowserCurrentProfileAuthority,
        profileManager: ProfileManager,
        settingsAttachment: BrowserSettingsAttachmentCoordinator
    ) {
        self.currentProfileAuthority = currentProfileAuthority
        self.profileManager = profileManager
        self.settingsAttachment = settingsAttachment
    }

    var currentProfileId: UUID? {
        currentProfileAuthority.currentProfile?.id
    }

    var defaultProfileId: UUID? {
        currentProfileAuthority.currentProfile?.id ?? profileManager.profiles.first?.id
    }

    var settings: SumiSettingsService? {
        settingsAttachment.settings
    }

    func profileExists(_ profileId: UUID) -> Bool {
        profileManager.profiles.contains { $0.id == profileId }
    }

    func profile(with profileId: UUID) -> Profile? {
        profileManager.profiles.first { $0.id == profileId }
    }
}
