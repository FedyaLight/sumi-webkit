import Foundation
import SumiDomain

/// Complete window-local state touched while a regular tab or a released
/// launcher changes shortcut identity. Transactions calculate this value
/// without touching Observation-backed storage.
struct BrowserWindowShortcutMutationState: Equatable {
    var currentTabId: UUID?
    var currentSpaceId: UUID?
    var currentShortcutPinId: UUID?
    var currentShortcutPinRole: ShortcutPinRole?
    var isShowingEmptyState: Bool
    var splitSelection: WindowSplitSelection?
    var activeTabForSpace: [UUID: UUID]
    var selectedShortcutPinForSpace: [UUID: UUID]
    var selectionHistory: WindowSelectionHistory
    var webKitChildWindowIdentity: WebKitChildWindowIdentity?

    init(
        currentTabId: UUID? = nil,
        currentSpaceId: UUID? = nil,
        currentShortcutPinId: UUID? = nil,
        currentShortcutPinRole: ShortcutPinRole? = nil,
        isShowingEmptyState: Bool = false,
        splitSelection: WindowSplitSelection? = nil,
        activeTabForSpace: [UUID: UUID] = [:],
        selectedShortcutPinForSpace: [UUID: UUID] = [:],
        selectionHistory: WindowSelectionHistory = .init(),
        webKitChildWindowIdentity: WebKitChildWindowIdentity? = nil
    ) {
        self.currentTabId = currentTabId
        self.currentSpaceId = currentSpaceId
        self.currentShortcutPinId = currentShortcutPinId
        self.currentShortcutPinRole = currentShortcutPinRole
        self.isShowingEmptyState = isShowingEmptyState
        self.splitSelection = splitSelection
        self.activeTabForSpace = activeTabForSpace
        self.selectedShortcutPinForSpace = selectedShortcutPinForSpace
        self.selectionHistory = selectionHistory
        self.webKitChildWindowIdentity = webKitChildWindowIdentity
    }
}

/// Stages every affected window as values, installs every terminal value, then
/// opens Observation only after the complete multi-window aggregate exists.
/// Clearing the active batch before publication lets a synchronous observer
/// commit through a different model owner (for example topology) without a
/// later window install overwriting that reentrant terminal mutation. The
/// Observation registrar itself forbids same-registrar writes from `onChange`.
@MainActor
final class BrowserWindowShortcutMutationOwner {
    private struct Entry {
        let window: BrowserWindowState
        let expected: BrowserWindowShortcutMutationState
        var target: BrowserWindowShortcutMutationState
    }

    private final class Batch {
        var depth = 0
        var rejected = false
        var entries: [ObjectIdentifier: Entry] = [:]
    }

    private var batch: Batch?

    func withAggregate(_ operation: () -> Bool) -> Bool {
        withAggregate(operation, beforePublication: {})
    }

    /// Installs every raw window value first, then publishes already-admitted
    /// sibling model receipts before opening window Observation. The terminal
    /// callback is intentionally infallible: all validation and rollback must
    /// complete while the aggregate is still staged.
    func withAggregate(
        _ operation: () -> Bool,
        beforePublication: () -> Void
    ) -> Bool {
        let isRoot = batch == nil
        if isRoot {
            batch = Batch()
        }
        guard let batch else {
            preconditionFailure("Shortcut window batch was not installed")
        }

        batch.depth += 1
        let accepted = operation()
        batch.depth -= 1
        if accepted == false {
            batch.rejected = true
        }

        guard isRoot else { return accepted }
        precondition(batch.depth == 0, "Unbalanced shortcut window batch")
        let committed = accepted && batch.rejected == false
        finish(
            batch,
            committed: committed,
            beforePublication: beforePublication
        )
        return committed
    }

    @discardableResult
    func stage(
        _ window: BrowserWindowState,
        mutation: (inout BrowserWindowShortcutMutationState) -> Void
    ) -> Bool {
        guard let batch else {
            preconditionFailure("Shortcut window mutation escaped its aggregate")
        }
        let key = ObjectIdentifier(window)
        var entry = batch.entries[key] ?? Entry(
            window: window,
            expected: window.unpublishedShortcutMutationState,
            target: window.unpublishedShortcutMutationState
        )
        let previous = entry.target
        mutation(&entry.target)
        batch.entries[key] = entry
        return entry.target != previous
    }

    private func finish(
        _ batch: Batch,
        committed: Bool,
        beforePublication: () -> Void
    ) {
        let entries = batch.entries.values.sorted {
            $0.window.id.uuidString < $1.window.id.uuidString
        }
        self.batch = nil
        guard committed else { return }

        precondition(
            entries.allSatisfy {
                $0.window.unpublishedShortcutMutationState == $0.expected
            },
            "Shortcut window state changed outside its staged aggregate"
        )
        entries.forEach {
            $0.window.installUnpublishedShortcutMutationState($0.target)
        }
        beforePublication()
        entries.forEach {
            $0.window.publishShortcutMutation(
                from: $0.expected,
                to: $0.target
            )
        }
    }
}
