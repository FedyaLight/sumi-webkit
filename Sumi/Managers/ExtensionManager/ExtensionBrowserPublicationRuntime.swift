import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionBrowserPublicationRuntime {
    private let events: ExtensionBrowserAttachmentAuthority.BrowserEvents
    private let profiles: ExtensionProfileRuntimeTransition

    init(
        events: ExtensionBrowserAttachmentAuthority.BrowserEvents,
        profiles: ExtensionProfileRuntimeTransition
    ) {
        self.events = events
        self.profiles = profiles
    }

    func publishWindow(
        _ window: BrowserWindowState
    ) -> BrowserWindowExtensionPublicationOutcome {
        events.publishWindow(window)
    }

    func closeWindow(_ window: BrowserWindowState) { events.closeWindow(window) }
    func focusWindow(_ window: BrowserWindowState) { _ = events.focus(window) }

    func switchProfile(_ profile: Profile) {
        profiles.switchProfile(profileID: profile.id)
    }

    func activateTab(_ tab: Tab, previous: Tab?) {
        events.activateTab(tab, previous: previous)
    }

    func closeTab(_ tab: Tab) { events.closeTab(tab) }
}
