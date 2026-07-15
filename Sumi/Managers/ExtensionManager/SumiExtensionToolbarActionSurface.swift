import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class SumiExtensionToolbarActionSurface {
    private let lifetime: SumiExtensionManagerLifetime
    private let surfaceStore: BrowserExtensionSurfaceStore
    private let siteAccess: SumiExtensionToolbarSiteAccessOwner
    private var pendingActionAnchors: [String: [WeakAnchor]] = [:]

    init(
        lifetime: SumiExtensionManagerLifetime,
        surfaceStore: BrowserExtensionSurfaceStore
    ) {
        self.lifetime = lifetime
        self.surfaceStore = surfaceStore
        siteAccess = SumiExtensionToolbarSiteAccessOwner(
            runtimeIfLoadedAndEnabled: { [weak lifetime] in
                lifetime?.loadedToolbarRuntimeIfEnabled()
            },
            runtimeIfEnabled: { [weak lifetime] in
                lifetime?.toolbarRuntimeIfEnabled()
            },
            fallbackProfileId: { [weak lifetime] in lifetime?.currentProfileID }
        )
    }

    @discardableResult
    func ensureActionMetadataLoadedIfNeeded() -> Bool {
        guard lifetime.isEnabled else { return false }
        if lifetime.hasLoadedRuntime { return true }
        guard lifetime.hasEnabledPersistedExtensions() else { return false }
        return runtimeIfEnabled() != nil
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
        let display = surfaceStore.toolbarDisplaySnapshot
        let pinnedExtensionIDs = siteAccess.pinnedToolbarExtensionIDs(
            profileId: profileID
        )
        let pinnedIDs = Set(pinnedExtensionIDs)
        let unpinnedCandidates = display.enabledExtensions
            .filter(\.hasAction)
            .map(\.id)
            .filter { pinnedIDs.contains($0) == false }
        return BrowserExtensionToolbarPresentationSnapshot(
            display: display,
            pinnedExtensionIDs: pinnedExtensionIDs,
            unpinnedExtensionIDs: siteAccess.orderedUnpinnedExtensionIDs(
                candidateIDs: unpinnedCandidates,
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

    func pinToToolbar(_ extensionID: String, profileID: UUID?) {
        publishToolbarLayoutIfChanged(
            siteAccess.pinToToolbar(extensionID, profileId: profileID),
            profileID: profileID
        )
    }

    func unpinFromToolbar(_ extensionID: String, profileID: UUID?) {
        publishToolbarLayoutIfChanged(
            siteAccess.unpinFromToolbar(extensionID, profileId: profileID),
            profileID: profileID
        )
    }

    func movePinnedToolbarSlot(id: String, to index: Int, profileID: UUID?) {
        publishToolbarLayoutIfChanged(
            siteAccess.movePinnedToolbarSlot(
                id: id,
                to: index,
                profileId: profileID
            ),
            profileID: profileID
        )
    }

    func orderedUnpinnedExtensionIDs(candidateIDs: [String], profileID: UUID?) -> [String] {
        siteAccess.orderedUnpinnedExtensionIDs(candidateIDs: candidateIDs, profileId: profileID)
    }

    func moveUnpinnedExtension(
        id: String,
        to index: Int,
        within order: [String],
        profileID: UUID?
    ) {
        publishToolbarLayoutIfChanged(
            siteAccess.moveUnpinnedExtension(
                id: id,
                to: index,
                within: order,
                profileId: profileID
            ),
            profileID: profileID
        )
    }

    private func publishToolbarLayoutIfChanged(
        _ didChange: Bool,
        profileID: UUID?
    ) {
        guard didChange else { return }
        surfaceStore.publishToolbarLayoutChanged(for: profileID)
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
        lifetime.loadedToolbarRuntimeIfEnabled()?.options.context(
            extensionID: extensionID
        )
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
        guard let runtime = runtimeIfEnabled() else { return nil }
        do {
            return try await runtime.options.request(
                extensionID: extensionID,
                profileID: profileID,
                fallbackProfileID: lifetime.currentProfileID
            )
        } catch {
            RuntimeDiagnostics.debug(category: "Extensions") {
                "Unable to load extension context for options page \(extensionID): \(error.localizedDescription)"
            }
            return nil
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
        guard let runtime = runtimeIfEnabled() else {
            return .blocked(
                .runtimeUnavailable,
                message: "Sumi could not create the local extension manager for this action popup."
            )
        }
        return await runtime.popup.open(
            extensionID: extensionID,
            currentTab: currentTab,
            anchorSessionToken: anchorSessionToken
        )
    }

    func setActionAnchorIfLoaded(for extensionID: String, anchorView: NSView) {
        storePendingActionAnchor(for: extensionID, anchorView: anchorView)
        lifetime.loadedToolbarRuntimeIfEnabled()?.popup.setAnchor(
            extensionID: extensionID,
            view: anchorView
        )
    }

    @discardableResult
    func captureActionPopupAnchor(
        extensionID: String,
        windowID: UUID,
        profileID: UUID?,
        tab: Tab? = nil
    ) -> UUID? {
        runtimeIfEnabled()?.popup.captureAnchor(
            extensionID: extensionID,
            windowID: windowID,
            profileID: profileID,
            tab: tab
        )
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        lifetime.loadedToolbarRuntimeIfEnabled()?.popup.stableAdapter(for: tab)
    }

    func actionPresentationTarget(
        extensionID: String,
        tab: Tab,
        window: BrowserWindowState
    ) -> ExtensionActionPresentationTarget? {
        lifetime.loadedToolbarRuntimeIfEnabled()?.actionPresentation.target(
            extensionID: extensionID,
            tab: tab,
            window: window
        )
    }

    func actionPresentationSnapshot(
        for target: ExtensionActionPresentationTarget
    ) -> BrowserExtensionActionButtonSnapshot? {
        lifetime.loadedToolbarRuntimeIfEnabled()?
            .actionPresentation.snapshot(for: target)
    }

    func closeAllOptionsWindowsIfLoaded() {
        lifetime.residentToolbarRuntime()?.options.closeAllWindows()
    }

    func clearPendingActionAnchors() { pendingActionAnchors.removeAll() }

    private func runtimeIfEnabled() -> ExtensionToolbarRuntime? {
        guard let runtime = lifetime.toolbarRuntimeIfEnabled() else { return nil }
        transferPendingActionAnchors(to: runtime.popup)
        return runtime
    }

    private func storePendingActionAnchor(for extensionID: String, anchorView: NSView) {
        var anchors = pendingActionAnchors[extensionID] ?? []
        anchors.removeAll { $0.view == nil || $0.view === anchorView }
        anchors.append(WeakAnchor(view: anchorView, window: anchorView.window))
        pendingActionAnchors[extensionID] = Array(anchors.suffix(8))
    }

    private func transferPendingActionAnchors(
        to popup: ExtensionToolbarPopupRuntime
    ) {
        for (extensionID, anchors) in pendingActionAnchors {
            for anchor in anchors {
                guard let view = anchor.view else { continue }
                popup.setAnchor(extensionID: extensionID, view: view)
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

    func pinToToolbar(_ extensionId: String, profileId: UUID?) {
        toolbarActions.pinToToolbar(extensionId, profileID: profileId)
    }

    func unpinFromToolbar(_ extensionId: String, profileId: UUID?) {
        toolbarActions.unpinFromToolbar(extensionId, profileID: profileId)
    }

    func movePinnedToolbarSlot(
        id: String,
        to targetIndex: Int,
        profileId: UUID?
    ) {
        toolbarActions.movePinnedToolbarSlot(
            id: id,
            to: targetIndex,
            profileID: profileId
        )
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
        within currentOrder: [String],
        profileId: UUID?
    ) {
        toolbarActions.moveUnpinnedExtension(
            id: id,
            to: targetIndex,
            within: currentOrder,
            profileID: profileId
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
