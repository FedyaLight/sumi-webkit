import Combine
import Foundation
import Observation

/// Stable rendering state for one saved folder identity.
///
/// SwiftUI observes these cells instead of the canonical `TabFolder` object.
/// Structural snapshots may replace their model objects, but the presentation
/// identity and expansion revision remain stable.
@MainActor
@Observable
final class SidebarFolderPresentationCell: Identifiable {
    let id: UUID
    private(set) var title: String
    private(set) var iconValue: String
    private(set) var isExpanded: Bool
    private(set) var expansionRevision: UInt64

    init(
        id: UUID,
        title: String,
        iconValue: String,
        isExpanded: Bool,
        expansionRevision: UInt64
    ) {
        self.id = id
        self.title = title
        self.iconValue = iconValue
        self.isExpanded = isExpanded
        self.expansionRevision = expansionRevision
    }

    func reconcileMetadata(title: String, iconValue: String) {
        self.title = title
        self.iconValue = iconValue
    }

    func applyExpansion(_ isExpanded: Bool, revision: UInt64) {
        guard revision >= expansionRevision else { return }
        self.isExpanded = isExpanded
        expansionRevision = revision
    }
}

/// Window-context lifetime owner of stable saved-content presentation cells.
///
/// One subscription fans canonical Folder Expansion revisions into O(1)
/// per-folder updates. Rendering never installs per-folder subscriptions.
@MainActor
final class SidebarSavedContentPresentationSession {
    private struct ExpansionValue {
        let isExpanded: Bool
        let revision: UInt64
    }

    private var cellsByFolderID: [UUID: SidebarFolderPresentationCell] = [:]
    private var latestExpansionByFolderID: [UUID: ExpansionValue] = [:]
    private var expansionCancellable: AnyCancellable?

    init(expansionChanges: AnyPublisher<TabFolderExpansionChange, Never>) {
        expansionCancellable = expansionChanges.sink { [weak self] change in
            self?.apply(change)
        }
    }

    func reconcile(
        folders: [TabFolder]
    ) -> [UUID: SidebarFolderPresentationCell] {
        for folder in folders {
            let latestExpansion = latestExpansionByFolderID[folder.id]
            let cell = cellsByFolderID[folder.id] ?? SidebarFolderPresentationCell(
                id: folder.id,
                title: folder.name,
                iconValue: folder.icon,
                isExpanded: latestExpansion?.isExpanded ?? folder.isOpen,
                expansionRevision: latestExpansion?.revision ?? 0
            )
            cellsByFolderID[folder.id] = cell
            cell.reconcileMetadata(title: folder.name, iconValue: folder.icon)
            if let latestExpansion {
                cell.applyExpansion(
                    latestExpansion.isExpanded,
                    revision: latestExpansion.revision
                )
            } else if cell.expansionRevision == 0 {
                cell.applyExpansion(folder.isOpen, revision: 0)
            }
        }

        return cellsByFolderID
    }

    private func apply(_ change: TabFolderExpansionChange) {
        for (folderID, isExpanded) in change.expansionByFolderID {
            let value = ExpansionValue(
                isExpanded: isExpanded,
                revision: change.revision
            )
            latestExpansionByFolderID[folderID] = value
            cellsByFolderID[folderID]?.applyExpansion(
                isExpanded,
                revision: change.revision
            )
        }
    }
}
