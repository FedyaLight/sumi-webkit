import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionBrowserPublicationRuntime {
    private let events: ExtensionBrowserAttachmentAuthority.BrowserEvents
    private let profiles: ExtensionProfileRuntimeTransition
    private let warmup: ExtensionProfileRuntimeWarmup

    init(
        events: ExtensionBrowserAttachmentAuthority.BrowserEvents,
        profiles: ExtensionProfileRuntimeTransition,
        warmup: ExtensionProfileRuntimeWarmup
    ) {
        self.events = events
        self.profiles = profiles
        self.warmup = warmup
    }

    func publishWindow(
        _ window: BrowserWindowState
    ) -> BrowserWindowExtensionPublicationOutcome {
        events.publishWindow(window)
    }

    func closeWindow(_ window: BrowserWindowState) { events.closeWindow(window) }
    func focusWindow(_ window: BrowserWindowState) { _ = events.focus(window) }

    func switchProfile(
        _ profile: Profile,
        mutationLease: ProfileReferenceMutationLease? = nil
    ) {
        profiles.rememberProfile(profile)
        let receipt = profiles.switchProfile(
            profileID: profile.id,
            mutationLease: mutationLease
        )
        // Load this profile's contexts now, while no popup can be in flight.
        // Deferring it to the first action click makes that click's own popup
        // race the load's WebView rebuild and toolbar republication.
        guard profile.isEphemeral == false else {
            warmup.cancel()
            return
        }
        warmup.warm(profileID: profile.id) { [profiles] in
            profiles.isCurrent(receipt)
        }
    }

    func activateTab(_ tab: Tab, previous: Tab?) {
        events.activateTab(tab, previous: previous)
    }

    func closeTab(_ tab: Tab) { events.closeTab(tab) }
}
