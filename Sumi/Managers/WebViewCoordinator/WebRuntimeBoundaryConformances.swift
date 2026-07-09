import Foundation
import SumiWebRuntime

extension Tab: WebRuntimeTabHandle {
    public var localSession: TabWebViewSession {
        webViewOwnershipOwner.localSession
    }

    public var resolvedProfileId: UUID? {
        resolveProfile()?.id ?? profileId
    }
}

extension Tab: WebRuntimeTabMaterializing, WebRuntimeTabOwnershipMutating, WebRuntimeTabTeardownLifecycle {}

extension Tab: WebRuntimeTabSiteReloadPolicyNotifying {}

extension Tab: WebRuntimeTabMainFrameLoading {}

extension Tab: WebRuntimeTabAudioMuteSnapshotting {
    public var isAudioMuted: Bool {
        audioState.isMuted
    }
}

extension BrowserWindowState: WebRuntimeWindowHandle {
    var ephemeralTabHandles: [any WebRuntimeTabHandle] {
        ephemeralTabs
    }
}

extension WebRuntimeTabHandle {
    /// Concrete app-target tab when the handle is a `Tab` adapter.
    var concreteTab: Tab? { self as? Tab }
}

extension WebRuntimeWindowHandle {
    /// Concrete app-target window when the handle is a `BrowserWindowState` adapter.
    var concreteWindowState: BrowserWindowState? { self as? BrowserWindowState }
}
