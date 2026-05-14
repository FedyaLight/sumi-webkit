//
//  SidebarZenMotion.swift
//  Sumi
//

import SwiftUI

enum SidebarRowMotionMetrics {
    static let pressedScale: CGFloat = 0.98
    static let pressCancelDistance: CGFloat = 3
    static let pressDuration: Double = 0.20
    static let splitPressDuration: Double = 0.10
    static let openDuration: Double = 0.12
    static let closeDuration: Double = 0.10
    static let actionFadeDuration: Double = 0.10
    static let openScale: CGFloat = 0.95
    static let closeScale: CGFloat = 0.95
    static let titleBlurRadius: CGFloat = 1
}

enum SidebarZenPressKind {
    case row
    case split

    var duration: Double {
        switch self {
        case .row:
            SidebarRowMotionMetrics.pressDuration
        case .split:
            SidebarRowMotionMetrics.splitPressDuration
        }
    }
}

private struct SidebarZenPressEffectModifier: ViewModifier {
    @Environment(SidebarInteractionState.self) private var sidebarInteractionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visualPressed = false

    let sourceID: String
    let kind: SidebarZenPressKind
    let isEnabled: Bool

    func body(content: Content) -> some View {
        let appKitPressed = sidebarInteractionState.activePressedSourceID == sourceID
        let isPressed = isEnabled && !reduceMotion && appKitPressed

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

        withAnimation(.easeOut(duration: kind.duration)) {
            visualPressed = false
        }
    }
}

private struct SidebarZenRowLifecycleModifier: ViewModifier {
    let isCollapsed: Bool
    let scale: CGFloat
    let blurRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(height: isCollapsed ? 0 : SidebarRowLayout.rowHeight, alignment: .top)
            .opacity(isCollapsed ? 0 : 1)
            .scaleEffect(isCollapsed ? scale : 1, anchor: .top)
            .blur(radius: isCollapsed ? blurRadius : 0)
            .clipped()
    }
}

private struct SidebarZenRowLifecycleTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.transition(isEnabled && !reduceMotion ? .zenSidebarRowLifecycle : .identity)
    }
}

private struct SidebarZenActionOpacityModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isVisible: Bool

    func body(content: Content) -> some View {
        content.animation(
            reduceMotion ? nil : .easeOut(duration: SidebarRowMotionMetrics.actionFadeDuration),
            value: isVisible
        )
    }
}

struct SidebarZenActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        SidebarZenActionButtonBody(
            configuration: configuration,
            isEnabled: isEnabled,
            reduceMotion: reduceMotion
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

        withAnimation(.easeOut(duration: SidebarRowMotionMetrics.splitPressDuration)) {
            visualPressed = false
        }
    }
}

extension AnyTransition {
    static var zenSidebarRowLifecycle: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SidebarZenRowLifecycleModifier(
                    isCollapsed: true,
                    scale: SidebarRowMotionMetrics.openScale,
                    blurRadius: SidebarRowMotionMetrics.titleBlurRadius
                ),
                identity: SidebarZenRowLifecycleModifier(
                    isCollapsed: false,
                    scale: 1,
                    blurRadius: 0
                )
            )
            .animation(.easeOut(duration: SidebarRowMotionMetrics.openDuration)),
            removal: .modifier(
                active: SidebarZenRowLifecycleModifier(
                    isCollapsed: true,
                    scale: SidebarRowMotionMetrics.closeScale,
                    blurRadius: 0
                ),
                identity: SidebarZenRowLifecycleModifier(
                    isCollapsed: false,
                    scale: 1,
                    blurRadius: 0
                )
            )
            .animation(.easeOut(duration: SidebarRowMotionMetrics.closeDuration))
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

    func sidebarZenActionOpacity(_ isVisible: Bool) -> some View {
        modifier(SidebarZenActionOpacityModifier(isVisible: isVisible))
    }
}
