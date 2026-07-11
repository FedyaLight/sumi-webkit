import Foundation

/// Command surface UI/App callsites use for session recovery.
///
/// Thin forwarding facade only: reopening a recently-closed item, restoring
/// the previous session's windows, and reopening one window from a snapshot
/// each live in their own domain service; this type holds no restore logic.
@MainActor
final class BrowserSessionRecoveryCommands {
    private let itemReopen: RecentlyClosedItemReopenService
    private let lastSessionRestore: LastSessionWindowsRestoreService
    private let windowReopen: any WindowSessionReopening

    init(
        itemReopen: RecentlyClosedItemReopenService,
        lastSessionRestore: LastSessionWindowsRestoreService,
        windowReopen: any WindowSessionReopening
    ) {
        self.itemReopen = itemReopen
        self.lastSessionRestore = lastSessionRestore
        self.windowReopen = windowReopen
    }

    var canOfferStartupSessionRestoreShortcut: Bool {
        lastSessionRestore.canOfferStartupSessionRestoreShortcut
    }

    var canRestoreAnyLastSession: Bool {
        lastSessionRestore.canRestoreAnyLastSession
    }

    func reopenMostRecentClosedItem() {
        itemReopen.reopenMostRecentItem()
    }

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        itemReopen.reopen(item)
    }

    func reopenAllWindowsFromLastSession() {
        lastSessionRestore.reopenAllWindowsFromLastSession()
    }

    @discardableResult
    func reopenWindow(from snapshot: LastSessionWindowSnapshot) async -> Bool {
        await windowReopen.reopenWindow(from: snapshot)
    }
}
