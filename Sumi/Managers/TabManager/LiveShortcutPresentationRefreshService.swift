import Foundation

/// Plans and atomically publishes presentation-page changes caused by one
/// durable shortcut mutation. Physical residence storage remains owned by
/// `LiveShortcutTabRegistry`; execution binding remains owned by
/// `ShortcutTabBindingSynchronizer`.
@MainActor
final class LiveShortcutPresentationRefreshService {
    private let registry: LiveShortcutTabRegistry
    private let resolution: ShortcutPinRuntimeResolutionOwner

    init(
        registry: LiveShortcutTabRegistry,
        resolution: ShortcutPinRuntimeResolutionOwner
    ) {
        self.registry = registry
        self.resolution = resolution
    }

    func admission(
        for pin: ShortcutPin
    ) -> LiveShortcutPresentationRefreshAdmission? {
        switch pin.role {
        case .essential where pin.profileId == nil:
            return nil
        case .spacePinned where pin.spaceId == nil:
            return nil
        default:
            break
        }
        var changes: [LiveShortcutPresentationRefreshAdmission.Change] = []
        for entry in registry.entries(for: pin.id) {
            let targetSpaceID = pin.spaceId
                ?? entry.presentationPage.page.spaceID
            guard let targetPage = resolution.presentationPageReceipt(
                for: pin,
                windowID: entry.windowId,
                presentationSpaceID: targetSpaceID
            ) else { return nil }
            changes.append(.init(
                tab: entry.tab,
                windowID: entry.windowId,
                sourcePage: entry.presentationPage,
                targetPage: targetPage
            ))
        }
        return LiveShortcutPresentationRefreshAdmission(
            pin: pin,
            changes: changes
        )
    }

    func reversedAdmission(
        _ admission: LiveShortcutPresentationRefreshAdmission,
        for pin: ShortcutPin
    ) -> LiveShortcutPresentationRefreshAdmission? {
        guard pin.id == admission.pinID else { return nil }
        var changes: [LiveShortcutPresentationRefreshAdmission.Change] = []
        for change in admission.changes {
            guard resolution.presentationPageReceipt(
                for: pin,
                windowID: change.windowID,
                presentationSpaceID: change.sourcePage.page.spaceID
            ) == change.sourcePage else { return nil }
            changes.append(.init(
                tab: change.tab,
                windowID: change.windowID,
                sourcePage: change.targetPage,
                targetPage: change.sourcePage
            ))
        }
        return LiveShortcutPresentationRefreshAdmission(
            pin: pin,
            changes: changes
        )
    }

    func acceptsCurrent(
        _ admission: LiveShortcutPresentationRefreshAdmission,
        for pin: ShortcutPin
    ) -> Bool {
        admission.accepts(pin) && admission.changes.allSatisfy { change in
            guard let entry = registry.entry(containing: change.tab) else {
                return false
            }
            return entry.windowId == change.windowID
                && entry.pinId == pin.id
                && entry.presentationPage == change.sourcePage
        }
    }

    func stageResidenceTransaction(
        _ admission: LiveShortcutPresentationRefreshAdmission,
        for pin: ShortcutPin
    ) -> LiveShortcutPresentationResidenceTransaction? {
        guard acceptsCurrent(admission, for: pin) else { return nil }
        var changes: [LiveShortcutResidenceMutationStaging.Change] = []
        for change in admission.changes
            where change.sourcePage != change.targetPage {
            guard let staged = registry.staging.relocate(
                change.tab,
                from: pin.id,
                to: pin.id,
                in: change.windowID,
                presentationPage: change.targetPage
            ) else {
                precondition(
                    registry.staging.rollback(changes),
                    "Presentation residence staging lost exact compensation"
                )
                return nil
            }
            changes.append(staged)
        }
        return LiveShortcutPresentationResidenceTransaction(
            pin: pin,
            admission: admission,
            staging: registry.staging,
            changes: changes
        )
    }

    /// Every residence is staged without publication first. A synchronous
    /// structure observer therefore cannot invalidate a later relocation in
    /// the same admission: the sole callback boundary is the final aggregate
    /// `publish` after all physical pages are already exact.
    func apply(
        _ admission: LiveShortcutPresentationRefreshAdmission,
        to pin: ShortcutPin
    ) -> Bool {
        guard let transaction = stageResidenceTransaction(
            admission,
            for: pin
        ) else { return false }
        guard transaction.publish() else {
            precondition(
                transaction.rollback(),
                "Presentation refresh diverged before aggregate publication"
            )
            return false
        }
        return true
    }
}
