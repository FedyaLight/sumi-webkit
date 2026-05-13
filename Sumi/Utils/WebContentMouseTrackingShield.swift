import AppKit

@MainActor
enum WebContentMouseTrackingShield {
    private final class WeakWindow {
        weak var value: NSWindow?

        init(_ value: NSWindow) {
            self.value = value
        }
    }

    private final class WeakView {
        weak var value: NSView?

        init(_ value: NSView) {
            self.value = value
        }
    }

    private static var activeShieldIDsByWindowID: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
    private static var windowByID: [ObjectIdentifier: WeakWindow] = [:]
    private static var shieldByID: [ObjectIdentifier: WeakView] = [:]
    private static var windowIDByShieldID: [ObjectIdentifier: ObjectIdentifier] = [:]

    static func setActive(_ isActive: Bool, for shieldView: NSView) {
        pruneStaleEntries()

        let shieldID = ObjectIdentifier(shieldView)
        let previousWindowID = windowIDByShieldID[shieldID]
        let nextWindow = shieldView.window
        let nextWindowID = nextWindow.map(ObjectIdentifier.init)

        if let previousWindowID, previousWindowID != nextWindowID {
            removeShield(shieldID, from: previousWindowID)
        }

        guard isActive, let nextWindow, let nextWindowID else {
            if let previousWindowID {
                removeShield(shieldID, from: previousWindowID)
            }
            shieldByID.removeValue(forKey: shieldID)
            windowIDByShieldID.removeValue(forKey: shieldID)
            return
        }

        windowByID[nextWindowID] = WeakWindow(nextWindow)
        shieldByID[shieldID] = WeakView(shieldView)
        windowIDByShieldID[shieldID] = nextWindowID

        var shieldIDs = activeShieldIDsByWindowID[nextWindowID] ?? []
        shieldIDs.insert(shieldID)
        activeShieldIDsByWindowID[nextWindowID] = shieldIDs

        applyShieldState(true, to: nextWindow)
    }

    static func refresh(for shieldView: NSView) {
        pruneStaleEntries()

        let shieldID = ObjectIdentifier(shieldView)
        guard let windowID = windowIDByShieldID[shieldID],
              activeShieldIDsByWindowID[windowID]?.contains(shieldID) == true,
              let window = windowByID[windowID]?.value
        else { return }

        applyShieldState(true, to: window)
    }

    static func unregister(_ shieldView: NSView) {
        pruneStaleEntries()

        let shieldID = ObjectIdentifier(shieldView)
        guard let windowID = windowIDByShieldID.removeValue(forKey: shieldID) else {
            shieldByID.removeValue(forKey: shieldID)
            return
        }

        removeShield(shieldID, from: windowID)
        shieldByID.removeValue(forKey: shieldID)
    }

    static func isActive(in window: NSWindow) -> Bool {
        pruneStaleEntries()
        let windowID = ObjectIdentifier(window)
        return activeShieldIDsByWindowID[windowID]?.isEmpty == false
    }

    private static func removeShield(_ shieldID: ObjectIdentifier, from windowID: ObjectIdentifier) {
        guard var shieldIDs = activeShieldIDsByWindowID[windowID] else { return }

        let wasWindowShielded = !shieldIDs.isEmpty
        shieldIDs.remove(shieldID)

        if shieldIDs.isEmpty {
            activeShieldIDsByWindowID.removeValue(forKey: windowID)
            if wasWindowShielded, let window = windowByID[windowID]?.value {
                applyShieldState(false, to: window)
            }
        } else {
            activeShieldIDsByWindowID[windowID] = shieldIDs
        }
    }

    private static func pruneStaleEntries() {
        let staleShieldIDs = shieldByID.compactMap { shieldID, weakView in
            weakView.value == nil ? shieldID : nil
        }
        for shieldID in staleShieldIDs {
            if let windowID = windowIDByShieldID.removeValue(forKey: shieldID) {
                removeShield(shieldID, from: windowID)
            }
            shieldByID.removeValue(forKey: shieldID)
        }

        let staleWindowIDs = windowByID.compactMap { windowID, weakWindow in
            weakWindow.value == nil ? windowID : nil
        }
        for windowID in staleWindowIDs {
            activeShieldIDsByWindowID.removeValue(forKey: windowID)
            windowByID.removeValue(forKey: windowID)
        }
    }

    private static func applyShieldState(_ isShielded: Bool, to window: NSWindow) {
        guard let contentView = window.contentView else { return }
        applyShieldState(isShielded, in: contentView)
    }

    private static func applyShieldState(_ isShielded: Bool, in rootView: NSView) {
        if let webView = rootView as? FocusableWKWebView {
            webView.setTransientChromeMouseTrackingSuppressed(
                isShielded,
                shieldRects: isShielded ? activeShieldRects(for: webView) : []
            )
        }

        for subview in rootView.subviews {
            applyShieldState(isShielded, in: subview)
        }
    }

    private static func activeShieldRects(for webView: FocusableWKWebView) -> [SumiTransientChromeInteractionShieldRect] {
        guard let window = webView.window else { return [] }

        let windowID = ObjectIdentifier(window)
        guard let shieldIDs = activeShieldIDsByWindowID[windowID] else { return [] }

        return shieldIDs.compactMap { shieldID in
            guard let shieldView = shieldByID[shieldID]?.value,
                  shieldView.window === window
            else { return nil }

            let rectInWindow = shieldView.convert(shieldView.bounds, to: nil)
            let rectInWebView = webView.convert(rectInWindow, from: nil)
            let clippedRect = rectInWebView.intersection(webView.bounds)
            guard !clippedRect.isNull, clippedRect.width > 0, clippedRect.height > 0 else {
                return nil
            }

            let y = webView.isFlipped ? clippedRect.minY : webView.bounds.height - clippedRect.maxY
            return SumiTransientChromeInteractionShieldRect(
                x: clippedRect.minX,
                y: y,
                width: clippedRect.width,
                height: clippedRect.height
            )
        }
    }
}
