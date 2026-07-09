//
//  FloatingBarChromePlaceholder.swift
//  SumiFloatingBarChrome
//
//  Scaffold marker for the future move of FloatingBar chrome Views out of
//  the Sumi app target into this package. Do not move Views yet — that would
//  break the app target until adapters conform to SumiChromeContracts.
//

import SumiChromeContracts
import SumiChromeTokens

/// Namespace for the upcoming FloatingBar chrome SPM peel. Empty by design.
public enum FloatingBarChromePlaceholder {
    /// Documents the intended dependency surface (tokens + commanding).
    public static func bind(_ commanding: FloatingBarChromeCommanding) {
        _ = commanding
        _ = ChromeLayoutTokens.floatingBarHorizontalPadding
    }
}
