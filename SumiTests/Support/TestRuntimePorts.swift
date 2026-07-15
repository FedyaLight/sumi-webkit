import Foundation
import SumiWebRuntime

@testable import Sumi

/// Builds a `RuntimePortRegistry` from closures for unit tests that previously
/// constructed the legacy closure-bag runtime context with provider/handler bags.
@MainActor
private final class ClosureTabWebViewAvailabilityParticipant:
    TabWebViewAvailabilityParticipant {
    private let materializeAction: (Tab, BrowserWindowState) -> Void
    private let loadAction: (Tab) -> Void
    private let unloadAction: (Tab) -> Void
    private let prepareAction: (Tab) -> Void

    init(
        materialize: @escaping (Tab, BrowserWindowState) -> Void,
        load: @escaping (Tab) -> Void,
        unload: @escaping (Tab) -> Void,
        prepare: @escaping (Tab) -> Void
    ) {
        materializeAction = materialize
        loadAction = load
        unloadAction = unload
        prepareAction = prepare
    }

    func materializeVisibleWebViewIfNeeded(
        for tab: Tab,
        in windowState: BrowserWindowState
    ) {
        materializeAction(tab, windowState)
    }

    func load(_ tab: Tab) { loadAction(tab) }
    func unload(_ tab: Tab) { unloadAction(tab) }
    func prepare(_ tab: Tab) { prepareAction(tab) }
}

@MainActor
private final class ClosureTabWebViewOwnershipParticipant:
    TabWebViewOwnershipParticipant {
    private let removeAction: (Tab, Bool) -> Void
    private let trackingWindowIDs: (UUID) -> [UUID]
    private let primaryWindowID: (UUID) -> UUID?
    private let rebuildAction: (Tab, UUID?, URL?) -> Void
    private let liveWebView: (Tab) -> WKWebView?
    private let hasUntrackedWebView: (Tab) -> Bool

    init(
        remove: @escaping (Tab, Bool) -> Void,
        trackingWindowIDs: @escaping (UUID) -> [UUID],
        primaryWindowID: @escaping (UUID) -> UUID?,
        rebuild: @escaping (Tab, UUID?, URL?) -> Void,
        liveWebView: @escaping (Tab) -> WKWebView?,
        hasUntrackedWebView: @escaping (Tab) -> Bool
    ) {
        removeAction = remove
        self.trackingWindowIDs = trackingWindowIDs
        self.primaryWindowID = primaryWindowID
        rebuildAction = rebuild
        self.liveWebView = liveWebView
        self.hasUntrackedWebView = hasUntrackedWebView
    }

    func removeAllWebViews(
        for tab: Tab,
        closeActiveFullscreenMedia: Bool
    ) {
        removeAction(tab, closeActiveFullscreenMedia)
    }

    func trackingWindowIDs(for tabID: UUID) -> [UUID] {
        trackingWindowIDs(tabID)
    }

    func primaryTrackedWindowID(for tabID: UUID) -> UUID? {
        primaryWindowID(tabID)
    }

    func rebuildLiveWebViews(
        for tab: Tab,
        preferredPrimaryWindowID: UUID?,
        load url: URL?
    ) {
        rebuildAction(tab, preferredPrimaryWindowID, url)
    }

    func anyLiveWebView(for tab: Tab) -> WKWebView? { liveWebView(tab) }

    func hasUntrackedOwnedWebView(for tab: Tab) -> Bool {
        hasUntrackedWebView(tab)
    }
}

@MainActor
private final class ClosureTabWebViewRetirementParticipant:
    TabWebViewRetirementParticipant {
    private let capabilities: TestRuntimePorts.RetirementCapabilities

    init(_ capabilities: TestRuntimePorts.RetirementCapabilities) {
        self.capabilities = capabilities
    }

    func canRetire(_ tabs: [Tab]) -> Bool { capabilities.canRetire(tabs) }

    func beginCommittedRetirement(_ tabs: [Tab]) -> Bool {
        capabilities.beginCommitted(tabs)
    }

    func destroyRetiredGenerations(
        _ generations: [RetiredTabWebViewGeneration],
        completing tabs: [Tab]
    ) {
        capabilities.destroy(generations)
    }

    func destroyTerminallyDrainedGenerations(
        _ generations: [RetiredTabWebViewGeneration],
        belongingTo tabs: [Tab]
    ) {
        capabilities.destroyAfterTerminalDrain(generations)
    }
}

@MainActor
final class TestTabWebViewProfileTransitionParticipant:
    TabWebViewProfileTransitionParticipant {
    private let abortAction: (Set<UUID>) -> Int
    private let tabAction: (
        Tab,
        Profile,
        DeferredWebViewProfileAssignmentIntent,
        @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome
    private let spaceAction: (
        Space,
        Profile,
        DeferredWebViewSpaceProfileAssignmentIntent,
        any SpaceProfileWebViewReplacementTransaction,
        @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome

    init(
        abort: @escaping (Set<UUID>) -> Int = { _ in 0 },
        executeTab: @escaping (
            Tab,
            Profile,
            DeferredWebViewProfileAssignmentIntent,
            @escaping ProfileTransitionService.Settlement
        ) -> TabProfileAssignmentExecutionOutcome,
        executeSpace: @escaping (
            Space,
            Profile,
            DeferredWebViewSpaceProfileAssignmentIntent,
            any SpaceProfileWebViewReplacementTransaction,
            @escaping ProfileTransitionService.Settlement
        ) -> TabProfileAssignmentExecutionOutcome
    ) {
        abortAction = abort
        tabAction = executeTab
        spaceAction = executeSpace
    }

    func abortProfileTransitions(profileIDs: Set<UUID>) -> Int {
        abortAction(profileIDs)
    }

    func executeProfileAssignment(
        for tab: Tab,
        targetProfile: Profile,
        intent: DeferredWebViewProfileAssignmentIntent,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        tabAction(tab, targetProfile, intent, settlement)
    }

    func executeSpaceProfileAssignment(
        space: Space,
        targetProfile: Profile,
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        model: any SpaceProfileWebViewReplacementTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        spaceAction(space, targetProfile, intent, model, settlement)
    }
}

@MainActor
enum TestRuntimePorts {
    struct RetirementCapabilities {
        let canRetire: ([Tab]) -> Bool
        let beginCommitted: ([Tab]) -> Bool
        let destroy: ([RetiredTabWebViewGeneration]) -> Void
        let destroyAfterTerminalDrain: ([RetiredTabWebViewGeneration]) -> Void

        @MainActor static let rejecting = Self(
            canRetire: { _ in false },
            beginCommitted: { _ in false },
            destroy: { _ in
                preconditionFailure("Rejecting retirement fake cannot destroy")
            },
            destroyAfterTerminalDrain: { _ in
                preconditionFailure("Rejecting retirement fake cannot destroy")
            }
        )
    }

    static func webViewLifecycle(
        retirement: RetirementCapabilities,
        materializeVisibleTabWebViewIfNeeded: @escaping (Tab, BrowserWindowState) -> Void = { _, _ in /* No-op. */ },
        loadTab: @escaping (Tab) -> Void = { _ in /* No-op. */ },
        unloadTab: @escaping (Tab) -> Void = { _ in /* No-op. */ },
        requireRemoveAllWebViews: @escaping (Tab, Bool) -> Void = { _, _ in /* No-op. */ },
        windowIDsTrackingWebViews: @escaping (UUID) -> [UUID] = { _ in [] },
        primaryTrackedWindowId: @escaping (UUID) -> UUID? = { _ in nil },
        rebuildLiveWebViews: @escaping (Tab, UUID?, URL?) -> Void = { _, _, _ in /* No-op. */ },
        prepareTab: @escaping (Tab) -> Void = { _ in /* No-op. */ },
        anyLiveWebView: @escaping (Tab) -> WKWebView? = { _ in nil },
        hasUntrackedOwnedWebView: @escaping (Tab) -> Bool = { _ in false },
        retirementParticipant: (any TabWebViewRetirementParticipant)? = nil,
        profileTransitions: (any TabWebViewProfileTransitionParticipant)? = nil,
        executeProfileAssignment: @escaping (
            Tab,
            Profile,
            DeferredWebViewProfileAssignmentIntent
        ) -> TabProfileAssignmentExecutionOutcome = { tab, _, intent in
            tab.profileAssignment.commit(intent) ? .committed : .stale
        }
    ) -> TabManagerWebViewLifecycleService {
        let defaultProfileTransitions =
            TestTabWebViewProfileTransitionParticipant(
                executeTab: { tab, profile, intent, settlement in
                    let outcome = executeProfileAssignment(tab, profile, intent)
                    if outcome != .deferred {
                        settlement(
                            outcome == .committed
                                ? .committed
                                : .rejected(outcome)
                        )
                    }
                    return outcome
                },
                executeSpace: { _, _, _, model, settlement in
                    guard model.validateForStaging() else {
                        settlement(.rejected(.stale))
                        return .stale
                    }
                    do {
                        try model.stage()
                    } catch {
                        settlement(.rejected(.stale))
                        return .stale
                    }
                    guard model.stagedModelIsExact() else {
                        settlement(.conflicted)
                        return .failed
                    }
                    guard model.canClaimTerminalModel() else {
                        try? model.rollback()
                        model.publishRollback()
                        settlement(.rolledBack(.commitValidationFailed))
                        return .failed
                    }
                    guard model.claimTerminalModel() == .sealed else {
                        settlement(.leaseLost)
                        return .failed
                    }
                    model.publishCommit()
                    settlement(.committed)
                    return .committed
                }
            )
        return TabManagerWebViewLifecycleService(
            availability: ClosureTabWebViewAvailabilityParticipant(
                materialize: materializeVisibleTabWebViewIfNeeded,
                load: loadTab,
                unload: unloadTab,
                prepare: prepareTab
            ),
            ownership: ClosureTabWebViewOwnershipParticipant(
                remove: requireRemoveAllWebViews,
                trackingWindowIDs: windowIDsTrackingWebViews,
                primaryWindowID: primaryTrackedWindowId,
                rebuild: rebuildLiveWebViews,
                liveWebView: anyLiveWebView,
                hasUntrackedWebView: hasUntrackedOwnedWebView
            ),
            retirement: retirementParticipant
                ?? ClosureTabWebViewRetirementParticipant(retirement),
            profileTransitions: profileTransitions ?? defaultProfileTransitions
        )
    }

    static func make(
        currentProfileId: @escaping () -> UUID? = { nil },
        defaultProfileId: @escaping () -> UUID? = { nil },
        settings: @escaping () -> SumiSettingsService? = { nil },
        profileExists: @escaping (UUID) -> Bool = { _ in true },
        profile: @escaping (UUID) -> Profile? = { _ in nil },
        windowState: @escaping (UUID) -> BrowserWindowState? = { _ in nil },
        windows: @escaping () -> [(UUID, BrowserWindowState)] = { [] },
        windowStates: @escaping () -> [BrowserWindowState] = { [] },
        updateTabVisibility: @escaping () -> Void = { /* No-op. */ },
        webViewLifecycle: TabManagerWebViewLifecycleService? = nil,
        handleTabClosure: @escaping (UUID) -> Void = { _ in /* No-op. */ },
        handleTabClosures: ((Set<UUID>) -> Void)? = nil,
        visibleSplitTabIds: @escaping (UUID) -> [UUID] = { _ in [] },
        isTabVisibleInSplit: @escaping (UUID, UUID) -> Bool = { _, _ in false },
        isTabActiveInSplit: @escaping (UUID, UUID) -> Bool = { _, _ in false },
        notifyTabClosedIfLoaded: @escaping (Tab) -> Void = { _ in /* No-op. */ },
        notifyTabActivatedIfLoaded: @escaping (Tab, Tab?) -> Void = { _, _ in /* No-op. */ },
        captureClosedTab: @escaping (Tab, UUID?) -> Void = { _, _ in /* No-op. */ },
        captureDeletedShortcutLauncher: @escaping (ShortcutPin) -> Void = { _ in /* No-op. */ },
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)? = { nil },
        validateWindowStates: @escaping () -> Set<UUID> = { [] },
        persistWindowSession: @escaping (BrowserWindowState) -> Void = { _ in /* No-op. */ },
        syncWorkspaceThemeAcrossWindows: @escaping (Space, Bool) -> Void = { _, _ in /* No-op. */ },
        closeAuxiliaryMiniWindow: @escaping (Tab, AuxiliaryWindowCloseReason) -> Void = { _, _ in /* No-op. */ },
        isLiveFolder: @escaping (UUID) -> Bool = { _ in false },
        deleteLiveFolderState: @escaping (Set<UUID>) -> Void = { _ in /* No-op. */ }
    ) -> RuntimePortRegistry {
        RuntimePortRegistry(
            profileQuery: ClosureTabProfileQueryPort(
                currentProfileId: currentProfileId,
                defaultProfileId: defaultProfileId,
                settings: settings,
                profileExists: profileExists,
                profile: profile
            ),
            windowQuery: ClosureTabWindowQueryPort(
                windowState: windowState,
                windows: windows,
                windowStates: windowStates,
                updateTabVisibility: updateTabVisibility,
                validateWindowStates: validateWindowStates,
                persistWindowSession: persistWindowSession,
                syncWorkspaceThemeAcrossWindows: syncWorkspaceThemeAcrossWindows
            ),
            splitCoordination: ClosureTabSplitCoordinationPort(
                handleTabClosure: handleTabClosure,
                handleTabClosures: handleTabClosures,
                visibleSplitTabIds: visibleSplitTabIds,
                isTabVisibleInSplit: isTabVisibleInSplit,
                isTabActiveInSplit: isTabActiveInSplit
            ),
            extensionLifecycle: ClosureTabExtensionLifecyclePort(
                notifyTabClosedIfLoaded: notifyTabClosedIfLoaded,
                notifyTabActivatedIfLoaded: notifyTabActivatedIfLoaded
            ),
            sessionSideEffects: ClosureTabSessionSideEffectsPort(
                captureClosedTab: captureClosedTab,
                captureDeletedShortcutLauncher: captureDeletedShortcutLauncher,
                notifications: notifications,
                closeAuxiliaryMiniWindow: closeAuxiliaryMiniWindow,
                isLiveFolder: isLiveFolder,
                deleteLiveFolderState: deleteLiveFolderState
            ),
            webViewLifecycle: webViewLifecycle ?? self.webViewLifecycle(
                retirement: .rejecting
            )
        )
    }

    static var inactive: RuntimePortRegistry { make() }
}

@MainActor
private final class ClosureTabProfileQueryPort: TabProfileQueryPort {
    private let currentProfileIdProvider: () -> UUID?
    private let defaultProfileIdProvider: () -> UUID?
    private let settingsProvider: () -> SumiSettingsService?
    private let profileExistsHandler: (UUID) -> Bool
    private let profileProvider: (UUID) -> Profile?

    init(
        currentProfileId: @escaping () -> UUID?,
        defaultProfileId: @escaping () -> UUID?,
        settings: @escaping () -> SumiSettingsService?,
        profileExists: @escaping (UUID) -> Bool,
        profile: @escaping (UUID) -> Profile?
    ) {
        self.currentProfileIdProvider = currentProfileId
        self.defaultProfileIdProvider = defaultProfileId
        self.settingsProvider = settings
        self.profileExistsHandler = profileExists
        self.profileProvider = profile
    }

    var currentProfileId: UUID? { currentProfileIdProvider() }
    var defaultProfileId: UUID? { defaultProfileIdProvider() }
    var settings: SumiSettingsService? { settingsProvider() }

    func profileExists(_ profileId: UUID) -> Bool {
        profileExistsHandler(profileId)
    }

    func profile(with profileId: UUID) -> Profile? {
        profileProvider(profileId)
    }
}

@MainActor
private final class ClosureTabWindowQueryPort: TabWindowQueryPort {
    private let windowStateProvider: (UUID) -> BrowserWindowState?
    private let windowsProvider: () -> [(UUID, BrowserWindowState)]
    private let windowStatesProvider: () -> [BrowserWindowState]
    private let updateTabVisibilityHandler: () -> Void
    private let validateWindowStatesHandler: () -> Set<UUID>
    private let persistWindowSessionHandler: (BrowserWindowState) -> Void
    private let syncWorkspaceThemeAcrossWindowsHandler: (Space, Bool) -> Void

    init(
        windowState: @escaping (UUID) -> BrowserWindowState?,
        windows: @escaping () -> [(UUID, BrowserWindowState)],
        windowStates: @escaping () -> [BrowserWindowState],
        updateTabVisibility: @escaping () -> Void,
        validateWindowStates: @escaping () -> Set<UUID>,
        persistWindowSession: @escaping (BrowserWindowState) -> Void,
        syncWorkspaceThemeAcrossWindows: @escaping (Space, Bool) -> Void
    ) {
        self.windowStateProvider = windowState
        self.windowsProvider = windows
        self.windowStatesProvider = windowStates
        self.updateTabVisibilityHandler = updateTabVisibility
        self.validateWindowStatesHandler = validateWindowStates
        self.persistWindowSessionHandler = persistWindowSession
        self.syncWorkspaceThemeAcrossWindowsHandler = syncWorkspaceThemeAcrossWindows
    }

    func windowState(for windowId: UUID) -> BrowserWindowState? {
        windowStateProvider(windowId)
    }

    func forEachWindow(_ body: (UUID, BrowserWindowState) -> Void) {
        for (windowId, windowState) in windowsProvider() {
            body(windowId, windowState)
        }
    }

    func forEachWindowState(_ body: (BrowserWindowState) -> Void) {
        for windowState in windowStatesProvider() {
            body(windowState)
        }
    }

    func updateTabVisibility() {
        updateTabVisibilityHandler()
    }

    func validateWindowStates() -> Set<UUID> {
        validateWindowStatesHandler()
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        persistWindowSessionHandler(windowState)
    }

    func syncWorkspaceThemeAcrossWindows(for space: Space, animate: Bool) {
        syncWorkspaceThemeAcrossWindowsHandler(space, animate)
    }
}

@MainActor
private final class ClosureTabSplitCoordinationPort: TabSplitCoordinationPort {
    private let handleTabClosureHandler: (UUID) -> Void
    private let handleTabClosuresHandler: ((Set<UUID>) -> Void)?
    private let visibleSplitTabIdsProvider: (UUID) -> [UUID]
    private let isTabVisibleInSplitProvider: (UUID, UUID) -> Bool
    private let isTabActiveInSplitProvider: (UUID, UUID) -> Bool

    init(
        handleTabClosure: @escaping (UUID) -> Void,
        handleTabClosures: ((Set<UUID>) -> Void)?,
        visibleSplitTabIds: @escaping (UUID) -> [UUID],
        isTabVisibleInSplit: @escaping (UUID, UUID) -> Bool,
        isTabActiveInSplit: @escaping (UUID, UUID) -> Bool
    ) {
        self.handleTabClosureHandler = handleTabClosure
        self.handleTabClosuresHandler = handleTabClosures
        self.visibleSplitTabIdsProvider = visibleSplitTabIds
        self.isTabVisibleInSplitProvider = isTabVisibleInSplit
        self.isTabActiveInSplitProvider = isTabActiveInSplit
    }

    func handleTabClosure(_ tabId: UUID) {
        handleTabClosureHandler(tabId)
    }

    func stageTabClosures(
        _ tabIds: Set<UUID>
    ) -> (any TabSplitClosureSettlement)? {
        guard !tabIds.isEmpty else { return nil }
        return ClosureTabSplitClosureSettlement { [self] in
            if let handleTabClosuresHandler {
                handleTabClosuresHandler(tabIds)
            } else {
                tabIds.forEach(handleTabClosureHandler)
            }
        }
    }

    func visibleSplitTabIds(for windowId: UUID) -> [UUID] {
        visibleSplitTabIdsProvider(windowId)
    }

    func isTabVisibleInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        isTabVisibleInSplitProvider(tabId, windowId)
    }

    func isTabActiveInSplit(_ tabId: UUID, in windowId: UUID) -> Bool {
        isTabActiveInSplitProvider(tabId, windowId)
    }
}

@MainActor
private final class ClosureTabSplitClosureSettlement:
    TabSplitClosureSettlement {
    private let publishAction: () -> Void
    private var isPublished = false

    init(publish: @escaping () -> Void) {
        publishAction = publish
    }

    func publish() {
        guard !isPublished else { return }
        isPublished = true
        publishAction()
    }
}

@MainActor
private final class ClosureTabExtensionLifecyclePort: TabExtensionLifecyclePort {
    private let notifyTabClosedIfLoadedHandler: (Tab) -> Void
    private let notifyTabActivatedIfLoadedHandler: (Tab, Tab?) -> Void

    init(
        notifyTabClosedIfLoaded: @escaping (Tab) -> Void,
        notifyTabActivatedIfLoaded: @escaping (Tab, Tab?) -> Void
    ) {
        self.notifyTabClosedIfLoadedHandler = notifyTabClosedIfLoaded
        self.notifyTabActivatedIfLoadedHandler = notifyTabActivatedIfLoaded
    }

    func notifyTabClosedIfLoaded(_ tab: Tab) {
        notifyTabClosedIfLoadedHandler(tab)
    }

    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?) {
        notifyTabActivatedIfLoadedHandler(newTab, previous)
    }
}

@MainActor
private final class ClosureTabSessionSideEffectsPort: TabSessionSideEffectsPort {
    private let captureClosedTabHandler: (Tab, UUID?) -> Void
    private let captureDeletedShortcutLauncherHandler: (ShortcutPin) -> Void
    private let notificationsProvider: @MainActor () -> (any BrowserNotificationPresenting)?
    private let closeAuxiliaryMiniWindowHandler: (Tab, AuxiliaryWindowCloseReason) -> Void
    private let isLiveFolderProvider: (UUID) -> Bool
    private let deleteLiveFolderStateHandler: (Set<UUID>) -> Void

    init(
        captureClosedTab: @escaping (Tab, UUID?) -> Void,
        captureDeletedShortcutLauncher: @escaping (ShortcutPin) -> Void,
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)?,
        closeAuxiliaryMiniWindow: @escaping (Tab, AuxiliaryWindowCloseReason) -> Void,
        isLiveFolder: @escaping (UUID) -> Bool,
        deleteLiveFolderState: @escaping (Set<UUID>) -> Void
    ) {
        self.captureClosedTabHandler = captureClosedTab
        self.captureDeletedShortcutLauncherHandler = captureDeletedShortcutLauncher
        self.notificationsProvider = notifications
        self.closeAuxiliaryMiniWindowHandler = closeAuxiliaryMiniWindow
        self.isLiveFolderProvider = isLiveFolder
        self.deleteLiveFolderStateHandler = deleteLiveFolderState
    }

    func captureClosedTab(_ tab: Tab, sourceSpaceId: UUID?) {
        captureClosedTabHandler(tab, sourceSpaceId)
    }

    func captureDeletedShortcutLauncher(_ pin: ShortcutPin) {
        captureDeletedShortcutLauncherHandler(pin)
    }

    func notifications() -> (any BrowserNotificationPresenting)? {
        notificationsProvider()
    }

    func closeAuxiliaryMiniWindow(for tab: Tab, reason: AuxiliaryWindowCloseReason) {
        closeAuxiliaryMiniWindowHandler(tab, reason)
    }

    func isLiveFolder(_ folderId: UUID) -> Bool {
        isLiveFolderProvider(folderId)
    }

    func deleteLiveFolderState(forFolderIds folderIds: Set<UUID>) {
        deleteLiveFolderStateHandler(folderIds)
    }
}
