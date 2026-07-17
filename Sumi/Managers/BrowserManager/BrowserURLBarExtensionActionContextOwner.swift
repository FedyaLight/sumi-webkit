import Foundation
import SwiftUI

@MainActor
final class BrowserURLBarExtensionActionContextOwner {
    private let extensions: SumiExtensionsModule
    private let tabs: SidebarExtensionActionTabQuery
    private let profiles: BrowserCurrentProfileAuthority
    private let settings: BrowserSettingsNavigationService

    init(
        extensions: SumiExtensionsModule,
        tabs: SidebarExtensionActionTabQuery,
        profiles: BrowserCurrentProfileAuthority,
        settings: BrowserSettingsNavigationService
    ) {
        self.extensions = extensions
        self.tabs = tabs
        self.profiles = profiles
        self.settings = settings
    }

    var context: URLBarExtensionActionContext {
        URLBarExtensionActionContext(
            moduleEnabledChanges: extensions.enabledChanges,
            toolbarPresentationSnapshot: { [extensions] profileID in
                extensions.toolbarPresentationSnapshot(profileID: profileID)
            },
            toolbarPresentationSnapshots: { [extensions] profileID in
                extensions.toolbarPresentationSnapshots(profileID: profileID)
            },
            compactStrip: { [weak self] extensions, windowState, profileID in
                self?.view(
                    extensions,
                    layout: .compactStrip,
                    windowState: windowState,
                    profileID: profileID
                ) ?? AnyView(EmptyView())
            },
            hubTiles: { [weak self] extensions, windowState, profileID in
                self?.view(
                    extensions,
                    layout: .hubTiles,
                    windowState: windowState,
                    profileID: profileID
                ) ?? AnyView(EmptyView())
            },
            ensureActionMetadataLoadedIfNeeded: { [extensions] in
                extensions.ensureActionMetadataLoadedIfNeeded()
            }
        )
    }

    private func view(
        _ records: [BrowserExtensionToolbarDisplayRecord],
        layout: ExtensionActionLayout,
        windowState: BrowserWindowState,
        profileID: UUID?
    ) -> AnyView {
        AnyView(
            ExtensionActionView(
                extensions: records,
                layout: layout,
                profileId: profileID,
                browserContext: ExtensionActionBrowserContext(
                    extensionsModule: extensions,
                    windowState: windowState,
                    tabs: tabs,
                    profileAuthority: profiles,
                    settingsNavigation: settings
                )
            )
        )
    }
}
