import Foundation
import PrivacyConfig

enum SumiPrivacyFeature: String {
    case contentBlocking
}

protocol SumiPrivacyConfiguration {
    func isEnabled(featureKey: SumiPrivacyFeature, defaultValue: Bool) -> Bool
}

extension SumiPrivacyConfiguration {
    func isEnabled(featureKey: SumiPrivacyFeature, defaultValue: Bool = false) -> Bool {
        isEnabled(featureKey: featureKey, defaultValue: defaultValue)
    }
}

final class SumiContentBlockingPrivacyConfigurationManager: PrivacyConfigurationManaging {
    private let lock = NSLock()
    private var configuration: SumiContentBlockingPrivacyConfiguration

    init(isContentBlockingEnabled: Bool) {
        configuration = SumiContentBlockingPrivacyConfiguration(
            isContentBlockingEnabled: isContentBlockingEnabled
        )
    }

    var sumiPrivacyConfig: any SumiPrivacyConfiguration {
        lock.lock()
        let configuration = configuration
        lock.unlock()
        return configuration
    }

    var privacyConfig: any PrivacyConfiguration {
        lock.lock()
        let configuration = configuration
        lock.unlock()
        return configuration
    }

    func setContentBlockingEnabled(_ isEnabled: Bool) {
        lock.lock()
        let current = configuration
        guard current.isContentBlockingEnabled != isEnabled else {
            lock.unlock()
            return
        }
        configuration = SumiContentBlockingPrivacyConfiguration(isContentBlockingEnabled: isEnabled)
        lock.unlock()
    }
}

struct SumiContentBlockingPrivacyConfiguration: SumiPrivacyConfiguration, PrivacyConfiguration {
    let isContentBlockingEnabled: Bool

    func isEnabled(featureKey: SumiPrivacyFeature, defaultValue: Bool) -> Bool {
        _ = defaultValue
        return featureKey == .contentBlocking ? isContentBlockingEnabled : false
    }

    func isEnabled(featureKey: PrivacyFeature, defaultValue: Bool) -> Bool {
        _ = defaultValue
        return featureKey == .contentBlocking ? isContentBlockingEnabled : false
    }

}
