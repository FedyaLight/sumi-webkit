import Foundation
import WebKit

/// Composition boundary for the two independent context-residency roles.
/// Physical retirement and lazy loading remain separate authorities; this
/// adapter exists only because WebKit consumers need both protocol surfaces.
@available(macOS 15.5, *)
@MainActor
final class ExtensionContextResidencyOwner {
    let retention: ExtensionContextRetentionOwner
    let loading: ExtensionContextLoadingOwner
    let settlement: ExtensionContextSettlementOwner

    init(
        retention: ExtensionContextRetentionOwner,
        loading: ExtensionContextLoadingOwner,
        settlement: ExtensionContextSettlementOwner
    ) {
        self.retention = retention
        self.loading = loading
        self.settlement = settlement
    }

    func touchLiveExtensionContext(extensionId: String, profileId: UUID) {
        retention.touch(extensionID: extensionId, profileID: profileId)
    }

    func enforceBoundedLiveExtensionContexts(
        keepingProfileId: UUID,
        keepingExtensionId: String
    ) {
        retention.enforceLimit(
            keepingProfileID: keepingProfileId,
            keepingExtensionID: keepingExtensionId
        )
    }

    func unloadExtensionContextsForInactiveProfiles(keepingProfileId: UUID) {
        retention.unloadInactiveProfiles(keepingProfileID: keepingProfileId)
    }

    func unloadExtensionContextIfLoaded(extensionId: String, profileId: UUID) {
        retention.unloadIfLoaded(extensionID: extensionId, profileID: profileId)
    }

    func quiesceForWebsiteDataMutation(profileIDs: Set<UUID>) -> Bool {
        retention.quiesce(profileIDs: profileIDs)
    }

    func ensureExtensionLoaded(
        extensionId: String,
        profileId: UUID
    ) async throws -> WKWebExtensionContext? {
        try await loading.ensureLoaded(
            extensionID: extensionId,
            profileID: profileId
        )
    }

    func ensureEnabledExtensionsLoaded(for profileId: UUID) async {
        await loading.ensureEnabledExtensionsLoaded(profileID: profileId)
    }

    func settleLoadedContext(_ loadedContext: ExtensionLoadedContext) -> Bool {
        settlement.settle(loadedContext)
    }
}

@available(macOS 15.5, *)
extension ExtensionContextResidencyOwner: ExtensionInactiveProfileContextRetiring {}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func touchLiveExtensionContext(extensionId: String, profileId: UUID) {
        contextResidencyOwner.touchLiveExtensionContext(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func enforceBoundedLiveExtensionContexts(
        keepingProfileId: UUID,
        keepingExtensionId: String
    ) {
        contextResidencyOwner.enforceBoundedLiveExtensionContexts(
            keepingProfileId: keepingProfileId,
            keepingExtensionId: keepingExtensionId
        )
    }

    func unloadExtensionContextsForInactiveProfiles(keepingProfileId: UUID) {
        contextResidencyOwner.unloadExtensionContextsForInactiveProfiles(
            keepingProfileId: keepingProfileId
        )
    }

    func unloadExtensionContextIfLoaded(extensionId: String, profileId: UUID) {
        contextResidencyOwner.unloadExtensionContextIfLoaded(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func quiesceForWebsiteDataMutation(profileIDs: Set<UUID>) -> Bool {
        optionsWindows.closeWindows(backedBy: profileIDs)
        actionPopupRetirement.closePopup(backedBy: profileIDs)
        return contextResidencyOwner.quiesceForWebsiteDataMutation(
            profileIDs: profileIDs
        )
    }

    @discardableResult
    func ensureExtensionLoaded(
        extensionId: String,
        profileId: UUID
    ) async throws -> WKWebExtensionContext? {
        try await contextResidencyOwner.ensureExtensionLoaded(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func ensureEnabledExtensionsLoaded(for profileId: UUID) async {
        await contextResidencyOwner.ensureEnabledExtensionsLoaded(for: profileId)
    }
}
