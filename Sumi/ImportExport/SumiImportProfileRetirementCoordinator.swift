import Foundation

@MainActor
final class SumiImportProfileRetirementCoordinator: SumiImportProfileRetiring {
    private let maintenanceService: SumiProfileMaintenanceService
    private let context: SumiProfileMaintenanceService.Context

    init(
        maintenanceService: SumiProfileMaintenanceService = .init(),
        context: SumiProfileMaintenanceService.Context
    ) {
        self.maintenanceService = maintenanceService
        self.context = context
    }

    func retireProfiles(
        _ profileIDs: Set<UUID>,
        fallbackProfileID: UUID
    ) async throws {
        for profileID in profileIDs.sorted(by: uuidOrder) {
            guard let fallback = context.profileManager.profiles.first(where: {
                $0.id == fallbackProfileID
            }) else {
                throw SumiImportProfileRetirementError.fallbackMissing(
                    fallbackProfileID
                )
            }
            guard let profile = context.profileManager.profiles.first(where: {
                $0.id == profileID
            }) else {
                if context.profileManager.profileReferenceAdmission.records()
                    .contains(where: {
                        $0.snapshot.id == profileID && $0.phase == .retired
                    }) {
                    continue
                }
                if context.profileManager.profileReferenceAdmission.records()
                    .contains(where: { $0.snapshot.id == profileID }) {
                    throw SumiImportProfileRetirementError.deferred(profileID)
                }
                throw SumiImportProfileRetirementError
                    .profileMissing(profileID)
            }

            switch await maintenanceService.retireProfile(
                profile,
                fallback: fallback,
                using: context
            ) {
            case .completed:
                continue
            case .failed(let message):
                throw SumiImportProfileRetirementFailure(
                    profileID: profileID,
                    message: message
                )
            case .migrationPending, .cleanupPending:
                throw SumiImportProfileRetirementError.deferred(profileID)
            }
        }
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

private struct SumiImportProfileRetirementFailure: LocalizedError {
    let profileID: UUID
    let message: String

    var errorDescription: String? {
        "Profile \(profileID.uuidString) could not be retired: \(message)"
    }
}
