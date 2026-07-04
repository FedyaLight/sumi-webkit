import SwiftUI

enum SumiBoostEditorStyle {
    static let colorSpectrum: [Color] = [
        .red,
        .orange,
        .yellow,
        .green,
        .cyan,
        .blue,
        .purple,
        .pink,
        .red,
    ]

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

    static func canvasDotPattern(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color(hex: "#DCE4DE").opacity(0.9)
    }

    static func monochromeActiveBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white : Color(hex: "#3A3A3A")
    }

    static func monochromeInactiveBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#3A3A3A") : Color.white
    }

    static func monochromeIconForeground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#3A3A3A") : Color.white
    }

    static func fontGridShadow(for colorScheme: ColorScheme) -> Color {
        Color.black.opacity(colorScheme == .dark ? 0.34 : 0.16)
    }

    static let canvasShadow = Color.black.opacity(0.14)
    static let canvasGuideStroke = Color.gray.opacity(0.28)
    static let colorToolShadow = Color.black.opacity(0.08)
    static let colorDotBorder = Color.white
    static let colorDotShadow = Color.black.opacity(0.22)
    static let fontGridSelectionBackground = Color.primary.opacity(0.12)
    static let transparent = Color.clear
}

enum SumiBoostEditorTypography {
    static var actionTitle: Font { .system(size: 14, weight: .medium) }
    static var actionValue: Font { .system(size: 13, weight: .semibold) }
    static var actionIcon: Font { .system(size: 16, weight: .medium) }
    static var actionMonospaceTrailing: Font { .system(size: 17, weight: .semibold, design: .monospaced) }
    static var colorToolIcon: Font { .system(size: 12, weight: .bold) }
    static var iconButton: Font { .system(size: 17, weight: .medium) }
    static var advancedSliderLabel: Font { .system(size: 13, weight: .medium) }
    static var headerIcon: Font { .system(size: 19, weight: .semibold) }
    static var shuffleIcon: Font { .system(size: 18, weight: .semibold) }
    static var headerTitle: Font { .system(size: 13, weight: .semibold) }
    static var headerChevron: Font { .system(size: 8, weight: .semibold) }
    static var codeBackButton: Font { .system(size: 12, weight: .semibold) }
    static var codeEditor: Font { .system(size: 12, design: .monospaced) }
    static var menuItem: Font { .system(size: 13) }
    static var fontGridSample: CGFloat { 14 }
}
