import Foundation
import WebKit

/// Demand-scoped identity for one rendered action. The context receipt proves
/// the exact execution profile; presentation-profile IDs are never used as a
/// substitute for an account-forked Tab's runtime partition.
@available(macOS 15.5, *)
struct ExtensionActionPresentationTarget: Hashable {
    let extensionID: String
    let profileID: UUID
    let windowID: UUID
    let windowIdentifier: ObjectIdentifier
    let windowRegistrationReceipt: WindowRegistry.WindowRegistrationReceipt
    let tabID: UUID
    let tabIdentifier: ObjectIdentifier
    let adapterIdentifier: ObjectIdentifier
    let contextReceipt: ExtensionContextBindingReceipt
    let window: BrowserWindowState
    let tab: Tab

    static func == (
        lhs: ExtensionActionPresentationTarget,
        rhs: ExtensionActionPresentationTarget
    ) -> Bool {
        lhs.extensionID == rhs.extensionID
            && lhs.profileID == rhs.profileID
            && lhs.windowID == rhs.windowID
            && lhs.windowIdentifier == rhs.windowIdentifier
            && lhs.windowRegistrationReceipt == rhs.windowRegistrationReceipt
            && lhs.tabID == rhs.tabID
            && lhs.tabIdentifier == rhs.tabIdentifier
            && lhs.adapterIdentifier == rhs.adapterIdentifier
            && lhs.contextReceipt == rhs.contextReceipt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(extensionID)
        hasher.combine(profileID)
        hasher.combine(windowID)
        hasher.combine(windowIdentifier)
        hasher.combine(windowRegistrationReceipt)
        hasher.combine(tabID)
        hasher.combine(tabIdentifier)
        hasher.combine(adapterIdentifier)
        hasher.combine(contextReceipt)
    }
}

@available(macOS 15.5, *)
struct ExtensionActionPresentationChange: Equatable {
    let extensionID: String
    let profileID: UUID?

    func affects(_ target: ExtensionActionPresentationTarget) -> Bool {
        extensionID == target.extensionID
            && (profileID == nil || profileID == target.profileID)
    }
}

/// Resolves toolbar state only from the exact WebKit context/Tab publication
/// graph. Presentation profile and active-window fallbacks are intentionally
/// absent: an account-forked Tab executes in its context receipt's profile.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPresentationQuery {
    private let manager: @MainActor () -> ExtensionManager?

    init(manager: @escaping @MainActor () -> ExtensionManager?) {
        self.manager = manager
    }

    func target(
        extensionID: String,
        tab: Tab,
        window: BrowserWindowState
    ) -> ExtensionActionPresentationTarget? {
        guard let manager = manager(),
              let adapter = manager.adapterCatalog.stableAdapter(for: tab),
              let windowReceipt = manager.runtime.windowRegistrationReceipt(window),
              manager.runtime.registeredWindow(windowReceipt) === window,
              hasUniqueResidence(tab: tab, in: window, manager: manager)
        else { return nil }

        let candidates = manager.profileRuntime.contextsByProfile.compactMap {
            profileID, contexts -> ExtensionActionPresentationTarget? in
            guard let context = contexts[extensionID],
                  let exactIdentity = manager.profileRuntime
                  .exactContextIdentity(for: context),
                  exactIdentity.extensionId == extensionID,
                  exactIdentity.profileId == profileID,
                  let receipt = manager.profileRuntime.contextBindingReceipt(
                      extensionId: extensionID,
                      profileId: profileID
                  ),
                  manager.profileRuntime.context(ifCurrent: receipt) === context,
                  let publication = adapter.evidence.currentPublication(
                      visibleTo: context
                  ),
                  publication.tab === tab,
                  publication.contextIdentity.extensionID == extensionID,
                  publication.contextIdentity.profileID == profileID
            else { return nil }

            return ExtensionActionPresentationTarget(
                extensionID: extensionID,
                profileID: profileID,
                windowID: window.id,
                windowIdentifier: ObjectIdentifier(window),
                windowRegistrationReceipt: windowReceipt,
                tabID: tab.id,
                tabIdentifier: ObjectIdentifier(tab),
                adapterIdentifier: ObjectIdentifier(adapter),
                contextReceipt: receipt,
                window: window,
                tab: tab
            )
        }
        guard candidates.count == 1 else { return nil }
        return candidates[0]
    }

    func snapshot(
        for target: ExtensionActionPresentationTarget
    ) -> BrowserExtensionActionButtonSnapshot? {
        guard let manager = manager(),
              target.contextReceipt.key.extensionId == target.extensionID,
              target.contextReceipt.key.profileId == target.profileID,
              ObjectIdentifier(target.window) == target.windowIdentifier,
              target.window.id == target.windowID,
              manager.runtime.registeredWindow(
                  target.windowRegistrationReceipt
              ) === target.window,
              hasUniqueResidence(
                  tab: target.tab,
                  in: target.window,
                  manager: manager
              ),
              ObjectIdentifier(target.tab) == target.tabIdentifier,
              target.tab.id == target.tabID,
              let context = manager.profileRuntime.context(
                  ifCurrent: target.contextReceipt
              ),
              let exactIdentity = manager.profileRuntime
              .exactContextIdentity(for: context),
              exactIdentity.extensionId == target.extensionID,
              exactIdentity.profileId == target.profileID,
              let adapter = manager.adapterCatalog.stableAdapter(
                  for: target.tab
              ),
              ObjectIdentifier(adapter) == target.adapterIdentifier,
              let publication = adapter.evidence.currentPublication(
                  visibleTo: context
              ),
              publication.tab === target.tab,
              publication.contextIdentity.extensionID == target.extensionID,
              publication.contextIdentity.profileID == target.profileID,
              let action = context.action(for: adapter),
              let update = ExtensionActionSurfaceStatePresenter.makeUpdate(
                  for: action,
                  extensionID: target.extensionID
              )
        else { return nil }
        return BrowserExtensionActionButtonSnapshot(update.state)
    }

    private func hasUniqueResidence(
        tab: Tab,
        in targetWindow: BrowserWindowState,
        manager: ExtensionManager
    ) -> Bool {
        let claimingWindows = manager.runtime.allWindowStates().filter { window in
            guard manager.runtime.windowRegistrationReceipt(window) != nil,
                  window.currentTabId == tab.id
            else { return false }

            if window.isIncognito {
                return window.containsEphemeralTab(ifIdentical: tab)
            }
            if let entry = window.tabManager?.liveShortcutTabs.entry(containing: tab) {
                return entry.windowId == window.id
            }
            guard let spaceID = tab.spaceId,
                  window.currentSpaceId == spaceID,
                  let tabs = window.tabManager
            else { return false }
            return tabs.regularTabCollectionOwner.containsIdentical(
                tab,
                in: spaceID
            )
        }
        return claimingWindows.count == 1 && claimingWindows[0] === targetWindow
    }
}
