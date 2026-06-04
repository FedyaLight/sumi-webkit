//
//  FloatingBarMotionPolicy.swift
//  Sumi
//
//

import SwiftUI

enum FloatingBarMotionPolicy {
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

struct FloatingBarSearchModeConfirmation: Identifiable {
    let id = UUID()
    let color: Color
}

struct FloatingBarSearchModeConfirmationView: View {
    let confirmation: FloatingBarSearchModeConfirmation
    let progress: CGFloat

    var body: some View {
        let remainingOpacity = max(0, min(1, Double(1 - progress)))
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(confirmation.color.opacity(0.42 * remainingOpacity), lineWidth: 1.2)
            .padding(0.5)
            .id(confirmation.id)
    }
}

struct FloatingBarLocalVignetteModifier: ViewModifier {
    let chromeScheme: ColorScheme
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .shadow(color: Color.black.opacity(0.165), radius: 16, x: 0, y: 8)
        } else {
            switch chromeScheme {
            case .light:
                content
                    .shadow(color: Color.black.opacity(0.14), radius: 22, x: 0, y: 10)
                    .shadow(color: Color.black.opacity(0.05), radius: 7, x: 0, y: 2)
            case .dark:
                content
                    .shadow(color: Color.black.opacity(0.30), radius: 22, x: 0, y: 10)
            @unknown default:
                content
                    .shadow(color: Color.black.opacity(0.14), radius: 22, x: 0, y: 10)
            }
        }
    }
}
