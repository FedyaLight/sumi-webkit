import Foundation

/// Restores every profile that held an enabled extension before a partially
/// completed lifecycle transaction. Profiles are attempted independently so
/// one failure cannot strand all later profiles without recovery attempts.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeRecovery {
    private let activation: ExtensionEnabledRuntimeActivation

    init(
        activation: ExtensionEnabledRuntimeActivation
    ) {
        self.activation = activation
    }

    func recoverEnabledRuntime(
        from entity: InstalledExtensionMetadata,
        profileIDs: Set<UUID>,
        mutationLease: ExtensionRuntimeMutationLease
    ) async throws {
        var failures: [String] = []
        for profileID in profileIDs.sorted(by: {
            $0.uuidString < $1.uuidString
        }) {
            do {
                try await activation.recover(
                    entity: entity,
                    profileID: profileID,
                    mutationLease: mutationLease
                )
            } catch {
                failures.append(
                    "\(profileID.uuidString): \(error.localizedDescription)"
                )
            }
        }
        guard failures.isEmpty else {
            throw ExtensionError.installationFailed(
                "Runtime recovery failed for profiles "
                    + failures.joined(separator: "; ")
            )
        }
    }
}
