//
//  WebContentProcessDisplayNameProvider.swift
//  Sumi
//

import Foundation
import WebKit

/// Applies WebKit-private `_setProcessDisplayName:` on `WKWebViewConfiguration` for
/// Activity Monitor / diagnostics. All SPI for this feature stays in this file.
enum WebContentProcessDisplayNameProvider {
    private enum ProcessNameSelector {
        static let setProcessDisplayName = NSSelectorFromString("_setProcessDisplayName:")
    }

    static let normalTab = "Sumi Web Content"
    static let popup = "Sumi Web Content (Popup)"
    static let auxiliaryTemplate = "Sumi Web Content (Auxiliary)"

    static func apply(_ displayName: String, to configuration: WKWebViewConfiguration) {
        guard configuration.responds(to: ProcessNameSelector.setProcessDisplayName) else {
            return
        }
        configuration.perform(ProcessNameSelector.setProcessDisplayName, with: displayName)
    }
}
