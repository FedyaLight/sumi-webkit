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
    struct ContextBinding {
        let context: WKWebExtensionContext
        let receipt: ExtensionContextBindingReceipt
    }

    typealias ContextBindings = @MainActor (
        _ extensionID: String
    ) -> [ContextBinding]
    typealias CurrentContext = @MainActor (
        _ receipt: ExtensionContextBindingReceipt
    ) -> WKWebExtensionContext?
    typealias StableAdapter = @MainActor (Tab) -> ExtensionTabAdapter?
    typealias WindowRegistrationReceipt = @MainActor (
        BrowserWindowState
    ) -> WindowRegistry.WindowRegistrationReceipt?
    typealias RegisteredWindow = @MainActor (
        WindowRegistry.WindowRegistrationReceipt
    ) -> BrowserWindowState?
    typealias AllWindows = @MainActor () -> [BrowserWindowState]

    private let contextBindings: ContextBindings
    private let currentContext: CurrentContext
    private let stableAdapter: StableAdapter
    private let windowRegistrationReceipt: WindowRegistrationReceipt
    private let registeredWindow: RegisteredWindow
    private let allWindows: AllWindows

    init(
        contextBindings: @escaping ContextBindings,
        currentContext: @escaping CurrentContext,
        stableAdapter: @escaping StableAdapter,
        windowRegistrationReceipt: @escaping WindowRegistrationReceipt,
        registeredWindow: @escaping RegisteredWindow,
        allWindows: @escaping AllWindows
    ) {
        self.contextBindings = contextBindings
        self.currentContext = currentContext
        self.stableAdapter = stableAdapter
        self.windowRegistrationReceipt = windowRegistrationReceipt
        self.registeredWindow = registeredWindow
        self.allWindows = allWindows
    }

    func target(
        extensionID: String,
        tab: Tab,
        window: BrowserWindowState
    ) -> ExtensionActionPresentationTarget? {
        guard let adapter = stableAdapter(tab),
              let windowReceipt = windowRegistrationReceipt(window),
              registeredWindow(windowReceipt) === window,
              hasUniqueResidence(tab: tab, in: window)
        else { return nil }

        let candidates = contextBindings(extensionID).compactMap {
            binding -> ExtensionActionPresentationTarget? in
            let context = binding.context
            let receipt = binding.receipt
            let profileID = receipt.key.profileId
            guard receipt.key.extensionId == extensionID,
                  currentContext(receipt) === context,
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
        guard target.contextReceipt.key.extensionId == target.extensionID,
              target.contextReceipt.key.profileId == target.profileID,
              ObjectIdentifier(target.window) == target.windowIdentifier,
              target.window.id == target.windowID,
              registeredWindow(
                  target.windowRegistrationReceipt
              ) === target.window,
              hasUniqueResidence(
                  tab: target.tab,
                  in: target.window
              ),
              ObjectIdentifier(target.tab) == target.tabIdentifier,
              target.tab.id == target.tabID,
              let context = currentContext(target.contextReceipt),
              let adapter = stableAdapter(target.tab),
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
        in targetWindow: BrowserWindowState
    ) -> Bool {
        let claimingWindows = allWindows().filter { window in
            guard windowRegistrationReceipt(window) != nil,
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
