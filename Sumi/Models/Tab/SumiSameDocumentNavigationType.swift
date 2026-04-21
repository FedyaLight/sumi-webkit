//
//  SumiSameDocumentNavigationType.swift
//  Sumi
//
//  Integer cases match WebKit `_WKSameDocumentNavigationType` and DuckDuckGo
//  `BrowserServicesKit.WKSameDocumentNavigationType` (see DistributedNavigationDelegate).
//

import Foundation

/// Same-document navigation kind passed to `WKNavigationDelegatePrivate` as `NSInteger`.
enum SumiSameDocumentNavigationType: Int {
    case anchorNavigation = 0
    case sessionStatePush = 1
    case sessionStateReplace = 2
    case sessionStatePop = 3

    /// Parity with DDG `FindInPageTabExtension`: dismiss find only for session history push/pop.
    static func shouldCloseFindInPage(forWebKitSameDocumentNavigationRaw raw: Int) -> Bool {
        guard let type = Self(rawValue: raw) else { return false }
        switch type {
        case .sessionStatePush, .sessionStatePop:
            return true
        case .anchorNavigation, .sessionStateReplace:
            return false
        }
    }
}
