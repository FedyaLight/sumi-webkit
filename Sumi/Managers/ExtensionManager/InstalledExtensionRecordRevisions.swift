import Foundation

/// Tombstoned per-extension mutation revisions for the installed-extension
/// catalog. Entries deliberately survive removal, so a remove/re-add of the
/// same extension ID cannot revive authority that was captured against an
/// older record.
@available(macOS 15.5, *)
@MainActor
final class InstalledExtensionRecordRevisions {
    private var revisionsByID: [String: UInt64] = [:]

    /// Monotonic revision of one extension's catalog record. Any semantic
    /// mutation of that record (install, replace, enable/disable, removal)
    /// advances it; unrelated extensions keep their revisions.
    func revision(for id: String) -> UInt64 {
        revisionsByID[id] ?? 0
    }

    func bump(_ id: String) {
        let current = revisionsByID[id] ?? 0
        precondition(
            current < UInt64.max,
            "Installed-extension record revision exhausted"
        )
        revisionsByID[id] = current + 1
    }
}
