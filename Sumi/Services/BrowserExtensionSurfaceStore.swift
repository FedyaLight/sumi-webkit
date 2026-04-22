//
//  BrowserExtensionSurfaceStore.swift
//  Sumi
//
//  Thin observable projection of the live Safari/WebExtension runtime.
//

import Combine
import Foundation

@MainActor
final class BrowserExtensionSurfaceStore: ObservableObject {
    @Published private(set) var installedExtensions: [InstalledExtension] = []

    private var cancellables: Set<AnyCancellable> = []
    private var scheduledInstalledExtensionsGeneration = 0

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
            return
        }

        extensionManager.$installedExtensions
            .sink { [weak self] installedExtensions in
                self?.scheduleInstalledExtensionsUpdate(installedExtensions)
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
}
