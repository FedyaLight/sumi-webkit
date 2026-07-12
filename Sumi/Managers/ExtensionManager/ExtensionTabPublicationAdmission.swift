import Foundation

/// Ordered Tab admission is separate from the read-only publication query.
/// Auxiliary Tabs may pass only through an exact committed auxiliary receipt;
/// all other Tabs use normal-window admission.
@available(macOS 15.5, *)
@MainActor
final class ExtensionTabPublicationAdmission {
    private let normalWindows: ExtensionNormalWindowLifecycle
    private let publications: ExtensionWindowPublicationQuery
    private let gate: ExtensionRuntimePublicationGate

    init(
        normalWindows: ExtensionNormalWindowLifecycle,
        publications: ExtensionWindowPublicationQuery,
        gate: ExtensionRuntimePublicationGate
    ) {
        self.normalWindows = normalWindows
        self.publications = publications
        self.gate = gate
    }

    func prepareTabOpen(_ tab: Tab) -> Bool {
        guard gate.admitStructuralBrowserEvent() else { return false }
        return prepareTabOpenAfterGateAdmission(tab)
    }

    func prepareTabOpen(
        _ tab: Tab,
        during claim: ExtensionRuntimePublicationGate.ReloadClaim
    ) -> Bool {
        guard gate.reloadIsCurrent(claim) else { return false }
        return prepareTabOpenAfterGateAdmission(tab)
    }

    private func prepareTabOpenAfterGateAdmission(_ tab: Tab) -> Bool {
        return switch publications.auxiliaryTabPublicationState(for: tab) {
        case .notAuxiliarySession:
            normalWindows.prepareTabOpen(tab)
        case .committed:
            true
        case .unavailable:
            false
        }
    }
}
