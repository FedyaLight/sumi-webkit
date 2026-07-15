import Foundation
import SumiDomain

/// Revalidates the exact window, placeholder, and incoming-member identities
/// captured while planning a placeholder replacement.
@MainActor
final class SplitPlaceholderRuntimeAuthority {
    private let window: BrowserWindowState
    private let expectedSpaceID: UUID?
    private let placeholder: Tab
    private let placeholderID: UUID
    private let incoming: Tab
    private let incomingID: SplitMemberID
    private let regularTabs: RegularTabCollectionOwner
    private let liveShortcuts: LiveShortcutTabRegistry

    init(
        window: BrowserWindowState,
        expectedSpaceID: UUID?,
        placeholder: Tab,
        placeholderID: UUID,
        incoming: Tab,
        incomingID: SplitMemberID,
        regularTabs: RegularTabCollectionOwner,
        liveShortcuts: LiveShortcutTabRegistry
    ) {
        self.window = window
        self.expectedSpaceID = expectedSpaceID
        self.placeholder = placeholder
        self.placeholderID = placeholderID
        self.incoming = incoming
        self.incomingID = incomingID
        self.regularTabs = regularTabs
        self.liveShortcuts = liveShortcuts
    }

    func isCurrent() -> Bool {
        window.currentSpaceId == expectedSpaceID
            && regularTabs.tab(for: placeholderID) === placeholder
            && canonicalIncoming() === incoming
    }

    private func canonicalIncoming() -> Tab? {
        switch incomingID {
        case .regularTab(let tabID):
            return regularTabs.tab(for: tabID)
        case .shortcutPin(let pinID):
            return liveShortcuts.tab(for: pinID, in: window.id)
        }
    }
}

/// Owns the reversible topology and placeholder-retirement participants.
@MainActor
final class SplitPlaceholderTopologyMutation {
    private let topology: SplitGroupReplacementReceipt
    private let launcherRelease: ShortcutSplitLauncherReleaseReceipt
    private let placeholderRetirement: EmptySplitPlaceholderRetirementReceipt

    init(
        topology: SplitGroupReplacementReceipt,
        launcherRelease: ShortcutSplitLauncherReleaseReceipt,
        placeholderRetirement: EmptySplitPlaceholderRetirementReceipt
    ) {
        self.topology = topology
        self.launcherRelease = launcherRelease
        self.placeholderRetirement = placeholderRetirement
    }

    func isCurrent() -> Bool {
        topology.isCurrent()
            && launcherRelease.isCurrent()
            && placeholderRetirement.isCurrent()
    }

    func commitModel() -> Bool {
        guard topology.commitModel() else { return false }
        guard placeholderRetirement.commitModel() else {
            precondition(topology.rollbackModel())
            return false
        }
        return true
    }

    func publish() {
        placeholderRetirement.publish()
        topology.publish()
    }

    func rollback() {
        placeholderRetirement.rollback()
        topology.rollback()
    }
}

/// Exact prepared split replacement with concrete authority, reversible model,
/// and terminal presentation participants.
@MainActor
final class SplitPlaceholderReplacementReceipt {
    private enum State {
        case prepared
        case modelCommitted
        case presentationSettled
        case published
        case cancelled
    }

    private let authority: SplitPlaceholderRuntimeAuthority
    private let topology: SplitPlaceholderTopologyMutation
    private let presentations: any SplitDropPresentationReconciling
    private let effect: SplitDropCommitEffect
    private var state = State.prepared

    init(
        authority: SplitPlaceholderRuntimeAuthority,
        topology: SplitPlaceholderTopologyMutation,
        presentations: any SplitDropPresentationReconciling,
        effect: SplitDropCommitEffect
    ) {
        self.authority = authority
        self.topology = topology
        self.presentations = presentations
        self.effect = effect
    }

    func isCurrent() -> Bool {
        guard case .prepared = state else { return false }
        return authority.isCurrent() && topology.isCurrent()
    }

    @discardableResult
    func commitModel() -> Bool {
        guard isCurrent(), topology.commitModel() else { return false }
        state = .modelCommitted
        return true
    }

    func settlePresentation() {
        guard case .modelCommitted = state else { return }
        state = .presentationSettled
        presentations.reconcile(effect)
    }

    func publish() {
        guard case .presentationSettled = state else { return }
        state = .published
        topology.publish()
    }

    func rollback() {
        guard case .prepared = state else { return }
        state = .cancelled
        topology.rollback()
    }
}
