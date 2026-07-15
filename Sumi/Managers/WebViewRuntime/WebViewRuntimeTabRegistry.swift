import Foundation
import SumiWebRuntime

enum WebViewRuntimeTabBindingOutcome: Equatable {
    case bound
    case alreadyBound
    case identityConflict
    case retiredIdentity
    case runtimeTerminated

    var isAccepted: Bool {
        switch self {
        case .bound, .alreadyBound:
            return true
        case .identityConflict, .retiredIdentity, .runtimeTerminated:
            return false
        }
    }
}

/// The only weak index from repository-owned Tab IDs back to app Tab models.
/// It validates canonical repository backing at bind time and never owns Tabs.
@MainActor
final class WebViewRuntimeTabRegistry {
    typealias RuntimeTabResolver = @MainActor @Sendable (UUID) -> Tab?

    private final class WeakTab {
        weak var value: Tab?

        init(_ value: Tab) {
            self.value = value
        }
    }

    private let webViewSessions: WebViewSessionRepository
    private var tabsByID: [UUID: WeakTab] = [:]
    private var retiringTabIDs: Set<UUID> = []
    private var retiringTabsByID: [UUID: WeakTab] = [:]
    private var retiredTabsByIdentity: [ObjectIdentifier: WeakTab] = [:]
    private var isTerminallyShutDown = false

    init(webViewSessions: WebViewSessionRepository) {
        self.webViewSessions = webViewSessions
    }

    @discardableResult
    func bind(_ tab: Tab) -> WebViewRuntimeTabBindingOutcome {
        guard isTerminallyShutDown == false else {
            return .runtimeTerminated
        }
        tab.webViewSession.requireBacking(by: webViewSessions)
        pruneReleasedRetiredTabs()
        if retiredTabsByIdentity[ObjectIdentifier(tab)]?.value === tab {
            return .retiredIdentity
        }
        if retiringTabIDs.contains(tab.id) {
            return retiringTabsByID[tab.id]?.value === tab
                ? .retiredIdentity
                : .identityConflict
        }
        if let current = tabsByID[tab.id]?.value {
            return current === tab ? .alreadyBound : .identityConflict
        }
        tabsByID[tab.id] = WeakTab(tab)
        return .bound
    }

    /// Admits a transaction's complete physical Tab set without leaving a
    /// partially bound prefix when any later identity conflicts. Binding is a
    /// cache mutation, but it is still part of runtime identity authority and
    /// therefore follows the same all-or-nothing rule as model staging.
    func bindAtomically(_ tabs: [Tab]) -> Bool {
        guard isTerminallyShutDown == false,
              Set(tabs.map(\.id)).count == tabs.count else { return false }
        pruneReleasedRetiredTabs()
        guard tabs.allSatisfy({ tab in
            if retiredTabsByIdentity[ObjectIdentifier(tab)]?.value === tab {
                return false
            }
            if retiringTabIDs.contains(tab.id) {
                return false
            }
            guard let current = tabsByID[tab.id]?.value else { return true }
            return current === tab
        }), tabs.allSatisfy({
            $0.webViewSession.isBacked(by: webViewSessions)
        }) else { return false }

        for tab in tabs {
            if tabsByID[tab.id]?.value == nil {
                tabsByID[tab.id] = WeakTab(tab)
            }
        }
        return true
    }

    func boundTab(_ tabID: UUID) -> Tab? {
        guard isTerminallyShutDown == false else { return nil }
        return tabsByID[tabID]?.value
    }

    @discardableResult
    func beginRetirement(_ tab: Tab) -> Bool {
        guard isTerminallyShutDown == false else { return false }
        pruneReleasedRetiredTabs()
        if retiredTabsByIdentity[ObjectIdentifier(tab)]?.value === tab {
            guard retiringTabIDs.contains(tab.id),
                  retiringTabsByID[tab.id]?.value === tab else {
                return false
            }
            return true
        }
        guard bind(tab).isAccepted else { return false }
        tabsByID.removeValue(forKey: tab.id)
        retiringTabIDs.insert(tab.id)
        retiringTabsByID[tab.id] = WeakTab(tab)
        retiredTabsByIdentity[ObjectIdentifier(tab)] = WeakTab(tab)
        return true
    }

    @discardableResult
    func finishRetirementIfDrained(_ tabID: UUID) -> Bool {
        guard retiringTabIDs.contains(tabID),
              webViewSessions.snapshot(for: tabID).allKnownWebViews.isEmpty
        else { return false }
        retiringTabIDs.remove(tabID)
        retiringTabsByID.removeValue(forKey: tabID)
        return true
    }

    /// Retiring Tabs are visible only to destructive deferred cleanup. Normal
    /// resolution remains closed so no WebView can be recreated while an old
    /// physical residence is draining.
    func tabForCleanup(
        _ tabID: UUID,
        resolveRuntimeTab: RuntimeTabResolver
    ) -> Tab? {
        guard isTerminallyShutDown == false else { return nil }
        if retiringTabIDs.contains(tabID) {
            return retiringTabsByID[tabID]?.value
        }
        return resolve(tabID, resolveRuntimeTab: resolveRuntimeTab)
    }

    func isRetiring(_ tab: Tab) -> Bool {
        retiringTabIDs.contains(tab.id)
            && retiringTabsByID[tab.id]?.value === tab
    }

    func resolve(
        _ tabID: UUID,
        resolveRuntimeTab: RuntimeTabResolver
    ) -> Tab? {
        guard isTerminallyShutDown == false else { return nil }
        if let tab = boundTab(tabID) {
            if let resolved = resolveRuntimeTab(tabID), resolved !== tab {
                return nil
            }
            return tab
        }
        guard let tab = resolveRuntimeTab(tabID) else {
            return nil
        }
        guard bind(tab).isAccepted else { return nil }
        return tab
    }

    func canonicalRuntimeOwnedTabs(
        resolveRuntimeTab: RuntimeTabResolver
    ) -> [Tab]? {
        guard isTerminallyShutDown == false else { return nil }
        var result: [Tab] = []
        let ownedIDs = webViewSessions.runtimeOwnedTabIDs
        for tabID in ownedIDs.sorted(by: uuidOrder) {
            guard let tab = resolve(
                tabID,
                resolveRuntimeTab: resolveRuntimeTab
            ) else {
                return nil
            }
            result.append(tab)
        }
        tabsByID = tabsByID.filter { tabID, reference in
            reference.value != nil && ownedIDs.contains(tabID)
        }
        return result
    }

    /// Closes the Tab identity authority before the repository terminal drain.
    /// Retained services can no longer recreate residences in a dead graph.
    func resetForTerminalShutdown() {
        isTerminallyShutDown = true
        tabsByID.removeAll()
        retiringTabIDs.removeAll()
        retiringTabsByID.removeAll()
        retiredTabsByIdentity.removeAll()
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    private func pruneReleasedRetiredTabs() {
        retiredTabsByIdentity = retiredTabsByIdentity.filter { _, reference in
            reference.value != nil
        }
    }
}
