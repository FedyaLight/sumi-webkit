import AppKit

enum SidebarChromePointerArbitration {
    static let didChangeNotification = Notification.Name("SidebarChromePointerArbitration.didChangeNotification")

    private struct SuppressionRegistry {
        private var ownersByWindowID: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]

        mutating func set(_ isSuppressed: Bool, owner: ObjectIdentifier, window: NSWindow?) -> Bool {
            let previous = ownersByWindowID

            for windowID in ownersByWindowID.keys {
                ownersByWindowID[windowID]?.remove(owner)
                if ownersByWindowID[windowID]?.isEmpty == true {
                    ownersByWindowID[windowID] = nil
                }
            }

            if isSuppressed, let window {
                ownersByWindowID[ObjectIdentifier(window), default: []].insert(owner)
            }

            return previous != ownersByWindowID
        }

        func isActive(in window: NSWindow?) -> Bool {
            guard let window else { return false }
            return ownersByWindowID[ObjectIdentifier(window)]?.isEmpty == false
        }
    }

    @MainActor private static var scrollSuppressesResize = SuppressionRegistry()
    @MainActor private static var resizeSuppressesScroll = SuppressionRegistry()

    @MainActor
    static func setScrollIndicatorSuppressesResize(_ isSuppressed: Bool, owner: AnyObject, window: NSWindow?) {
        if scrollSuppressesResize.set(isSuppressed, owner: ObjectIdentifier(owner), window: window) {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    @MainActor
    static func isResizeSuppressed(in window: NSWindow?) -> Bool {
        scrollSuppressesResize.isActive(in: window)
    }

    @MainActor
    static func setResizeSuppressesScrollIndicator(_ isSuppressed: Bool, owner: AnyObject, window: NSWindow?) {
        if resizeSuppressesScroll.set(isSuppressed, owner: ObjectIdentifier(owner), window: window) {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    @MainActor
    static func isScrollIndicatorSuppressed(in window: NSWindow?) -> Bool {
        resizeSuppressesScroll.isActive(in: window)
    }
}
