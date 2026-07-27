import Foundation

/// Retires and, when compensation is safe, restores the runtime that existed
/// before an installation candidate.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationRuntimeReplacement {
    struct PreviousRuntime {
        let entity: InstalledExtensionMetadata
        let profileIDs: Set<UUID>
        let shouldRecover: Bool
    }

    private let retirement: ExtensionRuntimeRetirement
    private let recovery: ExtensionRuntimeRecovery

    init(
        retirement: ExtensionRuntimeRetirement,
        recovery: ExtensionRuntimeRecovery
    ) {
        self.retirement = retirement
        self.recovery = recovery
    }

    func retire(
        _ entity: InstalledExtensionMetadata,
        mutationLease: ExtensionRuntimeMutationLease
    ) async throws -> PreviousRuntime {
        let result = retirement.retire(
            extensionID: entity.id,
            cause: .packageReplacement,
            mutationLease: mutationLease
        )
        guard result.completed else {
            guard result.completionStatus == .contextsRemaining else {
                throw CancellationError()
            }
            do {
                try await recovery.recoverEnabledRuntime(
                    from: entity,
                    profileIDs: result.initialProfileIDs,
                    mutationLease: mutationLease
                )
            } catch {
                throw ExtensionError.installationFailed(
                    "Package replacement retirement was partial and runtime recovery failed: "
                        + error.localizedDescription
                )
            }
            throw ExtensionError.installationFailed(
                "Extension runtime could not be unloaded for profiles: "
                    + result.remainingProfileIDs.map(\.uuidString).sorted()
                    .joined(separator: ", ")
            )
        }
        return PreviousRuntime(
            entity: entity,
            profileIDs: result.initialProfileIDs,
            shouldRecover: entity.isEnabled
        )
    }

    func recover(
        _ previousRuntime: PreviousRuntime,
        mutationLease: ExtensionRuntimeMutationLease
    ) async throws {
        guard previousRuntime.shouldRecover else { return }
        try await recovery.recoverEnabledRuntime(
            from: previousRuntime.entity,
            profileIDs: previousRuntime.profileIDs,
            mutationLease: mutationLease
        )
    }
}

@available(macOS 15.5, *)
extension ExtensionInstallationRuntimeReplacement:
    ExtensionInstallationPreviousRuntimeRecovering {}
