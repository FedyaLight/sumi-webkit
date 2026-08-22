import AppKit
import WebKit

@objc(SumiApplication)
final class SumiApplication: NSApplication {
    override func noResponder(for eventSelector: Selector) {
        guard Self.suppressesNoResponder(
            for: eventSelector,
            event: currentEvent
        ) else {
            super.noResponder(for: eventSelector)
            return
        }
    }

    static func suppressesNoResponder(
        for eventSelector: Selector,
        event: NSEvent?
    ) -> Bool {
        guard eventSelector == #selector(NSResponder.keyDown(with:)),
              let event,
              event.modifierFlags.intersection([
                  .command, .control, .option,
              ]).isEmpty else { return false }
        return isWebContentFirstResponder(in: event.window)
    }

    private static func isWebContentFirstResponder(in window: NSWindow?) -> Bool {
        var view = window?.firstResponder as? NSView
        while let current = view {
            if current is WKWebView { return true }
            view = current.superview
        }
        return false
    }
}
