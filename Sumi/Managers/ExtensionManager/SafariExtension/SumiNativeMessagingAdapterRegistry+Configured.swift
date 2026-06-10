//
//  SumiNativeMessagingAdapterRegistry+Configured.swift
//  Sumi
//
//  Production adapter registration for native messaging relay.
//

import Foundation

@available(macOS 15.5, *)
@MainActor
enum SumiNativeMessagingConfiguredAdapters {
    /// Production adapters registered by normalized host bundle key.
    /// Bitwarden: registry key `com.bitwarden.desktop`; public application identifiers
    /// `com.bitwarden.desktop`, `com.8bit.bitwarden`, `com.8bit.bitwarden.desktop` (alias table).
    static let all: [SumiNativeMessagingProtocolAdapter] = [
        BitwardenNativeMessagingAdapter(),
    ]

    static let registeredHostBundleKeys: [String] = BitwardenNativeMessagingIdentifiers
        .registryHostBundleKeys
}

@MainActor
extension SumiNativeMessagingAdapterRegistry {
    static let shared: SumiNativeMessagingAdapterRegistry = {
        if #available(macOS 15.5, *) {
            return SumiNativeMessagingAdapterRegistry(adapters: SumiNativeMessagingConfiguredAdapters.all)
        }
        return SumiNativeMessagingAdapterRegistry(adapters: [])
    }()
}
