/// Connects a window-local sidebar media store to the shared native
/// now-playing runtime without exposing a configuration closure to views.
@MainActor
final class SidebarMediaStoreConfigurationOwner {
    private let context: SumiNativeNowPlayingRuntimeContext

    init(context: SumiNativeNowPlayingRuntimeContext) {
        self.context = context
    }

    func configure(
        _ store: SumiBackgroundMediaCardStore,
        for windowState: BrowserWindowState
    ) {
        store.configure(
            context: context,
            windowState: windowState
        )
    }
}
