import Foundation
import SumiDomain

enum StartupNormalTabMaterializationPolicy {
    static func shouldDefer(
        appliedProtectionLevel: SumiProtectionLevel,
        hasFinishedStartupProtectionRestore: Bool
    ) -> Bool {
        appliedProtectionLevel != .off && !hasFinishedStartupProtectionRestore
    }
}

@MainActor
final class BrowserStartupProtectionRuntime {
    private let materializationGate: BrowserStartupMaterializationGate
    private let deferredTabs: BrowserStartupDeferredTabMaterialization
    private let visibleWindows: BrowserStartupVisibleWindowSettlement

    private var startupProtectionRestoreTask: Task<Void, Never>?

    init(
        materializationGate: BrowserStartupMaterializationGate,
        deferredTabs: BrowserStartupDeferredTabMaterialization,
        visibleWindows: BrowserStartupVisibleWindowSettlement
    ) {
        self.materializationGate = materializationGate
        self.deferredTabs = deferredTabs
        self.visibleWindows = visibleWindows
    }

    var shouldDeferNormalTabMaterializationDuringStartup: Bool {
        materializationGate.shouldDeferNormalTabMaterialization
    }

    func beginProtectionRestoreForStartupIfNeeded() {
        guard !materializationGate.hasFinishedProtectionRestore else { return }
        guard startupProtectionRestoreTask == nil else { return }
        guard !RuntimeDiagnostics.isRunningTests else {
            finishStartupProtectionRestore()
            return
        }

        startupProtectionRestoreTask = Task { @MainActor [weak self] in
            await self?.restoreProtectionForStartupIfNeeded()
        }
    }

    func canMaterializeWebViewDuringStartup(_ tab: Tab) -> Bool {
        materializationGate.canMaterialize(tab)
    }

    func deferBackgroundTabUntilStartupReady(_ tab: Tab) {
        deferredTabs.deferTab(tab)
    }

    func cancelProtectionRestoreTask() {
        startupProtectionRestoreTask?.cancel()
        startupProtectionRestoreTask = nil
    }

    private func restoreProtectionForStartupIfNeeded() async {
        let startupTrace = StartupPerformanceTrace.protectionRestoreStarted()
        defer {
            StartupPerformanceTrace.protectionRestoreFinished(startupTrace)
            finishStartupProtectionRestore()
        }

        do {
            try await materializationGate
                .restoreAppliedProtectionLevelForStartup()
        } catch {
            RuntimeDiagnostics.debug(
                "Protection startup restore failed: \(error.localizedDescription)",
                category: "Protection"
            )
        }
    }

    func finishStartupProtectionRestore() {
        guard materializationGate.finishProtectionRestore() else { return }
        deferredTabs.materializeDeferredTabs()
        visibleWindows.settleVisibleWindows()

#if DEBUG
        Task { @MainActor in
            await Task.yield()
            StartupPerformanceTrace.postStartupIdlePoint()
        }
#endif
    }

#if DEBUG
    func drainProtectionRestoreTaskForTests(cancel: Bool = false) async {
        if cancel {
            startupProtectionRestoreTask?.cancel()
        }
        if let startupProtectionRestoreTask {
            await startupProtectionRestoreTask.value
            self.startupProtectionRestoreTask = nil
        }
    }
#endif
}
