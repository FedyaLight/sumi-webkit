//
//  CommandPaletteMotionPolicy.swift
//  Sumi
//
//

import AppKit
import QuartzCore
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

}

struct CommandPaletteSearchModeConfirmation: Identifiable {
    let id = UUID()
    let color: Color
}

struct CommandPaletteSearchModeConfirmationView: View {
    let confirmation: CommandPaletteSearchModeConfirmation

    var body: some View {
        CommandPaletteSearchModeGlowView(confirmation: confirmation)
            .allowsHitTesting(false)
    }
}

struct CommandPaletteSearchModeConfirmationModifier: ViewModifier {
    let confirmation: CommandPaletteSearchModeConfirmation?
    @State private var cardScale: CGFloat = 1
    @State private var glowConfirmation:
        CommandPaletteSearchModeConfirmation?

    func body(content: Content) -> some View {
        content
            .scaleEffect(cardScale)
            .overlay {
                if let glowConfirmation {
                    CommandPaletteSearchModeConfirmationView(
                        confirmation: glowConfirmation
                    )
                }
            }
            .task(id: confirmation?.id) {
                guard let confirmation else {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        cardScale = 1
                        glowConfirmation = nil
                    }
                    return
                }

                glowConfirmation = confirmation
                withAnimation(.easeIn(duration: 0.125)) {
                    cardScale = 0.98
                }
                try? await Task.sleep(nanoseconds: 125_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.125)) {
                    cardScale = 1
                }
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled else { return }
                glowConfirmation = nil
            }
    }
}

private struct CommandPaletteSearchModeGlowView: NSViewRepresentable {
    let confirmation: CommandPaletteSearchModeConfirmation

    func makeNSView(context _: Context) -> CommandPaletteSearchModeGlowNSView {
        CommandPaletteSearchModeGlowNSView()
    }

    func updateNSView(
        _ nsView: CommandPaletteSearchModeGlowNSView,
        context _: Context
    ) {
        nsView.present(confirmation)
    }
}

private final class CommandPaletteSearchModeGlowNSView: NSView {
    private let glowLayer = CALayer()
    private var presentedID: UUID?
    private var pendingConfirmation: CommandPaletteSearchModeConfirmation?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        glowLayer.masksToBounds = false
        glowLayer.backgroundColor =
            NSColor.white.withAlphaComponent(0.01).cgColor
        layer?.addSublayer(glowLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        glowLayer.frame = bounds
        glowLayer.cornerRadius =
            ChromeLayoutTokens.commandPaletteCornerRadius
        glowLayer.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: ChromeLayoutTokens.commandPaletteCornerRadius,
            cornerHeight: ChromeLayoutTokens.commandPaletteCornerRadius,
            transform: nil
        )
        playPendingConfirmationIfPossible()
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    func present(_ confirmation: CommandPaletteSearchModeConfirmation) {
        guard confirmation.id != presentedID else { return }
        pendingConfirmation = confirmation
        needsLayout = true
        layoutSubtreeIfNeeded()
        playPendingConfirmationIfPossible()
    }

    private func playPendingConfirmationIfPossible() {
        guard !bounds.isEmpty,
              let confirmation = pendingConfirmation,
              confirmation.id != presentedID
        else { return }

        pendingConfirmation = nil
        presentedID = confirmation.id
        glowLayer.shadowColor = NSColor(confirmation.color).cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowLayer.shadowRadius = 250
        glowLayer.shadowOpacity = 0
        glowLayer.shadowOffset = .zero
        CATransaction.commit()

        let radius = CABasicAnimation(keyPath: "shadowRadius")
        radius.fromValue = 20
        radius.toValue = 250

        let opacity = CABasicAnimation(keyPath: "shadowOpacity")
        opacity.fromValue = 0.48
        opacity.toValue = 0

        let group = CAAnimationGroup()
        group.animations = [radius, opacity]
        group.duration = 1
        group.timingFunction = CAMediaTimingFunction(
            name: .easeOut
        )
        group.isRemovedOnCompletion = true
        glowLayer.add(group, forKey: "search-mode-confirmation")
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
