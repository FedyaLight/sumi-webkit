//
//  SumiStartupSessionCoordinator.swift
//  Sumi
//

import Foundation

@MainActor
final class SumiStartupSessionCoordinator {
    struct Dependencies {
        let hasLoadedInitialTabData: @MainActor () -> Bool
        let startupMode: @MainActor () -> SumiStartupMode?
        let startupWindow: @MainActor () -> BrowserWindowState?
        let applyStartupPolicy: @MainActor (SumiStartupMode) -> Void
    }

    private var didApplyStartupPolicy = false
    private var isApplyingStartupPolicy = false

    func applyIfReady(dependencies: Dependencies) {
        guard !didApplyStartupPolicy,
              !isApplyingStartupPolicy,
              dependencies.hasLoadedInitialTabData(),
              let startupMode = dependencies.startupMode(),
              dependencies.startupWindow() != nil
        else {
            return
        }

        isApplyingStartupPolicy = true
        defer { isApplyingStartupPolicy = false }

        dependencies.applyStartupPolicy(startupMode)
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
        existingSessions: Set<WindowSessionSnapshot>,
        hasStartupWindow: Bool
    ) -> Plan {
        let hasArchivedSessionInExistingWindow = archivedSnapshots.contains {
            existingSessions.contains($0.session)
        }

        if hasArchivedSessionInExistingWindow {
            return Plan(
                primarySnapshotForStartupWindow: nil,
                additionalSnapshots: archivedSnapshots.filter {
                    !existingSessions.contains($0.session)
                }
            )
        }

        guard hasStartupWindow, let primarySnapshot = archivedSnapshots.first else {
            return Plan(
                primarySnapshotForStartupWindow: nil,
                additionalSnapshots: archivedSnapshots.filter {
                    !existingSessions.contains($0.session)
                }
            )
        }

        return Plan(
            primarySnapshotForStartupWindow: primarySnapshot,
            additionalSnapshots: Array(archivedSnapshots.dropFirst())
        )
    }
}

@MainActor
extension BrowserManager {
    func reconcileStartupSessionIfPossible() {
        startupSessionRestoreOwner.reconcileIfReady(
            dependencies: .init(
                hasLoadedInitialTabData: { [weak self] in
                    self?.tabManager.hasLoadedInitialData ?? false
                },
                startupMode: { [weak self] in
                    self?.sumiSettings?.startupMode
                },
                startupWindow: { [weak self] in
                    self?.startupPolicyOwner.firstRegularWindowForStartupPolicy
                },
                applyStartupPolicy: { [weak self] mode in
                    self?.startupPolicyOwner.applyStartupPolicy(mode)
                }
            )
        )
    }

    func applyStartupPolicy(_ mode: SumiStartupMode) {
        startupPolicyOwner.applyStartupPolicy(mode)
    }
}
