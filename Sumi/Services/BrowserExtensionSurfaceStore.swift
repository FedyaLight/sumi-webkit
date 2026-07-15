//
//  BrowserExtensionSurfaceStore.swift
//  Sumi
//
//  Thin observable projection of installed extension metadata plus any
//  already-published WebExtension action state.
//

import AppKit
import Combine
import Foundation

struct BrowserExtensionActionSurfaceState {
    var extensionID: String
    var label: String
    var badgeText: String
    var hasUnreadBadgeText: Bool
    var isEnabled: Bool
    var presentsPopup: Bool
    var icon: NSImage?
}

struct BrowserExtensionActionButtonSnapshot: Equatable {
    let label: String?
    let badgeText: String?
    let hasUnreadBadgeText: Bool
    let isEnabled: Bool?
    let icon: NSImage?

    static let unavailable = Self(
        label: nil,
        badgeText: nil,
        hasUnreadBadgeText: false,
        isEnabled: false,
        icon: nil
    )

    init(
        label: String?,
        badgeText: String?,
        hasUnreadBadgeText: Bool,
        isEnabled: Bool?,
        icon: NSImage?
    ) {
        self.label = label
        self.badgeText = badgeText
        self.hasUnreadBadgeText = hasUnreadBadgeText
        self.isEnabled = isEnabled
        self.icon = icon
    }

    init(_ state: BrowserExtensionActionSurfaceState?) {
        label = state?.label
        badgeText = state?.badgeText
        hasUnreadBadgeText = state?.hasUnreadBadgeText == true
        isEnabled = state?.isEnabled
        icon = state?.icon
    }

    static func == (
        lhs: BrowserExtensionActionButtonSnapshot,
        rhs: BrowserExtensionActionButtonSnapshot
    ) -> Bool {
        lhs.label == rhs.label
            && lhs.badgeText == rhs.badgeText
            && lhs.hasUnreadBadgeText == rhs.hasUnreadBadgeText
            && lhs.isEnabled == rhs.isEnabled
            && lhs.icon === rhs.icon
    }
}

@MainActor
final class BrowserExtensionActionButtonModel: ObservableObject {
    typealias Query = @MainActor (
        ExtensionActionPresentationTarget
    ) -> BrowserExtensionActionButtonSnapshot?

    @Published private(set) var snapshot: BrowserExtensionActionButtonSnapshot
    private let query: Query
    private var target: ExtensionActionPresentationTarget?
    private var generation: UInt64 = 0
    private var cancellable: AnyCancellable?

    init(
        changes: AnyPublisher<ExtensionActionPresentationChange, Never>,
        query: @escaping Query
    ) {
        snapshot = .unavailable
        self.query = query
        cancellable = changes
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self, let target = self.target,
                      change.affects(target)
                else { return }
                publishCurrent(target, generation: generation)
            }
    }

    func setTarget(_ target: ExtensionActionPresentationTarget?) {
        generation &+= 1
        self.target = target
        guard let target else {
            publish(.unavailable)
            return
        }
        publishCurrent(target, generation: generation)
    }

    func snapshot(
        for currentTarget: ExtensionActionPresentationTarget?
    ) -> BrowserExtensionActionButtonSnapshot {
        guard target == currentTarget else { return .unavailable }
        return snapshot
    }

    private func publishCurrent(
        _ target: ExtensionActionPresentationTarget,
        generation: UInt64
    ) {
        let next = query(target) ?? .unavailable
        guard self.generation == generation, self.target == target else {
            return
        }
        publish(next)
    }

    private func publish(_ next: BrowserExtensionActionButtonSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

enum BrowserExtensionToolbarLayoutScope: Equatable {
    case allProfiles
    case profile(UUID?)

    func affects(profileID: UUID?) -> Bool {
        switch self {
        case .allProfiles:
            true
        case .profile(let changedProfileID):
            changedProfileID == profileID
        }
    }
}

/// Installed-record fields consumed by toolbar/sidebar action presentation.
/// Package/runtime metadata is intentionally absent so idempotent catalog
/// refreshes do not invalidate a mounted toolbar.
struct BrowserExtensionToolbarDisplayRecord: Equatable, Identifiable {
    let id: String
    let name: String
    let isEnabled: Bool
    let hasAction: Bool
    let hasOptionsPage: Bool
    let iconPath: String?

    init(_ record: InstalledExtension) {
        id = record.id
        name = record.name
        isEnabled = record.isEnabled
        hasAction = record.hasAction
        hasOptionsPage = record.hasOptionsPage
        iconPath = record.iconPath
    }
}

struct BrowserExtensionToolbarDisplaySnapshot: Equatable {
    let extensions: [BrowserExtensionToolbarDisplayRecord]

    static let empty = Self(extensions: [])

    init(extensions: [BrowserExtensionToolbarDisplayRecord]) {
        self.extensions = extensions
    }

    init(_ records: [InstalledExtension]) {
        extensions = records.map(BrowserExtensionToolbarDisplayRecord.init)
    }

    var enabledExtensions: [BrowserExtensionToolbarDisplayRecord] {
        extensions.filter(\.isEnabled)
    }
}

struct BrowserExtensionToolbarPresentationSnapshot: Equatable {
    let display: BrowserExtensionToolbarDisplaySnapshot
    let pinnedExtensionIDs: [String]
    let unpinnedExtensionIDs: [String]

    static let empty = Self(
        display: .empty,
        pinnedExtensionIDs: [],
        unpinnedExtensionIDs: []
    )

    init(
        display: BrowserExtensionToolbarDisplaySnapshot,
        pinnedExtensionIDs: [String],
        unpinnedExtensionIDs: [String]
    ) {
        self.display = display
        self.pinnedExtensionIDs = pinnedExtensionIDs
        self.unpinnedExtensionIDs = unpinnedExtensionIDs
    }

    var extensions: [BrowserExtensionToolbarDisplayRecord] {
        display.extensions
    }

    var enabledExtensions: [BrowserExtensionToolbarDisplayRecord] {
        display.enabledExtensions
    }

    var unpinnedEnabledActionExtensions:
        [BrowserExtensionToolbarDisplayRecord] {
        let pinnedIDs = Set(pinnedExtensionIDs)
        let candidates = enabledExtensions
            .filter(\.hasAction)
            .filter { pinnedIDs.contains($0.id) == false }
        let candidatesByID = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.id, $0) }
        )
        let ordered = unpinnedExtensionIDs.compactMap { candidatesByID[$0] }
        let orderedIDs = Set(ordered.map(\.id))
        return ordered + candidates.filter { orderedIDs.contains($0.id) == false }
    }
}

@MainActor
final class URLBarExtensionDisplayModel: ObservableObject {
    typealias Current = @MainActor (
        UUID?
    ) -> BrowserExtensionToolbarPresentationSnapshot
    typealias Changes = @MainActor (
        UUID?
    ) -> AnyPublisher<BrowserExtensionToolbarPresentationSnapshot, Never>

    @Published private(set) var snapshot: BrowserExtensionToolbarPresentationSnapshot = .empty
    private let moduleEnabledChanges: AnyPublisher<Bool, Never>
    private let current: Current
    private let changes: Changes
    private var isDemanded = false
    private var profileID: UUID?
    private var moduleEnabled = false
    private var moduleCancellable: AnyCancellable?
    private var surfaceCancellable: AnyCancellable?

    init(
        moduleEnabledChanges: AnyPublisher<Bool, Never>,
        current: @escaping Current,
        changes: @escaping Changes
    ) {
        self.moduleEnabledChanges = moduleEnabledChanges
        self.current = current
        self.changes = changes
    }

    func setDemanded(_ isDemanded: Bool, profileID: UUID?) {
        guard isDemanded else {
            self.isDemanded = false
            self.profileID = profileID
            moduleCancellable?.cancel()
            moduleCancellable = nil
            surfaceCancellable?.cancel()
            surfaceCancellable = nil
            publish(.empty)
            return
        }

        let profileChanged = self.profileID != profileID
        self.isDemanded = true
        self.profileID = profileID
        if moduleCancellable == nil {
            moduleCancellable = moduleEnabledChanges.sink { [weak self] enabled in
                self?.setModuleEnabled(enabled)
            }
        } else if profileChanged {
            installSurfaceSubscriptionIfNeeded()
        }
    }

    private func setModuleEnabled(_ isEnabled: Bool) {
        guard moduleEnabled != isEnabled else {
            if isEnabled { installSurfaceSubscriptionIfNeeded() }
            return
        }
        moduleEnabled = isEnabled
        installSurfaceSubscriptionIfNeeded()
    }

    private func installSurfaceSubscriptionIfNeeded() {
        surfaceCancellable?.cancel()
        surfaceCancellable = nil
        guard isDemanded, moduleEnabled else {
            publish(.empty)
            return
        }

        let profileID = profileID
        // Subscribe before the demand-time read. Exact display/layout changes
        // are scheduled onto the main run loop, so the fresh read installs
        // first and any queued mutation wins afterward.
        surfaceCancellable = changes(profileID)
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.publish(snapshot)
            }
        publish(current(profileID))
    }

    private func publish(
        _ next: BrowserExtensionToolbarPresentationSnapshot
    ) {
        guard snapshot != next else { return }
        snapshot = next
    }

    isolated deinit {
        moduleCancellable?.cancel()
        surfaceCancellable?.cancel()
    }
}

@MainActor
final class BrowserExtensionSurfaceStore: ObservableObject {
    typealias UpdateScheduler = @MainActor (
        _ operation: @escaping @MainActor () -> Void
    ) -> Void

    @Published private(set) var installedExtensions: [InstalledExtension] = []
    @Published private(set) var actionStatesByExtensionID:
        [String: BrowserExtensionActionSurfaceState] = [:]
    @Published private(set) var siteAccessPoliciesByExtensionID:
        [String: SafariExtensionSiteAccessPolicy] = [:]

    let iconCache = ExtensionIconCache()
    private let toolbarLayoutChanged = PassthroughSubject<
        BrowserExtensionToolbarLayoutScope,
        Never
    >()
    private let actionPresentationChanged = PassthroughSubject<
        ExtensionActionPresentationChange,
        Never
    >()
    private var cancellables: Set<AnyCancellable> = []
    private var binding: BrowserExtensionSurfaceBinding?
    private var activeSiteAccessProfileId: UUID?
    private var scheduledInstalledExtensionsGeneration = 0
    private var toolbarRecordProjection: [BrowserExtensionToolbarDisplayRecord] = []
    private var scheduledActionStatesGeneration = 0
    private var scheduledSiteAccessPoliciesGeneration = 0
    private let updateScheduler: UpdateScheduler

    init(
        binding: BrowserExtensionSurfaceBinding? = nil,
        updateScheduler: @escaping UpdateScheduler = { operation in
            Task { @MainActor in
                await Task.yield()
                operation()
            }
        }
    ) {
        self.updateScheduler = updateScheduler
        if let binding {
            activate(binding)
        }
    }

    var enabledExtensions: [InstalledExtension] {
        installedExtensions.filter(\.isEnabled)
    }

    var toolbarDisplaySnapshot: BrowserExtensionToolbarDisplaySnapshot {
        BrowserExtensionToolbarDisplaySnapshot(installedExtensions)
    }

    var toolbarDisplaySnapshots: AnyPublisher<
        BrowserExtensionToolbarDisplaySnapshot,
        Never
    > {
        $installedExtensions
            .map(BrowserExtensionToolbarDisplaySnapshot.init)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func toolbarLayoutChanges(
        for profileID: UUID?
    ) -> AnyPublisher<Void, Never> {
        toolbarLayoutChanged
            .filter { $0.affects(profileID: profileID) }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func publishToolbarLayoutChanged(for profileID: UUID?) {
        toolbarLayoutChanged.send(.profile(profileID))
    }

    var actionPresentationChanges: AnyPublisher<
        ExtensionActionPresentationChange,
        Never
    > {
        actionPresentationChanged.eraseToAnyPublisher()
    }

    @discardableResult
    func activate(_ binding: BrowserExtensionSurfaceBinding) -> Bool {
        guard self.binding !== binding else { return false }

        cancellables.removeAll()
        self.binding = binding

        binding.installedExtensionsPublisher
            .sink { [weak self] installedExtensions in
                self?.scheduleInstalledExtensionsUpdate(installedExtensions)
                self?.refreshSiteAccessPoliciesForCurrentProfile(
                    extensionIds: installedExtensions.map(\.id)
                )
            }
            .store(in: &cancellables)

        binding.actionStatesPublisher
            .sink { [weak self] actionStates in
                self?.scheduleActionStatesUpdate(actionStates)
            }
            .store(in: &cancellables)

        binding.actionPresentationChangePublisher
            .sink { [weak self] change in
                self?.actionPresentationChanged.send(change)
            }
            .store(in: &cancellables)

        binding.siteAccessPolicyChangePublisher
        .sink { [weak self] _ in
            self?.refreshSiteAccessPoliciesForCurrentProfile()
        }
        .store(in: &cancellables)

        return true
    }

    func deactivate() {
        guard binding != nil else { return }

        cancellables.removeAll()
        binding = nil
        activeSiteAccessProfileId = nil
        scheduleInstalledExtensionsUpdate([])
        scheduleActionStatesUpdate([:])
        scheduleSiteAccessPoliciesUpdate([:])
    }

    func refreshSiteAccessPolicies(profileId: UUID?) {
        activeSiteAccessProfileId = profileId
        refreshSiteAccessPoliciesForCurrentProfile()
    }

    private func scheduleInstalledExtensionsUpdate(
        _ installedExtensions: [InstalledExtension]
    ) {
        scheduledInstalledExtensionsGeneration &+= 1
        let generation = scheduledInstalledExtensionsGeneration
        updateScheduler { [weak self] in
            guard self?.scheduledInstalledExtensionsGeneration == generation else {
                return
            }
            guard let self else { return }
            let nextToolbarProjection = installedExtensions.map(
                BrowserExtensionToolbarDisplayRecord.init
            )
            let toolbarLayoutDidChange = nextToolbarProjection != toolbarRecordProjection
            self.installedExtensions = installedExtensions
            toolbarRecordProjection = nextToolbarProjection
            if toolbarLayoutDidChange {
                toolbarLayoutChanged.send(.allProfiles)
            }
        }
    }

    private func scheduleActionStatesUpdate(
        _ actionStates: [String: BrowserExtensionActionSurfaceState]
    ) {
        scheduledActionStatesGeneration &+= 1
        let generation = scheduledActionStatesGeneration
        updateScheduler { [weak self] in
            guard self?.scheduledActionStatesGeneration == generation else {
                return
            }
            self?.actionStatesByExtensionID = actionStates
        }
    }

    private func refreshSiteAccessPoliciesForCurrentProfile(
        extensionIds: [String]? = nil
    ) {
        guard let binding, let activeSiteAccessProfileId else {
            scheduleSiteAccessPoliciesUpdate([:])
            return
        }

        let resolvedExtensionIds =
            extensionIds ?? binding.installedExtensions().map(\.id)
        scheduleSiteAccessPoliciesUpdate(
            binding.siteAccessPolicySnapshot(
                resolvedExtensionIds,
                activeSiteAccessProfileId
            )
        )
    }

    private func scheduleSiteAccessPoliciesUpdate(
        _ policies: [String: SafariExtensionSiteAccessPolicy]
    ) {
        scheduledSiteAccessPoliciesGeneration &+= 1
        let generation = scheduledSiteAccessPoliciesGeneration
        updateScheduler { [weak self] in
            guard self?.scheduledSiteAccessPoliciesGeneration == generation else {
                return
            }
            self?.siteAccessPoliciesByExtensionID = policies
        }
    }
}

@MainActor
final class BrowserExtensionSurfaceBinding {
    let installedExtensionsPublisher:
        Published<[InstalledExtension]>.Publisher
    let actionStatesPublisher:
        Published<[String: BrowserExtensionActionSurfaceState]>.Publisher
    let actionPresentationChangePublisher:
        AnyPublisher<ExtensionActionPresentationChange, Never>
    let siteAccessPolicyChangePublisher: AnyPublisher<Void, Never>
    let installedExtensions: @MainActor () -> [InstalledExtension]
    let siteAccessPolicySnapshot: @MainActor (
        _ extensionIDs: [String],
        _ profileID: UUID
    ) -> [String: SafariExtensionSiteAccessPolicy]

    init(
        installedExtensionsPublisher:
            Published<[InstalledExtension]>.Publisher,
        actionStatesPublisher:
            Published<[String: BrowserExtensionActionSurfaceState]>.Publisher,
        actionPresentationChangePublisher:
            AnyPublisher<ExtensionActionPresentationChange, Never>,
        siteAccessPolicyChangePublisher: AnyPublisher<Void, Never>,
        installedExtensions: @escaping @MainActor () -> [InstalledExtension],
        siteAccessPolicySnapshot: @escaping @MainActor (
            _ extensionIDs: [String],
            _ profileID: UUID
        ) -> [String: SafariExtensionSiteAccessPolicy]
    ) {
        self.installedExtensionsPublisher = installedExtensionsPublisher
        self.actionStatesPublisher = actionStatesPublisher
        self.actionPresentationChangePublisher =
            actionPresentationChangePublisher
        self.siteAccessPolicyChangePublisher = siteAccessPolicyChangePublisher
        self.installedExtensions = installedExtensions
        self.siteAccessPolicySnapshot = siteAccessPolicySnapshot
    }
}
