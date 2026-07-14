import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class SumiExtensionToolbarActionSurface {
    private let lifetime: SumiExtensionManagerLifetime
    private let surfaceStore: BrowserExtensionSurfaceStore
    private let siteAccess: SumiExtensionToolbarSiteAccessOwner
    private let actionPresentation: ExtensionActionPresentationQuery
    private var pendingActionAnchors: [String: [WeakAnchor]] = [:]

    init(
        lifetime: SumiExtensionManagerLifetime,
        surfaceStore: BrowserExtensionSurfaceStore
    ) {
        self.lifetime = lifetime
        self.surfaceStore = surfaceStore
        siteAccess = SumiExtensionToolbarSiteAccessOwner(
            managerIfLoadedAndEnabled: { [weak lifetime] in lifetime?.loadedManagerIfEnabled() },
            managerIfEnabled: { [weak lifetime] in lifetime?.managerIfEnabled() },
            fallbackProfileId: { [weak lifetime] in lifetime?.currentProfileID }
        )
        actionPresentation = ExtensionActionPresentationQuery(
            manager: { [weak lifetime] in lifetime?.loadedManagerIfEnabled() }
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
        enabledExtensions: [BrowserExtensionToolbarDisplayRecord],
        profileID: UUID? = nil
    ) -> [PinnedToolbarSlot] {
        siteAccess.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            profileId: profileID
        )
    }

    func toolbarPresentationSnapshot(
        profileID: UUID?
    ) -> BrowserExtensionToolbarPresentationSnapshot {
        guard lifetime.isEnabled else { return .empty }
        _ = ensureActionMetadataLoadedIfNeeded()
        return BrowserExtensionToolbarPresentationSnapshot(
            display: surfaceStore.toolbarDisplaySnapshot,
            pinnedExtensionIDs: siteAccess.pinnedToolbarExtensionIDs(
                profileId: profileID
            )
        )
    }

    func toolbarPresentationSnapshots(
        profileID: UUID?
    ) -> AnyPublisher<BrowserExtensionToolbarPresentationSnapshot, Never> {
        Publishers.Merge(
            surfaceStore.toolbarDisplaySnapshots.dropFirst().map { _ in () }
                .eraseToAnyPublisher(),
            surfaceStore.toolbarLayoutChanges(for: profileID)
        )
        .compactMap { [weak self] _ in
            self?.toolbarPresentationSnapshot(profileID: profileID)
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    func isPinnedToToolbar(_ extensionID: String) -> Bool {
        siteAccess.isPinnedToToolbar(extensionID)
    }

    func pinToToolbar(_ extensionID: String) {
        publishToolbarLayoutIfChanged(siteAccess.pinToToolbar(extensionID))
    }

    func unpinFromToolbar(_ extensionID: String) {
        publishToolbarLayoutIfChanged(siteAccess.unpinFromToolbar(extensionID))
    }

    func movePinnedToolbarSlot(id: String, to index: Int) {
        publishToolbarLayoutIfChanged(
            siteAccess.movePinnedToolbarSlot(id: id, to: index)
        )
    }

    func orderedUnpinnedExtensionIDs(candidateIDs: [String], profileID: UUID?) -> [String] {
        siteAccess.orderedUnpinnedExtensionIDs(candidateIDs: candidateIDs, profileId: profileID)
    }

    func moveUnpinnedExtension(id: String, to index: Int, within order: [String]) {
        siteAccess.moveUnpinnedExtension(id: id, to: index, within: order)
    }

    private func publishToolbarLayoutIfChanged(_ didChange: Bool) {
        guard didChange else { return }
        surfaceStore.publishToolbarLayoutChanged(
            for: siteAccess.currentProfileID()
        )
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
        guard let request = await optionsWindowRequest(
            extensionID: extensionID,
            profileID: profileID
        ) else { return }

        await withCheckedContinuation { continuation in
            request.service.presentOptionsPageWindow(
                invocation: request.invocation
            ) { error in
                if let error {
                    RuntimeDiagnostics.debug(category: "Extensions") {
                        "Unable to open extension options for \(extensionID): \(error.localizedDescription)"
                    }
                }
                continuation.resume()
            }
        }
    }

    private func optionsWindowRequest(
        extensionID: String,
        profileID: UUID?
    ) async -> (
        service: ExtensionOptionsWindowService,
        invocation: ExtensionOptionsWindowCallbackComposition.Invocation
    )? {
        guard let manager = managerIfEnabled() else { return nil }
        let resolvedProfileID =
            profileID
            ?? manager.profileRuntime.currentProfileId
            ?? lifetime.currentProfileID
        guard let resolvedProfileID else { return nil }

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
            return nil
        }
        guard let context else { return nil }
        guard let controller = manager.profileRuntime.controller(
                  for: resolvedProfileID
              ),
              let evidence = manager.controllerCallbackAdmission.capture(
                  context: context,
                  controller: controller
              ),
              let invocation = ExtensionOptionsWindowCallbackComposition
                .invocation(from: manager, evidence: evidence)
        else {
            return nil
        }
        return (manager.optionsWindows, invocation)
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

    func actionPresentationTarget(
        extensionID: String,
        tab: Tab,
        window: BrowserWindowState
    ) -> ExtensionActionPresentationTarget? {
        actionPresentation.target(
            extensionID: extensionID,
            tab: tab,
            window: window
        )
    }

    func actionPresentationSnapshot(
        for target: ExtensionActionPresentationTarget
    ) -> BrowserExtensionActionButtonSnapshot? {
        actionPresentation.snapshot(for: target)
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
    func toolbarPresentationSnapshot(
        profileID: UUID?
    ) -> BrowserExtensionToolbarPresentationSnapshot {
        toolbarActions.toolbarPresentationSnapshot(profileID: profileID)
    }

    func toolbarPresentationSnapshots(
        profileID: UUID?
    ) -> AnyPublisher<BrowserExtensionToolbarPresentationSnapshot, Never> {
        toolbarActions.toolbarPresentationSnapshots(profileID: profileID)
    }

    @discardableResult
    func ensureActionMetadataLoadedIfNeeded() -> Bool {
        toolbarActions.ensureActionMetadataLoadedIfNeeded()
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [BrowserExtensionToolbarDisplayRecord]
    ) -> [PinnedToolbarSlot] {
        toolbarActions.orderedPinnedToolbarSlots(enabledExtensions: enabledExtensions)
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [BrowserExtensionToolbarDisplayRecord],
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

    func actionPresentationTarget(
        extensionID: String,
        tab: Tab,
        window: BrowserWindowState
    ) -> ExtensionActionPresentationTarget? {
        toolbarActions.actionPresentationTarget(
            extensionID: extensionID,
            tab: tab,
            window: window
        )
    }

    func actionPresentationSnapshot(
        for target: ExtensionActionPresentationTarget
    ) -> BrowserExtensionActionButtonSnapshot? {
        toolbarActions.actionPresentationSnapshot(for: target)
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
