import AppKit
import SwiftUI

/// Shared motion language for the sidebar shell and its local interactions.
/// Keep product-specific motion here so SwiftUI and AppKit edges agree on timing.
enum SidebarMotionPolicy {
    typealias Mode = SumiChromeMotionPolicy.Mode

    static let rowPressedScale: CGFloat = 0.98

    /// How long a row keeps its press visual once it can first be drawn.
    /// Page Activation materializes a Cold Page synchronously on press, so a
    /// fast click would otherwise collapse press and release into one frame.
    static let rowPressMinimumVisibleDuration: TimeInterval = 0.09

    static func currentMode(
        reduceMotion: Bool,
        energySaverReducesMotion: Bool = false
    ) -> Mode {
        SumiChromeMotionPolicy.currentMode(
            reduceMotion: reduceMotion,
            energySaverReducesMotion: energySaverReducesMotion
        )
    }

    @MainActor
    static func appKitCurrentMode(settings: SumiSettingsService?) -> Mode {
        SumiChromeMotionPolicy.appKitCurrentMode(settings: settings)
    }

    static func dockedLayoutAnimation(for mode: Mode, isShowing: Bool) -> Animation? {
        switch mode {
        case .reducedMotion:
            return nil
        case .standard:
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
        let duration = overlayAnimationDuration(for: mode)
        switch mode {
        case .reducedMotion:
            return .easeOut(duration: duration)
        case .standard:
            return .smooth(duration: duration)
        }
    }

    static func overlayAnimationDuration(for mode: Mode) -> TimeInterval {
        switch mode {
        case .reducedMotion:
            return 0.08
        case .standard:
            return 0.22
        }
    }

    static func rowReleaseAnimation(for mode: Mode, split: Bool) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .easeOut(duration: split ? 0.10 : 0.20)
    }

    static func actionFadeAnimation(for mode: Mode) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .easeOut(duration: 0.10)
    }

    static func dragGapAnimation(for mode: Mode) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .interactiveSpring(response: 0.22, dampingFraction: 0.86)
    }

    /// Post-drop settle: rows slide into their committed positions (Zen:
    /// 100ms ease-out FLIP after the model mutates).
    static func dropSettleAnimation(for mode: Mode) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .easeOut(duration: 0.10)
    }

    /// Shared duration for list/folder content reflow. Also gates when model
    /// mutations commit after a gap-collapse (see `SidebarDropMotion`).
    static let contentLayoutDuration: TimeInterval = 0.16

    static func contentLayoutAnimation(for mode: Mode) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .smooth(duration: contentLayoutDuration)
    }

    static let selectedItemRevealDuration: TimeInterval = 0.25

    static func selectedItemRevealAnimation(for mode: Mode) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .smooth(duration: selectedItemRevealDuration)
    }

    static func spaceSwitchAnimation(for mode: Mode) -> Animation? {
        guard mode != .reducedMotion else { return nil }
        return .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.37)
    }

    static func overlayUsesTravel(for mode: Mode) -> Bool {
        mode != .reducedMotion
    }
}
