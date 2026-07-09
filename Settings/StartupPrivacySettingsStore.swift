//
//  StartupPrivacySettingsStore.swift
//  Sumi
//

import Foundation
import SumiDomain

@MainActor
@Observable
final class StartupPrivacySettingsStore {
    private let userDefaults: UserDefaults
    private let startupModeKey: String
    private let startupPageURLStringKey: String
    private let browsingDataRetentionDaysKey: String
    private let gpcEnabledKey: String

    var startupMode: SumiStartupMode {
        didSet {
            Persisted.rawRepresentable(startupMode, key: startupModeKey, defaults: userDefaults)
        }
    }

    var startupPageURLString: String {
        didSet {
            Persisted.string(startupPageURLString, key: startupPageURLStringKey, defaults: userDefaults)
        }
    }

    var browsingDataRetentionPeriod: SumiBrowsingDataRetentionPeriod {
        didSet {
            Persisted.rawRepresentable(
                browsingDataRetentionPeriod,
                key: browsingDataRetentionDaysKey,
                defaults: userDefaults
            )
            NotificationCenter.default.post(
                name: .sumiBrowsingDataRetentionChanged,
                object: nil,
                userInfo: ["days": browsingDataRetentionPeriod.rawValue]
            )
        }
    }

    /// Global Privacy Control: broadcasts the user's opt-out of sale/sharing of
    /// personal data to every site, via both a DOM signal and a `Sec-GPC` request
    /// header. On by default, matching Firefox/Brave/DDG's stance that GPC is a
    /// baseline privacy signal rather than an opt-in feature.
    var isGPCEnabled: Bool {
        didSet {
            Persisted.bool(isGPCEnabled, key: gpcEnabledKey, defaults: userDefaults)
        }
    }

    var resolvedStartupPageURL: URL {
        SumiStartupPageURL.runtimeURL(from: startupPageURLString)
    }

    init(
        userDefaults: UserDefaults,
        startupModeKey: String,
        startupPageURLStringKey: String,
        browsingDataRetentionDaysKey: String,
        gpcEnabledKey: String
    ) {
        self.userDefaults = userDefaults
        self.startupModeKey = startupModeKey
        self.startupPageURLStringKey = startupPageURLStringKey
        self.browsingDataRetentionDaysKey = browsingDataRetentionDaysKey
        self.gpcEnabledKey = gpcEnabledKey

        let storedStartupMode = userDefaults.string(forKey: startupModeKey)
        let resolvedStartupMode = SumiStartupMode.persistedValue(storedStartupMode)
        self.startupMode = resolvedStartupMode
        if storedStartupMode != resolvedStartupMode.rawValue {
            Persisted.rawRepresentable(resolvedStartupMode, key: startupModeKey, defaults: userDefaults)
        }
        self.startupPageURLString =
            userDefaults.string(forKey: startupPageURLStringKey)
            ?? SumiStartupPageURL.defaultURLString
        let storedBrowsingDataRetentionDays = userDefaults.object(
            forKey: browsingDataRetentionDaysKey
        ) as? Int
        let resolvedBrowsingDataRetentionPeriod = SumiBrowsingDataRetentionPeriod.persistedValue(
            storedBrowsingDataRetentionDays
        )
        self.browsingDataRetentionPeriod = resolvedBrowsingDataRetentionPeriod
        if storedBrowsingDataRetentionDays != resolvedBrowsingDataRetentionPeriod.rawValue {
            Persisted.rawRepresentable(
                resolvedBrowsingDataRetentionPeriod,
                key: browsingDataRetentionDaysKey,
                defaults: userDefaults
            )
        }
        if userDefaults.object(forKey: gpcEnabledKey) == nil {
            self.isGPCEnabled = true
        } else {
            self.isGPCEnabled = userDefaults.bool(forKey: gpcEnabledKey)
        }
    }
}
