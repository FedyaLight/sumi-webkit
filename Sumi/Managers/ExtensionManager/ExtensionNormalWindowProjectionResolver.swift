import Foundation
import WebKit

/// Immutable proof that one exact registry window can be represented by one
/// WebExtension profile without exposing an empty or cross-profile Tab list.
@available(macOS 15.5, *)
@MainActor
struct ExtensionNormalWindowProjection {
    let windowIdentity: ObjectIdentifier
    let selectedTabIdentity: ObjectIdentifier
    let selectedTabID: UUID
    let profileID: UUID
    let tabGeneration: UInt64
    let controller: WKWebExtensionController
    let windowAdapter: ExtensionWindowAdapter
    let selectedTabAdapter: ExtensionTabAdapter

    func belongsToSameWindowPublication(
        as other: ExtensionNormalWindowProjection
    ) -> Bool {
        windowIdentity == other.windowIdentity
            && profileID == other.profileID
            && tabGeneration == other.tabGeneration
            && controller === other.controller
            && windowAdapter === other.windowAdapter
    }
}

/// Resolves model/profile/adapter facts for normal windows. Lifecycle state
/// and WebKit event ordering deliberately live in ExtensionNormalWindowLifecycle.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowProjectionResolver {
    private weak var manager: ExtensionManager?
    private let preparedTabVisibility: ExtensionPreparedTabVisibility

    init(
        manager: ExtensionManager,
        preparedTabVisibility: ExtensionPreparedTabVisibility
    ) {
        self.manager = manager
        self.preparedTabVisibility = preparedTabVisibility
    }

    func resolve(
        _ window: BrowserWindowState,
        allowWhenExtensionsNotLoaded: Bool = false
    ) -> ExtensionNormalWindowProjection? {
        guard let manager,
              manager.extensionsLoaded || allowWhenExtensionsNotLoaded,
              let windowQuery = manager.extensionWindowQuery,
              windowQuery.extensionWindowState(for: window.id) === window,
              window.isIncognito == false,
              let selectedTabID = window.currentTabId,
              let selectedTab = windowQuery.currentExtensionTab(in: window),
              selectedTab.id == selectedTabID,
              selectedTab.isEphemeral == false,
              let profileID = manager.resolvedProfileId(for: window),
              manager.resolvedProfileId(for: selectedTab) == profileID,
              manager.preparedExtensionTabs.containsPreparedTab(selectedTab),
              let controller = manager.profileRuntime
              .controllersByProfile[profileID],
              manager.extensionController(for: selectedTab) === controller,
              let selectedTabAdapter = manager.adapterCatalog
              .stableAdapter(for: selectedTab),
              let windowAdapter = manager.adapterCatalog
              .windowAdapter(
                  for: window.id,
                  preparedTabVisibility: preparedTabVisibility
              ),
              windowAdapter.represents(window)
        else {
            return nil
        }

        return ExtensionNormalWindowProjection(
            windowIdentity: ObjectIdentifier(window),
            selectedTabIdentity: ObjectIdentifier(selectedTab),
            selectedTabID: selectedTabID,
            profileID: profileID,
            tabGeneration: manager.runtimeSession
                .tabOpenNotificationGeneration,
            controller: controller,
            windowAdapter: windowAdapter,
            selectedTabAdapter: selectedTabAdapter
        )
    }

    func validate(
        _ projection: ExtensionNormalWindowProjection,
        for window: BrowserWindowState,
        allowWhenExtensionsNotLoaded: Bool = false
    ) -> Bool {
        guard projection.windowIdentity == ObjectIdentifier(window),
              let manager,
              manager.extensionsLoaded || allowWhenExtensionsNotLoaded,
              manager.runtimeSession.tabOpenNotificationGeneration
                == projection.tabGeneration,
              let windowQuery = manager.extensionWindowQuery,
              windowQuery.extensionWindowState(for: window.id) === window,
              window.currentTabId == projection.selectedTabID,
              let selectedTab = windowQuery.currentExtensionTab(in: window),
              selectedTab.id == projection.selectedTabID,
              ObjectIdentifier(selectedTab)
                == projection.selectedTabIdentity,
              manager.resolvedProfileId(for: window)
                == projection.profileID,
              manager.resolvedProfileId(for: selectedTab)
                == projection.profileID,
              manager.preparedExtensionTabs.containsPreparedTab(selectedTab),
              manager.profileRuntime.controllersByProfile[projection.profileID]
                === projection.controller,
              manager.extensionController(for: selectedTab)
                === projection.controller,
              manager.adapterStore.existingWindowAdapter(for: window.id)
                === projection.windowAdapter,
              manager.adapterStore.tabAdapters[selectedTab.id]
                === projection.selectedTabAdapter,
              projection.windowAdapter.represents(window)
        else {
            return false
        }
        return true
    }

    func preferredWindow(for tab: Tab) -> BrowserWindowState? {
        guard let manager,
              let windowQuery = manager.extensionWindowQuery,
              let window = windowQuery.preferredExtensionWindowState(
                  containing: tab
              ),
              windowQuery.extensionWindowState(for: window.id) === window
        else {
            return nil
        }
        return window
    }

    func isExactRegistered(_ window: BrowserWindowState) -> Bool {
        manager?.extensionWindowQuery?.extensionWindowState(
            for: window.id
        ) === window
    }

    func profileID(for tab: Tab) -> UUID? {
        manager?.resolvedProfileId(for: tab)
    }

    func canPublishWithoutNormalWindow(_ tab: Tab) -> Bool {
        guard let tabQuery = manager?.extensionTabQuery else { return false }
        return tabQuery.isTransientExtensionTab(tab)
            && tabQuery.isAuxiliaryMiniWindowTab(tab) == false
    }

    func switchToWindowProfile(_ window: BrowserWindowState) {
        guard let manager else { return }
        let runtime = manager.runtime
        if window.isIncognito, let profile = window.ephemeralProfile {
            manager.switchProfile(profileId: profile.id)
        } else if let profileID = window.currentProfileId,
                  runtime.profile(profileID) != nil {
            manager.switchProfile(profileId: profileID)
        } else if let currentProfile = runtime.currentProfile() {
            manager.switchProfile(profileId: currentProfile.id)
        }
    }
}
