//
//  ExtensionSettingsSectionCommands.swift
//  Sumi
//

import Foundation

@MainActor
struct ExtensionSettingsInstalledCommands {
    typealias SetEnabled = @MainActor (
        _ extensionID: String,
        _ isEnabled: Bool
    ) async throws -> Void
    typealias SetDefaultSiteAccess = @MainActor (
        _ extensionID: String,
        _ access: SafariExtensionSiteAccessLevel
    ) -> Void
    typealias SetPrivateAccess = @MainActor (
        _ extensionID: String,
        _ isAllowed: Bool
    ) -> Void
    typealias SetConfiguredSiteAccess = @MainActor (
        _ extensionID: String,
        _ matchPattern: String,
        _ access: SafariExtensionSiteAccessLevel
    ) -> Void
    typealias OpenOptions = @MainActor (_ extensionID: String) async -> Void
    typealias Uninstall = @MainActor (_ extensionID: String) async throws -> Void

    private let setEnabledCommand: SetEnabled
    private let setDefaultSiteAccessCommand: SetDefaultSiteAccess
    private let setPrivateAccessCommand: SetPrivateAccess
    private let setConfiguredSiteAccessCommand: SetConfiguredSiteAccess
    private let openOptionsCommand: OpenOptions
    private let uninstallCommand: Uninstall

    init(
        setEnabled: @escaping SetEnabled,
        setDefaultSiteAccess: @escaping SetDefaultSiteAccess,
        setPrivateAccess: @escaping SetPrivateAccess,
        setConfiguredSiteAccess: @escaping SetConfiguredSiteAccess,
        openOptions: @escaping OpenOptions,
        uninstall: @escaping Uninstall
    ) {
        setEnabledCommand = setEnabled
        setDefaultSiteAccessCommand = setDefaultSiteAccess
        setPrivateAccessCommand = setPrivateAccess
        setConfiguredSiteAccessCommand = setConfiguredSiteAccess
        openOptionsCommand = openOptions
        uninstallCommand = uninstall
    }

    func setEnabled(_ isEnabled: Bool, for extensionID: String) async throws {
        try await setEnabledCommand(extensionID, isEnabled)
    }

    func setDefaultSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        for extensionID: String
    ) {
        setDefaultSiteAccessCommand(extensionID, access)
    }

    func setPrivateAccess(_ isAllowed: Bool, for extensionID: String) {
        setPrivateAccessCommand(extensionID, isAllowed)
    }

    func setConfiguredSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        for extensionID: String,
        matchPattern: String
    ) {
        setConfiguredSiteAccessCommand(extensionID, matchPattern, access)
    }

    func openOptions(for extensionID: String) async {
        await openOptionsCommand(extensionID)
    }

    func uninstall(_ extensionID: String) async throws {
        try await uninstallCommand(extensionID)
    }
}

@MainActor
struct ExtensionSettingsFindingsCommands {
    typealias Add = @MainActor (
        _ candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledExtension

    private let addCommand: Add

    init(add: @escaping Add) {
        addCommand = add
    }

    func add(
        _ candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledExtension {
        try await addCommand(candidate)
    }
}

@MainActor
struct ExtensionSettingsContentBlockerCommands {
    typealias Enable = @MainActor (
        _ candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledSafariContentBlockerRecord
    typealias SetEnabled = @MainActor (
        _ bundleIdentifier: String,
        _ isEnabled: Bool
    ) async throws -> InstalledSafariContentBlockerRecord?

    private let enableCommand: Enable
    private let setEnabledCommand: SetEnabled

    init(
        enable: @escaping Enable,
        setEnabled: @escaping SetEnabled
    ) {
        enableCommand = enable
        setEnabledCommand = setEnabled
    }

    func setEnabled(
        _ isEnabled: Bool,
        for candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledSafariContentBlockerRecord? {
        if isEnabled {
            return try await enableCommand(candidate)
        }
        return try await setEnabledCommand(
            candidate.extensionBundleIdentifier,
            false
        )
    }
}
