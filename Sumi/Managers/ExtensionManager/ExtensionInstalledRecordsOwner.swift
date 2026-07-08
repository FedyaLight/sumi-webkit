import Foundation

/// Owns CRUD access to `ExtensionManager.installedExtensions`. A thin,
/// weak-backed seam so sibling owners (install/enable/disable flows) mutate
/// the published records array through one collaborator instead of a bundle
/// of individually-passed closures.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInstalledRecordsOwner {
    private weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    var records: [InstalledExtension] {
        manager?.installedExtensions ?? []
    }

    func upsert(_ record: InstalledExtension) {
        manager?.upsertInstalledExtension(record)
    }

    func replace(at index: Int, with record: InstalledExtension) {
        guard let manager, manager.installedExtensions.indices.contains(index) else { return }
        manager.installedExtensions[index] = record
    }

    func remove(id: String) {
        manager?.installedExtensions.removeAll { $0.id == id }
    }

    func setAll(_ records: [InstalledExtension]) {
        manager?.installedExtensions = records
    }

    func sort() {
        manager?.sortInstalledExtensions()
    }
}
