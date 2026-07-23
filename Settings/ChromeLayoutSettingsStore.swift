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
    private let showSidebarToggleButtonKey: String
    private let showNewTabButtonInTabListKey: String
    private let tabListNewTabButtonPositionKey: String
    private let showLinkStatusBarKey: String
    private let showBrowserToastsKey: String
    private let framelessChromeKey: String
    private let commandPaletteEmptyStateModeKey: String
    private let newTabModeKey: String
    private let newTabPageURLStringKey: String
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

    var showSidebarToggleButton: Bool {
        didSet {
            Persisted.bool(
                showSidebarToggleButton,
                key: showSidebarToggleButtonKey,
                defaults: userDefaults
            )
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

    var commandPaletteEmptyStateMode: CommandPaletteEmptyStateMode {
        didSet {
            Persisted.rawRepresentable(
                commandPaletteEmptyStateMode,
                key: commandPaletteEmptyStateModeKey,
                defaults: userDefaults
            )
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
        showSidebarToggleButtonKey: String,
        showNewTabButtonInTabListKey: String,
        tabListNewTabButtonPositionKey: String,
        showLinkStatusBarKey: String,
        showBrowserToastsKey: String,
        framelessChromeKey: String,
        commandPaletteEmptyStateModeKey: String,
        newTabModeKey: String,
        newTabPageURLStringKey: String,
        didFinishOnboardingKey: String,
        onSidebarMiniPlayerEnabledChanged: @escaping (Bool) -> Void
    ) {
        self.userDefaults = userDefaults
        self.askBeforeQuitKey = askBeforeQuitKey
        self.sidebarPositionKey = sidebarPositionKey
        self.sidebarMiniPlayerEnabledKey = sidebarMiniPlayerEnabledKey
        self.glanceEnabledKey = glanceEnabledKey
        self.showSidebarToggleButtonKey = showSidebarToggleButtonKey
        self.showNewTabButtonInTabListKey = showNewTabButtonInTabListKey
        self.tabListNewTabButtonPositionKey = tabListNewTabButtonPositionKey
        self.showLinkStatusBarKey = showLinkStatusBarKey
        self.showBrowserToastsKey = showBrowserToastsKey
        self.framelessChromeKey = framelessChromeKey
        self.commandPaletteEmptyStateModeKey = commandPaletteEmptyStateModeKey
        self.newTabModeKey = newTabModeKey
        self.newTabPageURLStringKey = newTabPageURLStringKey
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
        if userDefaults.object(forKey: showSidebarToggleButtonKey) == nil {
            self.showSidebarToggleButton = true
        } else {
            self.showSidebarToggleButton = userDefaults.bool(forKey: showSidebarToggleButtonKey)
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
        self.showLinkStatusBar = userDefaults.bool(forKey: showLinkStatusBarKey)
        self.showInAppNotifications = userDefaults.bool(forKey: showBrowserToastsKey)
        self.framelessChrome = userDefaults.bool(forKey: framelessChromeKey)
        self.commandPaletteEmptyStateMode = CommandPaletteEmptyStateMode(
            rawValue: userDefaults.string(forKey: commandPaletteEmptyStateModeKey)
                ?? CommandPaletteEmptyStateMode.compact.rawValue
        ) ?? .compact
        let storedNewTabMode = userDefaults.string(forKey: newTabModeKey)
        let resolvedNewTabMode = SumiNewTabMode.persistedValue(storedNewTabMode)
        self.newTabMode = resolvedNewTabMode
        if storedNewTabMode != resolvedNewTabMode.rawValue {
            Persisted.rawRepresentable(resolvedNewTabMode, key: newTabModeKey, defaults: userDefaults)
        }
        self.newTabPageURLString =
            userDefaults.string(forKey: newTabPageURLStringKey)
            ?? SumiNewTabPageURL.defaultURLString
        self.didFinishOnboarding = userDefaults.bool(forKey: didFinishOnboardingKey)
    }

    func enforceSumiChromeDefaults() {
        if !didFinishOnboarding {
            didFinishOnboarding = true
        }
    }
}
