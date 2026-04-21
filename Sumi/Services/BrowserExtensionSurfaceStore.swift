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

    private weak var extensionManager: ExtensionManager?
    private var cancellables: Set<AnyCancellable> = []

    init(extensionManager: ExtensionManager?) {
        self.extensionManager = extensionManager
        bind(extensionManager)
    }

    var enabledExtensions: [InstalledExtension] {
        installedExtensions.filter(\.isEnabled)
    }

    func reload() {
        scheduleInstalledExtensionsUpdate(
            extensionManager?.installedExtensions ?? []
        )
    }

    func bind(_ extensionManager: ExtensionManager?) {
        cancellables.removeAll()
        self.extensionManager = extensionManager

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
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.installedExtensions = installedExtensions
        }
    }
}
