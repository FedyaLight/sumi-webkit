import Foundation

@MainActor
final class SumiProfileMaintenanceService {
    enum RetirementResult: Equatable {
        case completed
        case failed(String)
        case migrationPending
        case cleanupPending
    }

    struct Context {
        var profileManager: ProfileManager
        var migrateReferences: @MainActor (
            UUID,
            Profile
        ) async -> Bool
        var sealProfileRuntime: @MainActor (UUID) async -> Bool
        var cleanupDependencies: ProfileRetirementCleanupDependencies
    }

    func retireProfile(
        _ profile: Profile,
        using context: Context
    ) async -> RetirementResult {
        guard context.profileManager.profiles.contains(where: {
            $0.id == profile.id
        }) else {
            return .failed("The profile is unavailable.")
        }
        if let replacement = context.profileManager.profiles.first(where: {
            $0.id != profile.id
        }) {
            return await retireProfile(
                profile,
                fallback: replacement,
                using: context,
                provisionalFallback: nil
            )
        }

        let replacement: Profile
        do {
            replacement = try context.profileManager.createProfile(
                name: ProfileManager.defaultProfileName
            )
        } catch {
            return .failed("A new default profile could not be created.")
        }
        return await retireProfile(
            profile,
            fallback: replacement,
            using: context,
            provisionalFallback: replacement
        )
    }

    func retireProfile(
        _ profile: Profile,
        fallback replacement: Profile,
        using context: Context
    ) async -> RetirementResult {
        await retireProfile(
            profile,
            fallback: replacement,
            using: context,
            provisionalFallback: nil
        )
    }

    private func retireProfile(
        _ profile: Profile,
        fallback replacement: Profile,
        using context: Context,
        provisionalFallback: Profile?
    ) async -> RetirementResult {
        guard profile.id != replacement.id,
              context.profileManager.profiles.contains(where: { $0.id == profile.id }),
              context.profileManager.profiles.contains(where: { $0.id == replacement.id })
        else {
            return .failed("The profile or its replacement is unavailable.")
        }
        let token: ProfileRetirementToken
        do {
            token = try context.profileManager.profileReferenceAdmission.reserve(
                profile: profile,
                fallbackID: replacement.id
            )
        } catch {
            rollbackFallbackIfNeeded(
                provisionalFallback,
                using: context
            )
            return .failed("The profile could not be reserved for safe deletion.")
        }

        do {
            guard try context.profileManager.beginReferenceMigration(token) else {
                throw ProfileDeletionCleanupFailure.staleRetirement
            }
        } catch {
            let reservationWasCancelled = cancelReservation(token, using: context)
            rollbackFallbackIfNeeded(
                reservationWasCancelled ? provisionalFallback : nil,
                using: context
            )
            return .failed("The profile could not begin safe reference migration.")
        }

        guard await context.migrateReferences(
            profile.id,
            replacement
        ) else {
            RuntimeDiagnostics.emit(
                "[ProfileRetirement] Runtime/reference migration deferred for "
                    + profile.id.uuidString
            )
            return .migrationPending
        }
        guard context.profileManager.profileReferenceAdmission.validate(token)
        else {
            RuntimeDiagnostics.emit(
                "[ProfileRetirement] Migration token became stale for "
                    + profile.id.uuidString
            )
            return .migrationPending
        }

        guard await context.sealProfileRuntime(profile.id) else {
            RuntimeDiagnostics.emit(
                "[ProfileRetirement] Runtime drain deferred for "
                    + profile.id.uuidString
            )
            return .migrationPending
        }
        guard context.profileManager.profileReferenceAdmission.validate(token)
        else {
            RuntimeDiagnostics.emit(
                "[ProfileRetirement] Runtime drain lost its migration token for "
                    + profile.id.uuidString
            )
            return .migrationPending
        }

        do {
            guard try context.profileManager.commitLogicalDeletion(token) else {
                RuntimeDiagnostics.emit(
                    "[ProfileRetirement] Logical deletion commit was rejected for "
                        + profile.id.uuidString
                )
                return .migrationPending
            }
        } catch {
            RuntimeDiagnostics.emit(
                "[ProfileRetirement] Logical deletion commit failed for "
                    + "\(profile.id.uuidString): \(error)"
            )
            return .migrationPending
        }

        return await completeRetirementCleanup(
            profile,
            token: token,
            cleanup: ProfileRetirementCleanupComposition.make(
                profile: profile,
                dependencies: context.cleanupDependencies
            ),
            using: context
        )
    }

    private func completeRetirementCleanup(
        _ profile: Profile,
        token: ProfileRetirementToken,
        cleanup: ProfileDeletionCleanupOrchestrator,
        using context: Context
    ) async -> RetirementResult {
        var pendingStep = ProfileRetirementCleanupStep.websiteData
        do {
            guard try context.profileManager.profileReferenceAdmission
                .beginCleaning(token),
                  let record = context.profileManager.profileReferenceAdmission
                    .record(for: token)
            else {
                throw ProfileDeletionCleanupFailure.staleRetirement
            }
            pendingStep = record.nextCleanupStep
            try await cleanup.cleanup(
                profileId: profile.id,
                startingAt: record.nextCleanupStep,
                checkpoint: { completedStep in
                    guard try context.profileManager.profileReferenceAdmission
                        .completeCleanupStep(completedStep, using: token) else {
                        throw ProfileDeletionCleanupFailure.staleRetirement
                    }
                    pendingStep = completedStep.successor
                        ?? .completed
                }
            )
            guard try context.profileManager.profileReferenceAdmission
                .markRetired(token) else {
                throw ProfileDeletionCleanupFailure.staleRetirement
            }
            return .completed
        } catch {
            RuntimeDiagnostics.emit(
                "[ProfileRetirement] Cleanup deferred for "
                    + "\(profile.id.uuidString) at "
                    + "\(pendingStep.rawValue): \(error)"
            )
            return .cleanupPending
        }
    }

    private func cancelReservation(
        _ token: ProfileRetirementToken,
        using context: Context
    ) -> Bool {
        do {
            return try context.profileManager.profileReferenceAdmission.cancel(
                token
            )
        } catch {
            RuntimeDiagnostics.emit(
                "[ProfileRetirement] Failed to cancel reservation: \(error)"
            )
            return false
        }
    }

    private func rollbackFallbackIfNeeded(
        _ fallback: Profile?,
        using context: Context
    ) {
        guard let fallback else { return }
        do {
            guard try context.profileManager
                .rollbackRetirementFallbackCreation(fallback) else {
                RuntimeDiagnostics.emit(
                    "[ProfileRetirement] Provisional fallback could not be rolled back"
                )
                return
            }
        } catch {
            RuntimeDiagnostics.emit(
                "[ProfileRetirement] Provisional fallback rollback failed: \(error)"
            )
        }
    }
}

private enum ProfileDeletionCleanupFailure: Error {
    case staleRetirement
}
