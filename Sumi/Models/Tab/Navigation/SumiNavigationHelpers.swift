import AppKit
import Foundation
import WebKit

extension URL {
    var sumiIsExternalSchemeLink: Bool {
        guard let scheme = scheme?.lowercased(),
              ![
                "sumi",
                "sumi-internal",
                "safari-web-extension",
            ].contains(scheme)
        else {
            return false
        }

        return ![
            .https,
            .http,
            .about,
            .file,
            .blob,
            .data,
            .ftp,
            .javascript,
            .duck,
            .webkitExtension,
        ].contains(sumiNavigationalScheme)
    }
}

extension WKWebView {
    func sumiCloseWindow() {
        evaluateJavaScript("window.close()")
    }
}

enum SumiLinkOpenBehavior: Equatable {
    case currentTab
    case newTab(selected: Bool)
    case newWindow(selected: Bool)

    var shouldSelectNewTab: Bool {
        switch self {
        case .currentTab:
            return false
        case .newTab(let selected), .newWindow(let selected):
            return selected
        }
    }

    init(
        buttonIsMiddle: Bool,
        modifierFlags: NSEvent.ModifierFlags,
        switchToNewTabWhenOpenedPreference: Bool,
        canOpenLinkInCurrentTab: Bool = true,
        shouldSelectNewTab: Bool = false
    ) {
        let modifierFlags = modifierFlags.intersection([.command, .option, .control, .shift])
        let shouldOpenNewTab = buttonIsMiddle || modifierFlags.contains(.command)
        let isShiftPressed = modifierFlags.contains(.shift)

        guard shouldOpenNewTab || !canOpenLinkInCurrentTab else {
            self = .currentTab
            return
        }

        let isSelected: Bool
        if shouldSelectNewTab && !shouldOpenNewTab {
            isSelected = true
        } else {
            isSelected = (switchToNewTabWhenOpenedPreference && !isShiftPressed)
                || (!switchToNewTabWhenOpenedPreference && isShiftPressed)
        }

        if modifierFlags.contains(.option) {
            self = .newWindow(selected: isSelected)
        } else {
            self = .newTab(selected: isSelected)
        }
    }

    init(
        event: NSEvent?,
        switchToNewTabWhenOpenedPreference: Bool,
        canOpenLinkInCurrentTab: Bool = true,
        shouldSelectNewTab: Bool = false
    ) {
        self.init(
            buttonIsMiddle: event?.buttonNumber == 2,
            modifierFlags: event?.modifierFlags ?? [],
            switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference,
            canOpenLinkInCurrentTab: canOpenLinkInCurrentTab,
            shouldSelectNewTab: shouldSelectNewTab
        )
    }
}

enum SumiNewWindowPolicy: Equatable {
    case tab(selected: Bool)
    case popup(origin: NSPoint?, size: NSSize?)
    case window(active: Bool)

    @MainActor init(
        _ windowFeatures: WKWindowFeatures,
        linkOpenBehavior: SumiLinkOpenBehavior,
        preferTabsToWindows: Bool = true
    ) {
        if case .newWindow(let selected) = linkOpenBehavior {
            self = .window(active: selected)
            return
        }

        if windowFeatures.sumiWantsPopup == true {
            self = .popup(origin: windowFeatures.sumiOrigin, size: windowFeatures.sumiSize)
        } else if windowFeatures.toolbarsVisibility?.boolValue == true, preferTabsToWindows {
            self = .tab(selected: linkOpenBehavior.shouldSelectNewTab)
        } else if windowFeatures.width != nil {
            self = .popup(origin: windowFeatures.sumiOrigin, size: windowFeatures.sumiSize)
        } else if windowFeatures.statusBarVisibility == nil,
                  windowFeatures.menuBarVisibility == nil,
                  preferTabsToWindows {
            self = .tab(selected: linkOpenBehavior.shouldSelectNewTab)
        } else {
            self = .window(active: linkOpenBehavior.shouldSelectNewTab)
        }
    }

    var shouldActivateTab: Bool {
        switch self {
        case .tab(let selected):
            return selected
        case .popup, .window:
            return true
        }
    }

    var isPopup: Bool {
        if case .popup = self { return true }
        return false
    }

}

extension WKWindowFeatures {
    /// WebCore's complete popup-feature classification. The public feature
    /// properties omit `popup`, location, scrollbars, and unknown features.
    var sumiWantsPopup: Bool? {
        let selector = NSSelectorFromString("_wantsPopup")
        guard responds(to: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let getter = unsafeBitCast(method(for: selector), to: Getter.self)
        return getter(self, selector)
    }

    var sumiOrigin: NSPoint? {
        guard x != nil || y != nil else { return nil }
        return NSPoint(x: x?.intValue ?? 0, y: y?.intValue ?? 0)
    }

    var sumiSize: NSSize? {
        guard width != nil || height != nil else { return nil }
        return NSSize(width: width?.intValue ?? 0, height: height?.intValue ?? 0)
    }
}
