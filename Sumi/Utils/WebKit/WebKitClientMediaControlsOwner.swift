import AppKit

@MainActor
final class WebKitClientMediaControlsOwner {
    struct ProviderMediaControls {
        let provider: NSObject
        let touchBar: NSTouchBar
    }

    typealias ProviderMediaControlsBuilder = @MainActor (NSView) -> ProviderMediaControls?

    private let makeProviderMediaControls: ProviderMediaControlsBuilder
    private var controlsView: NSView?
    private var cachedTouchBar: NSTouchBar?
    private var cachedProvider: NSObject?

    init(
        makeProviderMediaControls: @escaping ProviderMediaControlsBuilder =
            WebKitClientMediaControlsOwner.makeAVKitProviderMediaControls
    ) {
        self.makeProviderMediaControls = makeProviderMediaControls
    }

    func makeTouchBar() -> NSTouchBar? {
        guard let controlsView else { return nil }
        if let cachedTouchBar {
            return cachedTouchBar
        }

        guard let mediaControls = makeProviderMediaControls(controlsView) else {
            return nil
        }

        cachedProvider = mediaControls.provider
        cachedTouchBar = mediaControls.touchBar
        return mediaControls.touchBar
    }

    func addMediaPlaybackControlsView(_ controlsView: NSView) -> NSTouchBar? {
        self.controlsView = controlsView
        clearCache()
        return makeTouchBar()
    }

    func removeMediaPlaybackControlsView() {
        controlsView = nil
        clearCache()
    }

    private func clearCache() {
        cachedTouchBar = nil
        cachedProvider = nil
    }

    private static func makeAVKitProviderMediaControls(from controlsView: NSView) -> ProviderMediaControls? {
        // After element fullscreen WebKit asks the client to host its media controls view.
        // Rebuild AVKit's provider so the post-fullscreen bar matches WebKit's normal layout.
        guard let providerClass = NSClassFromString("AVTouchBarPlaybackControlsProvider") as? NSObject.Type,
              let playbackControlsController = controlsView.value(forKey: "playbackControlsController")
        else {
            return nil
        }

        let provider = providerClass.init()
        provider.setValue(playbackControlsController, forKey: "playbackControlsController")
        guard let touchBar = provider.value(forKey: "touchBar") as? NSTouchBar else {
            return nil
        }

        return ProviderMediaControls(provider: provider, touchBar: touchBar)
    }
}
