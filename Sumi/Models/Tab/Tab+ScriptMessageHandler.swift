import AppKit
import Foundation
import WebKit

extension Tab {
    func normalTabCoreUserScripts() -> [SumiUserScript] {
        scriptMessageRuntimeOwner.normalTabCoreUserScripts()
    }

    func setClickModifierFlags(_ flags: NSEvent.ModifierFlags) {
        scriptMessageRuntimeOwner.setClickModifierFlags(flags)
    }

    func isGlanceTriggerActive(_ flags: NSEvent.ModifierFlags? = nil) -> Bool {
        scriptMessageRuntimeOwner.isGlanceTriggerActive(flags)
    }

    func openURLInGlance(_ url: URL, originRectInWindow: CGRect? = nil) {
        scriptMessageRuntimeOwner.openURLInGlance(url, originRectInWindow: originRectInWindow)
    }

    func openURLInGlanceFromLinkGesture(_ url: URL) {
        scriptMessageRuntimeOwner.openURLInGlanceFromLinkGesture(url)
    }

    func updateHoveredLink(_ href: String?) {
        scriptMessageRuntimeOwner.updateHoveredLink(href)
    }

    func dynamicGlanceURLForWebViewMouseDown(_ event: NSEvent) -> URL? {
        scriptMessageRuntimeOwner.dynamicGlanceURLForWebViewMouseDown(event)
    }

    func glanceOriginRectInWindow(maxAge: TimeInterval = 1.5) -> CGRect? {
        scriptMessageRuntimeOwner.glanceOriginRectInWindow(maxAge: maxAge)
    }

    func navigationModifierFlags(from navigationAction: WKNavigationAction) -> NSEvent.ModifierFlags {
        scriptMessageRuntimeOwner.navigationModifierFlags(from: navigationAction)
    }

    /// Resolves link gesture modifiers when WebKit reports empty or stale flags.
    func resolvedNavigationModifierFlags(actionFlags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        scriptMessageRuntimeOwner.resolvedNavigationModifierFlags(actionFlags: actionFlags)
    }

    func shouldOpenDynamicallyInGlance(
        url: URL,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        scriptMessageRuntimeOwner.shouldOpenDynamicallyInGlance(url: url, modifierFlags: modifierFlags)
    }
}
