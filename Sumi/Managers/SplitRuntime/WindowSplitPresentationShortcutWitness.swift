import Foundation
import SumiDomain

@MainActor
enum WindowSplitPresentationShortcutWitness {
    case activated(
        request: ShortcutPresentationActivationService.Request,
        tab: Tab
    )
    case displayedBinding(DisplayedShortcutMemberWitness)

    var memberID: SplitMemberID {
        .shortcutPin(pinID)
    }

    var pinID: UUID {
        switch self {
        case .activated(let request, _): request.pinID
        case .displayedBinding(let witness): witness.entry.pinID
        }
    }

    var windowID: UUID {
        switch self {
        case .activated(let request, _): request.windowID
        case .displayedBinding(let witness): witness.entry.window.id
        }
    }

    var tab: Tab {
        switch self {
        case .activated(_, let tab): tab
        case .displayedBinding(let witness): witness.entry.tab
        }
    }

    func preparedIdentityIsExact(
        in registry: LiveShortcutTabRegistry
    ) -> Bool {
        switch self {
        case .activated:
            return boundIdentityIsExact(in: registry)
        case .displayedBinding(let witness):
            return witness.preparedIdentityIsExact()
        }
    }

    func boundIdentityIsExact(
        in registry: LiveShortcutTabRegistry
    ) -> Bool {
        switch self {
        case .activated:
            guard let entry = registry.entry(containing: tab) else { return false }
            return entry.windowId == windowID
                && entry.pinId == pinID
                && entry.tab === tab
        case .displayedBinding(let witness):
            return witness.boundIdentityIsExact()
        }
    }

    func applySelection(
        to state: inout BrowserWindowShortcutMutationState
    ) {
        switch self {
        case .activated:
            _ = WindowTabSelectionStateApplicator.apply(
                tab,
                to: &state,
                updateSpaceFromTab: true,
                rememberSelection: true
            )
        case .displayedBinding(let witness):
            ShortcutCurrentSelectionProjection.apply(
                tabID: witness.entry.tab.id,
                target: witness.entry.target,
                to: &state
            )
        }
    }
}
