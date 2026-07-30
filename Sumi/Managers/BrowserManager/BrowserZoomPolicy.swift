import WebKit

@MainActor
final class BrowserZoomPolicy {
    let manager: ZoomManager
    private let boosts: SumiBoostsModule

    init(manager: ZoomManager, boosts: SumiBoostsModule) {
        self.manager = manager
        self.boosts = boosts
    }

    func apply(to target: BrowserZoomTarget) {
        let savedZoom = manager.getZoomLevel(
            for: target.domain,
            profileId: target.profileID,
            isEphemeralProfile: target.isEphemeralProfile
        )
        let multiplier = boosts.sizeOverride(
            for: target.tab.url,
            profileId: target.profileID
        )
        manager.applyTransientZoom(
            manager.effectiveZoom(baseZoom: savedZoom, multiplier: multiplier),
            to: target.webView,
            domain: target.domain,
            tabId: target.tab.id
        )
    }

    func reset(_ target: BrowserZoomTarget) {
        manager.saveZoomLevel(
            1,
            for: target.domain,
            profileId: target.profileID,
            isEphemeralProfile: target.isEphemeralProfile
        )
        apply(to: target)
    }

    func step(_ direction: ZoomStepDirection, target: BrowserZoomTarget) {
        let current = manager.getZoomLevel(
            for: target.domain,
            profileId: target.profileID,
            isEphemeralProfile: target.isEphemeralProfile
        )
        manager.saveZoomLevel(
            manager.nextZoomLevel(from: current, direction: direction),
            for: target.domain,
            profileId: target.profileID,
            isEphemeralProfile: target.isEphemeralProfile
        )
        apply(to: target)
    }

    func removeTab(_ tabID: UUID) {
        manager.removeTabZoomLevel(for: tabID)
    }
}
