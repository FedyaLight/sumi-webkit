import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextLoadingOwner {
    typealias EnabledExtensionLoad = @MainActor (
        ExtensionEntity,
        UUID
    ) async throws -> Void

    private let installedExtensions: InstalledExtensionCollection
    private let runtimeAccess: ExtensionRuntimeAccess
    private let metadataStore: ExtensionInstallationMetadataStore
    private let retention: ExtensionContextRetentionOwner
    private let runtimeIsEnabled: @MainActor () -> Bool
    private let loadEnabledExtension: EnabledExtensionLoad

    init(
        installedExtensions: InstalledExtensionCollection,
        runtimeAccess: ExtensionRuntimeAccess,
        metadataStore: ExtensionInstallationMetadataStore,
        retention: ExtensionContextRetentionOwner,
        runtimeIsEnabled: @escaping @MainActor () -> Bool,
        loadEnabledExtension: @escaping EnabledExtensionLoad
    ) {
        self.installedExtensions = installedExtensions
        self.runtimeAccess = runtimeAccess
        self.metadataStore = metadataStore
        self.retention = retention
        self.runtimeIsEnabled = runtimeIsEnabled
        self.loadEnabledExtension = loadEnabledExtension
    }

    func ensureLoaded(
        extensionID: String,
        profileID: UUID
    ) async throws -> WKWebExtensionContext? {
        guard runtimeIsEnabled() else { return nil }
        runtimeAccess.ensureExtensionController(profileID)
        if let context = runtimeAccess.getExtensionContext(extensionID, profileID),
           context.isLoaded {
            retain(extensionID: extensionID, profileID: profileID)
            return context
        }
        guard let entity = try metadataStore.extensionEntity(for: extensionID),
              entity.isEnabled
        else { return nil }
        try await loadEnabledExtension(entity, profileID)
        retain(extensionID: extensionID, profileID: profileID)
        return runtimeAccess.getExtensionContext(extensionID, profileID)
    }

    func ensureEnabledExtensionsLoaded(profileID: UUID) async {
        guard runtimeIsEnabled() else { return }
        runtimeAccess.ensureExtensionController(profileID)
        for record in installedExtensions.records where record.isEnabled {
            guard runtimeAccess.getExtensionContext(record.id, profileID) == nil
            else { continue }
            do {
                guard let entity = try metadataStore.extensionEntity(for: record.id),
                      entity.isEnabled
                else { continue }
                try await loadEnabledExtension(entity, profileID)
            } catch {
                ExtensionManager.logger.error(
                    "Failed to load enabled extension \(record.id, privacy: .public) for profile \(profileID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func retain(extensionID: String, profileID: UUID) {
        retention.touch(extensionID: extensionID, profileID: profileID)
        retention.enforceLimit(
            keepingProfileID: profileID,
            keepingExtensionID: extensionID
        )
    }
}
