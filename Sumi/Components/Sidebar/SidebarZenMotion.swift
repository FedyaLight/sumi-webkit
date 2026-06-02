//
//  SidebarZenMotion.swift
//  Sumi
//

import SwiftUI

enum SidebarRowMotionMetrics {
    static let pressedScale = SidebarMotionPolicy.rowPressedScale
}

enum SidebarDropMotion {
    static let contentLayoutDuration: Double = 0.18
    static let gap = SidebarMotionPolicy.dragGapAnimation(for: .standard)
    static let contentLayout = SidebarMotionPolicy.contentLayoutAnimation(for: .standard)
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
    @Environment(SidebarInteractionState.self) private var sidebarInteractionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    @State private var visualPressed = false

    let sourceID: String
    let kind: SidebarZenPressKind
    let isEnabled: Bool

    func body(content: Content) -> some View {
        let appKitPressed = sidebarInteractionState.activePressedSourceID == sourceID
        let isPressed = isEnabled && !shouldReduceMotion && appKitPressed

        content
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
            .onChange(of: sumiSettings.shouldReduceChromeMotion) { _, _ in
                updateVisualPressed(isPressed)
            }
    }

    private func updateVisualPressed(_ isPressed: Bool) {
        if isPressed || shouldReduceMotion || !isEnabled {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                visualPressed = isPressed
            }
            return
        }

        withAnimation(SidebarMotionPolicy.rowReleaseAnimation(
            for: SidebarMotionPolicy.currentMode(reduceMotion: shouldReduceMotion),
            split: kind.isSplit
        )) {
            visualPressed = false
        }
    }

    private var shouldReduceMotion: Bool {
        reduceMotion || sumiSettings.shouldReduceChromeMotion
    }
}

private struct SidebarZenRowLifecycleModifier: ViewModifier {
    let isCollapsed: Bool

    func body(content: Content) -> some View {
        content
            .frame(height: isCollapsed ? 0 : SidebarRowLayout.rowHeight, alignment: .top)
            .opacity(isCollapsed ? 0 : 1)
            .clipped()
    }
}

private struct SidebarZenRowLifecycleTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.transition(isEnabled && !shouldReduceMotion ? .zenSidebarRowLifecycle : .identity)
    }

    private var shouldReduceMotion: Bool {
        reduceMotion || sumiSettings.shouldReduceChromeMotion
    }
}

private struct SidebarZenCompositeLifecycleTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.transition(isEnabled && !shouldReduceMotion ? .zenSidebarCompositeLifecycle : .identity)
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

extension AnyTransition {
    static var zenSidebarRowLifecycle: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SidebarZenRowLifecycleModifier(
                    isCollapsed: true
                ),
                identity: SidebarZenRowLifecycleModifier(
                    isCollapsed: false
                )
            )
            .animation(SidebarMotionPolicy.rowLifecycleAnimation(for: .standard)),
            removal: .modifier(
                active: SidebarZenRowLifecycleModifier(
                    isCollapsed: true
                ),
                identity: SidebarZenRowLifecycleModifier(
                    isCollapsed: false
                )
            )
            .animation(SidebarMotionPolicy.rowLifecycleAnimation(for: .standard))
        )
    }

    static var zenSidebarCompositeLifecycle: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(SidebarMotionPolicy.rowLifecycleAnimation(for: .standard)),
            removal: .opacity.animation(SidebarMotionPolicy.rowLifecycleAnimation(for: .standard))
        )
    }
}

extension View {
    func sidebarZenPressEffect(
        sourceID: String,
        kind: SidebarZenPressKind = .row,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarZenPressEffectModifier(
                sourceID: sourceID,
                kind: kind,
                isEnabled: isEnabled
            )
        )
    }

    func sidebarZenRowLifecycleTransition(isEnabled: Bool = true) -> some View {
        modifier(SidebarZenRowLifecycleTransitionModifier(isEnabled: isEnabled))
    }

    func sidebarZenCompositeLifecycleTransition(isEnabled: Bool = true) -> some View {
        modifier(SidebarZenCompositeLifecycleTransitionModifier(isEnabled: isEnabled))
    }

    func sidebarZenActionOpacity(_ isVisible: Bool) -> some View {
        modifier(SidebarZenActionOpacityModifier(isVisible: isVisible))
    }
}
