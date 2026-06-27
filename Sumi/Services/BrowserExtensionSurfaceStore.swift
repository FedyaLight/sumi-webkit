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

extension Notification.Name {
    static let sumiExtensionSiteAccessPoliciesDidChange = Notification.Name(
        "SumiExtensionSiteAccessPoliciesDidChange"
    )
}

struct BrowserExtensionActionSurfaceState {
    var extensionID: String
    var label: String
    var badgeText: String
    var hasUnreadBadgeText: Bool
    var isEnabled: Bool
    var presentsPopup: Bool
    var icon: NSImage?
}

@MainActor
final class BrowserExtensionSurfaceStore: ObservableObject {
    @Published private(set) var installedExtensions: [InstalledExtension] = []
    @Published private(set) var actionStatesByExtensionID:
        [String: BrowserExtensionActionSurfaceState] = [:]
    @Published private(set) var siteAccessPoliciesByExtensionID:
        [String: SafariExtensionSiteAccessPolicy] = [:]

    private var cancellables: Set<AnyCancellable> = []
    private weak var extensionManager: ExtensionManager?
    private var activeSiteAccessProfileId: UUID?
    private var scheduledInstalledExtensionsGeneration = 0
    private var scheduledActionStatesGeneration = 0
    private var scheduledSiteAccessPoliciesGeneration = 0

    init(extensionManager: ExtensionManager?) {
        bind(extensionManager)
    }

    var enabledExtensions: [InstalledExtension] {
        installedExtensions.filter(\.isEnabled)
    }

    func bind(_ extensionManager: ExtensionManager?) {
        guard self.extensionManager !== extensionManager else { return }

        cancellables.removeAll()
        self.extensionManager = extensionManager

        guard let extensionManager else {
            activeSiteAccessProfileId = nil
            scheduleInstalledExtensionsUpdate([])
            scheduleActionStatesUpdate([:])
            scheduleSiteAccessPoliciesUpdate([:])
            return
        }

        extensionManager.$installedExtensions
            .sink { [weak self] installedExtensions in
                self?.scheduleInstalledExtensionsUpdate(installedExtensions)
                self?.refreshSiteAccessPoliciesForCurrentProfile(
                    extensionIds: installedExtensions.map(\.id)
                )
            }
            .store(in: &cancellables)

        extensionManager.$actionStatesByExtensionID
            .sink { [weak self] actionStates in
                self?.scheduleActionStatesUpdate(actionStates)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: .sumiExtensionSiteAccessPoliciesDidChange,
            object: extensionManager
        )
        .sink { [weak self] _ in
            self?.refreshSiteAccessPoliciesForCurrentProfile()
        }
        .store(in: &cancellables)
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
        Task { @MainActor [weak self] in
            await Task.yield()
            guard self?.scheduledInstalledExtensionsGeneration == generation else {
                return
            }
            self?.installedExtensions = installedExtensions
        }
    }

    private func scheduleActionStatesUpdate(
        _ actionStates: [String: BrowserExtensionActionSurfaceState]
    ) {
        scheduledActionStatesGeneration &+= 1
        let generation = scheduledActionStatesGeneration
        Task { @MainActor [weak self] in
            await Task.yield()
            guard self?.scheduledActionStatesGeneration == generation else {
                return
            }
            self?.actionStatesByExtensionID = actionStates
        }
    }

    private func refreshSiteAccessPoliciesForCurrentProfile(
        extensionIds: [String]? = nil
    ) {
        guard let extensionManager, let activeSiteAccessProfileId else {
            scheduleSiteAccessPoliciesUpdate([:])
            return
        }

        let resolvedExtensionIds =
            extensionIds ?? extensionManager.installedExtensions.map(\.id)
        scheduleSiteAccessPoliciesUpdate(
            extensionManager.siteAccessPolicySnapshot(
                extensionIds: resolvedExtensionIds,
                profileId: activeSiteAccessProfileId
            )
        )
    }

    private func scheduleSiteAccessPoliciesUpdate(
        _ policies: [String: SafariExtensionSiteAccessPolicy]
    ) {
        scheduledSiteAccessPoliciesGeneration &+= 1
        let generation = scheduledSiteAccessPoliciesGeneration
        Task { @MainActor [weak self] in
            await Task.yield()
            guard self?.scheduledSiteAccessPoliciesGeneration == generation else {
                return
            }
            self?.siteAccessPoliciesByExtensionID = policies
        }
    }
}
