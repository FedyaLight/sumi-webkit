import Foundation

/// Ordered Tab admission is separate from the read-only publication query.
/// Auxiliary Tabs may pass only through an exact committed auxiliary receipt;
/// all other Tabs use normal-window admission.
@available(macOS 15.5, *)
@MainActor
final class ExtensionTabPublicationAdmission {
    private let normalWindows: ExtensionNormalWindowLifecycle
    private let publications: ExtensionWindowPublicationQuery

    init(
        normalWindows: ExtensionNormalWindowLifecycle,
        publications: ExtensionWindowPublicationQuery
    ) {
        self.normalWindows = normalWindows
        self.publications = publications
    }

    func prepareTabOpen(_ tab: Tab) -> Bool {
        switch publications.auxiliaryTabPublicationState(for: tab) {
        case .notAuxiliarySession:
            normalWindows.prepareTabOpen(tab)
        case .committed:
            true
        case .unavailable:
            false
        }
    }
}
