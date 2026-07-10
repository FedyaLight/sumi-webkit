import Combine
import Foundation
import SumiDomain

@MainActor
final class SumiProtectionSettings: ObservableObject {
    private enum DefaultsKey {
        static let level = "settings.protection.level"
        static let appliedLevel = "settings.protection.appliedLevel"
        static let browserRestartRequired = "settings.protection.browserRestartRequired"
    }

    @Published private(set) var level: SumiProtectionLevel {
        didSet {
            userDefaults.set(level.rawValue, forKey: DefaultsKey.level)
            changesSubject.send(())
        }
    }

    @Published private(set) var appliedLevel: SumiProtectionLevel {
        didSet {
            userDefaults.set(appliedLevel.rawValue, forKey: DefaultsKey.appliedLevel)
            changesSubject.send(())
        }
    }

    @Published private(set) var browserRestartRequired: Bool {
        didSet {
            userDefaults.set(browserRestartRequired, forKey: DefaultsKey.browserRestartRequired)
            changesSubject.send(())
        }
    }

    private let userDefaults: UserDefaults
    private let changesSubject = PassthroughSubject<Void, Never>()

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let rawLevel = userDefaults.string(forKey: DefaultsKey.level)
        let resolvedLevel = rawLevel.flatMap(SumiProtectionLevel.init(rawValue:)) ?? .off
        if rawLevel != resolvedLevel.rawValue {
            userDefaults.set(resolvedLevel.rawValue, forKey: DefaultsKey.level)
        }
        level = resolvedLevel
        browserRestartRequired = userDefaults.bool(forKey: DefaultsKey.browserRestartRequired)

        let rawAppliedLevel = userDefaults.string(forKey: DefaultsKey.appliedLevel)
        let resolvedAppliedLevel = rawAppliedLevel.flatMap(SumiProtectionLevel.init(rawValue:)) ?? resolvedLevel
        appliedLevel = resolvedAppliedLevel
        if rawAppliedLevel != resolvedAppliedLevel.rawValue {
            userDefaults.set(resolvedAppliedLevel.rawValue, forKey: DefaultsKey.appliedLevel)
        }
    }

    func setLevel(_ level: SumiProtectionLevel) {
        guard self.level != level else { return }
        self.level = level
    }

    func setAppliedLevel(_ level: SumiProtectionLevel) {
        guard appliedLevel != level else { return }
        appliedLevel = level
    }

    func setBrowserRestartRequired(_ isRequired: Bool) {
        guard browserRestartRequired != isRequired else { return }
        browserRestartRequired = isRequired
    }
}
