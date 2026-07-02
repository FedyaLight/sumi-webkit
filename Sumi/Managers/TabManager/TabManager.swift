import AppKit
import Combine
import Observation
import SwiftData
import WebKit

@MainActor
class TabManager: ObservableObject {
    private static let faviconPresentationRefreshDebounceNanoseconds: UInt64 = 250_000_000

    enum TabManagerError: LocalizedError {
        case spaceNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .spaceNotFound(let id):
                return "Space with id \(id.uuidString) was not found."
            }
        }
    }

    typealias SpaceLauncherProjection = SpaceLauncherProjectionSnapshot
    typealias EssentialsCapacityPolicy = EssentialsShortcutPlacementOwner.CapacityPolicy
    typealias EssentialsTargetContext = EssentialsShortcutPlacementOwner.TargetContext
    typealias EssentialsTargetSource = EssentialsShortcutPlacementOwner.TargetSource
    typealias EssentialsTargetResolution = EssentialsShortcutPlacementOwner.TargetResolution
    typealias EssentialsInsertionContext = EssentialsShortcutPlacementOwner.InsertionContext
    typealias EssentialsInsertionPlan = EssentialsShortcutPlacementOwner.InsertionPlan

    private(set) var runtimeContext: TabManagerRuntimeContext?
    weak var sumiSettings: SumiSettingsService?
    let context: ModelContext
    let persistence: TabSnapshotRepository
    let runtimeStateCoalescer: RuntimeStateCoalescer
    let faviconService: any BrowserFaviconServicing
    let faviconImageService: any BrowserFaviconImageServicing
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging

    lazy var runtimeStore = DefaultTabRuntimeStore(tabManager: self)
    lazy var folderMutationOwner = TabFolderMutationOwner(tabManager: self)
    let spaceCollectionStateOwner = TabSpaceCollectionStateOwner()
    let regularTabCollectionStateOwner = RegularTabCollectionStateOwner()
    lazy var regularTabCollectionOwner = RegularTabCollectionOwner(
        tabManager: self,
        stateOwner: regularTabCollectionStateOwner
    )
    lazy var regularTabLifecycleOwner = TabRegularLifecycleOwner(tabManager: self)
    lazy var tabRemovalOwner = TabRemovalOwner(tabManager: self)
    lazy var activeSelectionOwner = TabActiveSelectionOwner(tabManager: self)
    lazy var regularTabDragService = SidebarRegularTabDragService(tabManager: self)
    lazy var lazyRestoreCoordinator = TabLazyRestoreCoordinator(tabManager: self)
    lazy var spacePinnedStructureOwner = SpacePinnedStructureOwner(tabManager: self)
    lazy var spaceLifecycleOwner = TabSpaceLifecycleOwner(tabManager: self)
    lazy var profileAssignmentOwner = TabProfileAssignmentOwner(tabManager: self)
    lazy var lastSessionRestoreOwner = TabLastSessionRestoreOwner(tabManager: self)
    lazy var shortcutPinCommandOwner = ShortcutPinCommandOwner(tabManager: self)
    lazy var sidebarDragRoutingOwner = SidebarDragOperationRoutingOwner(tabManager: self)
    private lazy var essentialsShortcutPlacementOwner = EssentialsShortcutPlacementOwner(
        dependencies: EssentialsShortcutPlacementOwner.Dependencies(
            spaces: { [weak self] in
                self?.spaces ?? []
            },
            runtimeContext: { [weak self] in
                self?.runtimeContext
            },
            essentialPins: { [weak self] profileId in
                self?.essentialPins(for: profileId) ?? []
            }
        )
    )
    private lazy var shortcutPinStoreOwner = ShortcutPinStoreOwner(
        dependencies: ShortcutPinStoreOwner.Dependencies(
            runtimeContext: { [weak self] in
                self?.runtimeContext
            },
            pinnedByProfile: { [weak self] in
                self?.pinnedByProfile ?? [:]
            },
            setPinnedTabs: { [weak self] pins, profileId in
                self?.setPinnedTabs(pins, for: profileId)
            },
            topLevelSpacePinnedItems: { [weak self] spaceId in
                self?.topLevelSpacePinnedItems(for: spaceId) ?? []
            },
            applyTopLevelSpacePinnedOrder: { [weak self] items, spaceId in
                self?.applyTopLevelSpacePinnedOrder(items, for: spaceId)
            },
            insertTopLevelSpacePinnedShortcut: { [weak self] pin, spaceId, targetIndex in
                self?.insertTopLevelSpacePinnedShortcut(pin, in: spaceId, at: targetIndex)
            },
            withSpacePinnedShortcutGroup: { [weak self] spaceId, folderId, mutate in
                self?.withSpacePinnedShortcutGroup(for: spaceId, folderId: folderId) { pins in
                    mutate(&pins)
                }
            },
            spacePinnedPins: { [weak self] spaceId in
                self?.spacePinnedPins(for: spaceId) ?? []
            },
            openFolderIfNeeded: { [weak self] folderId in
                self?.openFolderIfNeeded(folderId)
            },
            adjustedSameContainerInsertionIndex: { [weak self] currentIndex, proposedIndex in
                guard let self else { return proposedIndex }
                return self.adjustedSameContainerInsertionIndex(
                    currentIndex: currentIndex,
                    proposedIndex: proposedIndex
                )
            }
        )
    )
    private lazy var shortcutPinRuntimeResolutionOwner = ShortcutPinRuntimeResolutionOwner(
        dependencies: ShortcutPinRuntimeResolutionOwner.Dependencies(
            spaces: { [weak self] in
                self?.spaces ?? []
            },
            runtimeContext: { [weak self] in
                self?.runtimeContext
            },
            faviconService: { [weak self] in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.faviconService
            }
        )
    )
    private lazy var shortcutPinConversionOwner = ShortcutPinConversionOwner(
        dependencies: ShortcutPinConversionOwner.Dependencies(
            insertRegularTabFromShortcut: { [weak self] pin, spaceId, targetIndex in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.insertRegularTabFromShortcut(pin, into: spaceId, at: targetIndex)
            },
            removeShortcutPinFromContainers: { [weak self] pin in
                self?.removeShortcutPinFromContainers(pin)
            },
            scheduleStructuralPersistence: { [weak self] in
                self?.scheduleStructuralPersistence()
            },
            makeShortcutPin: { [weak self] tab, role, profileId, spaceId, folderId, index in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.makeShortcutPin(
                    from: tab,
                    role: role,
                    profileId: profileId,
                    spaceId: spaceId,
                    folderId: folderId,
                    index: index
                )
            },
            insertShortcutPin: { [weak self] pin, targetIndex, openTargetFolder in
                self?.insertShortcutPin(
                    pin,
                    at: targetIndex,
                    openTargetFolder: openTargetFolder
                )
            },
            convertDisplayedTabToShortcutLiveInstances: { [weak self] tab, pin, preferredWindowId in
                self?.convertDisplayedTabToShortcutLiveInstances(
                    tab,
                    pin: pin,
                    preferredWindowId: preferredWindowId
                ) ?? false
            },
            removeTab: { [weak self] tabId in
                self?.removeTab(tabId)
            }
        )
    )
    private lazy var shortcutDragOperationOwner = ShortcutDragOperationOwner(
        dependencies: ShortcutDragOperationOwner.Dependencies(
            reorderEssential: { [weak self] pin, index in
                self?.reorderEssential(pin, to: index) ?? false
            },
            moveShortcutPin: { [weak self] pin, role, profileId, spaceId, folderId, index, openTargetFolder in
                self?.moveShortcutPin(
                    pin,
                    to: role,
                    profileId: profileId,
                    spaceId: spaceId,
                    folderId: folderId,
                    index: index,
                    openTargetFolder: openTargetFolder
                )
            },
            folderSpaceId: { [weak self] folderId in
                self?.folderSpaceId(for: folderId)
            },
            resolvedEssentialsProfileId: { [weak self] operation in
                self?.resolvedEssentialsProfileId(for: operation)
            },
            convertShortcutPinToRegularTab: { [weak self] pin, spaceId, targetIndex in
                self?.convertShortcutPinToRegularTab(pin, in: spaceId, at: targetIndex) ?? false
            },
            removeShortcutPinFromContainers: { [weak self] pin in
                self?.removeShortcutPinFromContainers(pin)
            },
            insertRegularTabFromShortcut: { [weak self] pin, spaceId, targetIndex in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.insertRegularTabFromShortcut(pin, into: spaceId, at: targetIndex)
            },
            scheduleStructuralPersistence: { [weak self] in
                self?.scheduleStructuralPersistence()
            }
        )
    )
    private lazy var shortcutPresentationOwner = TabShortcutPresentationOwner(
        dependencies: TabShortcutPresentationOwner.Dependencies(
            transientShortcutTabsByWindow: { [weak self] in
                self?.transientTabRegistryOwner.transientShortcutTabsByWindow ?? [:]
            },
            windowState: { [weak self] windowId in
                self?.runtimeContext?.windowState(for: windowId)
            },
            shortcutPin: { [weak self] pinId in
                self?.shortcutPin(by: pinId)
            },
            resolvedExecutionProfileId: { [weak self] pin, currentSpaceId in
                self?.resolvedExecutionProfileId(for: pin, currentSpaceId: currentSpaceId)
            },
            faviconService: { [weak self] in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.faviconService
            },
            faviconImageService: { [weak self] in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.faviconImageService
            },
            visitedLinkStore: { [weak self] in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.visitedLinkStore
            },
            prepareTabForRuntime: { [weak self] tab in
                self?.prepareTabForRuntime(tab)
            }
        )
    )
    private lazy var shortcutLiveTabOwner = ShortcutLiveTabOwner(
        dependencies: ShortcutLiveTabOwner.Dependencies(
            runtimeContext: { [weak self] in
                self?.runtimeContext
            },
            transientShortcutTabsByWindow: { [weak self] in
                self?.transientTabRegistryOwner.transientShortcutTabsByWindow ?? [:]
            },
            updateTransientShortcutTabsByWindow: { [weak self] update in
                self?.transientTabRegistryOwner.updateTransientShortcutTabsByWindow(update)
            },
            currentSpaceId: { [weak self] in
                self?.currentSpace?.id
            },
            firstRegularTabId: { [weak self] spaceId in
                self?.regularTabCollectionOwner.tabs(in: spaceId).first?.id
            },
            tab: { [weak self] tabId in
                self?.tab(for: tabId)
            },
            resolvedLiveSpaceId: { [weak self] pin, currentSpaceId in
                self?.resolvedLiveSpaceId(for: pin, currentSpaceId: currentSpaceId)
            },
            resolvedExecutionProfileId: { [weak self] pin, currentSpaceId in
                self?.resolvedExecutionProfileId(for: pin, currentSpaceId: currentSpaceId)
            },
            assignProfile: { [weak self] profileId, tab in
                self?.assignProfile(profileId, to: tab)
            },
            attach: { [weak self] tab in
                self?.attach(tab)
            },
            detach: { [weak self] tab in
                self?.detach(tab)
            },
            notifyTransientShortcutStateChanged: { [weak self] in
                self?.notifyTransientShortcutStateChanged()
            },
            cancelRuntimeStatePersistence: { [weak self] tabId in
                self?.cancelRuntimeStatePersistence(for: tabId)
            },
            pinnedByProfile: { [weak self] in
                self?.pinnedByProfile ?? [:]
            },
            setPinnedTabs: { [weak self] pins, profileId in
                self?.setPinnedTabs(pins, for: profileId)
            },
            removeRegularTab: { [weak self] tabId, spaceId, currentSpaceId in
                _ = self?.regularTabCollectionOwner.remove(
                    tabId,
                    from: spaceId,
                    currentSpaceId: currentSpaceId
                )
            },
            insertRegularTab: { [weak self] tab, spaceId, insertionIndex in
                self?.regularTabCollectionOwner.insert(tab, in: spaceId, at: insertionIndex)
            },
            faviconService: { [weak self] in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.faviconService
            },
            faviconImageService: { [weak self] in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.faviconImageService
            },
            visitedLinkStore: { [weak self] in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.visitedLinkStore
            }
        )
    )
    private lazy var spaceLauncherProjectionOwner = SpaceLauncherProjectionOwner(
        dependencies: SpaceLauncherProjectionOwner.Dependencies(
            regularTabs: { [weak self] spaceId in
                self?.regularTabCollectionOwner.tabs(in: spaceId) ?? []
            },
            spacePinnedPins: { [weak self] spaceId in
                self?.spacePinnedPins(for: spaceId) ?? []
            },
            folders: { [weak self] spaceId in
                self?.foldersBySpace[spaceId] ?? []
            },
            shortcutHostedSplitGroups: { [weak self] spaceId in
                self?.shortcutHostedSplitGroups(for: spaceId) ?? []
            },
            liveShortcutTabs: { [weak self] windowId in
                self?.shortcutPresentationOwner.liveShortcutTabs(in: windowId) ?? []
            },
            transientShortcutTabsByWindow: { [weak self] in
                self?.transientTabRegistryOwner.transientShortcutTabsByWindow ?? [:]
            }
        )
    )

    // Spaces
    var spaces: [Space] {
        get { spaceCollectionStateOwner.spaces }
        set {
            objectWillChange.send()
            spaceCollectionStateOwner.replaceSpaces(newValue)
        }
    }

    var currentSpace: Space? {
        get { spaceCollectionStateOwner.currentSpace }
        set {
            objectWillChange.send()
            spaceCollectionStateOwner.replaceCurrentSpace(newValue)
        }
    }

    // Normal tabs per space
    var tabsBySpace: [UUID: [Tab]] {
        get { regularTabCollectionStateOwner.tabsBySpace }
        set {
            objectWillChange.send()
            regularTabCollectionStateOwner.replaceTabsBySpace(newValue)
        }
    }

    var tabsBySpacePublisher: AnyPublisher<[UUID: [Tab]], Never> {
        regularTabCollectionStateOwner.tabsBySpacePublisher
    }

    let splitGroupCollectionStateOwner = SplitGroupCollectionStateOwner()

    // Structural split groups, restored and persisted with the tab model.
    var splitGroups: [SplitGroup] {
        get { splitGroupCollectionStateOwner.splitGroups }
        set {
            objectWillChange.send()
            splitGroupCollectionStateOwner.replaceSplitGroups(newValue)
        }
    }
    lazy var splitGroupRepairOwner = TabManagerSplitGroupRepairOwner(
        dependencies: .live(tabManager: self)
    )
    lazy var splitGroupStructureOwner = TabSplitGroupStructureOwner(tabManager: self)

    let folderCollectionStateOwner = TabFolderCollectionStateOwner()

    // Folders per space
    var foldersBySpace: [UUID: [TabFolder]] {
        get { folderCollectionStateOwner.foldersBySpace }
        set {
            objectWillChange.send()
            folderCollectionStateOwner.replaceFoldersBySpace(newValue)
        }
    }

    private let shortcutPinCollectionStateOwner = ShortcutPinCollectionStateOwner()

    // Global pinned launchers (essentials), isolated per profile
    var pinnedByProfile: [UUID: [ShortcutPin]] {
        get { shortcutPinCollectionStateOwner.pinnedByProfile }
        set {
            objectWillChange.send()
            shortcutPinCollectionStateOwner.replacePinnedByProfile(newValue)
        }
    }

    // Space-level shortcut launchers
    var spacePinnedShortcuts: [UUID: [ShortcutPin]] {
        get { shortcutPinCollectionStateOwner.spacePinnedShortcuts }
        set {
            objectWillChange.send()
            shortcutPinCollectionStateOwner.replaceSpacePinnedShortcuts(newValue)
        }
    }

    // Pinned launchers encountered during load that have no profile assignment yet
    var pendingPinnedWithoutProfile: [ShortcutPin] {
        get { shortcutPinCollectionStateOwner.pendingPinnedWithoutProfile }
        set {
            objectWillChange.send()
            shortcutPinCollectionStateOwner.replacePendingPinnedWithoutProfile(newValue)
        }
    }

    let transientTabRegistryOwner = TabTransientTabRegistryOwner()
    // Transient shortcut-backed live tabs per window, keyed by shortcut pin id.
    var transientShortcutTabsByWindow: [UUID: [UUID: Tab]] {
        get { transientTabRegistryOwner.transientShortcutTabsByWindow }
        set { transientTabRegistryOwner.replaceTransientShortcutTabsByWindow(newValue) }
    }

    // Transient extension-owned tabs created for internal extension pages that
    // WebKit may close immediately during install/onboarding handshakes.
    var transientExtensionTabsByID: [UUID: Tab] {
        get { transientTabRegistryOwner.transientExtensionTabsByID }
        set { transientTabRegistryOwner.replaceTransientExtensionTabsByID(newValue) }
    }

    var auxiliaryMiniWindowTabsByID: [UUID: Tab] {
        get { transientTabRegistryOwner.auxiliaryMiniWindowTabsByID }
        set { transientTabRegistryOwner.replaceAuxiliaryMiniWindowTabsByID(newValue) }
    }
    private let structuralLookupOwner = TabStructuralLookupOwner()
    private lazy var structuralCollectionMutationOwner = TabStructuralCollectionMutationOwner(
        dependencies: .live(tabManager: self)
    )
    private lazy var tabCollectionMembershipOwner = TabCollectionMembershipOwner(
        tabManager: self,
        structuralLookupOwner: structuralLookupOwner,
        transientTabRegistryOwner: transientTabRegistryOwner
    )
    private lazy var transientWebKitTabLifecycleOwner = TabTransientWebKitTabLifecycleOwner(
        dependencies: TabTransientWebKitTabLifecycleOwner.Dependencies(
            settings: { [weak self] in self?.sumiSettings ?? self?.runtimeContext?.settings },
            runtimeContext: { [weak self] in self?.runtimeContext },
            membershipOwner: { [weak self] in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.tabCollectionMembershipOwner
            },
            regularTabCollectionOwner: { [weak self] in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.regularTabCollectionOwner
            },
            attach: { [weak self] tab in self?.attach(tab) },
            detach: { [weak self] tab in self?.detach(tab) },
            targetSpace: { [weak self] space in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.resolvedTargetSpace(preferred: space)
            },
            spaceForID: { [weak self] spaceId in
                self?.spaces.first { $0.id == spaceId }
            },
            backfillTargetSpaceProfileIfNeeded: { [weak self] space, profileId in
                guard let self else { return false }
                return self.backfillTargetSpaceProfileIfNeeded(space, profileId: profileId)
            },
            insertRegularTab: { [weak self] tab, spaceId, insertionIndex in
                self?.regularTabLifecycleOwner.insertRegularTab(tab, in: spaceId, at: insertionIndex)
            },
            scheduleStructuralPersistence: { [weak self] in self?.scheduleStructuralPersistence() },
            setActiveTab: { [weak self] tab in self?.setActiveTab(tab) },
            tabForID: { [weak self] id in self?.tab(for: id) },
            faviconService: { [weak self] in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.faviconService
            },
            faviconImageService: { [weak self] in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.faviconImageService
            },
            visitedLinkStore: { [weak self] in
                guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
                return self.visitedLinkStore
            }
        )
    )
    /// Emitted when tab structure changes without a corresponding `@Published` update (e.g. transient shortcut live tabs). Not used for persistence completion—`scheduleStructuralPersistence()` does not send this.
    let structuralChanges = PassthroughSubject<Void, Never>()
    private lazy var structuralPublishOwner = TabStructuralPublishOwner(structuralChanges: structuralChanges)
    var structuralLookupBatchFlushCount: Int { structuralLookupOwner.batchFlushCount }
    var structuralLookupImmediateFlushCount: Int { structuralLookupOwner.immediateFlushCount }
    private lazy var faviconPresentationRefreshOwner = TabFaviconPresentationRefreshOwner(
        dependencies: TabFaviconPresentationRefreshOwner.Dependencies(
            notificationCenter: .default,
            debounceNanoseconds: Self.faviconPresentationRefreshDebounceNanoseconds,
            tabsNeedingRefresh: { [weak self] in
                guard let self else { return [] }
                return regularTabCollectionStateOwner.allTabs()
                    + transientTabRegistryOwner.transientShortcutTabs
            },
            requestStructuralPublish: { [weak self] in
                self?.requestStructuralPublish()
            }
        )
    )
    // Space activation to resume after a deferred profile switch
    var pendingSpaceActivation: UUID?

    // Live essentials API for shell views that still read a tab-backed collection.
    var pinnedTabs: [Tab] {
        activeEssentialTabs(for: runtimeContext?.currentProfileId)
    }

    func essentialTabs(for profileId: UUID?) -> [Tab] {
        activeEssentialTabs(for: profileId)
    }

    func essentialPins(for profileId: UUID?) -> [ShortcutPin] {
        shortcutPinCollectionStateOwner.essentialPins(for: profileId)
    }

    func resolveEssentialsTarget(
        using context: EssentialsTargetContext? = nil
    ) -> EssentialsTargetResolution {
        essentialsShortcutPlacementOwner.resolveTarget(using: context)
    }

    func resolvedEssentialsProfileId(
        using context: EssentialsTargetContext? = nil
    ) -> UUID? {
        essentialsShortcutPlacementOwner.resolvedProfileId(using: context)
    }

    func canAddURLToEssentials(
        _ url: URL,
        using context: EssentialsTargetContext? = nil
    ) -> Bool {
        essentialsShortcutPlacementOwner.canAddURL(url, using: context)
    }

    func resolveEssentialsInsertion(
        using context: EssentialsInsertionContext
    ) -> EssentialsInsertionPlan? {
        essentialsShortcutPlacementOwner.resolveInsertion(using: context)
    }

    func resolvedEssentialsProfileId(for operation: DragOperation) -> UUID? {
        essentialsShortcutPlacementOwner.resolvedProfileId(for: operation)
    }

    func logEssentialsTargetMismatchIfNeeded(
        resolution: EssentialsTargetResolution,
        context: EssentialsTargetContext?
    ) {
        essentialsShortcutPlacementOwner.logTargetMismatchIfNeeded(
            resolution: resolution,
            context: context
        )
    }

    func withPinnedArray(for profileId: UUID, _ mutate: (inout [ShortcutPin]) -> Void) {
        shortcutPinStoreOwner.withPinnedArray(for: profileId, mutate)
    }

    func reindexed(_ pins: [ShortcutPin]) -> [ShortcutPin] {
        shortcutPinStoreOwner.reindexed(pins)
    }

    @discardableResult
    func insertShortcutPin(
        _ pin: ShortcutPin,
        at targetIndex: Int,
        openTargetFolder: Bool = true
    ) -> ShortcutPin? {
        shortcutPinStoreOwner.insert(
            pin,
            at: targetIndex,
            openTargetFolder: openTargetFolder
        )
    }

    @discardableResult
    func moveShortcutPin(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        openTargetFolder: Bool = true
    ) -> ShortcutPin? {
        withStructuralUpdateTransaction {
            let inserted = shortcutPinStoreOwner.move(
                pin,
                to: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                index: index,
                openTargetFolder: openTargetFolder
            )
            if let inserted {
                updateTransientShortcutBindings(for: inserted)
            }
            scheduleStructuralPersistence()
            return inserted
        }
    }

    func removeShortcutPinFromContainers(_ pin: ShortcutPin) {
        shortcutPinStoreOwner.removeFromContainers(pin)
    }

    func makeShortcutPin(
        from tab: Tab,
        role: ShortcutPinRole,
        profileId: UUID? = nil,
        spaceId: UUID? = nil,
        folderId: UUID? = nil,
        index: Int
    ) -> ShortcutPin {
        shortcutPinRuntimeResolutionOwner.makeShortcutPin(
            from: tab,
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            index: index
        )
    }

    func resolvedLiveSpaceId(for pin: ShortcutPin, currentSpaceId: UUID?) -> UUID? {
        shortcutPinRuntimeResolutionOwner.resolvedLiveSpaceId(
            for: pin,
            currentSpaceId: currentSpaceId
        )
    }

    func resolvedExecutionProfileId(for pin: ShortcutPin, currentSpaceId: UUID? = nil) -> UUID? {
        shortcutPinRuntimeResolutionOwner.resolvedExecutionProfileId(
            for: pin,
            currentSpaceId: currentSpaceId
        )
    }

    func resolvedFaviconPartition(for pin: ShortcutPin, currentSpaceId: UUID? = nil) -> SumiFaviconPartition {
        shortcutPinRuntimeResolutionOwner.resolvedFaviconPartition(
            for: pin,
            currentSpaceId: currentSpaceId
        )
    }

    @discardableResult
    func convertShortcutPinToRegularTab(
        _ pin: ShortcutPin,
        in targetSpaceId: UUID,
        at targetIndex: Int? = nil
    ) -> Bool {
        withStructuralUpdateTransaction {
            shortcutPinConversionOwner.convertShortcutPinToRegularTab(
                pin,
                in: targetSpaceId,
                at: targetIndex
            )
        }
    }

    @discardableResult
    func convertTabToShortcutPin(
        _ tab: Tab,
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        at targetIndex: Int,
        openTargetFolder: Bool = true,
        preferredWindowId: UUID? = nil
    ) -> ShortcutPin? {
        withStructuralUpdateTransaction {
            shortcutPinConversionOwner.convertTabToShortcutPin(
                tab,
                role: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                at: targetIndex,
                openTargetFolder: openTargetFolder,
                preferredWindowId: preferredWindowId
            )
        }
    }

    @discardableResult
    func handleShortcutDragOperation(_ pin: ShortcutPin, operation: DragOperation) -> Bool {
        withStructuralUpdateTransaction {
            shortcutDragOperationOwner.handleShortcutDragOperation(pin, operation: operation)
        }
    }

    func spacePinnedPins(for spaceId: UUID) -> [ShortcutPin] {
        shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId)
    }

    func liveSpacePinnedTabs(for spaceId: UUID) -> [Tab] {
        transientTabRegistryOwner.transientShortcutTabs
            .filter { $0.spaceId == spaceId && $0.shortcutPinRole == .spacePinned }
            .sorted { lhs, rhs in
                let lhsIndex = lhs.shortcutPinId.flatMap { shortcutPin(by: $0)?.index } ?? lhs.index
                let rhsIndex = rhs.shortcutPinId.flatMap { shortcutPin(by: $0)?.index } ?? rhs.index
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func selectionTabsForCurrentContext(in windowId: UUID? = nil) -> [Tab] {
        let contextWindowState = windowId.flatMap { runtimeContext?.windowState(for: $0) }
        let contextSpaceId = contextWindowState?.currentSpaceId ?? currentSpace?.id
        let contextProfileId =
            contextWindowState?.currentProfileId
            ?? contextSpaceId.flatMap { spaceId in
                spaceCollectionStateOwner.profileId(for: spaceId)
            }
            ?? runtimeContext?.currentProfileId
        let regularTabs = contextSpaceId.map { regularTabCollectionOwner.tabs(in: $0) } ?? []
        let activeLauncherTab = windowId
            .flatMap { activeShortcutTab(for: $0) }
            .flatMap { liveTab -> Tab? in
                guard liveTab.shortcutPinRole != .essential else { return nil }
                guard liveTab.spaceId == nil || liveTab.spaceId == contextSpaceId else { return nil }
                return liveTab
            }

        return activeEssentialTabs(for: contextProfileId) + (activeLauncherTab.map { [$0] } ?? []) + regularTabs
    }

    func folderPinnedPins(for folderId: UUID, in spaceId: UUID) -> [ShortcutPin] {
        spacePinnedPins(for: spaceId)
            .filter { $0.folderId == folderId }
            .sorted { $0.index < $1.index }
    }

    func childFolders(of parentFolderId: UUID?, in spaceId: UUID) -> [TabFolder] {
        folderCollectionStateOwner.childFolders(of: parentFolderId, in: spaceId)
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        shortcutPinCollectionStateOwner.shortcutPin(by: id)
    }

    func folder(by id: UUID) -> TabFolder? {
        folderCollectionStateOwner.folder(by: id)
    }

    func parentContainer(for folder: TabFolder) -> TabDragManager.DragContainer {
        if let parentFolderId = folder.parentFolderId {
            return .folder(parentFolderId)
        }
        return .spacePinned(folder.spaceId)
    }

    func resolveDragTab(for id: UUID) -> Tab? {
        if let live = tab(for: id) {
            return live
        }
        if let pin = shortcutPin(by: id) {
            return dragProxyTab(for: pin)
        }
        return nil
    }

    func resolveSidebarDragPayload(for item: SumiDragItem) -> DragOperation.Payload? {
        switch item.kind {
        case .tab:
            if let pin = shortcutPin(by: item.tabId) {
                return .pin(pin)
            }
            return resolveDragTab(for: item.tabId).map { .tab($0) }
        case .folder:
            return folder(by: item.tabId).map { .folder($0) }
        case .splitGroup:
            return splitGroup(with: item.tabId).map { .splitGroup($0) }
        }
    }

    // Flattened pinned across all profiles for internal ops
    var allPinnedTabsAllProfiles: [Tab] {
        activeShortcutTabs(role: .essential)
    }

    // Currently active tab
    var currentTab: Tab?
    private(set) var hasLoadedInitialData = false

    func markInitialDataLoadStarted() {
        hasLoadedInitialData = false
    }

    func markInitialDataLoadFinished() {
        hasLoadedInitialData = true
    }

    init(
        runtimeContext: TabManagerRuntimeContext? = nil,
        context: ModelContext,
        loadPersistedState: Bool = true,
        faviconService: any BrowserFaviconServicing = BrowserManagerDataServices.productionFaviconService,
        faviconImageService: any BrowserFaviconImageServicing = BrowserManagerDataServices.productionFaviconImageService,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = BrowserManagerDataServices.productionVisitedLinkStore
    ) {
        self.runtimeContext = runtimeContext
        self.context = context
        self.faviconService = faviconService
        self.faviconImageService = faviconImageService
        self.visitedLinkStore = visitedLinkStore
        let persistence = TabSnapshotRepository(container: context.container)
        self.persistence = persistence
        self.runtimeStateCoalescer = RuntimeStateCoalescer(
            debounceNanoseconds: Self.defaultRuntimeStatePersistDebounceNanoseconds,
            persistBatch: { runtimeStates in
                await persistence.persistRuntimeStates(runtimeStates)
            }
        )
        faviconPresentationRefreshOwner.startObserving()
        if loadPersistedState {
            Task { @MainActor in
                loadFromStore()
            }
        }
    }

    deinit {
        // MEMORY LEAK FIX: Clean up all tab references and break potential cycles.
        // Scheduled persistence and startup restore tasks are cancelled by the
        // owning TabStructuralPersistenceOwner/TabStoreRestoreOwner deinits.
        MainActor.assumeIsolated {
            faviconPresentationRefreshOwner.stop()
            regularTabCollectionStateOwner.removeAll()
            splitGroupCollectionStateOwner.removeAll()
            folderCollectionStateOwner.removeAll()
            shortcutPinCollectionStateOwner.removeAll()
            transientTabRegistryOwner.removeAll()
            structuralLookupOwner.removeAll()
            spaceCollectionStateOwner.removeAll()
            currentTab = nil
            runtimeContext = nil
        }

        RuntimeDiagnostics.debug("Cleaned up all tab resources.", category: "TabManager")
    }

    // MARK: - Convenience

    var tabs: [Tab] {
        guard let s = currentSpace else { return [] }
        // `setTabs` keeps each space’s array sorted by index (and id tie-break); copy for callers that mutate.
        return regularTabCollectionOwner.tabs(in: s)
    }

    func setTabs(_ items: [Tab], for spaceId: UUID) {
        structuralCollectionMutationOwner.setTabs(items, for: spaceId)
    }

    func setFolders(_ items: [TabFolder], for spaceId: UUID) {
        structuralCollectionMutationOwner.setFolders(items, for: spaceId)
    }

    func setPinnedTabs(_ items: [ShortcutPin], for profileId: UUID) {
        structuralCollectionMutationOwner.setPinnedTabs(items, for: profileId)
    }

    func setSpacePinnedShortcuts(_ items: [ShortcutPin], for spaceId: UUID) {
        structuralCollectionMutationOwner.setSpacePinnedShortcuts(items, for: spaceId)
    }

    func notifyTransientShortcutStateChanged() {
        queueTransientTabLookupRefresh()
        requestStructuralPublish()
    }

    private var structuralLookupSnapshot: TabStructuralLookupSnapshot {
        TabStructuralLookupSnapshot(
            tabsBySpace: tabsBySpace,
            transientShortcutTabsByWindow: transientTabRegistryOwner.transientShortcutTabsByWindow,
            transientExtensionTabsByID: transientTabRegistryOwner.transientExtensionTabsByID,
            auxiliaryMiniWindowTabsByID: transientTabRegistryOwner.auxiliaryMiniWindowTabsByID
        )
    }

    func tab(for id: UUID) -> Tab? {
        structuralLookupOwner.tab(for: id, snapshot: structuralLookupSnapshot)
    }

    private func rebuildTabLookup() {
        structuralLookupOwner.rebuild(with: structuralLookupSnapshot)
    }

    func rebuildTabLookupForRestore() {
        rebuildTabLookup()
    }

    @discardableResult
    func withStructuralUpdateTransaction<T>(_ operation: () throws -> T) rethrows -> T {
        try structuralPublishOwner.withTransaction(
            flushPendingLookupBatch: { flushPendingStructuralLookupBatchIfNeeded() },
            operation
        )
    }

    func requestStructuralPublish() {
        structuralPublishOwner.requestPublish()
    }

    func queueTabLookupEntries(removing previousTabs: [Tab], with currentTabs: [Tab]) {
        structuralLookupOwner.queueEntries(
            removing: previousTabs,
            with: currentTabs,
            batching: structuralPublishOwner.isBatching
        )
    }

    private func queueTransientTabLookupRefresh() {
        structuralLookupOwner.queueTransientRefresh(
            snapshot: structuralLookupSnapshot,
            batching: structuralPublishOwner.isBatching
        )
    }

    private func flushPendingStructuralLookupBatchIfNeeded() {
        structuralLookupOwner.flushBatchIfNeeded(snapshot: structuralLookupSnapshot)
    }
    func attach(_ tab: Tab) {
        tabCollectionMembershipOwner.attach(tab)
    }

    func detach(_ tab: Tab) {
        tabCollectionMembershipOwner.detach(tab)
    }

    // Public accessor for managers that need to iterate tabs (e.g., privacy, rules updates)
    func allTabs() -> [Tab] {
        tabCollectionMembershipOwner.allTabs()
    }

    /// Profile-filtered union of pinned, space-pinned and regular tabs.
    func allTabsForCurrentProfile() -> [Tab] {
        tabCollectionMembershipOwner.allTabsForCurrentProfile()
    }

    func contains(_ tab: Tab) -> Bool {
        tabCollectionMembershipOwner.contains(tab)
    }

    func prepareTabForRuntime(_ tab: Tab) {
        runtimeContext?.webViewLifecycle.prepareTab(tab)
        if tab.sumiSettings == nil {
            tab.sumiSettings = sumiSettings ?? runtimeContext?.settings
        }
    }

    // MARK: - Shortcut Presentation and Projection

    func shortcutHasDrifted(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Bool {
        shortcutPresentationOwner.shortcutHasDrifted(pin, in: windowState)
    }

    func shortcutRuntimeAffordanceState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> SumiLauncherRuntimeAffordanceState {
        shortcutPresentationOwner.shortcutRuntimeAffordanceState(for: pin, in: windowState)
    }

    func essentialRuntimeState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState,
        splitManager: SplitViewManager?
    ) -> SumiEssentialRuntimeState? {
        shortcutPresentationOwner.essentialRuntimeState(
            for: pin,
            in: windowState,
            splitManager: splitManager
        )
    }

    func selectedShortcutLiveTab(for pinId: UUID, in windowState: BrowserWindowState) -> Tab? {
        shortcutPresentationOwner.selectedShortcutLiveTab(for: pinId, in: windowState)
    }

    func dragProxyTab(for pin: ShortcutPin) -> Tab {
        shortcutPresentationOwner.dragProxyTab(for: pin)
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        shortcutPresentationOwner.activeShortcutTab(for: windowId)
    }

    func liveShortcutTabs(in windowId: UUID) -> [Tab] {
        shortcutPresentationOwner.liveShortcutTabs(in: windowId)
    }

    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab? {
        shortcutPresentationOwner.shortcutLiveTab(for: pinId, in: windowId)
    }

    func shortcutPresentationState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> ShortcutPresentationState {
        shortcutPresentationOwner.shortcutPresentationState(for: pin, in: windowState)
    }

    func activeShortcutTabs(role: ShortcutPinRole? = nil) -> [Tab] {
        shortcutPresentationOwner.activeShortcutTabs(role: role)
    }

    func activeEssentialTabs(for profileId: UUID?) -> [Tab] {
        shortcutPresentationOwner.activeEssentialTabs(for: profileId)
    }

    func launcherProjection(
        for spaceId: UUID,
        in windowId: UUID? = nil
    ) -> SpaceLauncherProjection {
        spaceLauncherProjectionOwner.projection(for: spaceId, in: windowId)
    }

    func convertTabToShortcutLiveInstance(
        _ tab: Tab,
        pin: ShortcutPin,
        in windowId: UUID,
        updateSelection: Bool = true
    ) {
        shortcutLiveTabOwner.convertTabToShortcutLiveInstance(
            tab,
            pin: pin,
            in: windowId,
            updateSelection: updateSelection
        )
    }

    @discardableResult
    func convertDisplayedTabToShortcutLiveInstances(
        _ tab: Tab,
        pin: ShortcutPin,
        preferredWindowId: UUID? = nil
    ) -> Bool {
        shortcutLiveTabOwner.convertDisplayedTabToShortcutLiveInstances(
            tab,
            pin: pin,
            preferredWindowId: preferredWindowId
        )
    }

    @discardableResult
    func rebindLiveShortcutTab(
        _ tab: Tab,
        from sourcePin: ShortcutPin,
        to insertedPin: ShortcutPin
    ) -> Bool {
        shortcutLiveTabOwner.rebindLiveShortcutTab(tab, from: sourcePin, to: insertedPin)
    }

    func updateTransientShortcutBindings(for pin: ShortcutPin) {
        shortcutLiveTabOwner.updateTransientShortcutBindings(for: pin)
    }

    @discardableResult
    func activateShortcutPin(_ pin: ShortcutPin, in windowId: UUID, currentSpaceId: UUID?) -> Tab {
        withStructuralUpdateTransaction {
            shortcutLiveTabOwner.activateShortcutPin(pin, in: windowId, currentSpaceId: currentSpaceId)
        }
    }

    @discardableResult
    func deactivateShortcutLiveTab(in windowId: UUID) -> Bool {
        guard let pinId = activeShortcutTab(for: windowId)?.shortcutPinId else { return false }
        return deactivateShortcutLiveTab(pinId: pinId, in: windowId)
    }

    @discardableResult
    func deactivateShortcutLiveTab(pinId: UUID, in windowId: UUID) -> Bool {
        withStructuralUpdateTransaction {
            shortcutLiveTabOwner.deactivateShortcutLiveTab(pinId: pinId, in: windowId)
        }
    }

    @discardableResult
    func removeLiveShortcutTabs(forDeletedPinId pinId: UUID) -> ShortcutPinSelectionCleanupResult {
        shortcutLiveTabOwner.removeLiveShortcutTabs(forDeletedPinId: pinId)
    }

    @discardableResult
    func clearDeletedShortcutPinSelectionReferences(_ pinId: UUID) -> ShortcutPinSelectionCleanupResult {
        shortcutLiveTabOwner.clearDeletedShortcutPinSelectionReferences(pinId)
    }

    func persistWindowSessionsForShortcutSelectionCleanup(_ cleanupResult: ShortcutPinSelectionCleanupResult) {
        shortcutLiveTabOwner.persistWindowSessionsForShortcutSelectionCleanup(cleanupResult)
    }

    func windowIdDisplaying(tabId: UUID, preferredWindowId: UUID? = nil) -> UUID? {
        shortcutLiveTabOwner.windowIdDisplaying(tabId: tabId, preferredWindowId: preferredWindowId)
    }

    func windowIdsSelecting(tabId: UUID, preferredWindowId: UUID? = nil) -> [UUID] {
        shortcutLiveTabOwner.windowIdsSelecting(tabId: tabId, preferredWindowId: preferredWindowId)
    }

    func windowIdsDisplaying(tabId: UUID, preferredWindowId: UUID? = nil) -> [UUID] {
        shortcutLiveTabOwner.windowIdsDisplaying(tabId: tabId, preferredWindowId: preferredWindowId)
    }

    func windowStateDisplaying(tabId: UUID) -> BrowserWindowState? {
        shortcutLiveTabOwner.windowStateDisplaying(tabId: tabId)
    }

    func removeFromCurrentContainer(_ tab: Tab) {
        shortcutLiveTabOwner.removeFromCurrentContainer(tab)
    }

    @discardableResult
    func insertRegularTabFromShortcut(
        _ pin: ShortcutPin,
        into targetSpaceId: UUID,
        at targetIndex: Int? = nil
    ) -> Tab {
        shortcutLiveTabOwner.insertRegularTabFromShortcut(pin, into: targetSpaceId, at: targetIndex)
    }

    // MARK: - Container Membership Helpers
    /// True if the tab is globally pinned (Essentials) in any profile.
    func isGlobalPinned(_ tab: Tab) -> Bool {
        allPinnedTabsAllProfiles.contains { $0.id == tab.id }
    }

    /// True if the tab is pinned at the space level within its space.
    func isSpacePinned(_ tab: Tab) -> Bool {
        if tab.shortcutPinRole == .spacePinned {
            return true
        }
        guard let shortcutId = tab.shortcutPinId,
              let pin = shortcutPin(by: shortcutId) else { return false }
        return pin.role == .spacePinned
    }

    func regularChildInsertionIndex(openedFrom sourceTab: Tab?, in targetSpace: Space?) -> Int? {
        regularTabCollectionOwner.childInsertionIndex(openedFrom: sourceTab, in: targetSpace)
    }

    /// Create a new regular tab duplicating the source tab's URL/name and insert near an anchor tab.
    /// - Parameters:
    ///   - source: The tab to duplicate (pinned/space-pinned or regular).
    ///   - anchor: A regular tab used to decide target space and placement.
    ///   - placeAfterAnchor: If true, insert right after the anchor's index; otherwise at the anchor's index.
    /// - Returns: The newly created regular Tab.
    @discardableResult
    func duplicateAsRegularForSplit(from source: Tab, anchor: Tab, placeAfterAnchor: Bool = true) -> Tab {
        withStructuralUpdateTransaction {
            let targetSpace = anchor.spaceId.flatMap { sid in
                spaceCollectionStateOwner.space(with: sid)
            } ?? ensureDefaultSpaceIfNeeded()

            // Build the duplicate with the same URL/name; favicon will refresh from URL.
            let newTab = Tab(
                url: source.url,
                name: source.name,
                favicon: "globe",
                spaceId: targetSpace.id,
                index: 0,
                faviconService: faviconService,
                faviconImageService: faviconImageService,
                visitedLinkStore: visitedLinkStore
            )

            let insertionIndex = regularTabCollectionOwner.firstIndex(of: anchor, in: targetSpace.id)
                .map { $0 + (placeAfterAnchor ? 1 : 0) }
            addTab(newTab, regularInsertionIndex: insertionIndex)

            return newTab
        }
    }

    // MARK: - Folder Management

    func createFolder(for spaceId: UUID, name: String = "New Folder") -> TabFolder {
        folderMutationOwner.createFolder(for: spaceId, name: name)
    }

    @discardableResult
    func createFolder(
        for spaceId: UUID,
        parentFolderId: UUID?,
        name: String = "New Folder"
    ) -> TabFolder? {
        folderMutationOwner.createFolder(for: spaceId, parentFolderId: parentFolderId, name: name)
    }

    func renameFolder(_ folderId: UUID, newName: String) {
        folderMutationOwner.renameFolder(folderId, newName: newName)
    }

    func updateFolderIcon(_ folderId: UUID, icon: String) {
        folderMutationOwner.updateFolderIcon(folderId, icon: icon)
    }

    func setFolder(_ folderId: UUID, open isOpen: Bool) {
        folderMutationOwner.setFolder(folderId, open: isOpen)
    }

    func toggleFolderOpenState(_ folderId: UUID) {
        folderMutationOwner.toggleFolderOpenState(folderId)
    }

    func deleteFolder(_ folderId: UUID) {
        folderMutationOwner.deleteFolder(folderId)
    }

    func ungroupFolder(_ folderId: UUID) {
        folderMutationOwner.ungroupFolder(folderId)
    }

    func folders(for spaceId: UUID) -> [TabFolder] {
        folderCollectionStateOwner.folders(for: spaceId)
    }

    func openFolderIfNeeded(_ folderId: UUID) {
        folderMutationOwner.openFolderIfNeeded(folderId)
    }

    func setAllFolders(open isOpen: Bool, in spaceId: UUID) {
        folderMutationOwner.setAllFolders(open: isOpen, in: spaceId)
    }

    func moveTabToFolder(tab: Tab, folderId: UUID) {
        folderMutationOwner.moveTabToFolder(tab: tab, folderId: folderId)
    }

    // MARK: - Tab Management (Normal within current space)

    func addTab(_ tab: Tab, regularInsertionIndex: Int? = nil) {
        regularTabLifecycleOwner.addTab(tab, regularInsertionIndex: regularInsertionIndex)
    }

    @discardableResult
    func adoptGlanceTab(
        _ tab: Tab,
        sourceTab: Tab?,
        in space: Space? = nil
    ) -> Tab {
        regularTabLifecycleOwner.adoptGlanceTab(tab, sourceTab: sourceTab, in: space)
    }

    func resolvedTargetSpace(preferred space: Space?, fallbackSpaceId: UUID? = nil) -> Space {
        space
            ?? fallbackSpaceId.flatMap { spaceId in
                spaceCollectionStateOwner.space(with: spaceId)
            }
            ?? ensureDefaultSpaceIfNeeded()
    }

    var defaultProfileIdForSpaceBootstrap: UUID? {
        runtimeContext?.currentProfileId ?? runtimeContext?.defaultProfileId
    }

    @discardableResult
    func backfillTargetSpaceProfileIfNeeded(
        _ targetSpace: Space,
        profileId: UUID?
    ) -> Bool {
        guard targetSpace.profileId == nil, let profileId else { return false }
        targetSpace.profileId = profileId
        markAllSpacesStructurallyDirty()
        return true
    }

    func isTransientExtensionTab(_ tab: Tab) -> Bool {
        transientWebKitTabLifecycleOwner.isTransientExtensionTab(tab)
    }

    @discardableResult
    func createTransientExtensionTab(
        url: String,
        in space: Space? = nil,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        transientWebKitTabLifecycleOwner.createTransientExtensionTab(
            url: url,
            in: space,
            webExtensionContextOverride: webExtensionContextOverride
        )
    }

    @discardableResult
    func createAuxiliaryMiniWindowTab(
        openerTab: Tab?,
        profileId: UUID? = nil,
        urlString: String? = nil,
        webExtensionContextOverride: WKWebExtensionContext? = nil
    ) -> Tab {
        transientWebKitTabLifecycleOwner.createAuxiliaryMiniWindowTab(
            openerTab: openerTab,
            profileId: profileId,
            urlString: urlString,
            webExtensionContextOverride: webExtensionContextOverride
        )
    }

    func removeAuxiliaryMiniWindowTab(_ tab: Tab) {
        transientWebKitTabLifecycleOwner.removeAuxiliaryMiniWindowTab(tab)
    }

    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool {
        transientWebKitTabLifecycleOwner.isAuxiliaryMiniWindowTab(tab)
    }

    @discardableResult
    func removeTransientExtensionTab(id: UUID) -> Bool {
        transientWebKitTabLifecycleOwner.removeTransientExtensionTab(id: id)
    }

    @discardableResult
    func closeAuxiliaryMiniWindowTabIfPresent(id: UUID) -> Bool {
        transientWebKitTabLifecycleOwner.closeAuxiliaryMiniWindowTabIfPresent(id: id)
    }

    @discardableResult
    func promoteTransientExtensionTab(
        _ tab: Tab,
        in space: Space? = nil,
        activate: Bool = false
    ) -> Bool {
        transientWebKitTabLifecycleOwner.promoteTransientExtensionTab(
            tab,
            in: space,
            activate: activate
        )
    }

    func removeTab(_ id: UUID) {
        tabRemovalOwner.removeTab(id)
    }

    func setActiveTab(_ tab: Tab) {
        activeSelectionOwner.setActiveTab(tab)
    }

    /// Update only the global tab state without triggering UI operations
    /// Used when BrowserManager.selectTab() has already handled all UI concerns
    func updateActiveTabState(_ tab: Tab) {
        activeSelectionOwner.updateActiveTabState(tab)
    }

    @discardableResult
    func createNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        webExtensionContextOverride: WKWebExtensionContext? = nil,
        regularInsertionIndex: Int? = nil
    ) -> Tab {
        regularTabLifecycleOwner.createNewTab(
            url: url,
            in: space,
            activate: activate,
            webViewConfigurationOverride: webViewConfigurationOverride,
            webExtensionContextOverride: webExtensionContextOverride,
            regularInsertionIndex: regularInsertionIndex
        )
    }

    // MARK: - Ephemeral Tab Creation (Incognito)

    /// Create a new ephemeral tab in an incognito window
    /// These tabs are NOT persisted and are stored in window state
    @discardableResult
    func createEphemeralTab(
        url: URL,
        in windowState: BrowserWindowState,
        profile: Profile
    ) -> Tab {
        let nextIndex = windowState.ephemeralTabs.map(\.index).max().map { $0 + 1 } ?? 0
        let newTab = Tab(
            url: url,
            name: url.host ?? "New Tab",
            favicon: "globe",
            spaceId: nil,
            index: nextIndex,
            faviconService: faviconService,
            faviconImageService: faviconImageService,
            visitedLinkStore: visitedLinkStore
        )
        newTab.profileId = profile.id
        prepareTabForRuntime(newTab)

        // Add to window's ephemeral tabs (NOT to persistent tabs)
        windowState.ephemeralTabs.append(newTab)
        windowState.currentTabId = newTab.id

        RuntimeDiagnostics.emit("🔒 [TabManager] Created ephemeral tab: \(newTab.id) in window: \(windowState.id)")

        return newTab
    }

    // Create a new tab with an existing WebView (used for Glance transfers)
    @discardableResult
    func createNewTabWithWebView(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        in space: Space? = nil,
        existingWebView: WKWebView? = nil
    ) -> Tab {
        regularTabLifecycleOwner.createNewTabWithWebView(
            url: url,
            in: space,
            existingWebView: existingWebView
        )
    }

    // Create a new blank tab intended to host a popup window. The returned tab's
    // WKWebView is returned to WebKit so it can load popup content. No initial
    // navigation is performed to preserve window.opener scripting semantics.
    @discardableResult
    func createPopupTab(
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        regularInsertionIndex: Int? = nil
    ) -> Tab {
        regularTabLifecycleOwner.createPopupTab(
            in: space,
            activate: activate,
            webViewConfigurationOverride: webViewConfigurationOverride,
            regularInsertionIndex: regularInsertionIndex
        )
    }

    // Ensure a deterministic default target space exists without inheriting process-global selection.
    private func ensureDefaultSpaceIfNeeded() -> Space {
        let profileId = defaultProfileIdForSpaceBootstrap
        if let profileId,
           let profileSpace = spaceCollectionStateOwner.first(where: { $0.profileId == profileId }) {
            return profileSpace
        }

        if let profileId,
           let unassignedSpace = spaceCollectionStateOwner.first(where: { $0.profileId == nil }) {
            objectWillChange.send()
            spaceCollectionStateOwner.assignProfile(spaceId: unassignedSpace.id, profileId: profileId)
            markAllSpacesStructurallyDirty()
            scheduleStructuralPersistence()
            return unassignedSpace
        }

        if profileId == nil,
           let firstSpace = spaceCollectionStateOwner.firstSpace {
            return firstSpace
        }

        let personal = Space(
            name: "Personal",
            icon: "🏠",
            workspaceTheme: .default,
            profileId: profileId
        )
        objectWillChange.send()
        spaceCollectionStateOwner.append(personal)
        markAllSpacesStructurallyDirty()
        setTabs([], for: personal.id)
        if spaceCollectionStateOwner.currentSpace == nil {
            spaceCollectionStateOwner.replaceCurrentSpace(personal)
        }
        scheduleStructuralPersistence()
        return personal
    }

    // MARK: - Launcher Pin Commands

    func pinTab(_ tab: Tab, context: EssentialsTargetContext? = nil) {
        shortcutPinCommandOwner.pinTab(tab, context: context)
    }

    @discardableResult
    func copyShortcutPinToEssentials(
        _ pin: ShortcutPin,
        title: String,
        context: EssentialsTargetContext? = nil
    ) -> ShortcutPin? {
        shortcutPinCommandOwner.copyShortcutPinToEssentials(pin, title: title, context: context)
    }

    func removeShortcutPin(_ pin: ShortcutPin) {
        shortcutPinCommandOwner.removeShortcutPin(pin)
    }

    @discardableResult
    func updateShortcutPin(
        _ pin: ShortcutPin,
        title: String? = nil,
        launchURL: URL? = nil,
        iconAsset: String?? = nil,
        executionProfileId: UUID?? = nil
    ) -> ShortcutPin? {
        shortcutPinCommandOwner.updateShortcutPin(
            pin,
            title: title,
            launchURL: launchURL,
            iconAsset: iconAsset,
            executionProfileId: executionProfileId
        )
    }

    @discardableResult
    func replaceShortcutPinURLWithCurrent(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> ShortcutPin? {
        shortcutPinCommandOwner.replaceShortcutPinURLWithCurrent(pin, in: windowState)
    }

    @discardableResult
    func resetShortcutPinToLaunchURL(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        preserveCurrentPage: Bool = false
    ) -> ShortcutPin? {
        shortcutPinCommandOwner.resetShortcutPinToLaunchURL(
            pin,
            in: windowState,
            preserveCurrentPage: preserveCurrentPage
        )
    }

    func removeFromEssentials(_ pin: ShortcutPin) {
        shortcutPinCommandOwner.removeShortcutPin(pin)
    }

    @discardableResult
    func reorderEssential(_ pin: ShortcutPin, to index: Int) -> Bool {
        shortcutPinCommandOwner.reorderEssential(pin, to: index)
    }

    @discardableResult
    func reorderSpacePinned(_ pin: ShortcutPin, in spaceId: UUID, to index: Int) -> Bool {
        shortcutPinCommandOwner.reorderSpacePinned(pin, in: spaceId, to: index)
    }

    func pinTabToSpace(_ tab: Tab, spaceId: UUID) {
        shortcutPinCommandOwner.pinTabToSpace(tab, spaceId: spaceId)
    }

    func folderSpaceId(for folderId: UUID) -> UUID? {
        folderCollectionStateOwner.spaceId(for: folderId)
    }

    // MARK: - Sidebar Drag Routing and Tab Moves

    @discardableResult
    func performSidebarDragOperation(_ operation: DragOperation) -> Bool {
        withStructuralUpdateTransaction {
            sidebarDragRoutingOwner.handleDragOperation(operation)
        }
    }

    @discardableResult
    func handleDragOperation(_ operation: DragOperation) -> Bool {
        sidebarDragRoutingOwner.handleDragOperation(operation)
    }

    func alphabetizeFolderPins(_ folderId: UUID, in spaceId: UUID) {
        folderMutationOwner.alphabetizeFolderPins(folderId, in: spaceId)
    }

    @discardableResult
    func reorderSpacePinnedTabs(_ tab: Tab, in spaceId: UUID, to index: Int) -> Bool {
        regularTabDragService.reorderSpacePinnedTabs(tab, in: spaceId, to: index)
    }

    @discardableResult
    func reorderRegularTabs(_ tab: Tab, in spaceId: UUID, to index: Int) -> Bool {
        regularTabDragService.reorderRegularTabs(tab, in: spaceId, to: index)
    }

    func moveTab(_ tabId: UUID, to targetSpaceId: UUID) {
        sidebarDragRoutingOwner.moveTab(tabId, to: targetSpaceId)
    }

    func moveTabUp(_ tabId: UUID) {
        withStructuralUpdateTransaction {
            guard regularTabCollectionOwner.moveUp(tabId) else { return }
            scheduleStructuralPersistence()
        }
    }

    func moveTabDown(_ tabId: UUID) {
        withStructuralUpdateTransaction {
            guard regularTabCollectionOwner.moveDown(tabId) else { return }
            scheduleStructuralPersistence()
        }
    }

    // MARK: - Profile Assignment and Cleanup

    func cleanupProfileReferences(_ deletedProfileId: UUID, fallbackProfileId: UUID) {
        profileAssignmentOwner.cleanupProfileReferences(
            deletedProfileId,
            fallbackProfileId: fallbackProfileId
        )
    }

    func handleProfileSwitch(contextWindowId: UUID? = nil) {
        profileAssignmentOwner.handleProfileSwitch(contextWindowId: contextWindowId)
    }

    func reconcileSpaceProfilesIfNeeded() {
        profileAssignmentOwner.reconcileSpaceProfilesIfNeeded()
    }

    func assign(spaceId: UUID, toProfile profileId: UUID) {
        profileAssignmentOwner.assign(spaceId: spaceId, toProfile: profileId)
    }

    @discardableResult
    func assign(tab: Tab, toProfile profileId: UUID) -> Bool {
        profileAssignmentOwner.assign(tab: tab, toProfile: profileId)
    }

    @discardableResult
    func assign(shortcutPin pin: ShortcutPin, toExecutionProfile profileId: UUID) -> ShortcutPin? {
        profileAssignmentOwner.assign(shortcutPin: pin, toExecutionProfile: profileId)
    }

    func assignProfile(_ profileId: UUID?, to tab: Tab) {
        profileAssignmentOwner.assignProfile(profileId, to: tab)
    }

    func profileExists(_ profileId: UUID) -> Bool {
        profileAssignmentOwner.profileExists(profileId)
    }

    // MARK: - Tab Closure Undo and Bulk Removal

    func tabs(in space: Space) -> [Tab] {
        regularTabCollectionOwner.tabs(in: space)
    }

    func captureRecentlyClosedTab(_ tab: Tab, spaceId: UUID?) {
        tabRemovalOwner.captureRecentlyClosedTab(tab, spaceId: spaceId)
    }

    func updateTabNavigationState(_ tab: Tab) {
        scheduleRuntimeStatePersistence(for: tab)
    }

    func closeAllTabsBelow(_ tab: Tab) {
        tabRemovalOwner.closeAllTabsBelow(tab)
    }

    // MARK: - Split Group Structure

    typealias SpacePinnedVisualItem = TabSplitGroupStructureOwner.SpacePinnedVisualItem

    func splitGroup(containing tabId: UUID) -> SplitGroup? {
        splitGroupStructureOwner.splitGroup(containing: tabId)
    }

    func splitGroup(with id: UUID) -> SplitGroup? {
        splitGroupCollectionStateOwner.group(with: id)
    }

    func splitGroupIds(containing tabId: UUID) -> [UUID] {
        splitGroupStructureOwner.splitGroupIds(containing: tabId)
    }

    func splitGroup(containingPinId pinId: UUID) -> SplitGroup? {
        splitGroupStructureOwner.splitGroup(containingPinId: pinId)
    }

    func splitGroupVisualOrderingResolver(for spaceId: UUID) -> SplitGroupVisualOrderingResolver {
        splitGroupStructureOwner.visualOrderingResolver(for: spaceId)
    }

    func shortcutHostedSplitGroups(for spaceId: UUID) -> [SplitGroup] {
        splitGroupStructureOwner.visualOrderingResolver(for: spaceId).shortcutHostedGroups()
    }

    func shortcutHostedSplitGroup(containingPinId pinId: UUID, in spaceId: UUID? = nil) -> SplitGroup? {
        splitGroupStructureOwner.shortcutHostedSplitGroup(containingPinId: pinId, in: spaceId)
    }

    func regularHostedSplitGroup(containingPinId pinId: UUID) -> SplitGroup? {
        splitGroupStructureOwner.regularHostedSplitGroup(containingPinId: pinId)
    }

    func regularHostedSplitPlaceholderGroup(for pin: ShortcutPin) -> SplitGroup? {
        splitGroupStructureOwner.regularHostedSplitGroup(containingPinId: pin.id)
    }

    func shortcutHostedSplitGroupVisualIndex(_ group: SplitGroup, in spaceId: UUID) -> Int {
        splitGroupStructureOwner.visualOrderingResolver(for: spaceId).visualIndex(for: group)
    }

    func shortcutHostedSplitGroupFolderId(_ group: SplitGroup, in spaceId: UUID) -> UUID? {
        splitGroupStructureOwner.visualOrderingResolver(for: spaceId).folderId(for: group)
    }

    func shortcutHostedSplitGroups(for spaceId: UUID, inFolder folderId: UUID?) -> [SplitGroup] {
        splitGroupStructureOwner.visualOrderingResolver(for: spaceId).shortcutHostedGroups(inFolder: folderId)
    }

    func shortcutHostedSplitHiddenPinIds(for spaceId: UUID) -> Set<UUID> {
        splitGroupStructureOwner.visualOrderingResolver(for: spaceId).hiddenPinIds()
    }

    func topLevelSpacePinnedVisualItems(for spaceId: UUID) -> [SpacePinnedVisualItem] {
        splitGroupStructureOwner.topLevelSpacePinnedVisualItems(for: spaceId)
    }

    @discardableResult
    func moveShortcutHostedSplitGroup(_ group: SplitGroup, in spaceId: UUID, to index: Int) -> Bool {
        splitGroupStructureOwner.moveShortcutHostedSplitGroup(group, in: spaceId, to: index)
    }

    func visibleSplitTabIds(containing tabId: UUID?) -> [UUID] {
        splitGroupStructureOwner.visibleSplitTabIds(containing: tabId)
    }

    func upsertSplitGroup(_ group: SplitGroup, schedulePersistence shouldPersist: Bool = true) {
        splitGroupStructureOwner.upsertSplitGroup(group, schedulePersistence: shouldPersist)
    }

    func removeSplitGroup(id: UUID, schedulePersistence shouldPersist: Bool = true) {
        splitGroupStructureOwner.removeSplitGroup(id: id, schedulePersistence: shouldPersist)
    }

    func removeSplitGroups(containing tabId: UUID, schedulePersistence shouldPersist: Bool = true) {
        splitGroupStructureOwner.removeSplitGroups(containing: tabId, schedulePersistence: shouldPersist)
    }

    func replaceSplitGroups(_ groups: [SplitGroup], schedulePersistence shouldPersist: Bool = true) {
        splitGroupStructureOwner.replaceSplitGroups(groups, schedulePersistence: shouldPersist)
    }

    func sanitizedRepairedSplitGroups(_ groups: [SplitGroup]) -> [SplitGroup] {
        splitGroupStructureOwner.sanitizedRepairedSplitGroups(groups)
    }

    static func sanitizedSplitGroups(_ groups: [SplitGroup]) -> [SplitGroup] {
        SplitGroup.sanitized(groups)
    }

    func markSplitGroupsStructurallyDirty(schedulePersistence shouldPersist: Bool = true) {
        splitGroupStructureOwner.markSplitGroupsStructurallyDirty(schedulePersistence: shouldPersist)
    }

    // MARK: - Space Lifecycle

    func userVisibleTabCount(for spaceId: UUID) -> Int {
        launcherProjection(for: spaceId).userVisibleTabCount
    }

    @discardableResult
    func createSpace(
        name: String,
        icon: String = "square.grid.2x2",
        workspaceTheme: WorkspaceTheme? = nil,
        profileId: UUID? = nil
    ) -> Space {
        spaceLifecycleOwner.createSpace(
            name: name,
            icon: icon,
            workspaceTheme: workspaceTheme,
            profileId: profileId
        )
    }

    func removeSpace(_ id: UUID) {
        spaceLifecycleOwner.removeSpace(id)
    }

    @discardableResult
    func reorderSpace(spaceId: UUID, to targetIndex: Int) -> Bool {
        spaceLifecycleOwner.reorderSpace(spaceId: spaceId, to: targetIndex)
    }

    func setActiveSpace(
        _ space: Space,
        preferredTab: Tab? = nil,
        contextWindowId: UUID? = nil
    ) {
        spaceLifecycleOwner.setActiveSpace(
            space,
            preferredTab: preferredTab,
            contextWindowId: contextWindowId
        )
    }

    func renameSpace(spaceId: UUID, newName: String) throws {
        try spaceLifecycleOwner.renameSpace(spaceId: spaceId, newName: newName)
    }

    func updateSpaceIcon(spaceId: UUID, icon: String) throws {
        try spaceLifecycleOwner.updateSpaceIcon(spaceId: spaceId, icon: icon)
    }

    func clearRegularTabs(for spaceId: UUID) {
        withStructuralUpdateTransaction {
            let tabs = regularTabCollectionOwner.tabs(in: spaceId)
            guard !tabs.isEmpty else { return }

            RuntimeDiagnostics.emit("🧹 [TabManager] Clearing \(tabs.count) regular tabs for space \(spaceId)")

            let inactiveRegular = tabs.filter { $0.id != currentTab?.id }
            if !inactiveRegular.isEmpty {
                for tab in inactiveRegular {
                    removeTab(tab.id)
                }
                return
            }
            if let active = currentTab,
               active.spaceId == spaceId,
               tabs.contains(where: { $0.id == active.id }) {
                removeTab(active.id)
            }
        }
    }

    static let defaultRuntimeStatePersistDebounceNanoseconds: UInt64 = 250_000_000

    // MARK: - Structural Persistence and Store Restore Composition

    lazy var structuralPersistence = TabStructuralPersistenceOwner(
        persistence: persistence,
        runtimeStateCoalescer: runtimeStateCoalescer,
        dependencies: .live(tabManager: self)
    )
    lazy var storeRestore = TabStoreRestoreOwner(dependencies: .live(tabManager: self))

    var structuralDirtySet: TabStructuralDirtySet {
        structuralPersistence.dirtySet
    }

    var scheduledStructuralPersistTask: Task<Void, Never>? {
        structuralPersistence.scheduledPersistTask
    }

    public nonisolated func scheduleStructuralPersistence() {
        Task { @MainActor [weak self] in
            self?.structuralPersistence.scheduleStructuralPersistenceFromMain()
        }
    }

    /// Explicit full reconcile path for restore, repair, fallback, and termination only.
    public nonisolated func persistFullReconcileAwaitingResult(
        reason: String = "explicit full reconcile"
    ) async -> Bool {
        let owner = await MainActor.run { [weak self] in self?.structuralPersistence }
        guard let owner else { return false }
        return await owner.persistFullReconcileAwaitingResult(reason: reason)
    }

    @discardableResult
    public nonisolated func flushRuntimeStatePersistenceAwaitingResult() async -> Int {
        await runtimeStateCoalescer.flushImmediately()
    }

    func persistSelection() {
        structuralPersistence.persistSelection()
    }

    func scheduleRuntimeStatePersistence(for tab: Tab) {
        structuralPersistence.scheduleRuntimeStatePersistence(for: tab)
    }

    func cancelRuntimeStatePersistence(for tabId: UUID) {
        structuralPersistence.cancelRuntimeStatePersistence(for: tabId)
    }

    func shouldPersistRegularTab(_ tab: Tab) -> Bool {
        structuralPersistence.shouldPersistRegularTab(tab)
    }

    func persistableCurrentTabID() -> UUID? {
        structuralPersistence.persistableCurrentTabID()
    }

    func _buildSnapshot() -> TabSnapshotRepository.Snapshot {
        structuralPersistence.buildSnapshot()
    }

    func markSnapshotCacheDirty() {
        structuralPersistence.markSnapshotCacheDirty()
    }

    func markSpacesSnapshotDirty() {
        structuralPersistence.markSpacesSnapshotDirty()
    }

    func markAllSpacesStructurallyDirty() {
        structuralPersistence.markAllSpacesStructurallyDirty()
    }

    func markSpaceStructurallyDeleted(_ spaceId: UUID) {
        structuralPersistence.markSpaceStructurallyDeleted(spaceId)
    }

    func markPinnedSnapshotDirty(for profileId: UUID) {
        structuralPersistence.markPinnedSnapshotDirty(for: profileId)
    }

    func markSpacePinnedSnapshotDirty(for spaceId: UUID) {
        structuralPersistence.markSpacePinnedSnapshotDirty(for: spaceId)
    }

    func markRegularTabsSnapshotDirty(for spaceId: UUID) {
        structuralPersistence.markRegularTabsSnapshotDirty(for: spaceId)
    }

    func markRegularTabsStructurallyDirty(for spaceId: UUID) {
        structuralPersistence.markRegularTabsStructurallyDirty(for: spaceId)
    }

    func markFoldersSnapshotDirty(for spaceId: UUID) {
        structuralPersistence.markFoldersSnapshotDirty(for: spaceId)
    }

    func markFoldersStructurallyDirty(for spaceId: UUID) {
        structuralPersistence.markFoldersStructurallyDirty(for: spaceId)
    }

    func resetStructuralDirtySet() {
        structuralPersistence.resetDirtySet()
    }

    func recordRegularTabsStructuralChange(previous: [Tab], current: [Tab]) {
        structuralPersistence.recordRegularTabsStructuralChange(previous: previous, current: current)
    }

    func recordFoldersStructuralChange(previous: [TabFolder], current: [TabFolder]) {
        structuralPersistence.recordFoldersStructuralChange(previous: previous, current: current)
    }

    func recordShortcutPinsStructuralChange(previous: [ShortcutPin], current: [ShortcutPin]) {
        structuralPersistence.recordShortcutPinsStructuralChange(previous: previous, current: current)
    }

    func loadFromStore() {
        storeRestore.loadFromStore()
    }

    func resetRegularTabsAndShortcutLiveInstancesForStartup() {
        lastSessionRestoreOwner.resetRegularTabsAndShortcutLiveInstancesForStartup()
    }

    func mergeSnapshotForLastSessionRestore(_ snapshot: TabSnapshotRepository.Snapshot) {
        lastSessionRestoreOwner.mergeSnapshotForLastSessionRestore(snapshot)
    }

    @discardableResult
    func loadFromStoreAwaitingResult() async -> Bool {
        await storeRestore.loadFromStoreAwaitingResult()
    }

    func installRestoredCollections(_ restoredState: TabRestoreRuntimeState) {
        spaces = restoredState.spaces
        tabsBySpace = restoredState.tabsBySpace
        foldersBySpace = restoredState.foldersBySpace
        objectWillChange.send()
        shortcutPinCollectionStateOwner.replaceAll(
            pinnedByProfile: restoredState.pinnedByProfile,
            spacePinnedShortcuts: restoredState.spacePinnedShortcuts,
            pendingPinnedWithoutProfile: restoredState.pendingPinnedWithoutProfile
        )
    }

    func hasLiveRuntimeContent(in space: Space) -> Bool {
        let spaceId = space.id

        if regularTabCollectionStateOwner.hasTabs(in: spaceId) { return true }
        if shortcutPinCollectionStateOwner.hasSpacePinnedShortcuts(in: spaceId) { return true }
        if folderCollectionStateOwner.hasFolders(in: spaceId) { return true }

        return transientTabRegistryOwner.transientShortcutTabs
            .contains { $0.spaceId == spaceId }
    }

    func reconcileProfileRuntimeStates(activeSpaceId: UUID?) {
        for space in spaces {
            let hasRuntimeContent = hasLiveRuntimeContent(in: space)

            if space.id == activeSpaceId {
                space.profileRuntimeState = hasRuntimeContent ? .active : .dormant
            } else {
                space.profileRuntimeState = hasRuntimeContent ? .loadedInactive : .dormant
            }
        }
    }
}

extension TabManager {
    func requireRuntimeContext() -> TabManagerRuntimeContext {
        guard let runtimeContext else {
            preconditionFailure(
                "TabManager.runtimeContext is nil. BrowserManagerRuntimeWiring.attach(to:) must run before destructive tab operations."
            )
        }
        return runtimeContext
    }

    func attachRuntimeContext(_ context: TabManagerRuntimeContext) {
        runtimeContext = context

        let knownTabs = allTabs()
        for tab in knownTabs {
            prepareTabForRuntime(tab)
        }

        // Assign any pinned tabs that were loaded without a profile once currentProfile is known
        if let currentProfileId = runtimeContext?.currentProfileId,
           !pendingPinnedWithoutProfile.isEmpty {
            withPinnedArray(for: currentProfileId) { arr in
                arr.append(contentsOf: pendingPinnedWithoutProfile)
            }
            pendingPinnedWithoutProfile.removeAll()
            scheduleStructuralPersistence()
        }
        if let current = self.currentTab {
            if let match = knownTabs.first(where: { $0.id == current.id }) {
                self.currentTab = match
            }
        }
        // After attaching runtime, ensure gradient matches the restored current space.
        if let space = self.currentSpace {
            runtimeContext?.syncWorkspaceThemeAcrossWindows(for: space, animate: false)
        }

        // After attaching runtime, backfill any missing space.profileId.
        reconcileSpaceProfilesIfNeeded()
    }
}
