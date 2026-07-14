//
//  SumiExtensionsSettingsPane.swift
//  Sumi
//

import Foundation
import SwiftUI

struct SumiExtensionsSettingsPane: View {
    let extensionsModule: SumiExtensionsModule
    let currentProfileID: UUID?
    let extensionSurfaceStore: BrowserExtensionSurfaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SumiSettingsModuleToggleGate(descriptor: .extensions) {
                ExtensionSettingsRuntimeGate(
                    readiness: ExtensionSettingsRuntimeReadiness(
                        extensionsModule: extensionsModule
                    )
                ) {
                    ExtensionSettingsEnabledContent(
                        extensionsModule: extensionsModule,
                        currentProfileID: currentProfileID,
                        extensionSurfaceStore: extensionSurfaceStore
                    )
                }
            }
        }
    }
}

enum ExtensionSettingsRuntimeReadiness: Equatable {
    case ready
    case unavailable

    @MainActor
    init(extensionsModule: SumiExtensionsModule) {
        self = extensionsModule.extensionRuntimeIsAvailable()
            ? .ready
            : .unavailable
    }
}

struct ExtensionSettingsRuntimeGate<EnabledContent: View>: View {
    let readiness: ExtensionSettingsRuntimeReadiness
    @ViewBuilder let enabledContent: () -> EnabledContent

    var body: some View {
        switch readiness {
        case .ready:
            enabledContent()
        case .unavailable:
            Text("Enable the Extensions module to manage installed extensions.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ExtensionSettingsEnabledContent: View {
    let extensionsModule: SumiExtensionsModule
    let currentProfileID: UUID?
    @ObservedObject private var extensionSurfaceStore: BrowserExtensionSurfaceStore
    @State private var scanSession: ExtensionSettingsScanSession

    init(
        extensionsModule: SumiExtensionsModule,
        currentProfileID: UUID?,
        extensionSurfaceStore: BrowserExtensionSurfaceStore
    ) {
        self.extensionsModule = extensionsModule
        self.currentProfileID = currentProfileID
        _extensionSurfaceStore = ObservedObject(
            wrappedValue: extensionSurfaceStore
        )
        _scanSession = State(
            initialValue: ExtensionSettingsScanSession(
                scan: ExtensionSettingsSafariScanner.scanInstalledExtensions,
                synchronize: { [weak extensionsModule] candidates in
                    guard let extensionsModule else {
                        throw ExtensionSettingsCapabilityError.unavailable
                    }
                    let result = await extensionsModule
                        .syncDiscoveredSafariWebExtensions(candidates)
                    return ExtensionSettingsImportResult(
                        importedExtensionCount: result.addedExtensions.count,
                        failedMessages: result.failedMessages,
                        skippedUnreadableCount: result.skippedUnreadableCount
                    )
                },
                loadContentBlockers: { [weak extensionsModule] in
                    guard let extensionsModule else {
                        throw ExtensionSettingsCapabilityError.unavailable
                    }
                    return extensionsModule.installedSafariContentBlockers()
                }
            )
        )
    }

    var body: some View {
        let projection = ExtensionSettingsInstalledProjection(
            extensions: extensionSurfaceStore.installedExtensions,
            siteAccessPoliciesByExtensionID:
                extensionSurfaceStore.siteAccessPoliciesByExtensionID
        )
        let snapshot = scanSession.snapshot

        VStack(alignment: .leading, spacing: 16) {
            ExtensionSettingsInstalledSection(
                projection: projection,
                scanState: scanSession.state,
                commands: installedCommands,
                onRefresh: scanSession.refresh
            )

            if snapshot.contentBlockerCandidates.isEmpty == false {
                ExtensionSettingsContentBlockersSection(
                    candidates: snapshot.contentBlockerCandidates,
                    records: snapshot.contentBlockerRecords,
                    commands: contentBlockerCommands,
                    onRecordChanged: { [weak scanSession] record in
                        scanSession?.updateContentBlockerRecord(record)
                    }
                )
            }

            if snapshot.unsupportedCandidates.isEmpty == false {
                ExtensionSettingsUnsupportedSection(
                    candidates: snapshot.unsupportedCandidates
                )
            }
        }
        .onAppear {
            scanSession.beginIfNeeded()
        }
        .onChange(of: siteAccessPolicyRefreshKey, initial: true) { _, _ in
            extensionSurfaceStore.refreshSiteAccessPolicies(
                profileId: currentProfileID
            )
        }
        .onDisappear {
            scanSession.cancel()
            extensionSurfaceStore.refreshSiteAccessPolicies(profileId: nil)
        }
    }

    private var siteAccessPolicyRefreshKey: ExtensionsSiteAccessPolicyRefreshKey {
        ExtensionsSiteAccessPolicyRefreshKey(
            profileID: currentProfileID,
            extensionIDs: extensionSurfaceStore.installedExtensions.map(\.id)
        )
    }

    private var installedCommands: ExtensionSettingsInstalledCommands {
        ExtensionSettingsInstalledCommands(
            setEnabled: { [weak extensionsModule] extensionID, isEnabled in
                guard let extensionsModule else {
                    throw ExtensionSettingsCapabilityError.unavailable
                }
                if isEnabled {
                    _ = try await extensionsModule.enableExtension(extensionID)
                } else {
                    try await extensionsModule.disableExtension(extensionID)
                }
            },
            setDefaultSiteAccess: {
                [weak extensionsModule] extensionID, access in
                extensionsModule?.setDefaultSiteAccess(
                    access,
                    extensionId: extensionID,
                    profileId: currentProfileID
                )
            },
            setPrivateAccess: {
                [weak extensionsModule] extensionID, isAllowed in
                extensionsModule?.setPrivateBrowsingAccess(
                    isAllowed,
                    extensionId: extensionID,
                    profileId: currentProfileID
                )
            },
            setConfiguredSiteAccess: {
                [weak extensionsModule] extensionID, matchPattern, access in
                extensionsModule?.setConfiguredSiteAccess(
                    access,
                    extensionId: extensionID,
                    profileId: currentProfileID,
                    matchPatternString: matchPattern
                )
            },
            openOptions: { [weak extensionsModule] extensionID in
                await extensionsModule?.openOptionsPage(
                    extensionId: extensionID,
                    profileId: currentProfileID
                )
            }
        )
    }

    private var contentBlockerCommands: ExtensionSettingsContentBlockerCommands {
        ExtensionSettingsContentBlockerCommands(
            enable: { [weak extensionsModule] candidate in
                guard let extensionsModule else {
                    throw ExtensionSettingsCapabilityError.unavailable
                }
                return try await extensionsModule.enableSafariContentBlocker(
                    from: candidate
                )
            },
            setEnabled: {
                [weak extensionsModule] bundleIdentifier, isEnabled in
                guard let extensionsModule else {
                    throw ExtensionSettingsCapabilityError.unavailable
                }
                return try await extensionsModule.setSafariContentBlockerEnabled(
                    isEnabled,
                    bundleIdentifier: bundleIdentifier
                )
            }
        )
    }
}

private struct ExtensionsSiteAccessPolicyRefreshKey: Equatable {
    let profileID: UUID?
    let extensionIDs: [String]
}
