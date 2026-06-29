import AppKit
import Combine
import Foundation

struct SumiGlanceOriginSnapshot {
    let rectInWindow: CGRect
    let timestamp: TimeInterval
}

@MainActor
final class TabWebViewInteractionStateOwner {
    var lastWebViewInteractionEvent: NSEvent?
    var webViewInteractionCancellables: [ObjectIdentifier: AnyCancellable] = [:]
    var onLinkHover: ((String?) -> Void)?
    var lastHoveredLinkURL: URL?
    var lastWebPageContextMenuTarget: SumiWebPageContextMenuTargetSnapshot?
    var lastGlanceMouseDownOrigin: SumiGlanceOriginSnapshot?

    func recordInteraction(_ event: NSEvent) {
        lastWebViewInteractionEvent = event
        recordGlanceMouseDownOriginIfNeeded(event)
    }

    func clearInteractionEvent() {
        lastWebViewInteractionEvent = nil
    }

    func recentInteractionModifierFlags(maxAge: TimeInterval = 1.0) -> NSEvent.ModifierFlags? {
        guard let event = lastWebViewInteractionEvent else { return nil }
        let age = ProcessInfo.processInfo.systemUptime - event.timestamp
        guard age >= 0, age <= maxAge else { return nil }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return flags.isEmpty ? nil : flags
    }

    func recentMouseDownModifierFlags(maxAge: TimeInterval = 1.0) -> NSEvent.ModifierFlags? {
        guard let event = lastWebViewInteractionEvent,
              event.type == .leftMouseDown || event.type == .otherMouseDown
        else { return nil }
        return recentInteractionModifierFlags(maxAge: maxAge)
    }

    func recordGlanceMouseDownOriginIfNeeded(_ event: NSEvent) {
        guard event.type == .leftMouseDown else { return }
        let point = event.window?.mouseLocationOutsideOfEventStream ?? event.locationInWindow
        lastGlanceMouseDownOrigin = SumiGlanceOriginSnapshot(
            rectInWindow: CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44),
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }

    func recentGlanceMouseDownOriginRect(maxAge: TimeInterval = 1.5) -> CGRect? {
        guard let origin = lastGlanceMouseDownOrigin else { return nil }
        let age = ProcessInfo.processInfo.systemUptime - origin.timestamp
        guard age >= 0, age <= maxAge else { return nil }
        return origin.rectInWindow
    }
}
