import Foundation

struct TabSuspensionVisibilityLedger {
    private struct HiddenState {
        let startedAtLiveUptime: TimeInterval
    }

    private var hiddenStates: [UUID: HiddenState] = [:]
    private var revisitCounts: [UUID: Int] = [:]

    mutating func retainTabs(withIDs knownTabIDs: Set<UUID>) {
        hiddenStates = hiddenStates.filter { knownTabIDs.contains($0.key) }
        revisitCounts = revisitCounts.filter { knownTabIDs.contains($0.key) }
    }

    mutating func noteVisible(tabID: UUID) {
        guard hiddenStates.removeValue(forKey: tabID) != nil else { return }
        revisitCounts[tabID, default: 0] += 1
    }

    mutating func hiddenStart(
        for tabID: UUID,
        defaultingTo liveUptime: TimeInterval
    ) -> TimeInterval {
        if let hiddenState = hiddenStates[tabID] {
            return hiddenState.startedAtLiveUptime
        }
        hiddenStates[tabID] = HiddenState(startedAtLiveUptime: liveUptime)
        return liveUptime
    }

    mutating func restartHiddenInterval(for tabID: UUID, at liveUptime: TimeInterval) {
        hiddenStates[tabID] = HiddenState(startedAtLiveUptime: liveUptime)
    }

    mutating func resetRevisitCount(for tabID: UUID) {
        revisitCounts[tabID] = 0
    }

    func revisitCount(for tabID: UUID) -> Int {
        revisitCounts[tabID, default: 0]
    }

    func hiddenStart(for tabID: UUID) -> TimeInterval? {
        hiddenStates[tabID]?.startedAtLiveUptime
    }

    mutating func removeHiddenState(for tabID: UUID) {
        hiddenStates.removeValue(forKey: tabID)
    }
}
