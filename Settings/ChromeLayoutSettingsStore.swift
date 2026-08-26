//
//  ChromeLayoutSettingsStore.swift
//  Sumi
//

import Foundation
import SumiDomain

@MainActor
@Observable
final class ChromeLayoutSettingsStore {
    private let userDefaults: UserDefaults
    private let askBeforeQuitKey: String
    private let sidebarPositionKey: String
    private let sidebarMiniPlayerEnabledKey: String
    private let glanceEnabledKey: String
    private let showNewTabButtonInTabListKey: String
    private let tabListNewTabButtonPositionKey: String
    private let showUnloadedTabAppearanceKey: String
    private let showLinkStatusBarKey: String
    private let showBrowserToastsKey: String
    private let framelessChromeKey: String
    private let newTabModeKey: String
    private let newTabPageURLStringKey: String
    private let openBookmarksAndHistoryInNewTabKey: String
    private let didFinishOnboardingKey: String

    private let onSidebarMiniPlayerEnabledChanged: (Bool) -> Void

    var askBeforeQuit: Bool {
        didSet {
            Persisted.bool(askBeforeQuit, key: askBeforeQuitKey, defaults: userDefaults)
        }
    }

    var sidebarPosition: SidebarPosition {
        didSet {
            Persisted.rawRepresentable(sidebarPosition, key: sidebarPositionKey, defaults: userDefaults)
        }
    }

    var sidebarMiniPlayerEnabled: Bool {
        didSet {
            Persisted.bool(
                sidebarMiniPlayerEnabled,
                key: sidebarMiniPlayerEnabledKey,
                defaults: userDefaults
            )
            onSidebarMiniPlayerEnabledChanged(sidebarMiniPlayerEnabled)
        }
    }

    var glanceEnabled: Bool {
        didSet {
            Persisted.bool(glanceEnabled, key: glanceEnabledKey, defaults: userDefaults)
        }
    }

    var showNewTabButtonInTabList: Bool {
        didSet {
            Persisted.bool(
                showNewTabButtonInTabList,
                key: showNewTabButtonInTabListKey,
                defaults: userDefaults
            )
        }
    }

    var tabListNewTabButtonPosition: TabListNewTabButtonPosition {
        didSet {
            Persisted.rawRepresentable(
                tabListNewTabButtonPosition,
                key: tabListNewTabButtonPositionKey,
                defaults: userDefaults
            )
        }
    }

    var showUnloadedTabAppearance: Bool {
        didSet {
            Persisted.bool(
                showUnloadedTabAppearance,
                key: showUnloadedTabAppearanceKey,
                defaults: userDefaults
            )
        }
    }

    var showLinkStatusBar: Bool {
        didSet {
            Persisted.bool(showLinkStatusBar, key: showLinkStatusBarKey, defaults: userDefaults)
        }
    }

    var showInAppNotifications: Bool {
        didSet {
            Persisted.bool(showInAppNotifications, key: showBrowserToastsKey, defaults: userDefaults)
        }
    }

    /// Removes the side and bottom window frame around web content, extending
    /// it edge-to-edge while keeping the top bar gap and the sidebar.
    var framelessChrome: Bool {
        didSet {
            Persisted.bool(framelessChrome, key: framelessChromeKey, defaults: userDefaults)
        }
    }

    var newTabMode: SumiNewTabMode {
        didSet {
            Persisted.rawRepresentable(newTabMode, key: newTabModeKey, defaults: userDefaults)
        }
    }

    var newTabPageURLString: String {
        didSet {
            Persisted.string(newTabPageURLString, key: newTabPageURLStringKey, defaults: userDefaults)
        }
    }

    var openBookmarksAndHistoryInNewTab: Bool {
        didSet {
            Persisted.bool(
                openBookmarksAndHistoryInNewTab,
                key: openBookmarksAndHistoryInNewTabKey,
                defaults: userDefaults
            )
        }
    }

    var resolvedNewTabPageURL: URL {
        SumiNewTabPageURL.runtimeURL(from: newTabPageURLString)
    }

    var didFinishOnboarding: Bool {
        didSet {
            Persisted.bool(didFinishOnboarding, key: didFinishOnboardingKey, defaults: userDefaults)
        }
    }

    init(
        userDefaults: UserDefaults,
        askBeforeQuitKey: String,
        sidebarPositionKey: String,
        sidebarMiniPlayerEnabledKey: String,
        glanceEnabledKey: String,
        showNewTabButtonInTabListKey: String,
        tabListNewTabButtonPositionKey: String,
        showUnloadedTabAppearanceKey: String,
        showLinkStatusBarKey: String,
        showBrowserToastsKey: String,
        framelessChromeKey: String,
        newTabModeKey: String,
        newTabPageURLStringKey: String,
        openBookmarksAndHistoryInNewTabKey: String,
        didFinishOnboardingKey: String,
        onSidebarMiniPlayerEnabledChanged: @escaping (Bool) -> Void
    ) {
        self.userDefaults = userDefaults
        self.askBeforeQuitKey = askBeforeQuitKey
        self.sidebarPositionKey = sidebarPositionKey
        self.sidebarMiniPlayerEnabledKey = sidebarMiniPlayerEnabledKey
        self.glanceEnabledKey = glanceEnabledKey
        self.showNewTabButtonInTabListKey = showNewTabButtonInTabListKey
        self.tabListNewTabButtonPositionKey = tabListNewTabButtonPositionKey
        self.showUnloadedTabAppearanceKey = showUnloadedTabAppearanceKey
        self.showLinkStatusBarKey = showLinkStatusBarKey
        self.showBrowserToastsKey = showBrowserToastsKey
        self.framelessChromeKey = framelessChromeKey
        self.newTabModeKey = newTabModeKey
        self.newTabPageURLStringKey = newTabPageURLStringKey
        self.openBookmarksAndHistoryInNewTabKey = openBookmarksAndHistoryInNewTabKey
        self.didFinishOnboardingKey = didFinishOnboardingKey
        self.onSidebarMiniPlayerEnabledChanged = onSidebarMiniPlayerEnabledChanged

        self.askBeforeQuit = userDefaults.bool(forKey: askBeforeQuitKey)
        self.sidebarPosition = SidebarPosition(
            rawValue: userDefaults.string(forKey: sidebarPositionKey) ?? "left"
        ) ?? SidebarPosition.left
        if userDefaults.object(forKey: sidebarMiniPlayerEnabledKey) == nil {
            self.sidebarMiniPlayerEnabled = true
        } else {
            self.sidebarMiniPlayerEnabled = userDefaults.bool(forKey: sidebarMiniPlayerEnabledKey)
        }
        if userDefaults.object(forKey: glanceEnabledKey) == nil {
            self.glanceEnabled = true
        } else {
            self.glanceEnabled = userDefaults.bool(forKey: glanceEnabledKey)
        }
        if userDefaults.object(forKey: showNewTabButtonInTabListKey) == nil {
            self.showNewTabButtonInTabList = true
        } else {
            self.showNewTabButtonInTabList = userDefaults.bool(forKey: showNewTabButtonInTabListKey)
        }
        self.tabListNewTabButtonPosition = TabListNewTabButtonPosition(
            rawValue: userDefaults.string(forKey: tabListNewTabButtonPositionKey)
                ?? TabListNewTabButtonPosition.bottom.rawValue
        ) ?? .bottom
        self.showUnloadedTabAppearance = userDefaults.bool(
            forKey: showUnloadedTabAppearanceKey
        )
        self.showLinkStatusBar = userDefaults.bool(forKey: showLinkStatusBarKey)
        self.showInAppNotifications = userDefaults.bool(forKey: showBrowserToastsKey)
        self.framelessChrome = userDefaults.bool(forKey: framelessChromeKey)
        let storedNewTabMode = userDefaults.string(forKey: newTabModeKey)
        let resolvedNewTabMode = SumiNewTabMode.persistedValue(storedNewTabMode)
        self.newTabMode = resolvedNewTabMode
        if storedNewTabMode != resolvedNewTabMode.rawValue {
            Persisted.rawRepresentable(resolvedNewTabMode, key: newTabModeKey, defaults: userDefaults)
        }
        self.newTabPageURLString =
            userDefaults.string(forKey: newTabPageURLStringKey)
            ?? SumiNewTabPageURL.defaultURLString
        self.openBookmarksAndHistoryInNewTab = userDefaults.bool(
            forKey: openBookmarksAndHistoryInNewTabKey
        )
        self.didFinishOnboarding = userDefaults.bool(forKey: didFinishOnboardingKey)
    }

    func enforceSumiChromeDefaults() {
        if !didFinishOnboarding {
            didFinishOnboarding = true
        }
    }
}
