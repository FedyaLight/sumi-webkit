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

extension SumiStartupSessionCoordinator.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            hasLoadedInitialTabData: { [weak browserManager] in
                browserManager?.tabManager.hasLoadedInitialData ?? false
            },
            startupMode: { [weak browserManager] in
                browserManager?.sumiSettings?.startupMode
            },
            startupWindow: { [weak browserManager] in
                browserManager?.startupPolicyOwner.firstRegularWindowForStartupPolicy
            },
            applyStartupPolicy: { [weak browserManager] mode in
                browserManager?.startupPolicyOwner.applyStartupPolicy(mode)
            }
        )
    }
}
