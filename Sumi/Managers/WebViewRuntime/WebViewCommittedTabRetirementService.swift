import Foundation

/// Seals committed Tab identities until every retired WebView is gone.
@MainActor
final class WebViewCommittedTabRetirementService {
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let generations: WebViewRetiredGenerationDestroyer

    init(
        runtimeTabs: WebViewRuntimeTabRegistry,
        generations: WebViewRetiredGenerationDestroyer
    ) {
        self.runtimeTabs = runtimeTabs
        self.generations = generations
    }

    func canAdmit(_ tabs: [Tab]) -> Bool {
        guard let tabs = orderedUnique(tabs) else { return false }
        return tabs.allSatisfy { runtimeTabs.bind($0).isAccepted }
    }

    func beginCommitted(_ tabs: [Tab]) -> Bool {
        guard let tabs = orderedUnique(tabs) else { return false }
        var tabsNeedingClaim: [Tab] = []
        for tab in tabs {
            switch runtimeTabs.bind(tab) {
            case .bound, .alreadyBound:
                tabsNeedingClaim.append(tab)
            case .retiredIdentity: continue
            case .identityConflict, .runtimeTerminated: return false
            }
        }
        for tab in tabsNeedingClaim {
            precondition(runtimeTabs.beginRetirement(tab), "Retirement lost identity")
        }
        return true
    }

    func destroy(
        _ retired: [RetiredTabWebViewGeneration],
        completing tabs: [Tab]
    ) {
        destroy(retired, belongingTo: tabs, finishesRuntimeIdentity: true)
    }

    func destroyAfterRuntimeTermination(
        _ retired: [RetiredTabWebViewGeneration],
        belongingTo tabs: [Tab]
    ) {
        destroy(retired, belongingTo: tabs, finishesRuntimeIdentity: false)
    }

    private func destroy(
        _ retired: [RetiredTabWebViewGeneration],
        belongingTo tabs: [Tab],
        finishesRuntimeIdentity: Bool
    ) {
        guard let tabs = orderedUnique(tabs) else {
            preconditionFailure("Committed retirement contains duplicate Tabs")
        }
        precondition(
            Set(retired.map(\.tabID)).isSubset(of: Set(tabs.map(\.id))),
            "Retired WebView generation does not belong to a committed Tab"
        )
        generations.destroy(
            retired,
            navigationTabsByID: Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        )
        guard finishesRuntimeIdentity else { return }
        for tab in tabs {
            if runtimeTabs.isRetiring(tab) {
                precondition(runtimeTabs.finishRetirementIfDrained(tab.id),
                             "Retirement retained a WebView residence")
            } else {
                precondition(runtimeTabs.bind(tab) == .retiredIdentity,
                             "Retirement lost its runtime tombstone")
            }
        }
    }

    private func orderedUnique(_ tabs: [Tab]) -> [Tab]? {
        Set(tabs.map(\.id)).count == tabs.count
            ? tabs.sorted { $0.id.uuidString < $1.id.uuidString } : nil
    }
}
