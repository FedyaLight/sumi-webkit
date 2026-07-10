import Combine
import Foundation

/// The single mutable store for the installed-extension catalog.
@available(macOS 15.5, *)
@MainActor
final class InstalledExtensionCollection: ObservableObject {
    @Published private(set) var records: [InstalledExtension] = []
    private var didChangeRecords: (() -> Void)?

    func connectRecordChanges(_ handler: @escaping () -> Void) {
        precondition(
            didChangeRecords == nil && records.isEmpty,
            "Installed-extension record changes must be connected exactly once before publication"
        )
        didChangeRecords = handler
    }

    func upsert(_ record: InstalledExtension) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        sortRecords()
        notifyRecordChanges()
    }

    func replace(at index: Int, with record: InstalledExtension) {
        guard records.indices.contains(index) else { return }
        records[index] = record
        notifyRecordChanges()
    }

    func remove(id: String) {
        let originalCount = records.count
        records.removeAll { $0.id == id }
        guard records.count != originalCount else { return }
        notifyRecordChanges()
    }

    func setAll(_ records: [InstalledExtension]) {
        self.records = records
        notifyRecordChanges()
    }

    func sort() {
        sortRecords()
        notifyRecordChanges()
    }

    func nativeMessagingLoadSource(
        for extensionID: String?
    ) -> SafariAppExtensionRuntimeLoadSource? {
        guard let extensionID,
              let installed = records.first(where: { $0.id == extensionID })
        else {
            return nil
        }
        return installed.sourceKind == .safariAppExtension
            ? .originalAppexBundle
            : .copiedPackage
    }

    private func sortRecords() {
        records.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func notifyRecordChanges() {
        guard let didChangeRecords else {
            preconditionFailure(
                "Installed-extension records cannot mutate before change handling is connected"
            )
        }
        didChangeRecords()
    }
}
