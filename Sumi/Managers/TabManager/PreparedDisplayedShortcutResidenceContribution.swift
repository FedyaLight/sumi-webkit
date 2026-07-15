import Foundation

@MainActor
struct DisplayedShortcutActivationRemainder {
    let requests: [ShortcutPresentationActivationService.Request]

    init(
        excludingPinID: UUID,
        requests: [ShortcutPresentationActivationService.Request]
    ) {
        precondition(requests.allSatisfy { $0.pinID != excludingPinID })
        self.requests = requests
    }
}

@MainActor
final class PreparedDisplayedShortcutResidenceContribution {
    enum Selection {
        case contributed(Int)
        case activation(Int)
    }

    private enum State { case prepared, bound }

    private let contribution: DisplayedShortcutResidenceContribution
    private let selections: [Selection]
    let remainder: DisplayedShortcutActivationRemainder
    private var state = State.prepared

    init(
        contribution: DisplayedShortcutResidenceContribution,
        selections: [Selection],
        remainder: DisplayedShortcutActivationRemainder
    ) {
        self.contribution = contribution
        self.selections = selections
        self.remainder = remainder
    }

    func makeShortcutWitnesses(
        activationTabs: [Tab]
    ) -> [WindowSplitPresentationShortcutWitness]? {
        guard activationTabs.count == remainder.requests.count else { return nil }
        let witnesses: [WindowSplitPresentationShortcutWitness] = selections
            .compactMap { selection -> WindowSplitPresentationShortcutWitness? in
            switch selection {
            case .contributed(let index):
                guard let entry = contribution.entry(at: index) else { return nil }
                return .displayedBinding(
                    DisplayedShortcutMemberWitness(
                        contribution: contribution,
                        entryIndex: index,
                        entry: entry
                    )
                )
            case .activation(let index):
                guard activationTabs.indices.contains(index),
                      remainder.requests.indices.contains(index) else { return nil }
                return .activated(
                    request: remainder.requests[index],
                    tab: activationTabs[index]
                )
            }
            }
        return witnesses.count == selections.count ? witnesses : nil
    }

    func preparedIdentityIsExact() -> Bool {
        guard case .prepared = state else { return false }
        return contribution.preparedIdentityIsExact()
    }

    func acceptBoundIdentity() -> Bool {
        guard case .prepared = state,
              contribution.boundIdentityIsExact() else { return false }
        state = .bound
        return true
    }

    func boundIdentityIsExact() -> Bool {
        guard case .bound = state else { return false }
        return contribution.boundIdentityIsExact()
    }

    func terminalIdentityIsExact() -> Bool {
        guard case .bound = state else { return false }
        return contribution.terminalIdentityIsExact()
    }
}

@MainActor
struct DisplayedShortcutMemberWitness {
    private let contribution: DisplayedShortcutResidenceContribution
    private let entryIndex: Int
    let entry: DisplayedShortcutResidenceContribution.Entry

    init(
        contribution: DisplayedShortcutResidenceContribution,
        entryIndex: Int,
        entry: DisplayedShortcutResidenceContribution.Entry
    ) {
        self.contribution = contribution
        self.entryIndex = entryIndex
        self.entry = entry
    }

    func preparedIdentityIsExact() -> Bool {
        contribution.entry(at: entryIndex)?.tab === entry.tab
            && contribution.preparedIdentityIsExact()
    }

    func boundIdentityIsExact() -> Bool {
        contribution.entry(at: entryIndex)?.tab === entry.tab
            && contribution.boundIdentityIsExact()
    }
}
