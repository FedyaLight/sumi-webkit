//
//  BrowserLifecycleBundle.swift
//  Sumi
//
//  Capability bag: process lifecycle owners (shutdown, keyboard commands, init wiring).
//

import Combine
import Foundation

/// Groups process-lifecycle BrowserManager owners so shutdown / keyboard /
/// initialization wiring attach here instead of as peer `lazy var` Owners on
/// the BrowserManager façade.
@MainActor
final class BrowserLifecycleBundle {
    let shutdownCleanupOwner: BrowserShutdownCleanupOwner
    let keyboardShortcutCommandOwner: BrowserKeyboardShortcutCommandOwner
    let initializationWiringOwner: BrowserManagerInitializationWiringOwner

    init(browserManager: BrowserManager) {
        self.shutdownCleanupOwner = BrowserShutdownCleanupOwner(
            browserManager: browserManager
        )
        self.keyboardShortcutCommandOwner = BrowserKeyboardShortcutCommandOwner(
            browserManager: browserManager
        )
        self.initializationWiringOwner = BrowserManagerInitializationWiringOwner(
            tabStructureEventBus: browserManager.tabStructureEventBus,
            attachShellRuntime: { [weak browserManager] in
                guard let browserManager else { return }
                BrowserCompositionRoot.attachShellRuntime(to: browserManager)
            },
            attachRuntimeWiring: { [weak browserManager] in
                guard let browserManager else { return AnyCancellable {} }
                return BrowserManagerRuntimeWiring.attach(to: browserManager)
            },
            handleTabManagerDataLoaded: { [weak browserManager] in
                browserManager?.handleTabManagerDataLoaded()
            },
            scheduleBrowsingDataRetentionCleanup: { [weak browserManager] in
                browserManager?.privacyBundle.automaticDataCleanupOwner
                    .scheduleAutomaticBrowsingDataCleanup(
                        reason: "retention-setting-changed",
                        force: true,
                        delayNanoseconds: 0
                    )
            },
            beginProtectionRestoreForStartupIfNeeded: { [weak browserManager] in
                browserManager?.beginProtectionRestoreForStartupIfNeeded()
            }
        )
    }
}
