import Foundation
import SumiDomain

/// Prepares the displayed binding contribution and its rich window aggregate.
/// Terminal publication belongs to the enclosing profile-owned transaction.
@MainActor
final class DisplayedTabShortcutConversionCommitter {
    private let bindings: DisplayedTabShortcutBindingPreparer
    private let batches: ShortcutTabBindingBatchFactory
    private let runtime: DisplayedTabShortcutRuntimePreparer

    init(
        bindings: DisplayedTabShortcutBindingPreparer,
        batches: ShortcutTabBindingBatchFactory,
        runtime: DisplayedTabShortcutRuntimePreparer
    ) {
        self.bindings = bindings
        self.batches = batches
        self.runtime = runtime
    }

    func beginBindingBatch(
        using attachment: TabRuntimeAttachmentWitness
    ) -> ShortcutTabBindingBatchBuilder {
        batches.make(using: attachment)
    }

    func preflightBinding(
        to pin: ShortcutPin,
        using authorization: AuthorizedDisplayedTabShortcutConversion,
        builder: ShortcutTabBindingBatchBuilder
    ) -> DisplayedTabShortcutBindingPreflight? {
        bindings.preflight(
            pin: pin,
            authorization: authorization,
            builder: builder
        )
    }

    func preflightBinding(
        to pin: ShortcutPin,
        using authorization: AuthorizedDisplayedTabShortcutConversion,
        presentations: DisplayedShortcutPresentationResidencePlan,
        builder: ShortcutTabBindingBatchBuilder
    ) -> DisplayedTabShortcutBindingPreflight? {
        bindings.preflight(
            pin: pin,
            authorization: authorization,
            presentations: presentations,
            builder: builder
        )
    }

    func prepareRuntime(
        _ binding: PreparedDisplayedTabShortcutBinding,
        transition: RegularTabShortcutWindowTransitionPlan,
        using authorization: AuthorizedDisplayedTabShortcutConversion
    ) -> DisplayedTabShortcutRuntimeTransaction? {
        runtime.prepare(
            binding,
            transition: transition,
            using: authorization
        )
    }
}
