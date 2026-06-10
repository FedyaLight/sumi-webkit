//
//  BitwardenNativeMessagingIdentifiers.swift
//  Sumi
//
//  Stable public identifiers for Bitwarden native messaging adapter registration.
//

import Foundation

enum BitwardenNativeMessagingIdentifiers {
    static let hostBundleIdentifier = "com.bitwarden.desktop"
    static let protocolIdentifier = "com.bitwarden.desktop.native-messaging"
    static let proxyRelativePath = "Contents/MacOS/desktop_proxy"

    /// `runtime.sendNativeMessage` / `connectNative` application identifiers used by Bitwarden.
    static let publicApplicationIdentifiers: [String] = [
        "com.bitwarden.desktop",
        "com.8bit.bitwarden",
    ]

    /// Registry lookup keys: normalized host bundle `hostBundleIdentifier` only.
    static let registryHostBundleKeys: [String] = [hostBundleIdentifier]
}
