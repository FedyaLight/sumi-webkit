import SwiftUI

enum SumiBoostEditorStyle {
    static func primaryBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#171717") : Color(hex: "#FCFCFE")
    }

    static func secondaryBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#1C1C1E") : Color(hex: "#F6F6F8")
    }

    static func buttonBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#262626") : Color(hex: "#EBEBED")
    }

    static func fontBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#262626") : Color.white
    }

    static func primaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#F3F3F3") : Color(hex: "#3A3A3B")
    }

    static func secondaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#B1B1B1") : Color(hex: "#727272")
    }

    static func border(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#3A3A3A") : Color(hex: "#EDEDEF")
    }
}
