import Foundation
import PrivacyConfig

enum SumiPrivacyFeature: String {
    case contentBlocking
}

protocol SumiPrivacySubfeature: RawRepresentable where RawValue == String {}

enum SumiBrowserConfigSubfeature: String, SumiPrivacySubfeature {
    case faviconWKDownload
}

protocol SumiPrivacyConfiguration {
    func isEnabled(featureKey: SumiPrivacyFeature, defaultValue: Bool) -> Bool
    func isSubfeatureEnabled(_ subfeature: any SumiPrivacySubfeature, defaultValue: Bool) -> Bool
}

extension SumiPrivacyConfiguration {
    func isEnabled(featureKey: SumiPrivacyFeature, defaultValue: Bool = false) -> Bool {
        isEnabled(featureKey: featureKey, defaultValue: defaultValue)
    }

    func isSubfeatureEnabled(_ subfeature: any SumiPrivacySubfeature, defaultValue: Bool = false) -> Bool {
        isSubfeatureEnabled(subfeature, defaultValue: defaultValue)
    }
}

protocol SumiPrivacyConfigurationManaging: AnyObject {
    var sumiPrivacyConfig: any SumiPrivacyConfiguration { get }
}

final class SumiContentBlockingPrivacyConfigurationManager: SumiPrivacyConfigurationManaging, PrivacyConfigurationManaging {
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

    func isSubfeatureEnabled(
        _ subfeature: any SumiPrivacySubfeature,
        defaultValue: Bool
    ) -> Bool {
        _ = subfeature
        return defaultValue
    }

    func isSubfeatureEnabled(
        _ subfeature: any PrivacySubfeature,
        defaultValue: Bool
    ) -> Bool {
        _ = subfeature
        return defaultValue
    }
}
