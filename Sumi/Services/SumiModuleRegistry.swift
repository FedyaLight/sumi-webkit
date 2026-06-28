import Foundation

enum SumiModuleID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case extensions
    case userScripts

    var id: String {
        rawValue
    }
}

@MainActor
final class SumiModuleSettingsStore {
    static let standard = SumiModuleSettingsStore(userDefaults: .standard)

    let userDefaults: UserDefaults

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

@MainActor
final class SumiModuleRegistry {
    static let shared = SumiModuleRegistry()

    private let settingsStore: SumiModuleSettingsStore

    var userDefaults: UserDefaults {
        settingsStore.userDefaults
    }

    init(settingsStore: SumiModuleSettingsStore = .standard) {
        self.settingsStore = settingsStore
    }

    func isEnabled(_ moduleID: SumiModuleID) -> Bool {
        settingsStore.isEnabled(moduleID)
    }

    func setEnabled(_ isEnabled: Bool, for moduleID: SumiModuleID) {
        settingsStore.setEnabled(isEnabled, for: moduleID)
    }

    func enable(_ moduleID: SumiModuleID) {
        setEnabled(true, for: moduleID)
    }

    func disable(_ moduleID: SumiModuleID) {
        setEnabled(false, for: moduleID)
    }
}
