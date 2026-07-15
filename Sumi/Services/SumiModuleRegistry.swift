import Foundation

enum SumiModuleID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case extensions
    case boosts
    case liveFolders

    var id: String {
        rawValue
    }
}

@MainActor
final class SumiModuleSettingsStore {
    let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
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
    enum Availability: Equatable {
        case available
        case unavailable
    }

    private let settingsStore: SumiModuleSettingsStore
    private let availability: Availability

    var userDefaults: UserDefaults {
        settingsStore.userDefaults
    }

    init(
        settingsStore: SumiModuleSettingsStore,
        availability: Availability = .available
    ) {
        self.settingsStore = settingsStore
        self.availability = availability
    }

    static func unavailable() -> SumiModuleRegistry {
        SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(
                    suiteName: "Sumi.UnavailableModules.\(UUID().uuidString)"
                )!
            ),
            availability: .unavailable
        )
    }

    func isEnabled(_ moduleID: SumiModuleID) -> Bool {
        guard availability == .available else { return false }
        return settingsStore.isEnabled(moduleID)
    }

    /// Runtime-only compatibility for isolated/test composition. An
    /// unavailable registry means there is no product toggle authority, so a
    /// runtime that was explicitly constructed remains admissible. Product
    /// composition always supplies an available registry and follows its
    /// durable toggle.
    func isEnabledForRuntimeBoundary(_ moduleID: SumiModuleID) -> Bool {
        switch availability {
        case .available:
            return settingsStore.isEnabled(moduleID)
        case .unavailable:
            return true
        }
    }

    var isAvailable: Bool {
        availability == .available
    }

    func setEnabled(_ isEnabled: Bool, for moduleID: SumiModuleID) {
        guard availability == .available else { return }
        settingsStore.setEnabled(isEnabled, for: moduleID)
    }

    func enable(_ moduleID: SumiModuleID) {
        setEnabled(true, for: moduleID)
    }

    func disable(_ moduleID: SumiModuleID) {
        setEnabled(false, for: moduleID)
    }
}
