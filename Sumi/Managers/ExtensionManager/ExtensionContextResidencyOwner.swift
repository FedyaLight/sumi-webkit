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

    func retainActiveExtensionContext(
        extensionId: String,
        profileId: UUID
    ) {
        retention.retainActiveContext(
            extensionID: extensionId,
            profileID: profileId
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
