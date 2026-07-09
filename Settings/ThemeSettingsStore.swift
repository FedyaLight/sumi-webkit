//
//  ThemeSettingsStore.swift
//  Sumi
//

import Foundation

@MainActor
@Observable
final class ThemeSettingsStore {
    private let userDefaults: UserDefaults
    private let windowSchemeModeKey: String
    private let themeUseSystemColorsKey: String
    private let themeBorderRadiusKey: String
    private let darkThemeStyleKey: String

    var windowSchemeMode: WindowSchemeMode {
        didSet {
            Persisted.rawRepresentable(windowSchemeMode, key: windowSchemeModeKey, defaults: userDefaults)
        }
    }

    var themeUseSystemColors: Bool {
        didSet {
            Persisted.bool(themeUseSystemColors, key: themeUseSystemColorsKey, defaults: userDefaults)
        }
    }

    var themeBorderRadius: Int {
        didSet {
            Persisted.int(themeBorderRadius, key: themeBorderRadiusKey, defaults: userDefaults)
        }
    }

    var darkThemeStyle: DarkThemeStyle {
        didSet {
            Persisted.rawRepresentable(darkThemeStyle, key: darkThemeStyleKey, defaults: userDefaults)
        }
    }

    func resolvedCornerRadius(_ fallback: CGFloat) -> CGFloat {
        themeBorderRadius == -1 ? fallback : CGFloat(themeBorderRadius)
    }

    init(
        userDefaults: UserDefaults,
        windowSchemeModeKey: String,
        themeUseSystemColorsKey: String,
        themeBorderRadiusKey: String,
        darkThemeStyleKey: String
    ) {
        self.userDefaults = userDefaults
        self.windowSchemeModeKey = windowSchemeModeKey
        self.themeUseSystemColorsKey = themeUseSystemColorsKey
        self.themeBorderRadiusKey = themeBorderRadiusKey
        self.darkThemeStyleKey = darkThemeStyleKey

        self.windowSchemeMode = WindowSchemeMode(
            rawValue: userDefaults.string(forKey: windowSchemeModeKey) ?? WindowSchemeMode.auto.rawValue
        ) ?? .auto
        self.themeUseSystemColors = userDefaults.bool(forKey: themeUseSystemColorsKey)
        let storedBorderRadius = userDefaults.integer(forKey: themeBorderRadiusKey)
        self.themeBorderRadius = userDefaults.object(forKey: themeBorderRadiusKey) == nil
            ? -1
            : storedBorderRadius
        self.darkThemeStyle = DarkThemeStyle(
            rawValue: userDefaults.string(forKey: darkThemeStyleKey) ?? DarkThemeStyle.default.rawValue
        ) ?? .default
    }
}
