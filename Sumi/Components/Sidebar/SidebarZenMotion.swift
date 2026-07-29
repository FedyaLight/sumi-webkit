//
//  SidebarZenMotion.swift
//  Sumi
//

import SwiftUI

enum SidebarRowMotionMetrics {
    static let pressedScale = SidebarMotionPolicy.rowPressedScale
}

enum SidebarDropMotion {
    static let contentLayoutDuration: Double = SidebarMotionPolicy.contentLayoutDuration
}

enum SidebarZenPressKind {
    case row
    case split

    var isSplit: Bool {
        switch self {
        case .row:
            return false
        case .split:
            return true
        }
    }
}

private struct SidebarZenPressEffectModifier: ViewModifier {
    enum Sources {
        case one(String)
        case any([String])
    }

    @Environment(SidebarInteractionState.self) private var sidebarInteractionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings

    let sources: Sources
    let kind: SidebarZenPressKind

    func body(content: Content) -> some View {
        let isPressed = !shouldReduceMotion
            && presentsPressVisual

        content
            .scaleEffect(isPressed ? SidebarRowMotionMetrics.pressedScale : 1)
            .animation(releaseAnimation(isPressed: isPressed), value: isPressed)
    }

    private var presentsPressVisual: Bool {
        switch sources {
        case .one(let sourceID):
            return sidebarInteractionState.presentsPressVisual(for: sourceID)
        case .any(let sourceIDs):
            return sidebarInteractionState.presentsPressVisual(
                forAny: sourceIDs
            )
        }
    }

    private func releaseAnimation(isPressed: Bool) -> Animation? {
        guard !isPressed, !shouldReduceMotion else { return nil }
        return SidebarMotionPolicy.rowReleaseAnimation(
            for: SidebarMotionPolicy.currentMode(reduceMotion: shouldReduceMotion),
            split: kind.isSplit
        )
    }

    private var shouldReduceMotion: Bool {
        reduceMotion || sumiSettings.shouldReduceChromeMotion
    }
}

private struct SidebarZenActionOpacityModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    let isVisible: Bool

    func body(content: Content) -> some View {
        content.animation(
            SidebarMotionPolicy.actionFadeAnimation(
                for: SidebarMotionPolicy.currentMode(reduceMotion: shouldReduceMotion)
            ),
            value: isVisible
        )
    }

    private var shouldReduceMotion: Bool {
        reduceMotion || sumiSettings.shouldReduceChromeMotion
    }
}

struct SidebarZenActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        SidebarZenActionButtonBody(
            configuration: configuration,
            isEnabled: isEnabled,
            reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
        )
    }
}

private struct SidebarZenActionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    let reduceMotion: Bool
    @State private var visualPressed = false

    var body: some View {
        let isPressed = configuration.isPressed && isEnabled && !reduceMotion

        configuration.label
            .scaleEffect(visualPressed ? SidebarRowMotionMetrics.pressedScale : 1)
            .onAppear {
                visualPressed = isPressed
            }
            .onChange(of: isPressed) { _, newValue in
                updateVisualPressed(newValue)
            }
            .onChange(of: reduceMotion) { _, _ in
                updateVisualPressed(isPressed)
            }
    }

    private func updateVisualPressed(_ isPressed: Bool) {
        if isPressed || reduceMotion || !isEnabled {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                visualPressed = isPressed
            }
            return
        }

        withAnimation(SidebarMotionPolicy.rowReleaseAnimation(
            for: SidebarMotionPolicy.currentMode(reduceMotion: reduceMotion),
            split: true
        )) {
            visualPressed = false
        }
    }
}

enum SidebarMotionTransaction {
    static func withoutAnimation<Result>(
        _ body: () throws -> Result
    ) rethrows -> Result {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        return try withTransaction(transaction, body)
    }
}

extension View {
    func sidebarZenPressEffect(
        sourceID: String,
        kind: SidebarZenPressKind = .row
    ) -> some View {
        modifier(
            SidebarZenPressEffectModifier(
                sources: .one(sourceID),
                kind: kind
            )
        )
    }

    func sidebarZenPressEffect(
        sourceIDs: [String],
        kind: SidebarZenPressKind = .row
    ) -> some View {
        modifier(
            SidebarZenPressEffectModifier(
                sources: .any(sourceIDs),
                kind: kind
            )
        )
    }

    /// Reproduces the geometry transform `sidebarZenPressEffect` leaves on a
    /// live sidebar item even at rest.
    ///
    /// A transform opts its subtree out of SwiftUI's pixel snapping, so its
    /// contents rasterize at their true fractional position. Essentials tiles
    /// are the one sidebar surface whose width is a fraction of a point
    /// (the content width is divided between the grid columns), which makes
    /// snapped and unsnapped rendering land on different device pixels. A
    /// transition snapshot drawn without the transform therefore shifted the
    /// tile favicons by up to two pixels the moment the live grid was swapped
    /// for its snapshot, and back again on commit. Snapshot tiles carry the
    /// same identity transform so both trees rasterize alike.
    func sidebarZenPressEffectRestingGeometry() -> some View {
        scaleEffect(1)
    }

    func sidebarZenActionOpacity(_ isVisible: Bool) -> some View {
        modifier(SidebarZenActionOpacityModifier(isVisible: isVisible))
    }
}
