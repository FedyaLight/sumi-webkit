import Foundation
import SumiDomain
import SumiWebRuntime

/// Replaces a regular tab that is not displayed by any browser window with a
/// durable shortcut definition. It deliberately creates no live shortcut tab;
/// a window materializes one later when the launcher is activated.
@MainActor
final class DetachedTabShortcutSourcePreparer {
    private let windows: ShortcutTabWindowQuery
    private let containerRemoval: ShortcutContainerRemovalOwner
    private let membership: TabCollectionMembershipOwner
    private let selection: TabSelectionStateOwner
    private let runtimeTeardown: TabRuntimeTeardownService

    init(
        windows: ShortcutTabWindowQuery,
        containerRemoval: ShortcutContainerRemovalOwner,
        membership: TabCollectionMembershipOwner,
        selection: TabSelectionStateOwner,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        self.windows = windows
        self.containerRemoval = containerRemoval
        self.membership = membership
        self.selection = selection
        self.runtimeTeardown = runtimeTeardown
    }

    func prepare(
        using authorization: AuthorizedDetachedTabShortcutConversion
    ) -> DetachedTabRuntimeRetirementParticipant? {
        guard let source = DetachedTabShortcutSourceModelTransaction(
            tab: authorization.tab,
            container: containerRemoval,
            membership: membership,
            selection: selection
        ) else { return nil }
        guard let exposure = DetachedTabRuntimeExposureWitness(
            tab: authorization.tab,
            attachment: authorization.runtimeAttachment,
            windows: windows
        ) else { return nil }
        guard let terminal = DetachedTabTerminalRetirementPublisher(
            tab: authorization.tab,
            source: source,
            exposure: exposure,
            teardown: runtimeTeardown
        ) else { return nil }
        let runtime = DetachedTabRuntimeRetirementParticipant(
            source: source,
            exposure: exposure,
            terminal: terminal
        )
        guard runtime.validateForStaging() else { return nil }
        return runtime
    }
}
