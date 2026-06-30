//
//  SumiStartupSessionCoordinator.swift
//  Sumi
//

import Foundation

@MainActor
final class SumiStartupSessionCoordinator {
    private var didApplyStartupPolicy = false
    private var isApplyingStartupPolicy = false

    func applyIfReady(browserManager: BrowserManager) {
        guard !didApplyStartupPolicy,
              !isApplyingStartupPolicy,
              browserManager.tabManager.hasLoadedInitialData,
              let settings = browserManager.sumiSettings,
              browserManager.firstRegularWindowForStartupPolicy != nil
        else {
            return
        }

        isApplyingStartupPolicy = true
        defer { isApplyingStartupPolicy = false }

        browserManager.applyStartupPolicy(settings.startupMode)
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
    var firstRegularWindowForStartupPolicy: BrowserWindowState? {
        startupPolicyOwner.firstRegularWindowForStartupPolicy
    }

    func reconcileStartupSessionIfPossible() {
        startupSessionRestoreOwner.reconcileIfReady(browserManager: self)
    }

    func applyStartupPolicy(_ mode: SumiStartupMode) {
        startupPolicyOwner.applyStartupPolicy(mode)
    }
}
