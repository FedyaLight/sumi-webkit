import Combine
import Foundation

@MainActor
final class SumiProtectionBundleUpdateStatusStore: ObservableObject {
    private enum DefaultsKey {
        static let lastAttemptDate = "settings.protection.bundleUpdate.lastAttemptDate"
        static let lastSuccessDate = "settings.protection.bundleUpdate.lastSuccessDate"
        static let lastReleaseVersion = "settings.protection.bundleUpdate.lastReleaseVersion"
        static let lastBundleId = "settings.protection.bundleUpdate.lastBundleId"
        static let lastSummary = "settings.protection.bundleUpdate.lastSummary"
        static let lastFailureReason = "settings.protection.bundleUpdate.lastFailureReason"
        static let lastSignatureVerified = "settings.protection.bundleUpdate.lastSignatureVerified"
        static let lastSigningKeyId = "settings.protection.bundleUpdate.lastSigningKeyId"
        static let lastSigningKeyVersion = "settings.protection.bundleUpdate.lastSigningKeyVersion"
        static let lastSignatureError = "settings.protection.bundleUpdate.lastSignatureError"
        static let lastDowngradeRejected = "settings.protection.bundleUpdate.lastDowngradeRejected"
    }

    @Published private(set) var lastAttemptDate: Date?
    @Published private(set) var lastSuccessDate: Date?
    @Published private(set) var lastReleaseVersion: String?
    @Published private(set) var lastBundleId: String?
    @Published private(set) var lastSummary: String?
    @Published private(set) var lastFailureReason: String?
    @Published private(set) var lastSignatureVerified: Bool?
    @Published private(set) var lastSigningKeyId: String?
    @Published private(set) var lastSigningKeyVersion: Int?
    @Published private(set) var lastSignatureError: String?
    @Published private(set) var lastDowngradeRejected: Bool?

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        lastAttemptDate = userDefaults.object(forKey: DefaultsKey.lastAttemptDate) as? Date
        lastSuccessDate = userDefaults.object(forKey: DefaultsKey.lastSuccessDate) as? Date
        lastReleaseVersion = userDefaults.string(forKey: DefaultsKey.lastReleaseVersion)
        lastBundleId = userDefaults.string(forKey: DefaultsKey.lastBundleId)
        lastSummary = userDefaults.string(forKey: DefaultsKey.lastSummary)
        lastFailureReason = userDefaults.string(forKey: DefaultsKey.lastFailureReason)
        if userDefaults.object(forKey: DefaultsKey.lastSignatureVerified) != nil {
            lastSignatureVerified = userDefaults.bool(forKey: DefaultsKey.lastSignatureVerified)
        }
        lastSigningKeyId = userDefaults.string(forKey: DefaultsKey.lastSigningKeyId)
        if userDefaults.object(forKey: DefaultsKey.lastSigningKeyVersion) != nil {
            lastSigningKeyVersion = userDefaults.integer(forKey: DefaultsKey.lastSigningKeyVersion)
        }
        lastSignatureError = userDefaults.string(forKey: DefaultsKey.lastSignatureError)
        if userDefaults.object(forKey: DefaultsKey.lastDowngradeRejected) != nil {
            lastDowngradeRejected = userDefaults.bool(forKey: DefaultsKey.lastDowngradeRejected)
        }
    }

    func recordSuccess(_ outcome: SumiProtectionBundleManualUpdateOutcome, date: Date = Date()) {
        lastAttemptDate = date
        lastSuccessDate = date
        lastReleaseVersion = outcome.releaseVersion
        lastBundleId = outcome.bundleId
        lastSummary = outcome.summary
        lastFailureReason = nil
        lastSignatureVerified = outcome.manifestSignatureVerified
        lastSigningKeyId = outcome.signingKeyId
        lastSigningKeyVersion = outcome.signingKeyVersion
        lastSignatureError = nil
        lastDowngradeRejected = false
        persist()
    }

    func recordFailure(_ error: Error, date: Date = Date()) {
        lastAttemptDate = date
        lastSummary = nil
        lastFailureReason = error.localizedDescription
        lastSignatureVerified = false
        if let signatureError = Self.signatureFailureSummary(error) {
            lastSignatureError = signatureError
        }
        lastDowngradeRejected = Self.isDowngradeRejection(error)
        persist()
    }

    private func persist() {
        setOrRemove(lastAttemptDate, forKey: DefaultsKey.lastAttemptDate)
        setOrRemove(lastSuccessDate, forKey: DefaultsKey.lastSuccessDate)
        setOrRemove(lastReleaseVersion, forKey: DefaultsKey.lastReleaseVersion)
        setOrRemove(lastBundleId, forKey: DefaultsKey.lastBundleId)
        setOrRemove(lastSummary, forKey: DefaultsKey.lastSummary)
        setOrRemove(lastFailureReason, forKey: DefaultsKey.lastFailureReason)
        setOrRemove(lastSignatureVerified, forKey: DefaultsKey.lastSignatureVerified)
        setOrRemove(lastSigningKeyId, forKey: DefaultsKey.lastSigningKeyId)
        setOrRemove(lastSigningKeyVersion, forKey: DefaultsKey.lastSigningKeyVersion)
        setOrRemove(lastSignatureError, forKey: DefaultsKey.lastSignatureError)
        setOrRemove(lastDowngradeRejected, forKey: DefaultsKey.lastDowngradeRejected)
    }

    private func setOrRemove(_ value: Any?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    private static func signatureFailureSummary(_ error: Error) -> String? {
        guard let remoteError = error as? SumiProtectionBundleRemoteUpdateError else { return nil }
        switch remoteError {
        case .releaseManifestSignatureAssetMissing,
             .signatureMetadataMalformed,
             .signatureAlgorithmUnsupported,
             .signatureKeyUnknown,
             .signaturePublicKeyInvalid,
             .signatureInvalid:
            return remoteError.localizedDescription
        default:
            return nil
        }
    }

    private static func isDowngradeRejection(_ error: Error) -> Bool {
        guard let remoteError = error as? SumiProtectionBundleRemoteUpdateError else { return false }
        if case .releaseDowngradeRejected = remoteError {
            return true
        }
        return false
    }
}
