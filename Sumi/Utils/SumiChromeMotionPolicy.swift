import AppKit
import SwiftUI

/// Shared reduced-motion mode for native browser chrome surfaces.
enum SumiChromeMotionPolicy {
    enum Mode: Equatable {
        case standard
        case reducedMotion
    }

    static func currentMode(
        reduceMotion: Bool,
        energySaverReducesMotion: Bool = false
    ) -> Mode {
        reduceMotion || energySaverReducesMotion ? .reducedMotion : .standard
    }

    @MainActor
    static func appKitCurrentMode(settings: SumiSettingsService?) -> Mode {
        currentMode(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            energySaverReducesMotion: settings?.shouldReduceChromeMotion ?? false
        )
    }
}
