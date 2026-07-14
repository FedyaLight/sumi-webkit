import AppKit
import Foundation
import WebKit

@MainActor
final class SumiExtensionToolbarActionSurface {
    private let lifetime: SumiExtensionManagerLifetime
    private let siteAccess: SumiExtensionToolbarSiteAccessOwner
    private var pendingActionAnchors: [String: [WeakAnchor]] = [:]

    init(lifetime: SumiExtensionManagerLifetime) {
        self.lifetime = lifetime
        siteAccess = SumiExtensionToolbarSiteAccessOwner(
            managerIfLoadedAndEnabled: { [weak lifetime] in lifetime?.loadedManagerIfEnabled() },
            managerIfEnabled: { [weak lifetime] in lifetime?.managerIfEnabled() },
            fallbackProfileId: { [weak lifetime] in lifetime?.currentProfileID },
            invalidateTabStructuralRevision: { [weak lifetime] in
                lifetime?.invalidateTabStructuralRevision()
            }
        )
    }

    @discardableResult
    func ensureActionMetadataLoadedIfNeeded() -> Bool {
        guard lifetime.isEnabled else { return false }
        if lifetime.hasLoadedRuntime { return true }
        guard lifetime.hasEnabledPersistedExtensions() else { return false }
        return managerIfEnabled() != nil
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension],
        profileID: UUID? = nil
    ) -> [PinnedToolbarSlot] {
        siteAccess.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            profileId: profileID
        )
    }

    func isPinnedToToolbar(_ extensionID: String) -> Bool {
        siteAccess.isPinnedToToolbar(extensionID)
    }

    func pinToToolbar(_ extensionID: String) { siteAccess.pinToToolbar(extensionID) }
    func unpinFromToolbar(_ extensionID: String) { siteAccess.unpinFromToolbar(extensionID) }
    func movePinnedToolbarSlot(id: String, to index: Int) {
        siteAccess.movePinnedToolbarSlot(id: id, to: index)
    }

    func orderedUnpinnedExtensionIDs(candidateIDs: [String], profileID: UUID?) -> [String] {
        siteAccess.orderedUnpinnedExtensionIDs(candidateIDs: candidateIDs, profileId: profileID)
    }

    func moveUnpinnedExtension(id: String, to index: Int, within order: [String]) {
        siteAccess.moveUnpinnedExtension(id: id, to: index, within: order)
    }

    func siteAccessPolicy(extensionID: String, profileID: UUID? = nil) -> SafariExtensionSiteAccessPolicy? {
        siteAccess.siteAccessPolicy(extensionId: extensionID, profileId: profileID)
    }

    func setDefaultSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionID: String,
        profileID: UUID? = nil
    ) {
        siteAccess.setDefaultSiteAccess(access, extensionId: extensionID, profileId: profileID)
    }

    func setPrivateBrowsingAccess(
        _ allowed: Bool,
        extensionID: String,
        profileID: UUID? = nil
    ) {
        siteAccess.setPrivateBrowsingAccess(allowed, extensionId: extensionID, profileId: profileID)
    }

    func setConfiguredSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionID: String,
        profileID: UUID? = nil,
        matchPatternString: String
    ) {
        siteAccess.setConfiguredSiteAccess(
            access,
            extensionId: extensionID,
            profileId: profileID,
            matchPatternString: matchPatternString
        )
    }

    func getExtensionContext(for extensionID: String) -> WKWebExtensionContext? {
        lifetime.loadedManagerIfEnabled()?.getExtensionContext(for: extensionID)
    }

    func openOptionsPage(extensionID: String, profileID: UUID? = nil) async {
        guard let manager = managerIfEnabled() else { return }
        let resolvedProfileID =
            profileID
            ?? manager.profileRuntime.currentProfileId
            ?? lifetime.currentProfileID
        guard let resolvedProfileID else { return }

        let context: WKWebExtensionContext?
        do {
            context = try await manager.ensureExtensionLoaded(
                extensionId: extensionID,
                profileId: resolvedProfileID
            )
        } catch {
            RuntimeDiagnostics.debug(category: "Extensions") {
                "Unable to load extension context for options page \(extensionID): \(error.localizedDescription)"
            }
            return
        }
        guard let context else { return }

        await withCheckedContinuation { continuation in
            manager.optionsWindows.presentOptionsPageWindow(for: context, manager: manager) { error in
                if let error {
                    RuntimeDiagnostics.debug(category: "Extensions") {
                        "Unable to open extension options for \(extensionID): \(error.localizedDescription)"
                    }
                }
                continuation.resume()
            }
        }
    }

    func openActionPopup(
        extensionID: String,
        currentTab: Tab?,
        anchorSessionToken: UUID
    ) async -> BrowserExtensionActionPopupRequestResult {
        guard lifetime.isEnabled else {
            return .blocked(.moduleDisabled, message: "The Extensions module is disabled.")
        }
        guard let manager = managerIfEnabled() else {
            return .blocked(
                .runtimeUnavailable,
                message: "Sumi could not create the local extension manager for this action popup."
            )
        }
        return await manager.extensionActionInvocation.openPopup(
            extensionID: extensionID,
            currentTab: currentTab,
            popupTargetRequest: .explicitAnchor(anchorSessionToken)
        )
    }

    func setActionAnchorIfLoaded(for extensionID: String, anchorView: NSView) {
        storePendingActionAnchor(for: extensionID, anchorView: anchorView)
        lifetime.loadedManagerIfEnabled()?.actionAnchorStore.setAnchor(
            for: extensionID,
            anchorView: anchorView
        )
    }

    @discardableResult
    func captureActionPopupAnchor(
        extensionID: String,
        windowID: UUID,
        profileID: UUID?,
        tab: Tab? = nil
    ) -> UUID? {
        managerIfEnabled()?.actionPopupAnchorResolver.captureActionPopupAnchor(
            extensionId: extensionID,
            windowId: windowID,
            profileId: profileID,
            tab: tab
        )
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        lifetime.loadedManagerIfEnabled()?.adapterCatalog.stableAdapter(for: tab)
    }

    func closeAllOptionsWindowsIfLoaded() {
        lifetime.residentManager()?.optionsWindows.closeAllWindows()
    }

    func clearPendingActionAnchors() { pendingActionAnchors.removeAll() }

    private func managerIfEnabled() -> ExtensionManager? {
        guard let manager = lifetime.managerIfEnabled() else { return nil }
        transferPendingActionAnchors(to: manager)
        return manager
    }

    private func storePendingActionAnchor(for extensionID: String, anchorView: NSView) {
        var anchors = pendingActionAnchors[extensionID] ?? []
        anchors.removeAll { $0.view == nil || $0.view === anchorView }
        anchors.append(WeakAnchor(view: anchorView, window: anchorView.window))
        pendingActionAnchors[extensionID] = Array(anchors.suffix(8))
    }

    private func transferPendingActionAnchors(to manager: ExtensionManager) {
        for (extensionID, anchors) in pendingActionAnchors {
            for anchor in anchors {
                guard let view = anchor.view else { continue }
                manager.actionAnchorStore.setAnchor(for: extensionID, anchorView: view)
            }
        }
    }
}

@MainActor
extension SumiExtensionsModule {
    @discardableResult
    func ensureActionMetadataLoadedIfNeeded() -> Bool {
        toolbarActions.ensureActionMetadataLoadedIfNeeded()
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension]
    ) -> [PinnedToolbarSlot] {
        toolbarActions.orderedPinnedToolbarSlots(enabledExtensions: enabledExtensions)
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension],
        profileId: UUID?
    ) -> [PinnedToolbarSlot] {
        toolbarActions.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            profileID: profileId
        )
    }

    func isPinnedToToolbar(_ extensionId: String) -> Bool {
        toolbarActions.isPinnedToToolbar(extensionId)
    }

    func pinToToolbar(_ extensionId: String) {
        toolbarActions.pinToToolbar(extensionId)
    }

    func unpinFromToolbar(_ extensionId: String) {
        toolbarActions.unpinFromToolbar(extensionId)
    }

    func movePinnedToolbarSlot(id: String, to targetIndex: Int) {
        toolbarActions.movePinnedToolbarSlot(id: id, to: targetIndex)
    }

    func orderedUnpinnedExtensionIDs(
        candidateIDs: [String],
        profileId: UUID?
    ) -> [String] {
        toolbarActions.orderedUnpinnedExtensionIDs(
            candidateIDs: candidateIDs,
            profileID: profileId
        )
    }

    func moveUnpinnedExtension(
        id: String,
        to targetIndex: Int,
        within currentOrder: [String]
    ) {
        toolbarActions.moveUnpinnedExtension(
            id: id,
            to: targetIndex,
            within: currentOrder
        )
    }

    func siteAccessPolicy(
        extensionId: String,
        profileId: UUID? = nil
    ) -> SafariExtensionSiteAccessPolicy? {
        toolbarActions.siteAccessPolicy(extensionID: extensionId, profileID: profileId)
    }

    func setDefaultSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID? = nil
    ) {
        toolbarActions.setDefaultSiteAccess(
            access,
            extensionID: extensionId,
            profileID: profileId
        )
    }

    func setPrivateBrowsingAccess(
        _ isAllowed: Bool,
        extensionId: String,
        profileId: UUID? = nil
    ) {
        toolbarActions.setPrivateBrowsingAccess(
            isAllowed,
            extensionID: extensionId,
            profileID: profileId
        )
    }

    func setConfiguredSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID? = nil,
        matchPatternString: String
    ) {
        toolbarActions.setConfiguredSiteAccess(
            access,
            extensionID: extensionId,
            profileID: profileId,
            matchPatternString: matchPatternString
        )
    }

    func getExtensionContext(for extensionId: String) -> WKWebExtensionContext? {
        toolbarActions.getExtensionContext(for: extensionId)
    }

    func openOptionsPage(extensionId: String, profileId: UUID? = nil) async {
        await toolbarActions.openOptionsPage(
            extensionID: extensionId,
            profileID: profileId
        )
    }

    func openActionPopupFromURLHub(
        extensionId: String,
        currentTab: Tab?,
        anchorSessionToken: UUID
    ) async -> BrowserExtensionActionPopupRequestResult {
        await toolbarActions.openActionPopup(
            extensionID: extensionId,
            currentTab: currentTab,
            anchorSessionToken: anchorSessionToken
        )
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        toolbarActions.stableAdapter(for: tab)
    }

    func setActionAnchorIfLoaded(for extensionId: String, anchorView: NSView) {
        toolbarActions.setActionAnchorIfLoaded(for: extensionId, anchorView: anchorView)
    }

    @discardableResult
    func captureActionPopupAnchor(
        extensionId: String,
        windowId: UUID,
        profileId: UUID?,
        tab: Tab? = nil
    ) -> UUID? {
        toolbarActions.captureActionPopupAnchor(
            extensionID: extensionId,
            windowID: windowId,
            profileID: profileId,
            tab: tab
        )
    }

    func closeAllOptionsWindowsIfLoaded() {
        toolbarActions.closeAllOptionsWindowsIfLoaded()
    }
}
