import Foundation
import SumiWebRuntime

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

    init(webViewSessions: WebViewSessionRepository) {
        self.webViewSessions = webViewSessions
    }

    func bind(_ tab: Tab) {
        tab.webViewSession.requireBacking(by: webViewSessions)
        tabsByID[tab.id] = WeakTab(tab)
    }

    func boundTab(_ tabID: UUID) -> Tab? {
        tabsByID[tabID]?.value
    }

    func resolve(
        _ tabID: UUID,
        resolveRuntimeTab: RuntimeTabResolver
    ) -> Tab? {
        if let tab = boundTab(tabID) {
            return tab
        }
        guard let tab = resolveRuntimeTab(tabID) else {
            return nil
        }
        bind(tab)
        return tab
    }

    func canonicalRuntimeOwnedTabs(
        resolveRuntimeTab: RuntimeTabResolver
    ) -> [Tab]? {
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

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
