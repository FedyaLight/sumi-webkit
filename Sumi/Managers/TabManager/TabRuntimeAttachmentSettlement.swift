import Foundation

@MainActor
final class TabRuntimeAttachmentSettlement {
    enum Result {
        case completed
        case superseded
    }

    private let connection: TabRuntimePortConnection
    private let spaces: TabSpaceCollectionStateOwner
    private let deferredWork: TabRuntimeAttachmentDeferredWorkOwner
    private let restoreStarter: TabRuntimeAttachmentRestoreStarter?

    init(
        connection: TabRuntimePortConnection,
        spaces: TabSpaceCollectionStateOwner,
        deferredWork: TabRuntimeAttachmentDeferredWorkOwner,
        restoreStarter: TabRuntimeAttachmentRestoreStarter?
    ) {
        self.connection = connection
        self.spaces = spaces
        self.deferredWork = deferredWork
        self.restoreStarter = restoreStarter
    }

    func finish(using lease: TabRuntimePortLease) -> Result {
        guard connection.accepts(lease), let runtime = lease.registry else {
            return .superseded
        }
        if let space = spaces.currentSpace {
            runtime.syncWorkspaceThemeAcrossWindows(for: space, animate: false)
            guard connection.accepts(lease) else { return .superseded }
        }
        deferredWork.start(using: lease)
        guard connection.accepts(lease) else { return .superseded }
        restoreStarter?.startAutomatically(using: lease)
        return connection.accepts(lease) ? .completed : .superseded
    }

    func startPersistedStateRestoreIfNeeded(using lease: TabRuntimePortLease) {
        guard connection.accepts(lease) else { return }
        restoreStarter?.startManually(using: lease)
    }

    @discardableResult
    func prepareForDetach() -> Bool {
        guard deferredWork.prepareForDetach() else { return false }
        restoreStarter?.prepareForDetach()
        return true
    }
}
