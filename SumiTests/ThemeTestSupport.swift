import Foundation

@testable import Sumi

struct TestDefaultsHarness {
    let suiteName = "SumiTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
    }

    func reset() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
