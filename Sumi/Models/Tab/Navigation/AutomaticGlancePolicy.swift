import AppKit
import Foundation
import SumiDomain

@MainActor
enum AutomaticGlancePolicy {
    static func shouldPresent(
        _ targetURL: URL?,
        from tab: Tab,
        ordinaryBehavior: SumiLinkOpenBehavior,
        modifierFlags: NSEvent.ModifierFlags,
        isExtensionOriginated: Bool,
        isMiddleButtonClick: Bool,
        shouldDownload: Bool
    ) -> Bool {
        guard case .newTab(selected: true) = ordinaryBehavior else {
            return false
        }
        return shouldPresent(
            targetURL,
            from: tab,
            modifierFlags: modifierFlags,
            isExtensionOriginated: isExtensionOriginated,
            isMiddleButtonClick: isMiddleButtonClick,
            shouldDownload: shouldDownload
        )
    }

    static func shouldPresent(
        _ targetURL: URL?,
        from tab: Tab,
        ordinaryPolicy: SumiNewWindowPolicy,
        modifierFlags: NSEvent.ModifierFlags,
        isExtensionOriginated: Bool,
        isMiddleButtonClick: Bool,
        shouldDownload: Bool
    ) -> Bool {
        guard case .tab(selected: true) = ordinaryPolicy else { return false }
        return shouldPresent(
            targetURL,
            from: tab,
            modifierFlags: modifierFlags,
            isExtensionOriginated: isExtensionOriginated,
            isMiddleButtonClick: isMiddleButtonClick,
            shouldDownload: shouldDownload
        )
    }

    private static func shouldPresent(
        _ targetURL: URL?,
        from tab: Tab,
        modifierFlags: NSEvent.ModifierFlags,
        isExtensionOriginated: Bool,
        isMiddleButtonClick: Bool,
        shouldDownload: Bool
    ) -> Bool {
        guard isExtensionOriginated == false,
              isMiddleButtonClick == false,
              shouldDownload == false,
              let targetURL
        else { return false }
        return tab.shouldOpenDynamicallyInGlance(
            url: targetURL,
            modifierFlags: modifierFlags
        )
    }
}
