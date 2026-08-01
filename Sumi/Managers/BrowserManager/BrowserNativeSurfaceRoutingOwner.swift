import AppKit
import Foundation

@MainActor
final class BrowserNativeSurfaceRoutingOwner {
    private let residence: BrowserNativeSurfaceResidenceOwner
    private let tabOpening: BrowserTabOpeningOwner
    private let selection: BrowserTabSelectionOwner
    private let windows: WindowRegistry

    init(
        residence: BrowserNativeSurfaceResidenceOwner,
        tabOpening: BrowserTabOpeningOwner,
        selection: BrowserTabSelectionOwner,
        windows: WindowRegistry
    ) {
        self.residence = residence
        self.tabOpening = tabOpening
        self.selection = selection
        self.windows = windows
    }

    func openNativeBrowserSurface(
        _ kind: SumiNativeBrowserSurfaceKind,
        url: URL,
        in windowState: BrowserWindowState,
        preferredSpaceId: UUID? = nil
    ) {
        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            if let existing = windowState.ephemeralTabs.first(where: { kind.matches($0) }) {
                configureAndSelect(existing, kind: kind, url: url, in: windowState)
            } else {
                let newTab = residence.makeEphemeralTab(
                    url: url,
                    in: windowState,
                    profile: profile
                )
                configureAndSelect(newTab, kind: kind, url: url, in: windowState)
            }
            focus(windowState)
            return
        }

        let targetSpace = residence.targetSpace(
            for: windowState,
            preferredSpaceID: preferredSpaceId
        )

        if let existing = residence.existingRegularTab(
            matching: kind,
            in: targetSpace
        ) {
            configureAndSelect(existing, kind: kind, url: url, in: windowState)
            residence.persistRuntimeState(of: existing)
            focus(windowState)
            return
        }

        let newTab = tabOpening.openPreparedRegularTab(
            url: url.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: targetSpace?.id,
                loadPolicy: .deferred
            ),
            prepareBeforePublication: { tab in
                kind.configure(tab, url: url)
            }
        )
        residence.persistRuntimeState(of: newTab)
        focus(windowState)
    }

    private func configureAndSelect(
        _ tab: Tab,
        kind: SumiNativeBrowserSurfaceKind,
        url: URL,
        in windowState: BrowserWindowState
    ) {
        configureSurface(tab, kind: kind, url: url)
        _ = selection.selectTab(
            tab,
            in: windowState,
            loadPolicy: .immediate
        )
    }

    private func configureSurface(
        _ tab: Tab,
        kind: SumiNativeBrowserSurfaceKind,
        url: URL
    ) {
        kind.configure(tab, url: url)
    }

    private func focus(_ windowState: BrowserWindowState) {
        windowState.shellWindow(in: windows)?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
