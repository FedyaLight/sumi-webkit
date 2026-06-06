//
//  SidebarZenMotion.swift
//  Sumi
//

import SwiftUI

enum SidebarRowMotionMetrics {
    static let pressedScale = SidebarMotionPolicy.rowPressedScale
}

enum SidebarRowInsertionMotionPolicy {
    static let hiddenOpacity: Double = 0
    static let visibleOpacity: Double = 1
}

enum SidebarRowStagedRevealTiming {
    static let contentRevealDelay: Double = SidebarDropMotion.shortcutRestoreRevealStartDelay
}

/// Folder-style list mutation timing: keep a full-height gap slot, then collapse it so siblings reflow.
enum SidebarRowCollapseGapMotion {
    static let duration: Double = SidebarDropMotion.contentLayoutDuration
}

/// Height + opacity collapse used for row removal and split-group row dismissal.
struct SidebarRowLifecycleModifier: ViewModifier {
    let isCollapsed: Bool

    func body(content: Content) -> some View {
        let row = content
            .frame(height: isCollapsed ? 0 : SidebarRowLayout.rowHeight, alignment: .top)
            .opacity(isCollapsed ? SidebarRowInsertionMotionPolicy.hiddenOpacity : SidebarRowInsertionMotionPolicy.visibleOpacity)

        if isCollapsed {
            row.clipped()
        } else {
            row
        }
    }
}

/// Opacity-only reveal for row content while the slot keeps full row height.
private struct SidebarRowContentRevealModifier: ViewModifier {
    let isHidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isHidden ? SidebarRowInsertionMotionPolicy.hiddenOpacity : SidebarRowInsertionMotionPolicy.visibleOpacity)
            .transition(.identity)
    }
}

/// Folder-style staged row: full-height slot, content opacity animates separately from layout.
private struct SidebarRowStagedInsertionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    let isRevealing: Bool

    func body(content: Content) -> some View {
        content
            .frame(height: SidebarRowLayout.rowHeight, alignment: .top)
            .modifier(SidebarRowContentRevealModifier(isHidden: isRevealing))
            .animation(contentOpacityAnimation, value: isRevealing)
            .clipped()
    }

    private var contentOpacityAnimation: Animation? {
        guard !reduceMotion, !sumiSettings.shouldReduceChromeMotion else { return nil }
        return SidebarMotionPolicy.folderLayoutAnimation(for: .standard)
    }
}

enum SidebarDropMotion {
    static let contentLayoutDuration: Double = 0.18
    static let shortcutRestoreRevealStartDelay: Double = 0.016
    static let shortcutRestoreActionDelay: Double = contentLayoutDuration + shortcutRestoreRevealStartDelay + 0.01
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

private struct SidebarRowListItemTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.transition(isEnabled && !shouldReduceMotion ? .sidebarRowListItem : .identity)
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
        content.transition(isEnabled && !shouldReduceMotion ? .sidebarRowContentOpacity : .identity)
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
    static func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction, body)
    }

    static func afterContentLayout(_ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + SidebarRowCollapseGapMotion.duration) {
            Task { @MainActor in
                action()
            }
        }
    }
}

enum SidebarRowStagedReveal {
    static func insert(
        _ id: UUID,
        into set: inout Set<UUID>,
        withoutAnimation update: () -> Void
    ) {
        SidebarMotionTransaction.withoutAnimation {
            _ = set.insert(id)
            update()
        }
    }

    static func reveal(
        _ ids: some Collection<UUID>,
        in set: Binding<Set<UUID>>,
        animation: Animation?,
        delay: Double = SidebarRowStagedRevealTiming.contentRevealDelay,
        shouldComplete: @escaping @MainActor () -> Bool = { true }
    ) {
        let idsToReveal = Array(ids)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                guard shouldComplete() else { return }
                guard let animation else {
                    var updated = set.wrappedValue
                    idsToReveal.forEach { updated.remove($0) }
                    set.wrappedValue = updated
                    return
                }
                withAnimation(animation) {
                    var updated = set.wrappedValue
                    idsToReveal.forEach { updated.remove($0) }
                    set.wrappedValue = updated
                }
            }
        }
    }
}

extension AnyTransition {
    private static var sidebarRowLayoutAnimation: Animation? {
        SidebarMotionPolicy.folderLayoutAnimation(for: .standard)
    }

    static var sidebarRowContentOpacity: AnyTransition {
        .opacity.animation(sidebarRowLayoutAnimation)
    }

    static var sidebarRowDropGap: AnyTransition {
        .opacity
            .combined(with: .scale(scale: 0.98, anchor: .center))
            .animation(sidebarRowLayoutAnimation)
    }

    /// Prefer gap-collapse layout for list mutations; keep identity on stable rows.
    static var sidebarRowListItem: AnyTransition {
        .identity
    }

    static var zenSidebarCompositeLifecycle: AnyTransition {
        sidebarRowContentOpacity
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

    func sidebarRowLifecycle(isCollapsed: Bool) -> some View {
        modifier(SidebarRowLifecycleModifier(isCollapsed: isCollapsed))
    }

    func sidebarRowListItemTransition(isEnabled: Bool = true) -> some View {
        modifier(SidebarRowListItemTransitionModifier(isEnabled: isEnabled))
    }

    func sidebarZenCompositeLifecycleTransition(isEnabled: Bool = true) -> some View {
        modifier(SidebarZenCompositeLifecycleTransitionModifier(isEnabled: isEnabled))
    }

    func sidebarZenActionOpacity(_ isVisible: Bool) -> some View {
        modifier(SidebarZenActionOpacityModifier(isVisible: isVisible))
    }

    func sidebarRowStagedInsertion(isRevealing: Bool) -> some View {
        modifier(SidebarRowStagedInsertionModifier(isRevealing: isRevealing))
    }

    func sidebarRowAnimatedListSlot(_ motion: RegularTabRowMotion) -> some View {
        opacity(motion.hidesContent
            ? SidebarRowInsertionMotionPolicy.hiddenOpacity
            : SidebarRowInsertionMotionPolicy.visibleOpacity)
            .frame(height: motion.layoutHeight, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .allowsHitTesting(!motion.isInteractionDisabled)
            .accessibilityHidden(motion.isInteractionDisabled)
    }

    func sidebarRowLayoutGap(height: CGFloat) -> some View {
        Color.clear
            .sidebarRowAnimatedListSlot(
                RegularTabRowMotion(
                    layoutHeight: height,
                    hidesContent: false,
                    isInteractionDisabled: true
                )
            )
    }
}
