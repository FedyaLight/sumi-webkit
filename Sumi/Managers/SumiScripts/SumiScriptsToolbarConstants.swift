//
//  SumiScriptsToolbarConstants.swift
//  Sumi
//
//  Native SumiScripts toolbar pin identifier (shared with ExtensionManager pin list).
//  This is not a Safari WebExtension bundle id; it only keys UserDefaults ordering.
//

import Foundation

enum SumiScriptsToolbarConstants {
    /// Stable id for pinning SumiScripts in the same ordered list as extensions.
    static let nativeToolbarItemID = "com.sumi.userscripts"
}
