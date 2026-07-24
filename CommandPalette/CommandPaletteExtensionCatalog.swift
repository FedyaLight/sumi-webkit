import AppKit
import Foundation

struct CommandPaletteExtensionPresentation: Equatable {
    let id: String
    let title: String
}

@MainActor
final class CommandPaletteExtensionCatalog {
    struct Invocation {
        fileprivate let extensionID: String
        fileprivate let extensionName: String
        fileprivate let currentTab: Tab?
        fileprivate let anchorSessionToken: UUID
    }

    private let module: SumiExtensionsModule
    private let tabs: SidebarExtensionActionTabQuery

    init(
        module: SumiExtensionsModule,
        tabs: SidebarExtensionActionTabQuery
    ) {
        self.module = module
        self.tabs = tabs
    }

    func presentations(
        in windowState: BrowserWindowState
    ) -> [CommandPaletteExtensionPresentation] {
        guard module.isEnabled else { return [] }
        guard let profileID = currentProfileID(in: windowState) else {
            return []
        }
        _ = module.ensureActionMetadataLoadedIfNeeded()
        return module.toolbarPresentationSnapshot(profileID: profileID)
            .enabledExtensions
            .filter(\.hasAction)
            .map {
                CommandPaletteExtensionPresentation(
                    id: $0.id,
                    title: $0.name
                )
            }
    }

    func prepareInvocation(
        extensionID: String,
        in windowState: BrowserWindowState,
        anchorView: NSView
    ) -> Invocation? {
        guard let presentation = presentations(in: windowState)
            .first(where: { $0.id == extensionID }) else {
            return nil
        }
        let currentTab = tabs.currentTab(in: windowState)
        guard let profileID = currentTab?.profileId
            ?? windowState.currentProfileId else {
            return nil
        }

        module.setActionAnchorIfLoaded(
            for: extensionID,
            anchorView: anchorView
        )
        guard let token = module.captureActionPopupAnchor(
            extensionId: extensionID,
            windowId: windowState.id,
            profileId: profileID,
            tab: currentTab
        ) else {
            BrowserExtensionUnavailableAlert.present(
                extensionName: presentation.title,
                informativeText: String(
                    localized:
                        "Sumi could not bind this extension action to the command palette window."
                )
            )
            return nil
        }

        return Invocation(
            extensionID: extensionID,
            extensionName: presentation.title,
            currentTab: currentTab,
            anchorSessionToken: token
        )
    }

    func perform(_ invocation: Invocation) async {
        let result = await module.openActionPopupFromURLHub(
            extensionId: invocation.extensionID,
            currentTab: invocation.currentTab,
            anchorSessionToken: invocation.anchorSessionToken
        )
        guard !result.opened else { return }
        BrowserExtensionUnavailableAlert.present(
            extensionName: invocation.extensionName,
            informativeText: result.message
        )
    }

    private func currentProfileID(
        in windowState: BrowserWindowState
    ) -> UUID? {
        tabs.currentTab(in: windowState)?.profileId
            ?? windowState.currentProfileId
    }
}
