import AppKit
import SumiDomain

@MainActor
protocol SidebarSplitPairingCommitting: AnyObject {
    func commit(
        _ payload: DragOperation.Payload,
        to target: SidebarSplitPairingTarget,
        in windowState: BrowserWindowState
    ) -> Bool
}

@MainActor
final class SidebarSplitPairingTransaction: SidebarSplitPairingCommitting {
    private let splitDrops: SplitDropService

    init(splitDrops: SplitDropService) {
        self.splitDrops = splitDrops
    }

    func commit(
        _ payload: DragOperation.Payload,
        to target: SidebarSplitPairingTarget,
        in windowState: BrowserWindowState
    ) -> Bool {
        let dropTarget = SplitDropTarget(
            targetMemberID: target.memberID,
            side: target.side,
            targetRect: target.rect
        )
        switch payload {
        case .tab(let tab):
            return splitDrops.drop(tab, on: dropTarget, in: windowState)
        case .pin(let pin):
            return splitDrops.drop(
                .shortcutPin(pin.id),
                on: dropTarget,
                in: windowState
            )
        case .folder, .splitGroup:
            return false
        }
    }
}

/// The single sidebar drop commit boundary. Intent and pasteboard evidence are
/// resolved by the UI; this port validates the exact window owner and delegates
/// one canonical structural transaction to the existing drag router.
@MainActor
final class SidebarDragTransactionPort {
    private let windows: SidebarWindowIdentityQuery
    private let dragOperations: any SidebarDragOperationExecuting
    private let urlDropService: SidebarURLDropService
    private let splitPairing: (any SidebarSplitPairingCommitting)?

    init(
        windows: SidebarWindowIdentityQuery,
        dragOperations: any SidebarDragOperationExecuting,
        urlDropService: SidebarURLDropService,
        splitPairing: (any SidebarSplitPairingCommitting)? = nil
    ) {
        self.windows = windows
        self.dragOperations = dragOperations
        self.urlDropService = urlDropService
        self.splitPairing = splitPairing
    }

    func commit(
        pasteboard: NSPasteboard,
        resolution: SidebarDropResolution,
        windowState: BrowserWindowState?
    ) -> Bool {
        guard let windowState, windows.contains(windowState) else {
            return false
        }
        return SidebarDropCoordinator.performDrop(
            pasteboard: pasteboard,
            resolution: resolution,
            dragOperations: dragOperations,
            urlDropService: urlDropService,
            splitPairing: splitPairing,
            windowState: windowState
        )
    }
}
