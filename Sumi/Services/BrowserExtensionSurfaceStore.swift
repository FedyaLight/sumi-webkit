//
//  BrowserExtensionSurfaceStore.swift
//  Sumi
//
//  Thin observable projection of installed extension metadata plus any
//  already-published WebExtension action state.
//

import AppKit
import Combine
import Foundation

struct BrowserExtensionActionSurfaceState {
    var extensionID: String
    var label: String
    var badgeText: String
    var hasUnreadBadgeText: Bool
    var isEnabled: Bool
    var presentsPopup: Bool
    var icon: NSImage?
}

@MainActor
final class BrowserExtensionSurfaceStore: ObservableObject {
    @Published private(set) var installedExtensions: [InstalledExtension] = []
    @Published private(set) var actionStatesByExtensionID:
        [String: BrowserExtensionActionSurfaceState] = [:]

    private var cancellables: Set<AnyCancellable> = []
    private var scheduledInstalledExtensionsGeneration = 0
    private var scheduledActionStatesGeneration = 0

    init(extensionManager: ExtensionManager?) {
        bind(extensionManager)
    }

    var enabledExtensions: [InstalledExtension] {
        installedExtensions.filter(\.isEnabled)
    }

    func bind(_ extensionManager: ExtensionManager?) {
        cancellables.removeAll()

        guard let extensionManager else {
            scheduleInstalledExtensionsUpdate([])
            scheduleActionStatesUpdate([:])
            return
        }

        extensionManager.$installedExtensions
            .sink { [weak self] installedExtensions in
                self?.scheduleInstalledExtensionsUpdate(installedExtensions)
            }
            .store(in: &cancellables)

        extensionManager.$actionStatesByExtensionID
            .sink { [weak self] actionStates in
                self?.scheduleActionStatesUpdate(actionStates)
            }
            .store(in: &cancellables)
    }

    private func scheduleInstalledExtensionsUpdate(
        _ installedExtensions: [InstalledExtension]
    ) {
        scheduledInstalledExtensionsGeneration &+= 1
        let generation = scheduledInstalledExtensionsGeneration
        Task { @MainActor [weak self] in
            await Task.yield()
            guard self?.scheduledInstalledExtensionsGeneration == generation else {
                return
            }
            self?.installedExtensions = installedExtensions
        }
    }

    private func scheduleActionStatesUpdate(
        _ actionStates: [String: BrowserExtensionActionSurfaceState]
    ) {
        scheduledActionStatesGeneration &+= 1
        let generation = scheduledActionStatesGeneration
        Task { @MainActor [weak self] in
            await Task.yield()
            guard self?.scheduledActionStatesGeneration == generation else {
                return
            }
            self?.actionStatesByExtensionID = actionStates
        }
    }
}
