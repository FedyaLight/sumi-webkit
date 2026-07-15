import AppKit
import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionToolbarPopupRuntime {
    private let invocation: ExtensionActionInvocationService
    private let anchors: ExtensionActionAnchorStore
    private let anchorResolver: ExtensionActionPopupAnchorResolver
    private let normalTabs: ExtensionBrowserAttachmentAuthority.NormalTabQuery

    init(
        invocation: ExtensionActionInvocationService,
        anchors: ExtensionActionAnchorStore,
        anchorResolver: ExtensionActionPopupAnchorResolver,
        normalTabs: ExtensionBrowserAttachmentAuthority.NormalTabQuery
    ) {
        self.invocation = invocation
        self.anchors = anchors
        self.anchorResolver = anchorResolver
        self.normalTabs = normalTabs
    }

    func open(
        extensionID: String,
        currentTab: Tab?,
        anchorSessionToken: UUID
    ) async -> BrowserExtensionActionPopupRequestResult {
        await invocation.openPopup(
            extensionID: extensionID,
            currentTab: currentTab,
            popupTargetRequest: .explicitAnchor(anchorSessionToken)
        )
    }

    func setAnchor(extensionID: String, view: NSView) {
        anchors.setAnchor(for: extensionID, anchorView: view)
    }

    func captureAnchor(
        extensionID: String,
        windowID: UUID,
        profileID: UUID?,
        tab: Tab?
    ) -> UUID? {
        anchorResolver.captureActionPopupAnchor(
            extensionId: extensionID,
            windowId: windowID,
            profileId: profileID,
            tab: tab
        )
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        normalTabs.stableAdapter(for: tab)
    }
}
