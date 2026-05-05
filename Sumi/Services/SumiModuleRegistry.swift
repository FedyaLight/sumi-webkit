import Foundation

enum SumiModuleID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case trackingProtection
    case adBlocking
    case extensions
    case userScripts

    var id: String {
        rawValue
    }
}

final class SumiModuleSettingsStore {
    static let standard = SumiModuleSettingsStore(userDefaults: .standard)

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func isEnabled(_ moduleID: SumiModuleID) -> Bool {
        userDefaults.bool(forKey: key(for: moduleID))
    }

    func setEnabled(_ isEnabled: Bool, for moduleID: SumiModuleID) {
        userDefaults.set(isEnabled, forKey: key(for: moduleID))
    }

    func key(for moduleID: SumiModuleID) -> String {
        "settings.modules.\(moduleID.rawValue).enabled"
    }
}

final class SumiModuleRegistry {
    static let shared = SumiModuleRegistry()

    private let settingsStore: SumiModuleSettingsStore

    init(settingsStore: SumiModuleSettingsStore = .standard) {
        self.settingsStore = settingsStore
    }

    func isEnabled(_ moduleID: SumiModuleID) -> Bool {
        settingsStore.isEnabled(moduleID)
    }

    func setEnabled(_ isEnabled: Bool, for moduleID: SumiModuleID) {
        settingsStore.setEnabled(isEnabled, for: moduleID)
    }

}
