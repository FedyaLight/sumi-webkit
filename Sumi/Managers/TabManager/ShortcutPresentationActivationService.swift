import Foundation

@MainActor
protocol ShortcutPresentationActivating: AnyObject {
    func withActivation(
        _ pin: ShortcutPin,
        in windowID: UUID,
        presentationSpaceID: UUID?,
        applying downstream: (Tab) -> Bool
    ) -> Bool
}

/// A prepared downstream model participant. Every operation is mandatory:
/// activation cannot silently omit exact-current proof or compensation.
@MainActor
protocol ShortcutPresentationTerminalMutation: AnyObject {
    func isCurrent() -> Bool
    func commitModel() -> Bool
    func publish()
    func rollback()
}

/// Single authority for presenting durable shortcuts in exact window/Space
/// pages. The aggregate receipt is published only after downstream window or
/// split state accepts every prepared tab.
@MainActor
final class ShortcutPresentationActivationService: ShortcutPresentationActivating {
    struct Request {
        let pinID: UUID
        let windowID: UUID
        let presentationSpaceID: UUID?
    }

    private let planner: ShortcutPresentationActivationPlanner
    private let committer: ShortcutPresentationActivationCommitter
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        planner: ShortcutPresentationActivationPlanner,
        committer: ShortcutPresentationActivationCommitter,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.planner = planner
        self.committer = committer
        self.structuralLookup = structuralLookup
    }

    func activate(
        pinID: UUID,
        in windowID: UUID,
        presentationSpaceID: UUID?
    ) -> Tab? {
        var activated: Tab?
        let accepted = withActivation([
            Request(
                pinID: pinID,
                windowID: windowID,
                presentationSpaceID: presentationSpaceID
            ),
        ]) { tabs in
            activated = tabs.first
            return activated != nil
        }
        return accepted ? activated : nil
    }

    func activate(
        _ pin: ShortcutPin,
        in windowID: UUID,
        presentationSpaceID: UUID?
    ) -> Tab? {
        activate(
            pinID: pin.id,
            in: windowID,
            presentationSpaceID: presentationSpaceID
        )
    }

    func withActivation(
        _ requests: [Request],
        applying downstream: ([Tab]) -> Bool
    ) -> Bool {
        guard requests.isEmpty == false else { return downstream([]) }
        guard let receipt = prepareActivation(requests) else { return false }
        return structuralLookup.withTransaction {
            guard receipt.stage() else { return false }
            guard downstream(receipt.tabs) else {
                receipt.rollback()
                return false
            }
            guard receipt.canPublish() else {
                receipt.rollback()
                return false
            }
            receipt.publish()
            return true
        }
    }

    func withActivation(
        _ tab: Tab,
        in windowID: UUID,
        presentationSpaceID: UUID?,
        applying downstream: (Tab) -> Bool
    ) -> Bool {
        guard tab.isShortcutLiveInstance else { return downstream(tab) }
        guard let pinID = tab.shortcutPinId else { return false }
        return withActivation([
            Request(
                pinID: pinID,
                windowID: windowID,
                presentationSpaceID: presentationSpaceID
            ),
        ]) { tabs in
            guard tabs.first === tab else { return false }
            return downstream(tab)
        }
    }

    func withActivation(
        _ pin: ShortcutPin,
        in windowID: UUID,
        presentationSpaceID: UUID?,
        applying downstream: (Tab) -> Bool
    ) -> Bool {
        withActivation([
            Request(
                pinID: pin.id,
                windowID: windowID,
                presentationSpaceID: presentationSpaceID
            ),
        ]) { tabs in
            guard let tab = tabs.first else { return false }
            return downstream(tab)
        }
    }

    /// Runs infallible outward effects only after exact residence settlement.
    /// Prepared aggregate consumers may first install their canonical model
    /// without observation, then publish only after every participant is in
    /// its terminal state.
    func commitActivation(
        _ tab: Tab,
        in windowID: UUID,
        presentationSpaceID: UUID?,
        finalizing: (Tab) -> Void
    ) -> Bool {
        guard tab.isShortcutLiveInstance else {
            finalizing(tab)
            return true
        }
        guard let pinID = tab.shortcutPinId else { return false }
        return commitActivationFinalizing([
            Request(
                pinID: pinID,
                windowID: windowID,
                presentationSpaceID: presentationSpaceID
            ),
        ], accepts: { $0.first === tab }) { _ in
            finalizing(tab)
        }
    }

    func commitActivation(
        _ tab: Tab,
        in windowID: UUID,
        presentationSpaceID: UUID?,
        preparing terminal: (Tab) -> (any ShortcutPresentationTerminalMutation)?
    ) -> Bool {
        guard tab.isShortcutLiveInstance else {
            guard let terminal = terminal(tab) else { return false }
            return structuralLookup.withTransaction {
                guard terminal.isCurrent(), terminal.commitModel() else {
                    terminal.rollback()
                    return false
                }
                terminal.publish()
                return true
            }
        }
        guard let pinID = tab.shortcutPinId else { return false }
        return commitActivation([
            Request(
                pinID: pinID,
                windowID: windowID,
                presentationSpaceID: presentationSpaceID
            ),
        ]) { tabs in
            guard tabs.first === tab else { return nil }
            return terminal(tab)
        }
    }

    func commitActivation(
        _ pin: ShortcutPin,
        in windowID: UUID,
        presentationSpaceID: UUID?,
        finalizing: (Tab) -> Void
    ) -> Bool {
        commitActivationFinalizing([Request(
                pinID: pin.id,
                windowID: windowID,
                presentationSpaceID: presentationSpaceID
            )], accepts: { $0.count == 1 }) { tabs in
            guard let tab = tabs.first else {
                preconditionFailure("Accepted activation lost its only Tab")
            }
            finalizing(tab)
        }
    }

    private func commitActivation(
        _ requests: [Request],
        preparing terminal: ([Tab]) -> (any ShortcutPresentationTerminalMutation)?
    ) -> Bool {
        guard let receipt = prepareActivation(requests) else { return false }
        return structuralLookup.withTransaction {
            guard receipt.stage() else { return false }
            guard let terminal = terminal(receipt.tabs) else {
                receipt.rollback()
                return false
            }
            guard receipt.canPublish(), terminal.isCurrent() else {
                terminal.rollback()
                receipt.rollback()
                return false
            }
            guard terminal.commitModel() else {
                terminal.rollback()
                receipt.rollback()
                return false
            }
            receipt.publish()
            terminal.publish()
            return true
        }
    }

    private func commitActivationFinalizing(
        _ requests: [Request],
        accepts: ([Tab]) -> Bool,
        finalizing: ([Tab]) -> Void
    ) -> Bool {
        guard let receipt = prepareActivation(requests) else { return false }
        return structuralLookup.withTransaction {
            guard receipt.stage() else { return false }
            guard accepts(receipt.tabs), receipt.canPublish() else {
                receipt.rollback()
                return false
            }
            receipt.publish()
            finalizing(receipt.tabs)
            return true
        }
    }

    func prepareActivation(
        _ requests: [Request]
    ) -> ShortcutPresentationActivationReceipt? {
        guard let admissions = planner.prepare(requests) else { return nil }
        return ShortcutPresentationActivationReceipt(
            admissions: admissions,
            planner: planner,
            committer: committer
        )
    }

    func prepareActivation(
        _ remainder: DisplayedShortcutActivationRemainder,
        preview: ShortcutPresentationCatalogInsertionPreview
    ) -> ShortcutPresentationActivationReceipt? {
        guard let admissions = planner.prepare(
            remainder,
            preview: preview
        ) else { return nil }
        return ShortcutPresentationActivationReceipt(
            admissions: admissions,
            planner: planner,
            committer: committer
        )
    }
}
