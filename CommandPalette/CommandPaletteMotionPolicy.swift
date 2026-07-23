//
//  CommandPaletteMotionPolicy.swift
//  Sumi
//
//

import SwiftUI

enum CommandPaletteMotionPolicy {
    typealias Mode = SumiChromeMotionPolicy.Mode

    static func mode(reduceMotion: Bool, energySaverReducesMotion: Bool = false) -> Mode {
        SumiChromeMotionPolicy.currentMode(
            reduceMotion: reduceMotion,
            energySaverReducesMotion: energySaverReducesMotion
        )
    }

    static func chromeElementTransition(for mode: Mode) -> AnyTransition {
        guard mode == .standard else { return .identity }
        return .opacity
    }

    static func chromeContentAnimation(for mode: Mode) -> Animation? {
        guard mode == .standard else { return nil }
        return .smooth(duration: 0.24, extraBounce: 0)
    }

    static func microAffordanceAnimation(for mode: Mode) -> Animation? {
        guard mode == .standard else { return nil }
        return .easeOut(duration: 0.12)
    }

    static func searchModeConfirmationAnimation(for mode: Mode) -> Animation? {
        guard mode == .standard else { return nil }
        return .easeOut(duration: 0.18)
    }

    static func searchModeConfirmationLifetimeNanoseconds(for mode: Mode) -> UInt64? {
        guard mode == .standard else { return nil }
        return 180_000_000
    }
}

struct CommandPaletteSearchModeConfirmation: Identifiable {
    let id = UUID()
    let color: Color
}

struct CommandPaletteSearchModeConfirmationView: View {
    let confirmation: CommandPaletteSearchModeConfirmation
    let progress: CGFloat

    var body: some View {
        let remainingOpacity = max(0, min(1, Double(1 - progress)))
        RoundedRectangle(cornerRadius: ChromeLayoutTokens.commandPaletteCornerRadius, style: .continuous)
            .strokeBorder(confirmation.color.opacity(0.42 * remainingOpacity), lineWidth: 1.2)
            .padding(0.5)
            .id(confirmation.id)
    }
}

struct CommandPaletteLocalVignetteModifier: ViewModifier {
    let chromeScheme: ColorScheme
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .shadow(color: CommandPaletteThemeTokens.Colors.reducedTransparencyShadow, radius: 16, x: 0, y: 8)
        } else {
            switch chromeScheme {
            case .light:
                content
                    .shadow(color: CommandPaletteThemeTokens.Colors.localVignetteLightShadow, radius: 23, x: 0, y: 10)
            case .dark:
                content
                    .shadow(color: CommandPaletteThemeTokens.Colors.localVignetteDarkShadow, radius: 22, x: 0, y: 10)
            @unknown default:
                content
                    .shadow(color: CommandPaletteThemeTokens.Colors.localVignetteFallbackShadow, radius: 22, x: 0, y: 10)
            }
        }
    }
}
