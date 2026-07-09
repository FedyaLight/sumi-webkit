//
//  WebContentProcessDisplayNameProvider.swift
//  Sumi
//

import Foundation
import WebKit

/// Applies WebKit-private `_setProcessDisplayName:` on `WKWebViewConfiguration` for
/// Activity Monitor / diagnostics. All SPI for this feature stays in this file.
public enum WebContentProcessDisplayNameProvider {
    private enum ProcessNameSelector {
        static let setProcessDisplayName = NSSelectorFromString("_setProcessDisplayName:")
    }

    public static let normalTab = "Sumi Web Content"
    public static let popup = "Sumi Web Content (Popup)"
    public static let auxiliaryTemplate = "Sumi Web Content (Auxiliary)"

    public static func apply(_ displayName: String, to configuration: WKWebViewConfiguration) {
        guard configuration.responds(to: ProcessNameSelector.setProcessDisplayName) else {
            return
        }
        configuration.perform(ProcessNameSelector.setProcessDisplayName, with: displayName)
    }
}
