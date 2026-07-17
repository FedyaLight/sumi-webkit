import Foundation

@MainActor
final class BrowserSettingsState {
    private weak var value: SumiSettingsService?

    var settings: SumiSettingsService? {
        value
    }

    func update(_ settings: SumiSettingsService?) {
        value = settings
    }
}
