//
//  SumiStartupSessionCoordinator.swift
//  Sumi
//

import Foundation

@MainActor
final class SumiStartupSessionCoordinator {
    private var didApplyStartupPolicy = false
    private var isApplyingStartupPolicy = false

    func applyIfReady(
        hasLoadedInitialTabData: @MainActor () -> Bool,
        startupMode: @MainActor () -> SumiStartupMode?,
        startupWindow: @MainActor () -> BrowserWindowState?,
        applyStartupPolicy: @MainActor (SumiStartupMode) -> Void
    ) {
        guard !didApplyStartupPolicy,
              !isApplyingStartupPolicy,
              hasLoadedInitialTabData(),
              let startupMode = startupMode(),
              startupWindow() != nil
        else {
            return
        }

        isApplyingStartupPolicy = true
        defer { isApplyingStartupPolicy = false }

        applyStartupPolicy(startupMode)
        didApplyStartupPolicy = true
    }
}

enum StartupWindowRestorationPlanner {
    struct Plan {
        var primarySnapshotForStartupWindow: LastSessionWindowSnapshot?
        var additionalSnapshots: [LastSessionWindowSnapshot]
    }

    static func plan(
        archivedSnapshots: [LastSessionWindowSnapshot],
        existingWindowIDs: Set<UUID>,
        hasStartupWindow: Bool,
        startupWindowArchiveID: UUID? = nil
    ) -> Plan {
        let missingSnapshots = archivedSnapshots.filter {
            existingWindowIDs.contains($0.id) == false
        }
        let startupWindowAlreadyRestored = startupWindowArchiveID.map { archiveID in
            archivedSnapshots.contains { $0.id == archiveID }
        } ?? false
        guard hasStartupWindow,
              startupWindowAlreadyRestored == false,
              let primarySnapshot = missingSnapshots.first else {
            return Plan(
                primarySnapshotForStartupWindow: nil,
                additionalSnapshots: missingSnapshots
            )
        }

        return Plan(
            primarySnapshotForStartupWindow: primarySnapshot,
            additionalSnapshots: Array(missingSnapshots.dropFirst())
        )
    }
}
