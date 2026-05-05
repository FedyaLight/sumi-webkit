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
        windowRegistry?.allWindows
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .first { !$0.isIncognito }
    }

    func reconcileStartupSessionIfPossible() {
        startupSessionCoordinator.applyIfReady(browserManager: self)
    }

    func applyStartupPolicy(_ mode: SumiStartupMode) {
        switch mode {
        case .restorePreviousSession:
            restoreAdditionalStartupWindowsIfNeeded()
        case .nothing:
            applyCleanStartupPolicy(opening: nil)
        case .specificPage:
            applyCleanStartupPolicy(opening: sumiSettings?.resolvedStartupPageURL ?? SumiSurface.emptyTabURL)
        }
    }

    private func applyCleanStartupPolicy(opening startupURL: URL?) {
        archiveLoadedStartupSessionForManualRestore()

        tabManager.resetRegularTabsAndShortcutLiveInstancesForStartup()

        guard let windowState = firstRegularWindowForStartupPolicy else { return }
        resetWindowStatesForCleanStartup(selectedWindow: windowState)

        if let startupURL {
            let targetSpace = windowState.currentSpaceId.flatMap { space(for: $0) }
                ?? tabManager.currentSpace
                ?? tabManager.spaces.first
            let tab = tabManager.createNewTab(
                url: startupURL.absoluteString,
                in: targetSpace,
                activate: false
            )
            selectTab(tab, in: windowState, loadPolicy: .deferred)
        } else {
            showEmptyState(in: windowState)
        }

        Task { [weak self] in
            _ = await self?.tabManager.persistFullReconcileAwaitingResult(
                reason: "startup clean policy"
            )
        }
    }

    private func archiveLoadedStartupSessionForManualRestore() {
        let archivedWindowSnapshots = startupLastSessionWindowSnapshots.isEmpty
            ? currentRegularWindowSnapshots(excludingWindowID: nil)
            : startupLastSessionWindowSnapshots
        let tabSnapshot = tabManager._buildSnapshot()
        guard !archivedWindowSnapshots.isEmpty || !tabSnapshot.tabs.isEmpty else {
            return
        }
        startupLastSessionWindowSnapshots = archivedWindowSnapshots
        startupLastSessionTabSnapshot = tabSnapshot
        lastSessionWindowsStore.updateSnapshots(
            archivedWindowSnapshots,
            tabSnapshot: tabSnapshot
        )
        didConsumeStartupLastSessionRestoreOffer = false
    }

    private func resetWindowStatesForCleanStartup(selectedWindow: BrowserWindowState) {
        for windowState in windowRegistry?.allWindows ?? [] where !windowState.isIncognito {
            let fallbackSpaceId = windowState.currentSpaceId
                ?? tabManager.currentSpace?.id
                ?? tabManager.spaces.first?.id

            windowState.currentTabId = nil
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
            windowState.activeTabForSpace.removeAll()
            windowState.recentRegularTabIdsBySpace.removeAll()
            windowState.selectedShortcutPinForSpace.removeAll()
            windowState.isShowingEmptyState = windowState.id == selectedWindow.id
            windowState.commandPalettePresentationReason =
                windowState.id == selectedWindow.id ? .emptySpace : .none
            windowState.currentSpaceId = fallbackSpaceId
            windowState.currentProfileId = fallbackSpaceId.flatMap { space(for: $0)?.profileId }
                ?? currentProfile?.id
            windowState.isAwaitingInitialSessionResolution = false
            splitManager.restoreSession(nil, for: windowState.id)
            windowState.refreshCompositor()
        }
    }

    private func restoreAdditionalStartupWindowsIfNeeded() {
        guard !startupLastSessionWindowSnapshots.isEmpty else { return }

        didConsumeStartupLastSessionRestoreOffer = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let existingSessions = Set(
                self.currentRegularWindowSnapshots(excludingWindowID: nil).map(\.session)
            )
            let startupWindow = self.firstRegularWindowForStartupPolicy
            let restorationPlan = StartupWindowRestorationPlanner.plan(
                archivedSnapshots: self.startupLastSessionWindowSnapshots,
                existingSessions: existingSessions,
                hasStartupWindow: startupWindow != nil
            )

            if let startupWindow,
               let primarySnapshot = restorationPlan.primarySnapshotForStartupWindow
            {
                self.windowSessionService.applyWindowSessionSnapshot(
                    primarySnapshot.session,
                    to: startupWindow,
                    delegate: self
                )
            }

            let refreshedExistingSessions = Set(
                self.currentRegularWindowSnapshots(excludingWindowID: nil).map(\.session)
            )
            let unresolvedSnapshotsToRestore = restorationPlan.additionalSnapshots.filter {
                !refreshedExistingSessions.contains($0.session)
            }
            for snapshot in unresolvedSnapshotsToRestore {
                await self.reopenWindow(from: snapshot.session)
            }
            self.refreshLastSessionWindowsStore(excludingWindowID: nil)
        }
    }
}
