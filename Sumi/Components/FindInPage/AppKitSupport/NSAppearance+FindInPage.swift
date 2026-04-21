//
//  NSAppearance+FindInPage.swift
//  Sumi
//
//  SPDX-License-Identifier: Apache-2.0
//

import AppKit

extension NSAppearance {
    /// Match DuckDuckGo’s `NSAppearance.withAppAppearance` behavior for asset catalog / layer colors.
    static func sumi_findWithAppAppearance(_ body: () -> Void) {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance(body)
    }
}
