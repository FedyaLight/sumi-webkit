//
//  SettingsNavigationOwner.swift
//  Sumi
//

import Foundation

/// Owns transient navigation for the app's single Settings window.
/// Preference persistence remains in `SumiSettingsService`.
@MainActor
@Observable
final class SettingsNavigationOwner {
    var currentSettingsTab: SettingsTabs = .general
    var privacySettingsRoute: SumiPrivacySettingsRoute = .overview

    private var presentSettingsWindow: (() -> Void)?

    func installPresentationAction(_ action: @escaping () -> Void) {
        presentSettingsWindow = action
    }

    func openSettings(selecting pane: SettingsTabs) {
        currentSettingsTab = pane
        if pane == .privacy {
            privacySettingsRoute = .overview
        }
        presentSettingsWindow?()
    }

    func openSiteSettings(filter: SumiSettingsSiteSettingsFilter?) {
        currentSettingsTab = .privacy
        privacySettingsRoute = .siteSettings(filter)
        presentSettingsWindow?()
    }
}
