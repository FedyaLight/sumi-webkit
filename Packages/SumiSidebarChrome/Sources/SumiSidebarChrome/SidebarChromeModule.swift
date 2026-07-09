//
//  SidebarChromeModule.swift
//  SumiSidebarChrome
//
//  Package entry for sidebar chrome peels. Views depend on
//  `SidebarChromeCommanding` + `ChromeLayoutTokens`, not app hubs.
//

import SumiChromeContracts
import SumiChromeTokens

/// Namespace for SumiSidebarChrome peels and commanding bind points.
public enum SidebarChromeModule {
    /// Registers the app adapter that forwards chrome commands into the session.
    /// Leaf views may still take closures for one-off actions (e.g. space creation).
    public static func bind(_ commanding: SidebarChromeCommanding) {
        _ = commanding
        _ = ChromeLayoutTokens.sidebarContentHorizontalPadding
    }
}
