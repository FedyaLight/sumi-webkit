@MainActor
final class BrowserURLBarZoomContextOwner {
    private let manager: ZoomManager
    private let revision: BrowserZoomRevisionState
    private let commands: BrowserZoomCommandOwner

    init(
        manager: ZoomManager,
        revision: BrowserZoomRevisionState,
        commands: BrowserZoomCommandOwner
    ) {
        self.manager = manager
        self.revision = revision
        self.commands = commands
    }

    var context: URLBarZoomContext {
        URLBarZoomContext(
            manager: manager,
            stateRevision: revision.revision,
            resetCurrentTab: { [commands] windowState in
                commands.resetZoomCurrentTab(in: windowState)
            },
            zoomOutCurrentTab: { [commands] windowState in
                commands.zoomOutCurrentTab(in: windowState)
            },
            zoomInCurrentTab: { [commands] windowState in
                commands.zoomInCurrentTab(in: windowState)
            }
        )
    }
}
