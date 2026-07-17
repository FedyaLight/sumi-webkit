import Foundation

@MainActor
final class BrowserBackgroundMediaEnergyPolicy {
    private let settings: BrowserSettingsAttachmentCoordinator

    init(settings: BrowserSettingsAttachmentCoordinator) {
        self.settings = settings
    }

    func isEnergySaverActive() -> Bool {
        settings.settings?.energySaverActivation.isActive ?? false
    }
}
