import AppKit
import SwiftUI

/// Shared motion language for the sidebar shell and its local interactions.
/// Keep product-specific motion here so SwiftUI and AppKit edges agree on timing.
enum SidebarMotionPolicy {
    enum Mode: Equatable {
        case standard
        case interactive
        case reducedMotion
    }

    static let rowPressedScale: CGFloat = 0.98
    static let rowPressCancelDistance: CGFloat = 3

    static func currentMode(reduceMotion: Bool) -> Mode {
        reduceMotion ? .reducedMotion : .standard
    }

    static var appKitCurrentMode: Mode {
        currentMode(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    static func dockedLayoutAnimation(for mode: Mode, isShowing: Bool) -> Animation? {
        switch mode {
        case .reducedMotion:
            return nil
        case .standard, .interactive:
            return .timingCurve(
                isShowing ? 0.0 : 0.42,
                0.0,
                isShowing ? 0.58 : 1.0,
                1.0,
                duration: 0.20
            )
        }
    }

    static func overlayAnimation(for mode: Mode) -> Animation? {
        switch mode {
        case .reducedMotion:
            return .easeOut(duration: 0.08)
        case .standard, .interactive:
            return .smooth(duration: 0.22)
        }
    }

    static func rowReleaseAnimation(for mode: Mode, split: Bool) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .easeOut(duration: split ? 0.10 : 0.20)
    }

    static func rowLifecycleAnimation(for mode: Mode) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .smooth(duration: 0.14)
    }

    static func actionFadeAnimation(for mode: Mode) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .easeOut(duration: 0.10)
    }

    static func dragGapAnimation(for mode: Mode) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .interactiveSpring(response: 0.22, dampingFraction: 0.86)
    }

    static func contentLayoutAnimation(for mode: Mode) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .smooth(duration: 0.18)
    }

    static func spaceSwitchAnimation(for mode: Mode) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.37)
    }

    static func overlayUsesTravel(for mode: Mode) -> Bool {
        mode != .reducedMotion
    }
}
